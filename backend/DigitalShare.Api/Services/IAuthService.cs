using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Consent;

namespace DigitalShare.Api.Services;

public interface IAuthService
{
    Task<(bool Success, AuthResponse? Response, IEnumerable<string>? Errors)> RegisterAsync(RegisterRequest request);
    Task<(bool Success, AuthResponse? Response, string? Error)> LoginAsync(LoginRequest request);
    Task<(bool Success, AuthResponse? Response, string? Error)> RefreshTokenAsync(string rawRefreshToken, string? ipAddress = null);
    Task<bool> RevokeRefreshTokenAsync(string rawRefreshToken, string? ipAddress = null);
    Task<bool> RevokeAllUserRefreshTokensAsync(string userId);
    Task<(bool Success, string? Error)> DeleteAccountAsync(string userId, string password);
    Task<ConsentStatusResponse> GetConsentStatusAsync(string userId);
    Task<ConsentStatusResponse> RecordConsentAsync(string userId, RecordConsentRequest request, string? ipAddress = null, string? userAgent = null);
    Task<(bool Success, string Message, string? DebugToken)> ForgotPasswordAsync(ForgotPasswordRequest request);
    Task<(bool Success, string? Error)> ResetPasswordAsync(ResetPasswordRequest request);
}
