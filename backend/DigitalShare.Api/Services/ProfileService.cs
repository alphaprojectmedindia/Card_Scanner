using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.Profile;
using DigitalShare.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace DigitalShare.Api.Services;

public class ProfileService : IProfileService
{
    private readonly ApplicationDbContext _dbContext;
    private readonly IFileStorageService _fileStorageService;
    private readonly ILogger<ProfileService> _logger;

    public const long MaxPhotoSizeBytes = 5 * 1024 * 1024; // 5 MB
    private static readonly HashSet<string> AllowedMimeTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/webp",
        "image/gif"
    };

    public ProfileService(
        ApplicationDbContext dbContext,
        IFileStorageService fileStorageService,
        ILogger<ProfileService> logger)
    {
        _dbContext = dbContext;
        _fileStorageService = fileStorageService;
        _logger = logger;
    }

    public async Task<ProfileResponse?> GetProfileByUserIdAsync(string userId)
    {
        var profile = await _dbContext.UserProfiles
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.UserId == userId);

        if (profile == null)
        {
            return null;
        }

        return MapToResponse(profile);
    }

    public async Task<(bool Success, ProfileResponse? Response, string? Error)> UpdateProfileAsync(string userId, UpdateProfileRequest request)
    {
        var profile = await _dbContext.UserProfiles
            .FirstOrDefaultAsync(p => p.UserId == userId);

        if (profile == null)
        {
            return (false, null, "Profile not found.");
        }

        profile.FullName = request.FullName?.Trim();
        profile.PhoneNumber = request.PhoneNumber?.Trim();
        profile.Email = request.Email.Trim();
        profile.JobTitle = request.JobTitle?.Trim();
        profile.Company = request.Company?.Trim();
        profile.Website = request.Website?.Trim();
        profile.Address = request.Address?.Trim();
        profile.Bio = request.Bio?.Trim();
        profile.ProfilePhotoUrl = request.ProfilePhotoUrl?.Trim();
        profile.UpdatedAtUtc = DateTime.UtcNow;

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Profile updated for user {UserId}", userId);

        return (true, MapToResponse(profile), null);
    }

    public async Task<(bool Success, ProfileResponse? Response, string? Error, int StatusCode)> UploadProfilePhotoAsync(string userId, IFormFile file)
    {
        if (file == null || file.Length == 0)
        {
            return (false, null, "Please select an image file to upload.", StatusCodes.Status400BadRequest);
        }

        if (file.Length > MaxPhotoSizeBytes)
        {
            return (false, null, $"Image size exceeds the maximum allowed limit of {MaxPhotoSizeBytes / (1024 * 1024)} MB.", StatusCodes.Status400BadRequest);
        }

        if (!AllowedMimeTypes.Contains(file.ContentType))
        {
            return (false, null, "Unsupported image format. Allowed formats: JPEG, PNG, WebP, GIF.", StatusCodes.Status400BadRequest);
        }

        var profile = await _dbContext.UserProfiles
            .FirstOrDefaultAsync(p => p.UserId == userId);

        if (profile == null)
        {
            return (false, null, "Profile not found.", StatusCodes.Status404NotFound);
        }

        // Delete old local profile photo if present to avoid disk bloat
        if (!string.IsNullOrWhiteSpace(profile.ProfilePhotoUrl) &&
            profile.ProfilePhotoUrl.StartsWith(LocalFileStorageService.UrlPrefix, StringComparison.OrdinalIgnoreCase))
        {
            await _fileStorageService.DeleteProfilePhotoAsync(profile.ProfilePhotoUrl);
        }

        // Save new photo
        using var stream = file.OpenReadStream();
        var relativeUrl = await _fileStorageService.SaveProfilePhotoAsync(stream, file.FileName, file.ContentType);

        profile.ProfilePhotoUrl = relativeUrl;
        profile.UpdatedAtUtc = DateTime.UtcNow;

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Profile photo updated for user {UserId} at {RelativeUrl}", userId, relativeUrl);

        return (true, MapToResponse(profile), null, StatusCodes.Status200OK);
    }

    private static ProfileResponse MapToResponse(UserProfile profile)
    {
        return new ProfileResponse
        {
            Id = profile.Id,
            UserId = profile.UserId,
            ShareId = profile.ShareId,
            FullName = profile.FullName,
            PhoneNumber = profile.PhoneNumber,
            Email = profile.Email,
            JobTitle = profile.JobTitle,
            Company = profile.Company,
            Website = profile.Website,
            Address = profile.Address,
            Bio = profile.Bio,
            ProfilePhotoUrl = profile.ProfilePhotoUrl,
            CreatedAtUtc = profile.CreatedAtUtc,
            UpdatedAtUtc = profile.UpdatedAtUtc
        };
    }
}
