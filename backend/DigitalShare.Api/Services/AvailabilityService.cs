using System.Globalization;
using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.Availability;
using DigitalShare.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace DigitalShare.Api.Services;

public class AvailabilityService : IAvailabilityService
{
    private readonly ApplicationDbContext _dbContext;
    private readonly ITimeZoneService _timeZoneService;
    private readonly ILogger<AvailabilityService> _logger;

    public AvailabilityService(
        ApplicationDbContext dbContext,
        ITimeZoneService timeZoneService,
        ILogger<AvailabilityService> logger)
    {
        _dbContext = dbContext;
        _timeZoneService = timeZoneService;
        _logger = logger;
    }

    public async Task<AvailabilityResponse> GetAvailabilityAsync(string userId)
    {
        var settings = await _dbContext.AvailabilitySettings
            .AsNoTracking()
            .FirstOrDefaultAsync(s => s.UserId == userId);

        var slots = await _dbContext.AvailabilitySlots
            .AsNoTracking()
            .Where(s => s.UserId == userId)
            .OrderBy(s => s.DayOfWeek)
            .ThenBy(s => s.StartTime)
            .ToListAsync();

        return new AvailabilityResponse
        {
            MeetingRequestsEnabled = settings?.MeetingRequestsEnabled ?? true,
            TimeZoneId = settings?.TimeZoneId ?? "UTC",
            Slots = slots.Select(s => new AvailabilitySlotDto
            {
                Id = s.Id,
                DayOfWeek = s.DayOfWeek,
                StartTime = s.StartTime.ToString(@"hh\:mm", CultureInfo.InvariantCulture),
                EndTime = s.EndTime.ToString(@"hh\:mm", CultureInfo.InvariantCulture)
            }).ToList()
        };
    }

    public async Task<(bool Success, AvailabilityResponse? Response, string? Error, int StatusCode)> UpdateAvailabilityAsync(
        string userId, UpdateAvailabilityRequest request)
    {
        if (string.IsNullOrWhiteSpace(userId))
        {
            return (false, null, "Invalid user context.", 401);
        }

        // Validate TimeZoneId
        if (string.IsNullOrWhiteSpace(request.TimeZoneId))
        {
            return (false, null, "TimeZoneId is required.", 400);
        }

        if (!_timeZoneService.IsValidTimeZone(request.TimeZoneId))
        {
            return (false, null, $"Timezone '{request.TimeZoneId}' is not recognized.", 400);
        }

        var canonicalTimeZoneId = _timeZoneService.NormalizeToIana(request.TimeZoneId);

        // Validate slot times and overlaps
        var parsedSlots = new List<AvailabilitySlot>();
        var groupedByDay = request.Slots.GroupBy(s => s.DayOfWeek);

        foreach (var group in groupedByDay)
        {
            var daySlots = new List<(TimeSpan Start, TimeSpan End)>();

            foreach (var slotDto in group)
            {
                if (!TimeSpan.TryParseExact(slotDto.StartTime, @"hh\:mm", CultureInfo.InvariantCulture, out var startTime) &&
                    !TimeSpan.TryParse(slotDto.StartTime, CultureInfo.InvariantCulture, out startTime))
                {
                    return (false, null, $"Invalid StartTime format '{slotDto.StartTime}'. Use 'hh:mm'.", 400);
                }

                if (!TimeSpan.TryParseExact(slotDto.EndTime, @"hh\:mm", CultureInfo.InvariantCulture, out var endTime) &&
                    !TimeSpan.TryParse(slotDto.EndTime, CultureInfo.InvariantCulture, out endTime))
                {
                    return (false, null, $"Invalid EndTime format '{slotDto.EndTime}'. Use 'hh:mm'.", 400);
                }

                if (startTime >= endTime)
                {
                    return (false, null, $"StartTime ({slotDto.StartTime}) must be before EndTime ({slotDto.EndTime}) on {group.Key}.", 400);
                }

                daySlots.Add((startTime, endTime));
            }

            // Check for overlaps on the same day
            daySlots.Sort((a, b) => a.Start.CompareTo(b.Start));

            for (int i = 0; i < daySlots.Count - 1; i++)
            {
                var current = daySlots[i];
                var next = daySlots[i + 1];

                // Overlap occurs if current.End > next.Start
                if (current.End > next.Start)
                {
                    return (false, null, $"Overlapping time slots on {group.Key} are not allowed ({current.Start:hh\\:mm}-{current.End:hh\\:mm} overlaps with {next.Start:hh\\:mm}-{next.End:hh\\:mm}).", 400);
                }
            }

            foreach (var (start, end) in daySlots)
            {
                parsedSlots.Add(new AvailabilitySlot
                {
                    UserId = userId,
                    DayOfWeek = group.Key,
                    StartTime = start,
                    EndTime = end,
                    CreatedAtUtc = DateTime.UtcNow,
                    UpdatedAtUtc = DateTime.UtcNow
                });
            }
        }

        // Save or update AvailabilitySettings
        var settings = await _dbContext.AvailabilitySettings
            .FirstOrDefaultAsync(s => s.UserId == userId);

        if (settings == null)
        {
            settings = new AvailabilitySettings
            {
                UserId = userId,
                MeetingRequestsEnabled = request.MeetingRequestsEnabled,
                TimeZoneId = canonicalTimeZoneId,
                CreatedAtUtc = DateTime.UtcNow,
                UpdatedAtUtc = DateTime.UtcNow
            };
            _dbContext.AvailabilitySettings.Add(settings);
        }
        else
        {
            settings.MeetingRequestsEnabled = request.MeetingRequestsEnabled;
            settings.TimeZoneId = canonicalTimeZoneId;
            settings.UpdatedAtUtc = DateTime.UtcNow;
        }

        // Replace slots
        var existingSlots = await _dbContext.AvailabilitySlots
            .Where(s => s.UserId == userId)
            .ToListAsync();

        _dbContext.AvailabilitySlots.RemoveRange(existingSlots);
        _dbContext.AvailabilitySlots.AddRange(parsedSlots);

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Updated availability for user {UserId} with {Count} slots", userId, parsedSlots.Count);

        var response = new AvailabilityResponse
        {
            MeetingRequestsEnabled = settings.MeetingRequestsEnabled,
            TimeZoneId = settings.TimeZoneId,
            Slots = parsedSlots
                .OrderBy(s => s.DayOfWeek)
                .ThenBy(s => s.StartTime)
                .Select(s => new AvailabilitySlotDto
                {
                    Id = s.Id,
                    DayOfWeek = s.DayOfWeek,
                    StartTime = s.StartTime.ToString(@"hh\:mm", CultureInfo.InvariantCulture),
                    EndTime = s.EndTime.ToString(@"hh\:mm", CultureInfo.InvariantCulture)
                }).ToList()
        };

        return (true, response, null, 200);
    }

    public async Task<(bool Success, PublicAvailabilityResponse? Response, string? Error, int StatusCode)> GetPublicAvailabilityAsync(
        string requesterUserId, string targetUserId)
    {
        if (string.IsNullOrWhiteSpace(requesterUserId) || string.IsNullOrWhiteSpace(targetUserId))
        {
            return (false, null, "User IDs are required.", 400);
        }

        var targetProfile = await _dbContext.UserProfiles
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.UserId == targetUserId || p.ShareId == targetUserId);

        if (targetProfile == null)
        {
            return (false, null, "User profile not found.", 404);
        }

        var resolvedTargetUserId = targetProfile.UserId;

        // Check if an active connection exists between requester and target user
        var isConnected = requesterUserId == resolvedTargetUserId || await _dbContext.Connections
            .AsNoTracking()
            .AnyAsync(c =>
                (c.OwnerUserId == requesterUserId && c.SavedProfile != null && c.SavedProfile.UserId == resolvedTargetUserId) ||
                (c.OwnerUserId == resolvedTargetUserId && c.SavedProfile != null && c.SavedProfile.UserId == requesterUserId));

        if (!isConnected)
        {
            return (false, null, "You must have an existing Digital Share connection with this user to view their availability.", 403);
        }

        var settings = await _dbContext.AvailabilitySettings
            .AsNoTracking()
            .FirstOrDefaultAsync(s => s.UserId == resolvedTargetUserId);

        var slots = await _dbContext.AvailabilitySlots
            .AsNoTracking()
            .Where(s => s.UserId == resolvedTargetUserId)
            .OrderBy(s => s.DayOfWeek)
            .ThenBy(s => s.StartTime)
            .ToListAsync();

        var response = new PublicAvailabilityResponse
        {
            UserId = resolvedTargetUserId,
            FullName = targetProfile.FullName ?? string.Empty,
            ProfilePhotoUrl = targetProfile.ProfilePhotoUrl,
            MeetingRequestsEnabled = settings?.MeetingRequestsEnabled ?? true,
            TimeZoneId = settings?.TimeZoneId ?? "UTC",
            Slots = slots.Select(s => new AvailabilitySlotDto
            {
                Id = s.Id,
                DayOfWeek = s.DayOfWeek,
                StartTime = s.StartTime.ToString(@"hh\:mm", CultureInfo.InvariantCulture),
                EndTime = s.EndTime.ToString(@"hh\:mm", CultureInfo.InvariantCulture)
            }).ToList()
        };

        return (true, response, null, 200);
    }
}
