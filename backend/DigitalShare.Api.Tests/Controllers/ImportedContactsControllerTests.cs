using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.ImportedContacts;
using DigitalShare.Api.Tests.Helpers;

namespace DigitalShare.Api.Tests.Controllers;

public class ImportedContactsControllerTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public ImportedContactsControllerTests(CustomWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
    }

    private async Task<AuthResponse> RegisterUserAsync(string email)
    {
        var registerRequest = new RegisterRequest
        {
            Email = email,
            Password = "Password123!",
            ConfirmPassword = "Password123!"
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

    [Fact]
    public async Task TEST1_SaveImportedCard_ReturnsCreatedAndPersistsDetails()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        var request = new SaveImportedContactRequest
        {
            FullName = "Rahul Kumar",
            Company = "ABC Technologies",
            JobTitle = "Senior Developer",
            Website = "www.abctech.com",
            Address = "Chennai, Tamil Nadu",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+91 98765 43210", Label = "Mobile" }
            },
            EmailAddresses = new List<ImportedContactEmailDto>
            {
                new() { Email = "rahul@abctech.com", Label = "Work" }
            }
        };

        var response = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, request));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var created = await response.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);
        Assert.Equal("Rahul Kumar", created.FullName);
        Assert.Equal("ABC Technologies", created.Company);
        Assert.Single(created.PhoneNumbers);
        Assert.Single(created.EmailAddresses);
    }

    [Fact]
    public async Task TEST2_SaveMultiplePhones_PersistsAllWithLabelsAndNormalizedNumbers()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        var request = new SaveImportedContactRequest
        {
            FullName = "John Mathew",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+91 98765 43210", Label = "Mobile" },
                new() { Number = "+91 44 2345 6789", Label = "Office" }
            }
        };

        var response = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, request));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var created = await response.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);
        Assert.Equal(2, created.PhoneNumbers.Count);
        Assert.Contains(created.PhoneNumbers, p => p.Number == "+91 98765 43210" && p.Label == "Mobile");
        Assert.Contains(created.PhoneNumbers, p => p.Number == "+91 44 2345 6789" && p.Label == "Office");
    }

    [Fact]
    public async Task TEST3_SaveMultipleEmails_PersistsAllWithLabelsAndNormalizedEmails()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        var request = new SaveImportedContactRequest
        {
            FullName = "John Mathew",
            EmailAddresses = new List<ImportedContactEmailDto>
            {
                new() { Email = "john.work@example.com", Label = "Work" },
                new() { Email = "john.personal@example.com", Label = "Personal" }
            }
        };

        var response = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, request));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var created = await response.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);
        Assert.Equal(2, created.EmailAddresses.Count);
        Assert.Contains(created.EmailAddresses, e => e.NormalizedEmail == "john.work@example.com");
        Assert.Contains(created.EmailAddresses, e => e.NormalizedEmail == "john.personal@example.com");
    }

    [Fact]
    public async Task TEST4_RetrieveImportedCards_ReturnsAllForOwnerNewestFirst()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        // Save card 1
        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest { FullName = "Contact 1", PhoneNumbers = new() { new() { Number = "9876500001" } } }));

        // Save card 2
        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest { FullName = "Contact 2", PhoneNumbers = new() { new() { Number = "9876500002" } } }));

        var response = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Get, "/api/imported-contacts", auth.Token));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var list = await response.Content.ReadFromJsonAsync<List<ImportedContactResponse>>();
        Assert.NotNull(list);
        Assert.True(list.Count >= 2);
        Assert.Equal("Contact 2", list[0].FullName);
    }

    [Fact]
    public async Task TEST5_RetrieveSingleCard_ReturnsCardWithChildPhonesAndEmails()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        var createRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest
            {
                FullName = "Alice Walker",
                PhoneNumbers = new() { new() { Number = "9876543210" } },
                EmailAddresses = new() { new() { Email = "alice@example.com" } }
            }));
        var created = await createRes.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);

        var getRes = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Get, $"/api/imported-contacts/{created.Id}", auth.Token));

        Assert.Equal(HttpStatusCode.OK, getRes.StatusCode);
        var fetched = await getRes.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(fetched);
        Assert.Equal("Alice Walker", fetched.FullName);
        Assert.Single(fetched.PhoneNumbers);
        Assert.Single(fetched.EmailAddresses);
    }

    [Fact]
    public async Task TEST6_UpdateCard_ModifiesDetailsAndReplacesChildCollections()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        var createRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest
            {
                FullName = "Old Name",
                Company = "Old Co",
                PhoneNumbers = new() { new() { Number = "9876511111" } }
            }));
        var created = await createRes.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);

        var updateReq = new UpdateImportedContactRequest
        {
            FullName = "New Name",
            Company = "New Co",
            JobTitle = "Lead Architect",
            PhoneNumbers = new() { new() { Number = "9876522222", Label = "Work" } },
            EmailAddresses = new() { new() { Email = "new@example.com", Label = "Work" } }
        };

        var updateRes = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Put, $"/api/imported-contacts/{created.Id}", auth.Token, updateReq));

        Assert.Equal(HttpStatusCode.OK, updateRes.StatusCode);
        var updated = await updateRes.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(updated);
        Assert.Equal("New Name", updated.FullName);
        Assert.Equal("New Co", updated.Company);
        Assert.Equal("Lead Architect", updated.JobTitle);
        Assert.Single(updated.PhoneNumbers);
        Assert.Equal("9876522222", updated.PhoneNumbers[0].Number);
        Assert.Single(updated.EmailAddresses);
        Assert.Equal("new@example.com", updated.EmailAddresses[0].Email);
    }

    [Fact]
    public async Task TEST7_DeleteCard_RemovesCardAndChildren()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        var createRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest { FullName = "To Delete", PhoneNumbers = new() { new() { Number = "9876533333" } } }));
        var created = await createRes.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);

        var delRes = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Delete, $"/api/imported-contacts/{created.Id}", auth.Token));

        Assert.Equal(HttpStatusCode.NoContent, delRes.StatusCode);

        var getRes = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Get, $"/api/imported-contacts/{created.Id}", auth.Token));
        Assert.Equal(HttpStatusCode.NotFound, getRes.StatusCode);
    }

    [Fact]
    public async Task TEST8_OwnerIsolation_UserCannotAccessOrModifyAnotherUsersImportedCard()
    {
        var authA = await RegisterUserAsync($"user_a_{Guid.NewGuid()}@example.com");
        var authB = await RegisterUserAsync($"user_b_{Guid.NewGuid()}@example.com");

        var createRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", authA.Token,
            new SaveImportedContactRequest { FullName = "User A Private Contact", PhoneNumbers = new() { new() { Number = "9876544444" } } }));
        var created = await createRes.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);

        // User B attempts to GET User A's contact -> 404
        var getRes = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Get, $"/api/imported-contacts/{created.Id}", authB.Token));
        Assert.Equal(HttpStatusCode.NotFound, getRes.StatusCode);

        // User B attempts to UPDATE User A's contact -> 404
        var putRes = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Put, $"/api/imported-contacts/{created.Id}", authB.Token,
                new UpdateImportedContactRequest { FullName = "Hacked Name" }));
        Assert.Equal(HttpStatusCode.NotFound, putRes.StatusCode);

        // User B attempts to DELETE User A's contact -> 404
        var delRes = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Delete, $"/api/imported-contacts/{created.Id}", authB.Token));
        Assert.Equal(HttpStatusCode.NotFound, delRes.StatusCode);
    }

    [Fact]
    public async Task TEST9_DuplicateByPhone_DetectsMatchingPhone()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest
            {
                FullName = "Rahul Kumar",
                PhoneNumbers = new() { new() { Number = "+91 98765 43210" } }
            }));

        var checkRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts/check-duplicate", auth.Token,
            new CheckDuplicateRequest
            {
                PhoneNumbers = new() { "+91 98765 43210" }
            }));

        Assert.Equal(HttpStatusCode.OK, checkRes.StatusCode);
        var result = await checkRes.Content.ReadFromJsonAsync<CheckDuplicateResponse>();
        Assert.NotNull(result);
        Assert.True(result.IsDuplicate);
        Assert.NotNull(result.ExistingContact);
        Assert.Equal("Rahul Kumar", result.ExistingContact.FullName);
    }

    [Fact]
    public async Task TEST10_DuplicateByEmail_DetectsMatchingEmail()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest
            {
                FullName = "Priya Sharma",
                EmailAddresses = new() { new() { Email = "priya@example.com" } }
            }));

        var checkRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts/check-duplicate", auth.Token,
            new CheckDuplicateRequest
            {
                EmailAddresses = new() { "priya@example.com" }
            }));

        Assert.Equal(HttpStatusCode.OK, checkRes.StatusCode);
        var result = await checkRes.Content.ReadFromJsonAsync<CheckDuplicateResponse>();
        Assert.NotNull(result);
        Assert.True(result.IsDuplicate);
        Assert.Equal("Priya Sharma", result.ExistingContact?.FullName);
    }

    [Fact]
    public async Task TEST11_DuplicateUsingSecondPhone_DetectsMatchEvenWhenFirstPhoneDiffers()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest
            {
                FullName = "Multi Phone User",
                PhoneNumbers = new()
                {
                    new() { Number = "+91 98765 43210" },
                    new() { Number = "+91 44 2345 6789" }
                }
            }));

        // Query with a totally different first phone and the matching second phone
        var checkRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts/check-duplicate", auth.Token,
            new CheckDuplicateRequest
            {
                PhoneNumbers = new() { "9999900000", "+91 44 2345 6789" }
            }));

        var result = await checkRes.Content.ReadFromJsonAsync<CheckDuplicateResponse>();
        Assert.NotNull(result);
        Assert.True(result.IsDuplicate);
    }

    [Fact]
    public async Task TEST12_DuplicateUsingSecondEmail_DetectsMatchEvenWhenFirstEmailDiffers()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest
            {
                FullName = "Multi Email User",
                EmailAddresses = new()
                {
                    new() { Email = "work@example.com" },
                    new() { Email = "personal@example.com" }
                }
            }));

        var checkRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts/check-duplicate", auth.Token,
            new CheckDuplicateRequest
            {
                EmailAddresses = new() { "different@example.com", "personal@example.com" }
            }));

        var result = await checkRes.Content.ReadFromJsonAsync<CheckDuplicateResponse>();
        Assert.NotNull(result);
        Assert.True(result.IsDuplicate);
    }

    [Fact]
    public async Task TEST13_SameNameButDifferentContactInformation_IsNotDuplicate()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest
            {
                FullName = "Rahul Kumar",
                PhoneNumbers = new() { new() { Number = "+91 98765 11111" } },
                EmailAddresses = new() { new() { Email = "rahul1@example.com" } }
            }));

        // Another person also named Rahul Kumar but with completely different numbers and emails
        var checkRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts/check-duplicate", auth.Token,
            new CheckDuplicateRequest
            {
                PhoneNumbers = new() { "+91 98765 22222" },
                EmailAddresses = new() { "rahul2@example.com" }
            }));

        var result = await checkRes.Content.ReadFromJsonAsync<CheckDuplicateResponse>();
        Assert.NotNull(result);
        Assert.False(result.IsDuplicate);
    }

    [Fact]
    public async Task TEST14_EmailComparisonCaseInsensitive_DetectsDuplicate()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest
            {
                FullName = "Case Test",
                EmailAddresses = new() { new() { Email = "RAHUL@COMPANY.COM" } }
            }));

        var checkRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts/check-duplicate", auth.Token,
            new CheckDuplicateRequest
            {
                EmailAddresses = new() { "rahul@company.com" }
            }));

        var result = await checkRes.Content.ReadFromJsonAsync<CheckDuplicateResponse>();
        Assert.NotNull(result);
        Assert.True(result.IsDuplicate);
    }

    [Fact]
    public async Task TEST15_PhoneNormalizationDuplicate_MatchesAcrossFormats()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        // Saved as formatted +91 98765 43210
        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest
            {
                FullName = "Format Test",
                PhoneNumbers = new() { new() { Number = "+91 98765 43210" } }
            }));

        // Checked as compact 10-digit 9876543210
        var checkRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts/check-duplicate", auth.Token,
            new CheckDuplicateRequest
            {
                PhoneNumbers = new() { "9876543210" }
            }));

        var result = await checkRes.Content.ReadFromJsonAsync<CheckDuplicateResponse>();
        Assert.NotNull(result);
        Assert.True(result.IsDuplicate);
    }

    [Fact]
    public async Task TEST16_UserAContact_DoesNotTriggerDuplicateForUserB()
    {
        var authA = await RegisterUserAsync($"user_a_{Guid.NewGuid()}@example.com");
        var authB = await RegisterUserAsync($"user_b_{Guid.NewGuid()}@example.com");

        // User A saves contact with 9876555555
        await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", authA.Token,
            new SaveImportedContactRequest
            {
                FullName = "Contact A",
                PhoneNumbers = new() { new() { Number = "9876555555" } },
                EmailAddresses = new() { new() { Email = "shared@example.com" } }
            }));

        // User B checks the same phone number -> Should NOT be duplicate for User B
        var checkRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts/check-duplicate", authB.Token,
            new CheckDuplicateRequest
            {
                PhoneNumbers = new() { "9876555555" },
                EmailAddresses = new() { "shared@example.com" }
            }));

        var result = await checkRes.Content.ReadFromJsonAsync<CheckDuplicateResponse>();
        Assert.NotNull(result);
        Assert.False(result.IsDuplicate);
    }

    [Fact]
    public async Task TEST17_JwtRequired_RejectsUnauthenticatedRequests()
    {
        // Unauthenticated check duplicate
        var checkRes = await _client.PostAsJsonAsync("/api/imported-contacts/check-duplicate", new CheckDuplicateRequest());
        Assert.Equal(HttpStatusCode.Unauthorized, checkRes.StatusCode);

        // Unauthenticated save
        var saveRes = await _client.PostAsJsonAsync("/api/imported-contacts", new SaveImportedContactRequest());
        Assert.Equal(HttpStatusCode.Unauthorized, saveRes.StatusCode);

        // Unauthenticated get
        var getRes = await _client.GetAsync("/api/imported-contacts");
        Assert.Equal(HttpStatusCode.Unauthorized, getRes.StatusCode);
    }

    [Fact]
    public async Task TEST18_ChildPhonesAndEmails_CorrectlyUpdatedAndRemovedOnUpdate()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        var createRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest
            {
                FullName = "Initial",
                PhoneNumbers = new()
                {
                    new() { Number = "1111111111", Label = "OldPhone1" },
                    new() { Number = "2222222222", Label = "OldPhone2" }
                },
                EmailAddresses = new()
                {
                    new() { Email = "old1@example.com", Label = "OldEmail1" },
                    new() { Email = "old2@example.com", Label = "OldEmail2" }
                }
            }));
        var created = await createRes.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);
        Assert.Equal(2, created.PhoneNumbers.Count);
        Assert.Equal(2, created.EmailAddresses.Count);

        // Update with only ONE phone and NO emails
        var updateReq = new UpdateImportedContactRequest
        {
            FullName = "Updated",
            PhoneNumbers = new()
            {
                new() { Number = "3333333333", Label = "SolePhone" }
            },
            EmailAddresses = new() // Cleared
        };

        var updateRes = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Put, $"/api/imported-contacts/{created.Id}", auth.Token, updateReq));

        Assert.Equal(HttpStatusCode.OK, updateRes.StatusCode);
        var updated = await updateRes.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(updated);
        Assert.Single(updated.PhoneNumbers);
        Assert.Equal("3333333333", updated.PhoneNumbers[0].Number);
        Assert.Empty(updated.EmailAddresses);
    }
}
