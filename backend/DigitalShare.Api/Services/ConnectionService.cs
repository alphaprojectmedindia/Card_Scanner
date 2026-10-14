using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.Connections;
using DigitalShare.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace DigitalShare.Api.Services;

public class ConnectionService : IConnectionService
{
    private readonly ApplicationDbContext _dbContext;
    private readonly ILogger<ConnectionService> _logger;

    public ConnectionService(ApplicationDbContext dbContext, ILogger<ConnectionService> logger)
    {
        _dbContext = dbContext;
        _logger = logger;
    }

    public async Task<(bool Success, ConnectionResponse? Response, string? Error, int StatusCode)> SaveConnectionAsync(string ownerUserId, string shareId)
    {
        if (string.IsNullOrWhiteSpace(ownerUserId))
        {
            return (false, null, "Invalid user context.", 401);
        }

        if (string.IsNullOrWhiteSpace(shareId))
        {
            return (false, null, "ShareId is required.", 400);
        }

        var normalizedShareId = shareId.Trim();

        // 1. Resolve target profile from ShareId
        var targetProfile = await _dbContext.UserProfiles
            .FirstOrDefaultAsync(p => p.ShareId == normalizedShareId);

        if (targetProfile == null)
        {
            return (false, null, "Shared profile not found.", 404);
        }

        // 2. Prevent self-saving
        if (targetProfile.UserId == ownerUserId)
        {
            return (false, null, "You cannot save your own profile as a connection.", 400);
        }

        // 3. Prevent duplicate saves
        var alreadySaved = await _dbContext.Connections
            .AnyAsync(c => c.OwnerUserId == ownerUserId && c.SavedProfileId == targetProfile.Id);

        if (alreadySaved)
        {
            return (false, null, "This profile is already saved.", 409);
        }

        // 4. Create and persist connection
        var connection = new Connection
        {
            OwnerUserId = ownerUserId,
            SavedProfileId = targetProfile.Id,
            CreatedAtUtc = DateTime.UtcNow
        };

        _dbContext.Connections.Add(connection);
        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("User {OwnerUserId} saved connection to profile {ShareId}", ownerUserId, targetProfile.ShareId);

        var response = new ConnectionResponse
        {
            ShareId = targetProfile.ShareId,
            FullName = targetProfile.FullName ?? string.Empty,
            PhoneNumber = targetProfile.PhoneNumber,
            Email = targetProfile.Email,
            JobTitle = targetProfile.JobTitle,
            Company = targetProfile.Company,
            Website = targetProfile.Website,
            Address = targetProfile.Address,
            Bio = targetProfile.Bio,
            ProfilePhotoUrl = targetProfile.ProfilePhotoUrl,
            SavedAtUtc = connection.CreatedAtUtc
        };

        return (true, response, null, 201);
    }

    public async Task<IEnumerable<ConnectionResponse>> GetConnectionsAsync(string ownerUserId)
    {
        if (string.IsNullOrWhiteSpace(ownerUserId))
        {
            return Enumerable.Empty<ConnectionResponse>();
        }

        // Live profile reference: Join to live UserProfile so any updates made by Person A
        // are dynamically reflected to Person B on every fetch.
        var connections = await _dbContext.Connections
            .AsNoTracking()
            .Where(c => c.OwnerUserId == ownerUserId)
            .Include(c => c.SavedProfile)
            .OrderByDescending(c => c.CreatedAtUtc)
            .ToListAsync();

        return connections
            .Where(c => c.SavedProfile != null)
            .Select(c => new ConnectionResponse
            {
                ShareId = c.SavedProfile!.ShareId,
                FullName = c.SavedProfile.FullName ?? string.Empty,
                PhoneNumber = c.SavedProfile.PhoneNumber,
                Email = c.SavedProfile.Email,
                JobTitle = c.SavedProfile.JobTitle,
                Company = c.SavedProfile.Company,
                Website = c.SavedProfile.Website,
                Address = c.SavedProfile.Address,
                Bio = c.SavedProfile.Bio,
                ProfilePhotoUrl = c.SavedProfile.ProfilePhotoUrl,
                SavedAtUtc = c.CreatedAtUtc
            });
    }

    public async Task<bool> DeleteConnectionAsync(string ownerUserId, string shareId)
    {
        if (string.IsNullOrWhiteSpace(ownerUserId) || string.IsNullOrWhiteSpace(shareId))
        {
            return false;
        }

        var normalizedShareId = shareId.Trim();

        var connection = await _dbContext.Connections
            .Include(c => c.SavedProfile)
            .FirstOrDefaultAsync(c => c.OwnerUserId == ownerUserId && c.SavedProfile != null && c.SavedProfile.ShareId == normalizedShareId);

        if (connection == null)
        {
            return false;
        }

        _dbContext.Connections.Remove(connection);
        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("User {OwnerUserId} removed connection to profile {ShareId}", ownerUserId, normalizedShareId);
        return true;
    }
}
