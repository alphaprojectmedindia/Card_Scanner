using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.ImportedContacts;
using DigitalShare.Api.Tests.Helpers;
using Xunit;

namespace DigitalShare.Api.Tests.Controllers;

public class RememberThisContactAndSearchTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public RememberThisContactAndSearchTests(CustomWebApplicationFactory factory)
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
        return auth!;
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

    [Fact]
    public async Task CreateContact_WithRememberThisContact_PersistsAndReturnsMemory()
    {
        var auth = await RegisterUserAsync($"mem_user_{Guid.NewGuid()}@example.com");

        var saveRequest = new SaveImportedContactRequest
        {
            FullName = "Dr. (Prof.) Sudhir Bhandari",
            JobTitle = "Professor Emeritus",
            Company = "SMS Medical College",
            RememberThisContact = "Met at Chennai medical conference.",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "0141-2795050" }
            }
        };

        var request = CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.AccessToken, saveRequest);
        var response = await _client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var created = await response.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);
        Assert.Equal("Met at Chennai medical conference.", created.RememberThisContact);

        // Retrieve by ID
        var getReq = CreateAuthenticatedRequest(HttpMethod.Get, $"/api/imported-contacts/{created.Id}", auth.AccessToken);
        var getResp = await _client.SendAsync(getReq);
        Assert.Equal(HttpStatusCode.OK, getResp.StatusCode);
        var fetched = await getResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(fetched);
        Assert.Equal("Met at Chennai medical conference.", fetched.RememberThisContact);
    }

    [Fact]
    public async Task CreateContact_WithoutRememberThisContact_ReturnsNullMemory()
    {
        var auth = await RegisterUserAsync($"nomem_user_{Guid.NewGuid()}@example.com");

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
        Assert.Null(created.RememberThisContact);
    }

    [Fact]
    public async Task UpdateContactMemory_UpdatesSuccessfullyAndPreservesOnGeneralUpdate()
    {
        var auth = await RegisterUserAsync($"upmem_user_{Guid.NewGuid()}@example.com");

        var saveRequest = new SaveImportedContactRequest
        {
            FullName = "Alice Walker",
            Company = "Acme Corp",
            RememberThisContact = "Initial coffee chat in Austin",
            PhoneNumbers = new List<ImportedContactPhoneDto> { new() { Number = "+1 512 555 1234" } }
        };

        var postResp = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.AccessToken, saveRequest));
        var created = await postResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);

        // Update memory via dedicated PUT /memory
        var updateMemReq = new UpdateContactRemarkRequest { RememberThisContact = "Met at SXSW Austin 2026. Follow up on design." };
        var putMemResp = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Put, $"/api/imported-contacts/{created.Id}/memory", auth.AccessToken, updateMemReq));
        Assert.Equal(HttpStatusCode.OK, putMemResp.StatusCode);
        var updatedMem = await putMemResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(updatedMem);
        Assert.Equal("Met at SXSW Austin 2026. Follow up on design.", updatedMem.RememberThisContact);

        // General update with null RememberThisContact must PRESERVE existing memory
        var generalUpdate = new UpdateImportedContactRequest
        {
            FullName = "Alice Walker",
            Company = "Acme Global Industries",
            RememberThisContact = null,
            PhoneNumbers = new List<ImportedContactPhoneDto> { new() { Number = "+1 512 555 1234" } }
        };
        var putGeneralResp = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Put, $"/api/imported-contacts/{created.Id}", auth.AccessToken, generalUpdate));
        Assert.Equal(HttpStatusCode.OK, putGeneralResp.StatusCode);
        var afterGeneral = await putGeneralResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(afterGeneral);
        Assert.Equal("Acme Global Industries", afterGeneral.Company);
        Assert.Equal("Met at SXSW Austin 2026. Follow up on design.", afterGeneral.RememberThisContact);

        // Clear memory via DELETE /memory
        var clearResp = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Delete, $"/api/imported-contacts/{created.Id}/memory", auth.AccessToken));
        Assert.Equal(HttpStatusCode.OK, clearResp.StatusCode);
        var cleared = await clearResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(cleared);
        Assert.Null(cleared.RememberThisContact);
    }

    [Fact]
    public async Task CrossUserIsolation_CannotAccessOrModifyAnotherUsersMemory()
    {
        var user1 = await RegisterUserAsync($"mem_u1_{Guid.NewGuid()}@example.com");
        var user2 = await RegisterUserAsync($"mem_u2_{Guid.NewGuid()}@example.com");

        var saveReq = new SaveImportedContactRequest
        {
            FullName = "Private Contact",
            RememberThisContact = "User1 Top Secret Memory",
            PhoneNumbers = new List<ImportedContactPhoneDto> { new() { Number = "+1 555 000 1111" } }
        };

        var postResp = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", user1.AccessToken, saveReq));
        var created = await postResp.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);

        // User 2 attempts to get User 1's card
        var getResp = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Get, $"/api/imported-contacts/{created.Id}", user2.AccessToken));
        Assert.Equal(HttpStatusCode.NotFound, getResp.StatusCode);

        // User 2 attempts to modify User 1's memory
        var updateMemReq = new UpdateContactRemarkRequest { RememberThisContact = "Hacked memory" };
        var putResp = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Put, $"/api/imported-contacts/{created.Id}/memory", user2.AccessToken, updateMemReq));
        Assert.Equal(HttpStatusCode.NotFound, putResp.StatusCode);
    }

    [Fact]
    public async Task SearchContacts_ByWordPresentOnlyInRememberThisContact_ReturnsContact()
    {
        var auth = await RegisterUserAsync($"search_user_{Guid.NewGuid()}@example.com");

        var card1 = new SaveImportedContactRequest
        {
            FullName = "Dr. (Prof.) Sudhir Bhandari",
            JobTitle = "Professor Emeritus",
            PhoneNumbers = new List<ImportedContactPhoneDto> { new() { Number = "0141-2795050" } },
            RememberThisContact = "Met at Chennai"
        };

        var card2 = new SaveImportedContactRequest
        {
            FullName = "Elon Musk",
            Company = "Tesla",
            PhoneNumbers = new List<ImportedContactPhoneDto> { new() { Number = "+1 512 000 0000" } },
            RememberThisContact = "Met at Austin Gigafactory"
        };

        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.AccessToken, card1));
        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.AccessToken, card2));

        // Search for "chennai" (case-insensitive)
        var searchResp = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Get, "/api/imported-contacts?search=chennai", auth.AccessToken));
        Assert.Equal(HttpStatusCode.OK, searchResp.StatusCode);

        var results = await searchResp.Content.ReadFromJsonAsync<List<ImportedContactResponse>>();
        Assert.NotNull(results);
        Assert.Single(results);
        Assert.Equal("Dr. (Prof.) Sudhir Bhandari", results[0].FullName);
        Assert.Equal("Met at Chennai", results[0].RememberThisContact);

        // Partial match "chenn"
        var partialResp = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Get, "/api/imported-contacts?search=chenn", auth.AccessToken));
        var partialResults = await partialResp.Content.ReadFromJsonAsync<List<ImportedContactResponse>>();
        Assert.NotNull(partialResults);
        Assert.Single(partialResults);

        // Existing fields still work: search for "Tesla"
        var teslaResp = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Get, "/api/imported-contacts?search=Tesla", auth.AccessToken));
        var teslaResults = await teslaResp.Content.ReadFromJsonAsync<List<ImportedContactResponse>>();
        Assert.NotNull(teslaResults);
        Assert.Single(teslaResults);
        Assert.Equal("Elon Musk", teslaResults[0].FullName);

        // Empty search returns all contacts
        var allResp = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Get, "/api/imported-contacts", auth.AccessToken));
        var allResults = await allResp.Content.ReadFromJsonAsync<List<ImportedContactResponse>>();
        Assert.NotNull(allResults);
        Assert.Equal(2, allResults.Count);
    }
}

