using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.DTOs.ImportedContacts;
using DigitalShare.Api.Exceptions;
using DigitalShare.Api.Models;
using DigitalShare.Api.Services;
using DigitalShare.Api.Tests.Helpers;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace DigitalShare.Api.Tests.Controllers;

public class ImportedContactsIdempotencyTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly CustomWebApplicationFactory _factory;

    public ImportedContactsIdempotencyTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
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

    private HttpRequestMessage CreateAuthenticatedRequest(
        HttpMethod method,
        string url,
        string token,
        object? content = null,
        string? idempotencyKey = null)
    {
        var request = new HttpRequestMessage(method, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (!string.IsNullOrEmpty(idempotencyKey))
        {
            request.Headers.Add("Idempotency-Key", idempotencyKey);
        }
        if (content != null)
        {
            request.Content = JsonContent.Create(content);
        }
        return request;
    }

    [Fact]
    public async Task TEST1_SaveWithIdempotencyKey_ReturnsCreated()
    {
        var auth = await RegisterUserAsync($"idemp_user1_{Guid.NewGuid()}@example.com");
        var key = Guid.NewGuid().ToString("N");

        var payload = new SaveImportedContactRequest
        {
            FullName = "Alice Johnson",
            Company = "Tech Corp",
            JobTitle = "Staff Engineer",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+1 415 555 2671", Label = "Work" }
            },
            EmailAddresses = new List<ImportedContactEmailDto>
            {
                new() { Email = "alice@techcorp.com", Label = "Work" }
            }
        };

        var response = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, payload, key));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var createdContact = await response.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(createdContact);
        Assert.NotEqual(Guid.Empty, createdContact.Id);
        Assert.Equal("Alice Johnson", createdContact.FullName);
        Assert.Equal(key, createdContact.ClientRequestId);
    }

    [Fact]
    public async Task TEST2_RepeatingSameRequest_ReturnsSameContactWithoutDuplication()
    {
        var auth = await RegisterUserAsync($"idemp_user2_{Guid.NewGuid()}@example.com");
        var key = Guid.NewGuid().ToString("N");

        var payload = new SaveImportedContactRequest
        {
            FullName = "Bob Smith",
            Company = "Design Studio",
            JobTitle = "Principal Designer",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+1 212 555 8899", Label = "Mobile" }
            },
            EmailAddresses = new List<ImportedContactEmailDto>
            {
                new() { Email = "bob@designstudio.com", Label = "Work" }
            }
        };

        // First attempt
        var response1 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, payload, key));
        Assert.Equal(HttpStatusCode.Created, response1.StatusCode);
        var contact1 = await response1.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(contact1);

        // Second attempt with exact same key and payload
        var response2 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, payload, key));
        Assert.True(response2.StatusCode == HttpStatusCode.Created || response2.StatusCode == HttpStatusCode.OK);
        var contact2 = await response2.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(contact2);

        // Must return the exact same contact record
        Assert.Equal(contact1.Id, contact2.Id);
        Assert.Equal(contact1.FullName, contact2.FullName);

        // Verify total contacts owned by this user is exactly 1
        var listResponse = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Get, "/api/imported-contacts", auth.Token));
        Assert.Equal(HttpStatusCode.OK, listResponse.StatusCode);
        var contacts = await listResponse.Content.ReadFromJsonAsync<List<ImportedContactResponse>>();
        Assert.NotNull(contacts);
        Assert.Single(contacts);
        Assert.Equal(contact1.Id, contacts[0].Id);
    }

    [Fact]
    public async Task TEST3_ReusingIdempotencyKey_WithDifferentPayload_Returns409Conflict()
    {
        var auth = await RegisterUserAsync($"idemp_user3_{Guid.NewGuid()}@example.com");
        var key = Guid.NewGuid().ToString("N");

        var initialPayload = new SaveImportedContactRequest
        {
            FullName = "Charlie Brown",
            Company = "Peanuts Inc"
        };

        var response1 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, initialPayload, key));
        Assert.Equal(HttpStatusCode.Created, response1.StatusCode);

        // Second attempt with same key but different payload
        var conflictingPayload = new SaveImportedContactRequest
        {
            FullName = "Charlie Different",
            Company = "Other Corp"
        };

        var response2 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, conflictingPayload, key));
        Assert.Equal(HttpStatusCode.Conflict, response2.StatusCode);

        var error = await response2.Content.ReadFromJsonAsync<ErrorResponse>();
        Assert.NotNull(error);
        Assert.Contains("Idempotency key has already been used with a different request payload", error.Message);
    }

    [Fact]
    public async Task TEST4_SameKey_DifferentUsers_SucceedsIndependently()
    {
        var auth1 = await RegisterUserAsync($"idemp_user4a_{Guid.NewGuid()}@example.com");
        var auth2 = await RegisterUserAsync($"idemp_user4b_{Guid.NewGuid()}@example.com");
        var sharedKey = "shared-client-key-42";

        var payload1 = new SaveImportedContactRequest
        {
            FullName = "User One Contact",
            Company = "Company A"
        };

        var payload2 = new SaveImportedContactRequest
        {
            FullName = "User Two Contact",
            Company = "Company B"
        };

        var response1 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth1.Token, payload1, sharedKey));
        Assert.Equal(HttpStatusCode.Created, response1.StatusCode);
        var contact1 = await response1.Content.ReadFromJsonAsync<ImportedContactResponse>();

        var response2 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth2.Token, payload2, sharedKey));
        Assert.Equal(HttpStatusCode.Created, response2.StatusCode);
        var contact2 = await response2.Content.ReadFromJsonAsync<ImportedContactResponse>();

        Assert.NotNull(contact1);
        Assert.NotNull(contact2);
        Assert.NotEqual(contact1.Id, contact2.Id);
        Assert.Equal("User One Contact", contact1.FullName);
        Assert.Equal("User Two Contact", contact2.FullName);
    }

    [Fact]
    public async Task TEST5_RequestWithoutIdempotencyKey_SucceedsNormally()
    {
        var auth = await RegisterUserAsync($"idemp_user5_{Guid.NewGuid()}@example.com");

        var payload1 = new SaveImportedContactRequest
        {
            FullName = "Contact Alpha",
            Company = "Alpha Inc"
        };

        var payload2 = new SaveImportedContactRequest
        {
            FullName = "Contact Beta",
            Company = "Beta Inc"
        };

        // Two calls without Idempotency-Key
        var resp1 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, payload1));
        var resp2 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, payload2));

        Assert.Equal(HttpStatusCode.Created, resp1.StatusCode);
        Assert.Equal(HttpStatusCode.Created, resp2.StatusCode);

        var listResp = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Get, "/api/imported-contacts", auth.Token));
        var contacts = await listResp.Content.ReadFromJsonAsync<List<ImportedContactResponse>>();
        Assert.NotNull(contacts);
        Assert.Equal(2, contacts.Count);
    }

    [Fact]
    public async Task TEST6_IdempotencyKey_Exceeding64Characters_Returns400BadRequest()
    {
        var auth = await RegisterUserAsync($"idemp_user6_{Guid.NewGuid()}@example.com");
        var tooLongKey = new string('x', 65);

        var payload = new SaveImportedContactRequest
        {
            FullName = "Dave LongKey",
            Company = "Long Key Inc"
        };

        var response = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, payload, tooLongKey));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var error = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        Assert.NotNull(error);
        Assert.Contains("cannot exceed 64 characters", error.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task TEST7_ClientRequestIdInBody_ActsAsFallback()
    {
        var auth = await RegisterUserAsync($"idemp_user7_{Guid.NewGuid()}@example.com");
        var bodyKey = "body-key-" + Guid.NewGuid().ToString("N");

        var payload = new SaveImportedContactRequest
        {
            ClientRequestId = bodyKey,
            FullName = "Eva Green",
            Company = "Emerald Corp"
        };

        // Send without header, only body
        var response1 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, payload));
        Assert.Equal(HttpStatusCode.Created, response1.StatusCode);
        var contact1 = await response1.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(contact1);
        Assert.Equal(bodyKey, contact1.ClientRequestId);

        // Repeating same request
        var response2 = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, payload));
        Assert.True(response2.StatusCode == HttpStatusCode.Created || response2.StatusCode == HttpStatusCode.OK);
        var contact2 = await response2.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(contact2);
        Assert.Equal(contact1.Id, contact2.Id);
    }

    [Fact]
    public async Task TEST8_IdempotencyKeyHeader_OverridesBodyClientRequestId()
    {
        var auth = await RegisterUserAsync($"idemp_user8_{Guid.NewGuid()}@example.com");
        var headerKey = "header-key-" + Guid.NewGuid().ToString("N");
        var bodyKey = "body-key-" + Guid.NewGuid().ToString("N");

        var payload = new SaveImportedContactRequest
        {
            ClientRequestId = bodyKey,
            FullName = "Frank Castle",
            Company = "Punisher LLC"
        };

        var response = await _client.SendAsync(
            CreateAuthenticatedRequest(HttpMethod.Post, "/api/imported-contacts", auth.Token, payload, headerKey));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var contact = await response.Content.ReadFromJsonAsync<ImportedContactResponse>();
        Assert.NotNull(contact);
        Assert.Equal(headerKey, contact.ClientRequestId);
    }

    [Fact]
    public async Task TEST9_ServiceLevel_IdempotencyConflict_ThrowsExpectedException()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase("ServiceIdempotencyTestDb_" + Guid.NewGuid())
            .Options;

        using var dbContext = new ApplicationDbContext(options);
        var service = new ImportedContactService(dbContext, NullLogger<ImportedContactService>.Instance);

        var userId = "user-test-service-1";
        var clientRequestId = "req-service-abc";

        var initialRequest = new SaveImportedContactRequest
        {
            FullName = "Initial Name",
            Company = "Initial Co"
        };

        var created = await service.SaveContactAsync(userId, initialRequest, clientRequestId);
        Assert.NotNull(created);
        Assert.Equal("Initial Name", created.FullName);

        // Repeating same request returns created
        var repeated = await service.SaveContactAsync(userId, initialRequest, clientRequestId);
        Assert.Equal(created.Id, repeated.Id);

        // Conflicting request throws IdempotencyConflictException
        var conflictingRequest = new SaveImportedContactRequest
        {
            FullName = "Modified Name",
            Company = "Different Co"
        };

        await Assert.ThrowsAsync<IdempotencyConflictException>(() =>
            service.SaveContactAsync(userId, conflictingRequest, clientRequestId));
    }
}
