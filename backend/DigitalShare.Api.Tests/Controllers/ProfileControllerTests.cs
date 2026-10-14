using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Profile;
using DigitalShare.Api.Tests.Helpers;

namespace DigitalShare.Api.Tests.Controllers;

public class ProfileControllerTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public ProfileControllerTests(CustomWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
    }

    private async Task<AuthResponse> RegisterAndGetAuthAsync(string email, string password = "Password123!")
    {
        var registerRequest = new RegisterRequest
        {
            Email = email,
            Password = password,
            ConfirmPassword = password
        };

        var response = await _client.PostAsJsonAsync("/api/auth/register", registerRequest);
        response.EnsureSuccessStatusCode();

        var authResponse = await response.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(authResponse);
        return authResponse;
    }

    [Fact]
    public async Task GetProfile_WithoutToken_ReturnsUnauthorized()
    {
        // Act
        var response = await _client.GetAsync("/api/profile/me");

        // Assert
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetProfile_WithValidToken_ReturnsCurrentUserProfile()
    {
        // Arrange
        var email = $"profile_user_{Guid.NewGuid()}@example.com";
        var auth = await RegisterAndGetAuthAsync(email);

        var request = new HttpRequestMessage(HttpMethod.Get, "/api/profile/me");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var profile = await response.Content.ReadFromJsonAsync<ProfileResponse>();
        Assert.NotNull(profile);
        Assert.Equal(auth.UserId, profile.UserId);
        Assert.Equal(email.ToLowerInvariant(), profile.Email.ToLowerInvariant());
    }

    [Fact]
    public async Task ProfileMe_AlwaysReturnsAuthenticatedUsersOwnProfile_CannotAccessAnotherUsersProfile()
    {
        // Arrange - Register User A and User B
        var emailA = $"usera_{Guid.NewGuid()}@example.com";
        var emailB = $"userb_{Guid.NewGuid()}@example.com";

        var authA = await RegisterAndGetAuthAsync(emailA);
        var authB = await RegisterAndGetAuthAsync(emailB);

        // User A updates their profile with distinctive details
        var updateRequestA = new HttpRequestMessage(HttpMethod.Put, "/api/profile/me")
        {
            Content = JsonContent.Create(new UpdateProfileRequest
            {
                FullName = "Alice Wonder",
                Email = emailA,
                JobTitle = "Security Architect",
                Company = "Alice Corp"
            })
        };
        updateRequestA.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        var updateResponseA = await _client.SendAsync(updateRequestA);
        Assert.Equal(HttpStatusCode.OK, updateResponseA.StatusCode);

        // User B requests their own profile using User B's token
        var requestB = new HttpRequestMessage(HttpMethod.Get, "/api/profile/me");
        requestB.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);

        // Act
        var responseB = await _client.SendAsync(requestB);

        // Assert
        Assert.Equal(HttpStatusCode.OK, responseB.StatusCode);
        var profileB = await responseB.Content.ReadFromJsonAsync<ProfileResponse>();

        Assert.NotNull(profileB);
        Assert.Equal(authB.UserId, profileB.UserId);
        Assert.Equal(emailB.ToLowerInvariant(), profileB.Email.ToLowerInvariant());
        Assert.NotEqual("Alice Wonder", profileB.FullName);
        Assert.NotEqual(authA.UserId, profileB.UserId);
    }

    [Fact]
    public async Task UpdateProfile_WithInvalidData_ReturnsBadRequest()
    {
        // Arrange
        var email = $"invalidupdate_{Guid.NewGuid()}@example.com";
        var auth = await RegisterAndGetAuthAsync(email);

        var invalidRequest = new UpdateProfileRequest
        {
            Email = "not-an-email",
            Website = "not-a-valid-url"
        };

        var request = new HttpRequestMessage(HttpMethod.Put, "/api/profile/me")
        {
            Content = JsonContent.Create(invalidRequest)
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task UpdateProfile_WithValidData_UpdatesAndReturnsProfile()
    {
        // Arrange
        var email = $"validupdate_{Guid.NewGuid()}@example.com";
        var auth = await RegisterAndGetAuthAsync(email);

        var updateDto = new UpdateProfileRequest
        {
            FullName = "John Doe",
            PhoneNumber = "+1234567890",
            Email = email,
            JobTitle = "Lead Architect",
            Company = "Tech Innovators",
            Website = "https://example.com",
            Address = "123 Innovation Drive, Silicon Valley, CA",
            Bio = "Passionate engineer building next-gen digital identity solutions.",
            ProfilePhotoUrl = "https://images.example.com/profiles/johndoe.jpg"
        };

        var request = new HttpRequestMessage(HttpMethod.Put, "/api/profile/me")
        {
            Content = JsonContent.Create(updateDto)
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var updatedProfile = await response.Content.ReadFromJsonAsync<ProfileResponse>();
        Assert.NotNull(updatedProfile);
        Assert.Equal(auth.UserId, updatedProfile.UserId);
        Assert.Equal(updateDto.FullName, updatedProfile.FullName);
        Assert.Equal(updateDto.PhoneNumber, updatedProfile.PhoneNumber);
        Assert.Equal(updateDto.Email, updatedProfile.Email);
        Assert.Equal(updateDto.JobTitle, updatedProfile.JobTitle);
        Assert.Equal(updateDto.Company, updatedProfile.Company);
        Assert.Equal(updateDto.Website, updatedProfile.Website);
        Assert.Equal(updateDto.Address, updatedProfile.Address);
        Assert.Equal(updateDto.Bio, updatedProfile.Bio);
        Assert.Equal(updateDto.ProfilePhotoUrl, updatedProfile.ProfilePhotoUrl);
    }

    [Fact]
    public async Task UploadProfilePhoto_WithoutToken_ReturnsUnauthorized()
    {
        using var content = new MultipartFormDataContent();
        var fileContent = new ByteArrayContent(new byte[] { 0xFF, 0xD8, 0xFF, 0xE0 });
        fileContent.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
        content.Add(fileContent, "file", "avatar.jpg");

        var response = await _client.PostAsync("/api/profile/photo", content);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task UploadProfilePhoto_WithValidImage_UploadsAndUpdatesProfilePhotoUrl()
    {
        // Arrange
        var email = $"photouser_{Guid.NewGuid()}@example.com";
        var auth = await RegisterAndGetAuthAsync(email);

        using var content = new MultipartFormDataContent();
        var dummyJpegBytes = new byte[] { 0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46 };
        var fileContent = new ByteArrayContent(dummyJpegBytes);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
        content.Add(fileContent, "file", "my_photo.jpg");

        var request = new HttpRequestMessage(HttpMethod.Post, "/api/profile/photo")
        {
            Content = content
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var profile = await response.Content.ReadFromJsonAsync<ProfileResponse>();
        Assert.NotNull(profile);
        Assert.NotNull(profile.ProfilePhotoUrl);
        Assert.StartsWith("/uploads/profile-photos/", profile.ProfilePhotoUrl);
        Assert.EndsWith(".jpg", profile.ProfilePhotoUrl);

        // Verify static file serving: fetch the uploaded image from the server
        var staticResponse = await _client.GetAsync(profile.ProfilePhotoUrl);
        Assert.Equal(HttpStatusCode.OK, staticResponse.StatusCode);
        var fetchedBytes = await staticResponse.Content.ReadAsByteArrayAsync();
        Assert.Equal(dummyJpegBytes, fetchedBytes);
    }

    [Fact]
    public async Task UploadProfilePhoto_WithUnsupportedMimeType_ReturnsBadRequest()
    {
        // Arrange
        var email = $"unsupportedmime_{Guid.NewGuid()}@example.com";
        var auth = await RegisterAndGetAuthAsync(email);

        using var content = new MultipartFormDataContent();
        var fileContent = new ByteArrayContent("echo hello"u8.ToArray());
        fileContent.Headers.ContentType = new MediaTypeHeaderValue("application/x-sh");
        content.Add(fileContent, "file", "script.sh");

        var request = new HttpRequestMessage(HttpMethod.Post, "/api/profile/photo")
        {
            Content = content
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task UploadProfilePhoto_WithEmptyFile_ReturnsBadRequest()
    {
        // Arrange
        var email = $"emptyfile_{Guid.NewGuid()}@example.com";
        var auth = await RegisterAndGetAuthAsync(email);

        using var content = new MultipartFormDataContent();
        var fileContent = new ByteArrayContent(Array.Empty<byte>());
        fileContent.Headers.ContentType = new MediaTypeHeaderValue("image/png");
        content.Add(fileContent, "file", "empty.png");

        var request = new HttpRequestMessage(HttpMethod.Post, "/api/profile/photo")
        {
            Content = content
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
}
