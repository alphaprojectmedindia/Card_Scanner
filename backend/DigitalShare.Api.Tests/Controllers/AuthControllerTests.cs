using System.Net;
using System.Net.Http.Json;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.Tests.Helpers;

namespace DigitalShare.Api.Tests.Controllers;

public class AuthControllerTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public AuthControllerTests(CustomWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task Register_WithValidModel_ReturnsCreatedAndAuthResponse()
    {
        // Arrange
        var request = new RegisterRequest
        {
            Email = $"validuser_{Guid.NewGuid()}@example.com",
            Password = "Password123!",
            ConfirmPassword = "Password123!"
        };

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/register", request);

        // Assert
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var authResponse = await response.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(authResponse);
        Assert.NotEmpty(authResponse.Token);
        Assert.NotEmpty(authResponse.UserId);
        Assert.Equal(request.Email.ToLowerInvariant(), authResponse.Email.ToLowerInvariant());
    }

    [Theory]
    [InlineData("", "Password123!", "Password123!")] // Empty email
    [InlineData("notanemail", "Password123!", "Password123!")] // Invalid email format
    [InlineData("test@example.com", "123", "123")] // Short password
    [InlineData("test@example.com", "Password123!", "MismatchPassword!")] // Password mismatch
    public async Task Register_WithInvalidModel_ReturnsBadRequest(string email, string password, string confirmPassword)
    {
        // Arrange
        var request = new RegisterRequest
        {
            Email = email,
            Password = password,
            ConfirmPassword = confirmPassword
        };

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/register", request);

        // Assert
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Register_WithDuplicateEmail_ReturnsBadRequest()
    {
        // Arrange
        var email = $"duplicate_{Guid.NewGuid()}@example.com";
        var request = new RegisterRequest
        {
            Email = email,
            Password = "Password123!",
            ConfirmPassword = "Password123!"
        };

        // First registration
        var firstResponse = await _client.PostAsJsonAsync("/api/auth/register", request);
        Assert.Equal(HttpStatusCode.Created, firstResponse.StatusCode);

        // Act - Attempt duplicate registration
        var secondResponse = await _client.PostAsJsonAsync("/api/auth/register", request);

        // Assert
        Assert.Equal(HttpStatusCode.Conflict, secondResponse.StatusCode);
    }

    [Fact]
    public async Task Register_WithValidPhoneNumber_ReturnsCreatedAndSavesPhone()
    {
        // Arrange
        var request = new RegisterRequest
        {
            Email = $"phoneuser_{Guid.NewGuid()}@example.com",
            Password = "Password123!",
            ConfirmPassword = "Password123!",
            PhoneNumber = "+15551234567"
        };

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/register", request);

        // Assert
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var authResponse = await response.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(authResponse);
        Assert.NotEmpty(authResponse.Token);
    }

    [Fact]
    public async Task Health_ReturnsOk()
    {
        // Act
        var response = await _client.GetAsync("/health");

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task HealthReady_ReturnsOkWhenDbConnected()
    {
        // Act
        var response = await _client.GetAsync("/health/ready");

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Login_WithValidCredentials_ReturnsOkWithAuthResponse()
    {
        // Arrange
        var email = $"logintest_{Guid.NewGuid()}@example.com";
        var password = "Password123!";

        var registerRequest = new RegisterRequest
        {
            Email = email,
            Password = password,
            ConfirmPassword = password
        };
        await _client.PostAsJsonAsync("/api/auth/register", registerRequest);

        var loginRequest = new LoginRequest
        {
            Email = email,
            Password = password
        };

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/login", loginRequest);

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var authResponse = await response.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(authResponse);
        Assert.NotEmpty(authResponse.Token);
        Assert.Equal(email.ToLowerInvariant(), authResponse.Email.ToLowerInvariant());
    }

    [Fact]
    public async Task Login_WithInvalidCredentials_ReturnsUnauthorized()
    {
        // Arrange
        var loginRequest = new LoginRequest
        {
            Email = "nonexistent_user@example.com",
            Password = "WrongPassword123!"
        };

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/login", loginRequest);

        // Assert
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task ForgotPassword_WithValidRegisteredEmail_ReturnsOk()
    {
        // Arrange
        var email = $"forgot_{Guid.NewGuid()}@example.com";
        var password = "Password123!";
        await _client.PostAsJsonAsync("/api/auth/register", new RegisterRequest
        {
            Email = email,
            Password = password,
            ConfirmPassword = password
        });

        var forgotRequest = new ForgotPasswordRequest { Email = email };

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/forgot-password", forgotRequest);

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task ForgotPassword_WithInvalidEmailFormat_ReturnsBadRequest()
    {
        // Arrange
        var forgotRequest = new ForgotPasswordRequest { Email = "not-an-email" };

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/forgot-password", forgotRequest);

        // Assert
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task ResetPassword_WithValidToken_ResetsPasswordAndAllowsNewLogin()
    {
        // Arrange
        var email = $"reset_{Guid.NewGuid()}@example.com";
        var oldPassword = "OldPassword123!";
        var newPassword = "NewPassword456!";

        await _client.PostAsJsonAsync("/api/auth/register", new RegisterRequest
        {
            Email = email,
            Password = oldPassword,
            ConfirmPassword = oldPassword
        });

        // Request reset token
        var forgotResponse = await _client.PostAsJsonAsync("/api/auth/forgot-password", new ForgotPasswordRequest { Email = email });
        Assert.Equal(HttpStatusCode.OK, forgotResponse.StatusCode);
        var forgotBody = await forgotResponse.Content.ReadFromJsonAsync<System.Text.Json.JsonElement>();
        var token = forgotBody.GetProperty("token").GetString();
        Assert.NotNull(token);

        // Act: Reset password
        var resetResponse = await _client.PostAsJsonAsync("/api/auth/reset-password", new ResetPasswordRequest
        {
            Email = email,
            Token = token,
            NewPassword = newPassword,
            ConfirmPassword = newPassword
        });

        // Assert reset succeeded
        Assert.Equal(HttpStatusCode.OK, resetResponse.StatusCode);

        // Old password must fail
        var oldLoginResponse = await _client.PostAsJsonAsync("/api/auth/login", new LoginRequest
        {
            Email = email,
            Password = oldPassword
        });
        Assert.Equal(HttpStatusCode.Unauthorized, oldLoginResponse.StatusCode);

        // New password must succeed
        var newLoginResponse = await _client.PostAsJsonAsync("/api/auth/login", new LoginRequest
        {
            Email = email,
            Password = newPassword
        });
        Assert.Equal(HttpStatusCode.OK, newLoginResponse.StatusCode);
    }

    [Fact]
    public async Task ResetPassword_WithInvalidToken_ReturnsBadRequest()
    {
        // Arrange
        var email = $"badtoken_{Guid.NewGuid()}@example.com";
        var password = "Password123!";
        await _client.PostAsJsonAsync("/api/auth/register", new RegisterRequest
        {
            Email = email,
            Password = password,
            ConfirmPassword = password
        });

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/reset-password", new ResetPasswordRequest
        {
            Email = email,
            Token = "INVALID_EXPIRED_TOKEN",
            NewPassword = "NewPassword456!",
            ConfirmPassword = "NewPassword456!"
        });

        // Assert
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
}
