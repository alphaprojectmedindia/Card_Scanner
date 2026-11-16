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

    [Fact]
    public async Task TEST19_SaveImportedCard_ExactMaxLengths_Succeeds()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        var request = new SaveImportedContactRequest
        {
            FullName = new string('A', 100),
            Company = new string('B', 100),
            JobTitle = new string('C', 100),
            Website = "https://" + new string('d', 244) + ".com", // 8 + 244 + 4 = 256
            Address = new string('E', 500),
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+1" + new string('9', 48), Label = new string('L', 50) } // 50 chars
            },
            EmailAddresses = new List<ImportedContactEmailDto>
            {
                new() { Email = new string('a', 244) + "@example.com", Label = new string('M', 50) } // 244 + 12 = 256 chars
            }
        };

        var response = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, request));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var created = await response.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);
        Assert.Equal(100, created.FullName?.Length);
        Assert.Equal(100, created.Company?.Length);
        Assert.Equal(100, created.JobTitle?.Length);
        Assert.Equal(256, created.Website?.Length);
        Assert.Equal(500, created.Address?.Length);
        Assert.Equal(50, created.PhoneNumbers[0].Number.Length);
        Assert.Equal(50, created.PhoneNumbers[0].Label?.Length);
        Assert.Equal(256, created.EmailAddresses[0].Email.Length);
        Assert.Equal(50, created.EmailAddresses[0].Label?.Length);
    }

    [Theory]
    [InlineData("FullName", 101)]
    [InlineData("Company", 101)]
    [InlineData("JobTitle", 101)]
    [InlineData("Website", 257)]
    [InlineData("Address", 501)]
    public async Task TEST20_SaveImportedCard_FieldExceedingMaxLength_ReturnsBadRequest(string field, int length)
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        var request = new SaveImportedContactRequest
        {
            FullName = field == "FullName" ? new string('A', length) : "Valid Name",
            Company = field == "Company" ? new string('B', length) : "Valid Company",
            JobTitle = field == "JobTitle" ? new string('C', length) : "Valid Title",
            Website = field == "Website" ? new string('w', length) : "www.valid.com",
            Address = field == "Address" ? new string('E', length) : "Valid Address",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+91 98765 43210" }
            }
        };

        var response = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, request));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task TEST21_SaveImportedCard_PhoneOrEmailExceedingMaxLength_ReturnsBadRequest()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        // Phone number > 50
        var reqPhoneOver = new SaveImportedContactRequest
        {
            FullName = "Valid Name",
            PhoneNumbers = new() { new() { Number = "+1" + new string('9', 50) } } // 52 chars
        };
        var res1 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, reqPhoneOver));
        Assert.Equal(HttpStatusCode.BadRequest, res1.StatusCode);

        // Phone label > 50
        var reqPhoneLabelOver = new SaveImportedContactRequest
        {
            FullName = "Valid Name",
            PhoneNumbers = new() { new() { Number = "+1 555 123 4567", Label = new string('L', 51) } }
        };
        var res2 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, reqPhoneLabelOver));
        Assert.Equal(HttpStatusCode.BadRequest, res2.StatusCode);

        // Email > 256
        var reqEmailOver = new SaveImportedContactRequest
        {
            FullName = "Valid Name",
            EmailAddresses = new() { new() { Email = new string('e', 246) + "@example.com" } } // 258 chars
        };
        var res3 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, reqEmailOver));
        Assert.Equal(HttpStatusCode.BadRequest, res3.StatusCode);

        // Email label > 50
        var reqEmailLabelOver = new SaveImportedContactRequest
        {
            FullName = "Valid Name",
            EmailAddresses = new() { new() { Email = "valid@example.com", Label = new string('L', 51) } }
        };
        var res4 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, reqEmailLabelOver));
        Assert.Equal(HttpStatusCode.BadRequest, res4.StatusCode);
    }

    [Fact]
    public async Task TEST22_SaveImportedCard_MissingOrWhitespaceRequiredPhoneOrEmail_ReturnsBadRequest()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        // Phone with empty number
        var emptyPhoneReq = new SaveImportedContactRequest
        {
            FullName = "Valid Name",
            PhoneNumbers = new() { new() { Number = "" } }
        };
        var res1 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, emptyPhoneReq));
        Assert.Equal(HttpStatusCode.BadRequest, res1.StatusCode);

        // Phone with whitespace number
        var wsPhoneReq = new SaveImportedContactRequest
        {
            FullName = "Valid Name",
            PhoneNumbers = new() { new() { Number = "   " } }
        };
        var res2 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, wsPhoneReq));
        Assert.Equal(HttpStatusCode.BadRequest, res2.StatusCode);

        // Email with empty address
        var emptyEmailReq = new SaveImportedContactRequest
        {
            FullName = "Valid Name",
            EmailAddresses = new() { new() { Email = "" } }
        };
        var res3 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, emptyEmailReq));
        Assert.Equal(HttpStatusCode.BadRequest, res3.StatusCode);

        // Email with whitespace address
        var wsEmailReq = new SaveImportedContactRequest
        {
            FullName = "Valid Name",
            EmailAddresses = new() { new() { Email = "   " } }
        };
        var res4 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, wsEmailReq));
        Assert.Equal(HttpStatusCode.BadRequest, res4.StatusCode);

        // Completely empty / whitespace contact
        var wsContactReq = new SaveImportedContactRequest
        {
            FullName = "   ",
            Company = "   "
        };
        var res5 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, wsContactReq));
        Assert.Equal(HttpStatusCode.BadRequest, res5.StatusCode);
    }

    [Fact]
    public async Task TEST23_SaveImportedCard_InvalidEmailOrPhoneFormat_ReturnsBadRequest()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        // Invalid email format
        var badEmailReq = new SaveImportedContactRequest
        {
            FullName = "Valid Name",
            EmailAddresses = new() { new() { Email = "not-an-email" } }
        };
        var res1 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, badEmailReq));
        Assert.Equal(HttpStatusCode.BadRequest, res1.StatusCode);

        // Invalid phone format
        var badPhoneReq = new SaveImportedContactRequest
        {
            FullName = "Valid Name",
            PhoneNumbers = new() { new() { Number = "abcxyz!@#$" } }
        };
        var res2 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, badPhoneReq));
        Assert.Equal(HttpStatusCode.BadRequest, res2.StatusCode);
    }

    [Theory]
    [InlineData("+1-555-123-4567")]
    [InlineData("+44 20 7946 0991")]
    [InlineData("+91 98765 43210")]
    [InlineData("+81 3 1234 5678")]
    [InlineData("(02) 1234 5678")]
    [InlineData("1234567890")]
    public async Task TEST24_SaveImportedCard_ValidInternationalPhoneFormats_ReturnsCreated(string phoneNumber)
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        var req = new SaveImportedContactRequest
        {
            FullName = "International User",
            PhoneNumbers = new() { new() { Number = phoneNumber } }
        };

        var response = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, req));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Fact]
    public async Task TEST25_UpdateImportedCard_ValidationRulesEnforced_ReturnsBadRequest()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        // Create valid card first
        var createRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest
            {
                FullName = "Initial Contact",
                PhoneNumbers = new() { new() { Number = "+91 98765 43210" } }
            }));
        var created = await createRes.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);

        // Update with FullName > 100
        var updateOverLength = new UpdateImportedContactRequest
        {
            FullName = new string('Z', 101),
            PhoneNumbers = new() { new() { Number = "+91 98765 43210" } }
        };
        var res1 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Put, $"/api/imported-contacts/{created.Id}", auth.Token, updateOverLength));
        Assert.Equal(HttpStatusCode.BadRequest, res1.StatusCode);

        // Update with invalid email
        var updateBadEmail = new UpdateImportedContactRequest
        {
            FullName = "Valid Name",
            EmailAddresses = new() { new() { Email = "not-an-email" } }
        };
        var res2 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Put, $"/api/imported-contacts/{created.Id}", auth.Token, updateBadEmail));
        Assert.Equal(HttpStatusCode.BadRequest, res2.StatusCode);

        // Update with completely empty/whitespace contact
        var updateEmpty = new UpdateImportedContactRequest
        {
            FullName = "   ",
            Company = "   "
        };
        var res3 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Put, $"/api/imported-contacts/{created.Id}", auth.Token, updateEmpty));
        Assert.Equal(HttpStatusCode.BadRequest, res3.StatusCode);
    }

    [Fact]
    public async Task TEST26_UpdateImportedCard_ExactMaxLengths_Succeeds()
    {
        var auth = await RegisterUserAsync($"user_{Guid.NewGuid()}@example.com");

        var createRes = await _client.SendAsync(CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token,
            new SaveImportedContactRequest
            {
                FullName = "Initial Contact",
                PhoneNumbers = new() { new() { Number = "+91 98765 43210" } }
            }));
        var created = await createRes.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(created);

        var updateReq = new UpdateImportedContactRequest
        {
            FullName = new string('A', 100),
            Company = new string('B', 100),
            JobTitle = new string('C', 100),
            Website = "https://" + new string('d', 244) + ".com",
            Address = new string('E', 500),
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+1" + new string('9', 48), Label = new string('L', 50) }
            },
            EmailAddresses = new List<ImportedContactEmailDto>
            {
                new() { Email = new string('a', 244) + "@example.com", Label = new string('M', 50) }
            }
        };

        var updateRes = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Put, $"/api/imported-contacts/{created.Id}", auth.Token, updateReq));

        Assert.Equal(HttpStatusCode.OK, updateRes.StatusCode);
        var updated = await updateRes.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(updated);
        Assert.Equal(100, updated.FullName?.Length);
        Assert.Equal(100, updated.Company?.Length);
        Assert.Equal(100, updated.JobTitle?.Length);
        Assert.Equal(256, updated.Website?.Length);
        Assert.Equal(500, updated.Address?.Length);
        Assert.Equal(50, updated.PhoneNumbers[0].Number.Length);
        Assert.Equal(50, updated.PhoneNumbers[0].Label?.Length);
        Assert.Equal(256, updated.EmailAddresses[0].Email.Length);
        Assert.Equal(50, updated.EmailAddresses[0].Label?.Length);
    }
}
