using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Connections;
using DigitalShare.Api.DTOs.Profile;
using DigitalShare.Api.Tests.Helpers;

namespace DigitalShare.Api.Tests.Controllers;

public class ConnectionsControllerTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public ConnectionsControllerTests(CustomWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
    }

    private async Task<(AuthResponse Auth, ProfileResponse Profile)> RegisterAndGetProfileAsync(string email)
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

        var profileRequest = new HttpRequestMessage(HttpMethod.Get, "/api/profile/me");
        profileRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var profileResponse = await _client.SendAsync(profileRequest);
        profileResponse.EnsureSuccessStatusCode();

        var profile = await profileResponse.Content.ReadFromJsonAsync<ProfileResponse>();
        Assert.NotNull(profile);
        return (auth, profile);
    }

    [Fact]
    public async Task ConnectionsEndpoint_RequiresAuthentication()
    {
        // Act - Unauthenticated POST
        var postRes = await _client.PostAsJsonAsync("/api/connections", new SaveConnectionRequest { ShareId = "any_share_id" });
        Assert.Equal(HttpStatusCode.Unauthorized, postRes.StatusCode);

        // Act - Unauthenticated GET
        var getRes = await _client.GetAsync("/api/connections");
        Assert.Equal(HttpStatusCode.Unauthorized, getRes.StatusCode);

        // Act - Unauthenticated DELETE
        var delRes = await _client.DeleteAsync("/api/connections/any_share_id");
        Assert.Equal(HttpStatusCode.Unauthorized, delRes.StatusCode);
    }

    [Fact]
    public async Task SaveConnection_WhenUserSavesAnotherProfile_ReturnsCreatedAndSavesSuccessfully()
    {
        // Arrange - Create Person A (Target) and Person B (Owner)
        var (authA, profileA) = await RegisterAndGetProfileAsync($"target_a_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"owner_b_{Guid.NewGuid()}@example.com");

        // Act - Person B saves Person A's connection
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/connections")
        {
            Content = JsonContent.Create(new SaveConnectionRequest { ShareId = profileA.ShareId })
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var savedConnection = await response.Content.ReadFromJsonAsync<ConnectionResponse>();
        Assert.NotNull(savedConnection);
        Assert.Equal(profileA.ShareId, savedConnection.ShareId);
        Assert.Equal(profileA.Email.ToLowerInvariant(), savedConnection.Email?.ToLowerInvariant());
    }

    [Fact]
    public async Task SaveConnection_WhenUserSavesThemselves_ReturnsBadRequest()
    {
        // Arrange
        var (auth, profile) = await RegisterAndGetProfileAsync($"self_save_{Guid.NewGuid()}@example.com");

        // Act - Save own ShareId
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/connections")
        {
            Content = JsonContent.Create(new SaveConnectionRequest { ShareId = profile.ShareId })
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SaveConnection_WhenDuplicateSaveAttempted_ReturnsConflict()
    {
        // Arrange
        var (_, profileA) = await RegisterAndGetProfileAsync($"person_a_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"person_b_{Guid.NewGuid()}@example.com");

        var saveRequest = new SaveConnectionRequest { ShareId = profileA.ShareId };

        // First Save
        var req1 = new HttpRequestMessage(HttpMethod.Post, "/api/connections")
        {
            Content = JsonContent.Create(saveRequest)
        };
        req1.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var res1 = await _client.SendAsync(req1);
        Assert.Equal(HttpStatusCode.Created, res1.StatusCode);

        // Duplicate Save
        var req2 = new HttpRequestMessage(HttpMethod.Post, "/api/connections")
        {
            Content = JsonContent.Create(saveRequest)
        };
        req2.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var res2 = await _client.SendAsync(req2);

        // Assert
        Assert.Equal(HttpStatusCode.Conflict, res2.StatusCode);
    }

    [Fact]
    public async Task SaveConnection_WithUnknownShareId_ReturnsNotFound()
    {
        // Arrange
        var (authB, _) = await RegisterAndGetProfileAsync($"user_{Guid.NewGuid()}@example.com");

        // Act
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/connections")
        {
            Content = JsonContent.Create(new SaveConnectionRequest { ShareId = "non_existent_share_id" })
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task GetConnections_ReturnsOnlyCurrentUsersSavedProfiles()
    {
        // Arrange
        var (_, profileA) = await RegisterAndGetProfileAsync($"target1_{Guid.NewGuid()}@example.com");
        var (_, profileB) = await RegisterAndGetProfileAsync($"target2_{Guid.NewGuid()}@example.com");
        var (authUser1, _) = await RegisterAndGetProfileAsync($"user1_{Guid.NewGuid()}@example.com");
        var (authUser2, _) = await RegisterAndGetProfileAsync($"user2_{Guid.NewGuid()}@example.com");

        // User 1 saves target A
        var req1 = new HttpRequestMessage(HttpMethod.Post, "/api/connections")
        {
            Content = JsonContent.Create(new SaveConnectionRequest { ShareId = profileA.ShareId })
        };
        req1.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authUser1.Token);
        var res1 = await _client.SendAsync(req1);
        Assert.Equal(HttpStatusCode.Created, res1.StatusCode);

        // User 2 saves target B
        var req2 = new HttpRequestMessage(HttpMethod.Post, "/api/connections")
        {
            Content = JsonContent.Create(new SaveConnectionRequest { ShareId = profileB.ShareId })
        };
        req2.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authUser2.Token);
        var res2 = await _client.SendAsync(req2);
        Assert.Equal(HttpStatusCode.Created, res2.StatusCode);

        // Act - User 1 gets connections
        var getReq = new HttpRequestMessage(HttpMethod.Get, "/api/connections");
        getReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authUser1.Token);
        var getRes = await _client.SendAsync(getReq);
        Assert.Equal(HttpStatusCode.OK, getRes.StatusCode);

        var user1Connections = await getRes.Content.ReadFromJsonAsync<List<ConnectionResponse>>();
        Assert.NotNull(user1Connections);
        Assert.Single(user1Connections);
        Assert.Equal(profileA.ShareId, user1Connections[0].ShareId);
    }

    [Fact]
    public async Task GetConnections_ReflectsLiveProfileUpdatesFromPersonA()
    {
        // Arrange - Person A & Person B
        var (authA, profileA) = await RegisterAndGetProfileAsync($"alice_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"bob_{Guid.NewGuid()}@example.com");

        // Bob saves Alice
        var saveReq = new HttpRequestMessage(HttpMethod.Post, "/api/connections")
        {
            Content = JsonContent.Create(new SaveConnectionRequest { ShareId = profileA.ShareId })
        };
        saveReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var saveRes = await _client.SendAsync(saveReq);
        Assert.Equal(HttpStatusCode.Created, saveRes.StatusCode);

        // Alice updates her job title and phone number later
        var updateReq = new HttpRequestMessage(HttpMethod.Put, "/api/profile/me")
        {
            Content = JsonContent.Create(new UpdateProfileRequest
            {
                FullName = "Alice Johnson Updated",
                PhoneNumber = "+1-999-888-7777",
                Email = profileA.Email,
                JobTitle = "Principal Architect",
                Company = "Global Cloud Corp"
            })
        };
        updateReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        var updateRes = await _client.SendAsync(updateReq);
        Assert.Equal(HttpStatusCode.OK, updateRes.StatusCode);

        // Act - Bob gets his connections
        var getReq = new HttpRequestMessage(HttpMethod.Get, "/api/connections");
        getReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var getRes = await _client.SendAsync(getReq);
        Assert.Equal(HttpStatusCode.OK, getRes.StatusCode);

        var bobConnections = await getRes.Content.ReadFromJsonAsync<List<ConnectionResponse>>();
        Assert.NotNull(bobConnections);
        Assert.Single(bobConnections);

        // Assert: Live profile reference reflects updated data
        Assert.Equal("Alice Johnson Updated", bobConnections[0].FullName);
        Assert.Equal("+1-999-888-7777", bobConnections[0].PhoneNumber);
        Assert.Equal("Principal Architect", bobConnections[0].JobTitle);
        Assert.Equal("Global Cloud Corp", bobConnections[0].Company);
    }

    [Fact]
    public async Task DeleteConnection_RemovesConnectionAndEnforcesOwnership()
    {
        // Arrange
        var (_, profileA) = await RegisterAndGetProfileAsync($"target_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"owner_{Guid.NewGuid()}@example.com");
        var (authC, _) = await RegisterAndGetProfileAsync($"unrelated_{Guid.NewGuid()}@example.com");

        // Bob saves Target
        var saveReq = new HttpRequestMessage(HttpMethod.Post, "/api/connections")
        {
            Content = JsonContent.Create(new SaveConnectionRequest { ShareId = profileA.ShareId })
        };
        saveReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var saveRes = await _client.SendAsync(saveReq);
        Assert.Equal(HttpStatusCode.Created, saveRes.StatusCode);

        // Act 1: User C attempts to delete Bob's connection -> NotFound
        var delReqUnrelated = new HttpRequestMessage(HttpMethod.Delete, $"/api/connections/{profileA.ShareId}");
        delReqUnrelated.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authC.Token);
        var delResUnrelated = await _client.SendAsync(delReqUnrelated);
        Assert.Equal(HttpStatusCode.NotFound, delResUnrelated.StatusCode);

        // Act 2: Bob deletes his connection -> NoContent
        var delReqBob = new HttpRequestMessage(HttpMethod.Delete, $"/api/connections/{profileA.ShareId}");
        delReqBob.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var delResBob = await _client.SendAsync(delReqBob);
        Assert.Equal(HttpStatusCode.NoContent, delResBob.StatusCode);

        // Verify Bob's connections list is now empty
        var getReq = new HttpRequestMessage(HttpMethod.Get, "/api/connections");
        getReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var getRes = await _client.SendAsync(getReq);
        var connections = await getRes.Content.ReadFromJsonAsync<List<ConnectionResponse>>();
        Assert.NotNull(connections);
        Assert.Empty(connections);
    }

    [Fact]
    public async Task ConnectionResponse_DoesNotExposeSensitiveInternalIds()
    {
        // Arrange
        var (_, profileA) = await RegisterAndGetProfileAsync($"sec_target_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"sec_owner_{Guid.NewGuid()}@example.com");

        var saveReq = new HttpRequestMessage(HttpMethod.Post, "/api/connections")
        {
            Content = JsonContent.Create(new SaveConnectionRequest { ShareId = profileA.ShareId })
        };
        saveReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var saveRes = await _client.SendAsync(saveReq);
        Assert.Equal(HttpStatusCode.Created, saveRes.StatusCode);

        var jsonString = await saveRes.Content.ReadAsStringAsync();
        using var jsonDoc = JsonDocument.Parse(jsonString);
        var root = jsonDoc.RootElement;

        // Assert: Security Boundary
        Assert.False(root.TryGetProperty("ownerUserId", out _));
        Assert.False(root.TryGetProperty("savedProfileId", out _));
        Assert.False(root.TryGetProperty("id", out _));
        Assert.False(root.TryGetProperty("passwordHash", out _));
        Assert.True(root.TryGetProperty("shareId", out _));
        Assert.True(root.TryGetProperty("savedAtUtc", out _));
    }
}
