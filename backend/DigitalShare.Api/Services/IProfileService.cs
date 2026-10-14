using DigitalShare.Api.DTOs.Profile;

namespace DigitalShare.Api.Services;

public interface IProfileService
{
    Task<ProfileResponse?> GetProfileByUserIdAsync(string userId);
    Task<(bool Success, ProfileResponse? Response, string? Error)> UpdateProfileAsync(string userId, UpdateProfileRequest request);
    Task<(bool Success, ProfileResponse? Response, string? Error, int StatusCode)> UploadProfilePhotoAsync(string userId, IFormFile file);
}
