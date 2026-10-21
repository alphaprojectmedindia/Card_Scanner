using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.Services;
using DigitalShare.Api.Tests.Helpers;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace DigitalShare.Api.Tests.Controllers;

public class RefreshTokenTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;
    private readonly HttpClient _client;

    public RefreshTokenTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    private async Task<(string Email, string Password, AuthResponse InitialAuth)> RegisterTestUserAsync()
    {
        var email = $"refreshtest_{Guid.NewGuid()}@example.com";
        var password = "Password123!";
        var registerRequest = new RegisterRequest
        {
            Email = email,
            Password = password,
            ConfirmPassword = password
        };

        var response = await _client.PostAsJsonAsync("/api/auth/register", registerRequest);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var authResponse = await response.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(authResponse);
        Assert.NotEmpty(authResponse.AccessToken);
        Assert.NotEmpty(authResponse.RefreshToken);

        return (email, password, authResponse);
    }

    [Fact]
    public async Task Test01_Login_Returns_Both_AccessToken_And_RefreshToken()
    {
        // Arrange
        var (email, password, _) = await RegisterTestUserAsync();
        var loginRequest = new LoginRequest { Email = email, Password = password };

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/login", loginRequest);

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var auth = await response.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);

        // Verify both standard and backward-compatible fields are populated
        Assert.NotEmpty(auth.AccessToken);
        Assert.NotEmpty(auth.RefreshToken);
        Assert.NotEmpty(auth.Token); // backward compatibility
        Assert.True(auth.AccessTokenExpiresAt > DateTime.UtcNow);
        Assert.True(auth.RefreshTokenExpiresAt > DateTime.UtcNow);
    }

    [Fact]
    public async Task Test02_And_03_Raw_RefreshToken_Is_NEVER_Stored_In_Database_Only_Hash()
    {
        // Arrange
        var (_, _, registerAuth) = await RegisterTestUserAsync();
        var rawRefreshToken = registerAuth.RefreshToken;
        Assert.NotEmpty(rawRefreshToken);

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

        // Assert: Raw token string does NOT exist anywhere in RefreshTokens table
        var rawMatch = await db.RefreshTokens.AnyAsync(r => r.TokenHash == rawRefreshToken);
        Assert.False(rawMatch, "Security Failure: Raw refresh token was found in database!");

        // Assert: Computed SHA-256 hash DOES match
        var expectedHash = AuthService.HashToken(rawRefreshToken);
        var tokenRecord = await db.RefreshTokens.FirstOrDefaultAsync(r => r.TokenHash == expectedHash);
        Assert.NotNull(tokenRecord);
        Assert.NotEqual(rawRefreshToken, tokenRecord.TokenHash);
        Assert.Equal(registerAuth.UserId, tokenRecord.UserId);
        Assert.False(tokenRecord.IsRevoked);
        Assert.False(tokenRecord.IsExpired);
    }

    [Fact]
    public async Task Test04_And_05_Valid_Refresh_Issues_New_AccessToken_And_Rotates_RefreshToken()
    {
        // Arrange
        var (_, _, initialAuth) = await RegisterTestUserAsync();
        var refreshRequest = new RefreshTokenRequest { RefreshToken = initialAuth.RefreshToken };

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/refresh", refreshRequest);

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var newAuth = await response.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(newAuth);

        // New access token issued
        Assert.NotEmpty(newAuth.AccessToken);
        // Refresh token rotated (new token is DIFFERENT from old one)
        Assert.NotEmpty(newAuth.RefreshToken);
        Assert.NotEqual(initialAuth.RefreshToken, newAuth.RefreshToken);

        // Verify in database: Old token is revoked and linked to replacement
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var oldHash = AuthService.HashToken(initialAuth.RefreshToken);
        var oldRecord = await db.RefreshTokens.FirstOrDefaultAsync(r => r.TokenHash == oldHash);
        Assert.NotNull(oldRecord);
        Assert.True(oldRecord.IsRevoked);
        Assert.NotNull(oldRecord.RevokedAtUtc);
        Assert.NotNull(oldRecord.ReplacedByTokenId);

        // Verify new token exists and is active
        var newHash = AuthService.HashToken(newAuth.RefreshToken);
        var newRecord = await db.RefreshTokens.FirstOrDefaultAsync(r => r.TokenHash == newHash);
        Assert.NotNull(newRecord);
        Assert.Equal(oldRecord.ReplacedByTokenId, newRecord.Id);
        Assert.False(newRecord.IsRevoked);
        Assert.False(newRecord.IsExpired);
    }

    [Fact]
    public async Task Test06_Old_Rotated_RefreshToken_Cannot_Be_Reused_And_Triggers_Reuse_Revocation()
    {
        // Arrange
        var (_, _, initialAuth) = await RegisterTestUserAsync();
        var refreshRequest = new RefreshTokenRequest { RefreshToken = initialAuth.RefreshToken };

        // First refresh: succeeds and rotates token
        var firstResponse = await _client.PostAsJsonAsync("/api/auth/refresh", refreshRequest);
        Assert.Equal(HttpStatusCode.OK, firstResponse.StatusCode);
        var rotatedAuth = await firstResponse.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(rotatedAuth);

        // Act: Attacker attempts to REUSE old refresh token
        var reuseResponse = await _client.PostAsJsonAsync("/api/auth/refresh", refreshRequest);

        // Assert: Reuse rejected
        Assert.Equal(HttpStatusCode.Unauthorized, reuseResponse.StatusCode);

        // Assert: Reuse detection revokes all active tokens for this user
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

        var rotatedHash = AuthService.HashToken(rotatedAuth.RefreshToken);
        var rotatedRecord = await db.RefreshTokens.FirstOrDefaultAsync(r => r.TokenHash == rotatedHash);
        Assert.NotNull(rotatedRecord);
        Assert.True(rotatedRecord.IsRevoked, "Security Rule: Reuse of rotated token must revoke all active tokens in family!");
    }

    [Fact]
    public async Task Test07_Expired_RefreshToken_Is_Rejected()
    {
        // Arrange
        var (_, _, initialAuth) = await RegisterTestUserAsync();

        // Expire the token artificially in DB
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var hash = AuthService.HashToken(initialAuth.RefreshToken);
            var record = await db.RefreshTokens.FirstAsync(r => r.TokenHash == hash);
            record.ExpiresAtUtc = DateTime.UtcNow.AddMinutes(-5); // Expired 5 mins ago
            await db.SaveChangesAsync();
        }

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/refresh", new RefreshTokenRequest
        {
            RefreshToken = initialAuth.RefreshToken
        });

        // Assert
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Test08_Revoked_RefreshToken_Is_Rejected()
    {
        // Arrange
        var (_, _, initialAuth) = await RegisterTestUserAsync();

        // Explicitly revoke in DB
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var hash = AuthService.HashToken(initialAuth.RefreshToken);
            var record = await db.RefreshTokens.FirstAsync(r => r.TokenHash == hash);
            record.RevokedAtUtc = DateTime.UtcNow;
            await db.SaveChangesAsync();
        }

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/refresh", new RefreshTokenRequest
        {
            RefreshToken = initialAuth.RefreshToken
        });

        // Assert
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Test09_Random_Invalid_RefreshToken_Is_Rejected()
    {
        // Arrange: completely fabricated token
        var randomToken = "random_unregistered_token_xyz_1234567890abcdef";

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/refresh", new RefreshTokenRequest
        {
            RefreshToken = randomToken
        });

        // Assert
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Test10_Missing_Or_Empty_RefreshToken_Returns_BadRequest()
    {
        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/refresh", new RefreshTokenRequest
        {
            RefreshToken = ""
        });

        // Assert
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Test11_RefreshToken_Belonging_To_Deleted_User_Is_Rejected()
    {
        // Arrange
        var (_, _, initialAuth) = await RegisterTestUserAsync();

        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var user = await db.Users.FindAsync(initialAuth.UserId);
            if (user != null)
            {
                // Delete user (cascade removes tokens, or if orphaned, User is null)
                db.Users.Remove(user);
                await db.SaveChangesAsync();
            }
        }

        // Act
        var response = await _client.PostAsJsonAsync("/api/auth/refresh", new RefreshTokenRequest
        {
            RefreshToken = initialAuth.RefreshToken
        });

        // Assert
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Test12_Logout_Revokes_Current_RefreshToken()
    {
        // Arrange
        var (_, _, initialAuth) = await RegisterTestUserAsync();

        // Act: Logout with refresh token
        var logoutResponse = await _client.PostAsJsonAsync("/api/auth/logout", new RevokeTokenRequest
        {
            RefreshToken = initialAuth.RefreshToken
        });
        Assert.Equal(HttpStatusCode.OK, logoutResponse.StatusCode);

        // Verify in DB that token is revoked
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var hash = AuthService.HashToken(initialAuth.RefreshToken);
            var record = await db.RefreshTokens.FirstOrDefaultAsync(r => r.TokenHash == hash);
            Assert.NotNull(record);
            Assert.True(record.IsRevoked);
        }

        // Assert: Subsequent attempt to refresh using that token fails
        var refreshResponse = await _client.PostAsJsonAsync("/api/auth/refresh", new RefreshTokenRequest
        {
            RefreshToken = initialAuth.RefreshToken
        });
        Assert.Equal(HttpStatusCode.Unauthorized, refreshResponse.StatusCode);
    }

    [Fact]
    public async Task Test13_LogoutAll_Revokes_All_User_RefreshTokens()
    {
        // Arrange: User logs in from 2 devices (Device A and Device B)
        var (email, password, _) = await RegisterTestUserAsync();

        // Device A login
        var loginA = await _client.PostAsJsonAsync("/api/auth/login", new LoginRequest { Email = email, Password = password });
        var authA = await loginA.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(authA);

        // Device B login
        var loginB = await _client.PostAsJsonAsync("/api/auth/login", new LoginRequest { Email = email, Password = password });
        var authB = await loginB.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(authB);

        // Act: Device A calls /logout-all with its access token
        using var authedClient = _factory.CreateClient();
        authedClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", authA.AccessToken);

        var logoutAllResponse = await authedClient.PostAsync("/api/auth/logout-all", null);
        Assert.Equal(HttpStatusCode.OK, logoutAllResponse.StatusCode);

        // Assert: Neither Device A nor Device B can refresh anymore
        var refreshA = await _client.PostAsJsonAsync("/api/auth/refresh", new RefreshTokenRequest { RefreshToken = authA.RefreshToken });
        Assert.Equal(HttpStatusCode.Unauthorized, refreshA.StatusCode);

        var refreshB = await _client.PostAsJsonAsync("/api/auth/refresh", new RefreshTokenRequest { RefreshToken = authB.RefreshToken });
        Assert.Equal(HttpStatusCode.Unauthorized, refreshB.StatusCode);
    }

    [Fact]
    public async Task Test14_New_AccessToken_Can_Access_Protected_Endpoints()
    {
        // Arrange
        var (_, _, initialAuth) = await RegisterTestUserAsync();

        // Refresh to get new access token
        var refreshResponse = await _client.PostAsJsonAsync("/api/auth/refresh", new RefreshTokenRequest
        {
            RefreshToken = initialAuth.RefreshToken
        });
        Assert.Equal(HttpStatusCode.OK, refreshResponse.StatusCode);
        var refreshedAuth = await refreshResponse.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(refreshedAuth);

        // Act: Call protected endpoint /api/profile/me with the refreshed access token
        using var authedClient = _factory.CreateClient();
        authedClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", refreshedAuth.AccessToken);

        var profileResponse = await authedClient.GetAsync("/api/profile/me");

        // Assert: 200 OK
        Assert.Equal(HttpStatusCode.OK, profileResponse.StatusCode);
    }
}
