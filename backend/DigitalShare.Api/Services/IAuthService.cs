using DigitalShare.Api.DTOs.Auth;

namespace DigitalShare.Api.Services;

public interface IAuthService
{
    Task<(bool Success, AuthResponse? Response, IEnumerable<string>? Errors)> RegisterAsync(RegisterRequest request);
    Task<(bool Success, AuthResponse? Response, string? Error)> LoginAsync(LoginRequest request);
}
