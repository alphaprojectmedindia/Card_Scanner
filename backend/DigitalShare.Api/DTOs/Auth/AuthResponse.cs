namespace DigitalShare.Api.DTOs.Auth;

public class AuthResponse
{
    // Legacy compatibility
    public string Token { get; set; } = string.Empty;
    public DateTime ExpirationUtc { get; set; }

    // Standard naming
    public string AccessToken { get; set; } = string.Empty;
    public string RefreshToken { get; set; } = string.Empty;
    public DateTime AccessTokenExpiresAt { get; set; }
    public DateTime RefreshTokenExpiresAt { get; set; }

    public string UserId { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
}
