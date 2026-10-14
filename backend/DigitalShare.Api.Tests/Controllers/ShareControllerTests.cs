using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Profile;
using DigitalShare.Api.DTOs.Share;
using DigitalShare.Api.Tests.Helpers;

namespace DigitalShare.Api.Tests.Controllers;

public class ShareControllerTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public ShareControllerTests(CustomWebApplicationFactory factory)
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
    public async Task GetSharedProfile_WithValidShareId_ReturnsOkAndSharedProfileResponse()
    {
        // Arrange
        var email = $"person_a_{Guid.NewGuid()}@example.com";
        var (auth, profile) = await RegisterAndGetProfileAsync(email);
        Assert.NotEmpty(profile.ShareId);

        // Update profile with details
        var updateRequest = new HttpRequestMessage(HttpMethod.Put, "/api/profile/me")
        {
            Content = JsonContent.Create(new UpdateProfileRequest
            {
                FullName = "Person Alpha",
                PhoneNumber = "+1-555-0100",
                Email = email,
                JobTitle = "Staff Engineer",
                Company = "Digital Systems",
                Website = "https://alpha.example.com",
                Address = "San Francisco, CA",
                Bio = "Creating innovative digital cards.",
                ProfilePhotoUrl = "https://alpha.example.com/avatar.png"
            })
        };
        updateRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var updateRes = await _client.SendAsync(updateRequest);
        updateRes.EnsureSuccessStatusCode();

        // Act - Person B accesses public share endpoint without authentication
        var response = await _client.GetAsync($"/api/share/{profile.ShareId}");

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var sharedProfile = await response.Content.ReadFromJsonAsync<SharedProfileResponse>();
        Assert.NotNull(sharedProfile);
        Assert.Equal(profile.ShareId, sharedProfile.ShareId);
        Assert.Equal("Person Alpha", sharedProfile.FullName);
        Assert.Equal("+1-555-0100", sharedProfile.PhoneNumber);
        Assert.Equal(email.ToLowerInvariant(), sharedProfile.Email.ToLowerInvariant());
        Assert.Equal("Staff Engineer", sharedProfile.JobTitle);
        Assert.Equal("Digital Systems", sharedProfile.Company);
        Assert.Equal("https://alpha.example.com", sharedProfile.Website);
        Assert.Equal("San Francisco, CA", sharedProfile.Address);
        Assert.Equal("Creating innovative digital cards.", sharedProfile.Bio);
        Assert.Equal("https://alpha.example.com/avatar.png", sharedProfile.ProfilePhotoUrl);
    }

    [Fact]
    public async Task GetSharedProfile_WithNonExistentShareId_ReturnsNotFound()
    {
        // Act
        var response = await _client.GetAsync("/api/share/non_existent_share_id_12345");

        // Assert
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task GetSharedProfile_Response_DoesNotExposeUserIdOrInternalProfileIdOrTimestamps()
    {
        // Arrange
        var email = $"privacy_user_{Guid.NewGuid()}@example.com";
        var (_, profile) = await RegisterAndGetProfileAsync(email);

        // Act
        var response = await _client.GetAsync($"/api/share/{profile.ShareId}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var jsonString = await response.Content.ReadAsStringAsync();
        using var jsonDoc = JsonDocument.Parse(jsonString);
        var root = jsonDoc.RootElement;

        // Assert: Security Boundary Verification
        Assert.False(root.TryGetProperty("userId", out _), "Public response MUST NOT expose userId");
        Assert.False(root.TryGetProperty("id", out _), "Public response MUST NOT expose internal Profile Id");
        Assert.False(root.TryGetProperty("createdAtUtc", out _), "Public response MUST NOT expose internal CreatedAtUtc");
        Assert.False(root.TryGetProperty("updatedAtUtc", out _), "Public response MUST NOT expose internal UpdatedAtUtc");
        Assert.False(root.TryGetProperty("passwordHash", out _), "Public response MUST NOT expose identity security data");
    }

    [Fact]
    public async Task ShareEndpoint_IsPubliclyAccessible_WithoutAuthenticationToken()
    {
        // Arrange
        var email = $"public_card_{Guid.NewGuid()}@example.com";
        var (_, profile) = await RegisterAndGetProfileAsync(email);

        // Clear any authorization headers from client
        var request = new HttpRequestMessage(HttpMethod.Get, $"/api/share/{profile.ShareId}");

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}
