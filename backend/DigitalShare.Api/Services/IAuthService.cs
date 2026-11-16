using DigitalShare.Api.DTOs.Auth;

namespace DigitalShare.Api.Services;

public interface IAuthService
{
    Task<(bool Success, AuthResponse? Response, IEnumerable<string>? Errors)> RegisterAsync(RegisterRequest request);
    Task<(bool Success, AuthResponse? Response, string? Error)> LoginAsync(LoginRequest request);
    Task<(bool Success, AuthResponse? Response, string? Error)> RefreshTokenAsync(string rawRefreshToken, string? ipAddress = null);
    Task<bool> RevokeRefreshTokenAsync(string rawRefreshToken, string? ipAddress = null);
    Task<bool> RevokeAllUserRefreshTokensAsync(string userId);
    Task<(bool Success, string? Error)> DeleteAccountAsync(string userId, string password);
}
