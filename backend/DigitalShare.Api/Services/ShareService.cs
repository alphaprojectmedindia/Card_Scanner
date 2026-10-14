using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.Share;
using Microsoft.EntityFrameworkCore;

namespace DigitalShare.Api.Services;

public interface IShareService
{
    Task<SharedProfileResponse?> GetSharedProfileByShareIdAsync(string shareId);
}

public class ShareService : IShareService
{
    private readonly ApplicationDbContext _dbContext;
    private readonly ILogger<ShareService> _logger;

    public ShareService(ApplicationDbContext dbContext, ILogger<ShareService> logger)
    {
        _dbContext = dbContext;
        _logger = logger;
    }

    public async Task<SharedProfileResponse?> GetSharedProfileByShareIdAsync(string shareId)
    {
        if (string.IsNullOrWhiteSpace(shareId) || shareId.Length > 50)
        {
            return null;
        }

        var normalizedShareId = shareId.Trim();
        var profile = await _dbContext.UserProfiles
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.ShareId == normalizedShareId);

        if (profile == null)
        {
            _logger.LogInformation("No shared profile found for ShareId {ShareId}", normalizedShareId);
            return null;
        }

        // SECURITY BOUNDARY: Map strictly to SharedProfileResponse
        return new SharedProfileResponse
        {
            ShareId = profile.ShareId,
            FullName = profile.FullName,
            PhoneNumber = profile.PhoneNumber,
            Email = profile.Email,
            JobTitle = profile.JobTitle,
            Company = profile.Company,
            Website = profile.Website,
            Address = profile.Address,
            Bio = profile.Bio,
            ProfilePhotoUrl = profile.ProfilePhotoUrl
        };
    }
}
