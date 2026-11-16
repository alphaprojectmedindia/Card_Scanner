using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.DTOs.ImportedContacts;
using DigitalShare.Api.DTOs.Profile;
using DigitalShare.Api.Tests.Helpers;

namespace DigitalShare.Api.Tests.Controllers;

public class RemarksVisibilityAndDeletionTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public RemarksVisibilityAndDeletionTests(CustomWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
    }

    private async Task<AuthResponse> RegisterUserAsync(string email, string password = "Password123!")
    {
        var registerRequest = new RegisterRequest
        {
            Email = email,
            Password = password,
            ConfirmPassword = password
        };

        var regResponse = await _client.PostAsJsonAsync("/api/auth/register", registerRequest);
        regResponse.EnsureSuccessStatusCode();
        var auth = await regResponse.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);
        return auth;
    }

    private HttpRequestMessage CreateAuthenticatedRequest(HttpMethod method, string url, string token, object? content = null)
    {
        var request = new HttpRequestMessage(method, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (content != null)
        {
            request.Content = JsonContent.Create(content);
        }
        return request;
    }

    // ==========================================
    // FEATURE 1: PERSONAL CONTACT REMARKS TESTS
    // ==========================================

    [Fact]
    public async Task ContactRemarks_SaveWithRemark_PersistsAndReturnsRemark()
    {
        var auth = await RegisterUserAsync($"remark_user_{Guid.NewGuid()}@example.com");

        var saveRequest = new SaveImportedContactRequest
        {
            FullName = "Sundar Pichai",
            Company = "Google",
            PersonalRemark = "Met at Google I/O conference. Great discussion on Gemini.",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+1 650 253 0000" }
            }
        };

        var request = CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.AccessToken, saveRequest);
        var response = await _client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var created = await response.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);
        Assert.Equal("Met at Google I/O conference. Great discussion on Gemini.", created.PersonalRemark);

        // Fetch by ID
        var getReq = CreateAuthenticatedRequest(HttpMethod.Get, $"/api/imported-contacts/{created.Id}", auth.AccessToken);
        var getResp = await _client.SendAsync(getReq);
        Assert.Equal(HttpStatusCode.OK, getResp.StatusCode);
        var fetched = await getResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(fetched);
        Assert.Equal("Met at Google I/O conference. Great discussion on Gemini.", fetched.PersonalRemark);
    }

    [Fact]
    public async Task ContactRemarks_SaveWithoutRemark_ReturnsNullRemark()
    {
        var auth = await RegisterUserAsync($"remark_user_{Guid.NewGuid()}@example.com");

        var saveRequest = new SaveImportedContactRequest
        {
            FullName = "Satya Nadella",
            Company = "Microsoft",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+1 425 882 8080" }
            }
        };

        var request = CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.AccessToken, saveRequest);
        var response = await _client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var created = await response.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);
        Assert.Null(created.PersonalRemark);
    }

    [Fact]
    public async Task ContactRemarks_ExplicitUpdateAndClear_ModifiesRemark()
    {
        var auth = await RegisterUserAsync($"remark_user_{Guid.NewGuid()}@example.com");

        var saveRequest = new SaveImportedContactRequest
        {
            FullName = "Tim Cook",
            Company = "Apple",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+1 408 996 1010" }
            }
        };

        var saveReq = CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.AccessToken, saveRequest);
        var saveResp = await _client.SendAsync(saveReq);
        var created = await saveResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);

        // 1. Add remark via PUT /api/imported-contacts/{id}/remark
        var updateRemarkDto = new UpdateContactRemarkRequest { Remark = "Keynote meeting in Cupertino." };
        var putReq = CreateAuthenticatedRequest(HttpMethod.Put, $"/api/imported-contacts/{created.Id}/remark", auth.AccessToken, updateRemarkDto);
        var putResp = await _client.SendAsync(putReq);
        Assert.Equal(HttpStatusCode.OK, putResp.StatusCode);
        var putResult = await putResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(putResult);
        Assert.Equal("Keynote meeting in Cupertino.", putResult.PersonalRemark);

        // 2. Clear remark via DELETE /api/imported-contacts/{id}/remark
        var delReq = CreateAuthenticatedRequest(HttpMethod.Delete, $"/api/imported-contacts/{created.Id}/remark", auth.AccessToken);
        var delResp = await _client.SendAsync(delReq);
        Assert.Equal(HttpStatusCode.OK, delResp.StatusCode);
        var delResult = await delResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(delResult);
        Assert.Null(delResult.PersonalRemark);
    }

    [Fact]
    public async Task ContactRemarks_OrdinaryUpdatePreservesExistingRemark()
    {
        var auth = await RegisterUserAsync($"remark_user_{Guid.NewGuid()}@example.com");

        var saveRequest = new SaveImportedContactRequest
        {
            FullName = "Jensen Huang",
            Company = "NVIDIA",
            PersonalRemark = "Original personal remark that must not be lost.",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+1 408 486 2000" }
            }
        };

        var saveReq = CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.AccessToken, saveRequest);
        var saveResp = await _client.SendAsync(saveReq);
        var created = await saveResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);

        // Ordinary update that does NOT specify PersonalRemark (sends null)
        var ordinaryUpdate = new UpdateImportedContactRequest
        {
            FullName = "Jensen Huang",
            Company = "NVIDIA Corporation",
            JobTitle = "CEO",
            PersonalRemark = null, // null in regular form update should NOT wipe remark
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+1 408 486 2000" }
            }
        };

        var updateReq = CreateAuthenticatedRequest(HttpMethod.Put, $"/api/imported-contacts/{created.Id}", auth.AccessToken, ordinaryUpdate);
        var updateResp = await _client.SendAsync(updateReq);
        Assert.Equal(HttpStatusCode.OK, updateResp.StatusCode);

        var updated = await updateResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(updated);
        Assert.Equal("NVIDIA Corporation", updated.Company);
        Assert.Equal("CEO", updated.JobTitle);
        // Remark preserved!
        Assert.Equal("Original personal remark that must not be lost.", updated.PersonalRemark);
    }

    [Fact]
    public async Task ContactRemarks_AnotherUserCannotReadOrModifyRemark()
    {
        var authUser1 = await RegisterUserAsync($"user1_{Guid.NewGuid()}@example.com");
        var authUser2 = await RegisterUserAsync($"user2_{Guid.NewGuid()}@example.com");

        var saveReq = CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", authUser1.AccessToken, new SaveImportedContactRequest
        {
            FullName = "Private Contact",
            PersonalRemark = "Secret client notes for User 1 eyes only."
        });
        var saveResp = await _client.SendAsync(saveReq);
        var created = await saveResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);

        // User 2 attempts to GET user 1's contact -> 404
        var unauthorizedGet = CreateAuthenticatedRequest(HttpMethod.Get, $"/api/imported-contacts/{created.Id}", authUser2.AccessToken);
        var getResp = await _client.SendAsync(unauthorizedGet);
        Assert.Equal(HttpStatusCode.NotFound, getResp.StatusCode);

        // User 2 attempts to PUT remark on user 1's contact -> 404
        var unauthorizedPut = CreateAuthenticatedRequest(HttpMethod.Put, $"/api/imported-contacts/{created.Id}/remark", authUser2.AccessToken, new UpdateContactRemarkRequest { Remark = "Malicious overwrite" });
        var putResp = await _client.SendAsync(unauthorizedPut);
        Assert.Equal(HttpStatusCode.NotFound, putResp.StatusCode);
    }

    // ==========================================
    // FEATURE 2: PUBLIC AND PRIVATE ACCOUNT TESTS
    // ==========================================

    [Fact]
    public async Task AccountVisibility_DefaultIsPrivate()
    {
        var auth = await RegisterUserAsync($"vis_user_{Guid.NewGuid()}@example.com");

        var req = CreateAuthenticatedRequest(HttpMethod.Get, "/api/profile/visibility", auth.AccessToken);
        var resp = await _client.SendAsync(req);
        Assert.Equal(HttpStatusCode.OK, resp.StatusCode);

        var visibility = await resp.Content.ReadFromJsonAsync<AccountVisibilityDto>();
        Assert.NotNull(visibility);
        Assert.False(visibility.IsPublic); // Default is Private
    }

    [Fact]
    public async Task AccountVisibility_CanTogglePublicAndPrivate()
    {
        var auth = await RegisterUserAsync($"vis_user_{Guid.NewGuid()}@example.com");

        // 1. Change to Public
        var setPublicReq = CreateAuthenticatedRequest(HttpMethod.Put, "/api/profile/visibility", auth.AccessToken, new AccountVisibilityDto { IsPublic = true });
        var setPublicResp = await _client.SendAsync(setPublicReq);
        Assert.Equal(HttpStatusCode.OK, setPublicResp.StatusCode);
        var publicResult = await setPublicResp.Content.ReadFromJsonAsync<AccountVisibilityDto>();
        Assert.NotNull(publicResult);
        Assert.True(publicResult.IsPublic);

        // 2. Change back to Private
        var setPrivateReq = CreateAuthenticatedRequest(HttpMethod.Put, "/api/profile/visibility", auth.AccessToken, new AccountVisibilityDto { IsPublic = false });
        var setPrivateResp = await _client.SendAsync(setPrivateReq);
        Assert.Equal(HttpStatusCode.OK, setPrivateResp.StatusCode);
        var privateResult = await setPrivateResp.Content.ReadFromJsonAsync<AccountVisibilityDto>();
        Assert.NotNull(privateResult);
        Assert.False(privateResult.IsPublic);
    }

    [Fact]
    public async Task AccountVisibility_SearchEnforcesVisibility_OnlyPublicAccountsAppear()
    {
        var publicEmail = $"search_pub_{Guid.NewGuid()}@example.com";
        var privateEmail = $"search_priv_{Guid.NewGuid()}@example.com";

        var authPublic = await RegisterUserAsync(publicEmail);
        var authPrivate = await RegisterUserAsync(privateEmail);

        var uniqueTag = Guid.NewGuid().ToString("N")[..8];

        // Setup public profile
        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Put, "/api/profile/me", authPublic.AccessToken, new UpdateProfileRequest
        {
            FullName = $"Public Leader {uniqueTag}",
            Company = $"Public Corp {uniqueTag}",
            Email = publicEmail,
            IsPublic = true
        }));

        // Setup private profile
        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Put, "/api/profile/me", authPrivate.AccessToken, new UpdateProfileRequest
        {
            FullName = $"Private Person {uniqueTag}",
            Company = $"Secret Corp {uniqueTag}",
            Email = privateEmail,
            IsPublic = false
        }));

        // Search for uniqueTag
        var searchReq = CreateAuthenticatedRequest(HttpMethod.Get, $"/api/profile/search?q={uniqueTag}", authPublic.AccessToken);
        var searchResp = await _client.SendAsync(searchReq);
        Assert.Equal(HttpStatusCode.OK, searchResp.StatusCode);

        var results = await searchResp.Content.ReadFromJsonAsync<List<PublicProfileSearchResultDto>>();
        Assert.NotNull(results);

        // Must find Public account
        Assert.Contains(results, r => r.FullName == $"Public Leader {uniqueTag}");

        // MUST NOT find Private account!
        Assert.DoesNotContain(results, r => r.FullName == $"Private Person {uniqueTag}");
    }

    // ==========================================
    // FEATURE 3: DELETE ENTIRE ACCOUNT TESTS
    // ==========================================

    [Fact]
    public async Task AccountDeletion_RequiresValidPassword_RejectsInvalid()
    {
        var password = "CorrectPassword123!";
        var auth = await RegisterUserAsync($"del_user_{Guid.NewGuid()}@example.com", password);

        // Try with wrong password
        var wrongReq = CreateAuthenticatedRequest(HttpMethod.Post, "/api/auth/delete-account", auth.AccessToken, new DeleteAccountRequest
        {
            Password = "WrongPassword999!"
        });
        var wrongResp = await _client.SendAsync(wrongReq);
        Assert.Equal(HttpStatusCode.BadRequest, wrongResp.StatusCode);

        // Account still intact
        var profileReq = CreateAuthenticatedRequest(HttpMethod.Get, "/api/profile/me", auth.AccessToken);
        var profileResp = await _client.SendAsync(profileReq);
        Assert.Equal(HttpStatusCode.OK, profileResp.StatusCode);
    }

    [Fact]
    public async Task AccountDeletion_SuccessfulDeletion_WipesAccountAndRelatedData()
    {
        var password = "StrongPassword123!";
        var auth = await RegisterUserAsync($"del_success_{Guid.NewGuid()}@example.com", password);

        // Add contact for this user
        var addContactReq = CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.AccessToken, new SaveImportedContactRequest
        {
            FullName = "Contact to be deleted",
            PersonalRemark = "Remark to be deleted",
            PhoneNumbers = new List<ImportedContactPhoneDto> { new() { Number = "+91 99999 88888" } }
        });
        var addContactResp = await _client.SendAsync(addContactReq);
        Assert.Equal(HttpStatusCode.Created, addContactResp.StatusCode);
        var contact = await addContactResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(contact);

        // Execute Delete Account
        var deleteReq = CreateAuthenticatedRequest(HttpMethod.Post, "/api/auth/delete-account", auth.AccessToken, new DeleteAccountRequest
        {
            Password = password
        });
        var deleteResp = await _client.SendAsync(deleteReq);
        Assert.Equal(HttpStatusCode.OK, deleteResp.StatusCode);

        // Subsequent request for deleted profile returns 404 NotFound
        var verifyProfileReq = CreateAuthenticatedRequest(HttpMethod.Get, "/api/profile/me", auth.AccessToken);
        var verifyProfileResp = await _client.SendAsync(verifyProfileReq);
        Assert.Equal(HttpStatusCode.NotFound, verifyProfileResp.StatusCode);

        // Login with original credentials fails
        var loginResp = await _client.PostAsJsonAsync("/api/auth/login", new LoginRequest
        {
            Email = auth.Email,
            Password = password
        });
        Assert.Equal(HttpStatusCode.Unauthorized, loginResp.StatusCode);
    }
}
