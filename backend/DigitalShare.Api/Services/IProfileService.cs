using DigitalShare.Api.DTOs.Profile;

namespace DigitalShare.Api.Services;

public interface IProfileService
{
    Task<ProfileResponse?> GetProfileByUserIdAsync(string userId);
    Task<(bool Success, ProfileResponse? Response, string? Error)> UpdateProfileAsync(string userId, UpdateProfileRequest request);
    Task<(bool Success, ProfileResponse? Response, string? Error, int StatusCode)> UploadProfilePhotoAsync(string userId, IFormFile file);
    Task<(bool Success, AccountVisibilityDto? Response, string? Error)> GetVisibilityAsync(string userId);
    Task<(bool Success, AccountVisibilityDto? Response, string? Error)> UpdateVisibilityAsync(string userId, bool isPublic);
    Task<IEnumerable<PublicProfileSearchResultDto>> SearchPublicProfilesAsync(string? query, int limit = 20);
}
