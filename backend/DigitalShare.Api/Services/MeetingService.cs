using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.Meetings;
using DigitalShare.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace DigitalShare.Api.Services;

public class MeetingService : IMeetingService
{
    private readonly ApplicationDbContext _dbContext;
    private readonly ITimeZoneService _timeZoneService;
    private readonly ILogger<MeetingService> _logger;

    public MeetingService(
        ApplicationDbContext dbContext,
        ITimeZoneService timeZoneService,
        ILogger<MeetingService> logger)
    {
        _dbContext = dbContext;
        _timeZoneService = timeZoneService;
        _logger = logger;
    }

    public async Task<(bool Success, MeetingResponse? Response, string? Error, int StatusCode)> CreateMeetingRequestAsync(
        string requesterUserId, CreateMeetingRequest request)
    {
        if (string.IsNullOrWhiteSpace(requesterUserId))
        {
            return (false, null, "Invalid user context.", 401);
        }

        if (string.IsNullOrWhiteSpace(request.RecipientUserId))
        {
            return (false, null, "RecipientUserId is required.", 400);
        }

        if (requesterUserId == request.RecipientUserId)
        {
            return (false, null, "You cannot request a meeting with yourself.", 400);
        }

        // 1. Recipient user profile check
        var recipientProfile = await _dbContext.UserProfiles
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.UserId == request.RecipientUserId || p.ShareId == request.RecipientUserId);

        if (recipientProfile == null)
        {
            return (false, null, "Recipient profile not found.", 404);
        }

        var resolvedRecipientUserId = recipientProfile.UserId;

        if (requesterUserId == resolvedRecipientUserId)
        {
            return (false, null, "You cannot request a meeting with yourself.", 400);
        }

        var requesterProfile = await _dbContext.UserProfiles
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.UserId == requesterUserId);

        if (requesterProfile == null)
        {
            return (false, null, "Requester profile not found.", 404);
        }

        // 2. Connection check (must have valid Digital Share connection)
        var isConnected = await _dbContext.Connections
            .AsNoTracking()
            .AnyAsync(c =>
                (c.OwnerUserId == requesterUserId && c.SavedProfile != null && c.SavedProfile.UserId == resolvedRecipientUserId) ||
                (c.OwnerUserId == resolvedRecipientUserId && c.SavedProfile != null && c.SavedProfile.UserId == requesterUserId));

        if (!isConnected)
        {
            return (false, null, "You can only request meetings with connected Digital Share users.", 403);
        }

        // 3. Recipient settings check
        var settings = await _dbContext.AvailabilitySettings
            .AsNoTracking()
            .FirstOrDefaultAsync(s => s.UserId == resolvedRecipientUserId);

        if (settings != null && !settings.MeetingRequestsEnabled)
        {
            return (false, null, "Meeting requests are currently unavailable.", 400);
        }

        // 4. Validate time
        if (request.StartAtUtc >= request.EndAtUtc)
        {
            return (false, null, "Meeting start time must be before end time.", 400);
        }

        if (request.StartAtUtc <= DateTime.UtcNow)
        {
            return (false, null, "Meeting start time must be in the future.", 400);
        }

        // 5. Timezone & availability slot validation
        var tzId = settings?.TimeZoneId;
        var localStart = _timeZoneService.ConvertTimeFromUtc(request.StartAtUtc, tzId);
        var localEnd = _timeZoneService.ConvertTimeFromUtc(request.EndAtUtc, tzId);

        if (localStart.Date != localEnd.Date)
        {
            return (false, null, "Meetings spanning across multiple days are not supported.", 400);
        }

        var slots = await _dbContext.AvailabilitySlots
            .AsNoTracking()
            .Where(s => s.UserId == resolvedRecipientUserId && s.DayOfWeek == localStart.DayOfWeek)
            .ToListAsync();

        var localStartTime = localStart.TimeOfDay;
        var localEndTime = localEnd.TimeOfDay;

        var insideSlot = slots.Any(s => s.StartTime <= localStartTime && s.EndTime >= localEndTime);
        if (!insideSlot)
        {
            return (false, null, "Meeting time falls outside the recipient's availability.", 400);
        }

        // 6. Conflict detection with existing ACCEPTED meetings
        var hasConflict = await _dbContext.MeetingRequests
            .AsNoTracking()
            .AnyAsync(m =>
                (m.RecipientUserId == resolvedRecipientUserId || m.RequesterUserId == resolvedRecipientUserId) &&
                m.Status == MeetingStatus.Accepted &&
                request.StartAtUtc < m.EndAtUtc &&
                request.EndAtUtc > m.StartAtUtc);

        if (hasConflict)
        {
            return (false, null, "That time is no longer available.", 409);
        }

        // 7. Persist meeting
        var meeting = new MeetingRequest
        {
            RequesterUserId = requesterUserId,
            RecipientUserId = resolvedRecipientUserId,
            StartAtUtc = request.StartAtUtc,
            EndAtUtc = request.EndAtUtc,
            Title = request.Title?.Trim(),
            Note = request.Note?.Trim(),
            Status = MeetingStatus.Pending,
            CreatedAtUtc = DateTime.UtcNow,
            UpdatedAtUtc = DateTime.UtcNow
        };

        _dbContext.MeetingRequests.Add(meeting);
        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Meeting request created: {MeetingId} from {Requester} to {Recipient}",
            meeting.Id, requesterUserId, resolvedRecipientUserId);

        var response = new MeetingResponse
        {
            Id = meeting.Id,
            RequesterUserId = requesterUserId,
            RequesterName = requesterProfile.FullName ?? string.Empty,
            RequesterPhotoUrl = requesterProfile.ProfilePhotoUrl,
            RecipientUserId = resolvedRecipientUserId,
            RecipientName = recipientProfile.FullName ?? string.Empty,
            RecipientPhotoUrl = recipientProfile.ProfilePhotoUrl,
            StartAtUtc = meeting.StartAtUtc,
            EndAtUtc = meeting.EndAtUtc,
            Title = meeting.Title,
            Note = meeting.Note,
            Status = meeting.Status.ToString(),
            CreatedAtUtc = meeting.CreatedAtUtc,
            UpdatedAtUtc = meeting.UpdatedAtUtc
        };

        return (true, response, null, 201);
    }

    public async Task<MeetingListResponse> GetMeetingsAsync(string userId)
    {
        if (string.IsNullOrWhiteSpace(userId))
        {
            return new MeetingListResponse();
        }

        var meetings = await _dbContext.MeetingRequests
            .AsNoTracking()
            .Where(m => m.RequesterUserId == userId || m.RecipientUserId == userId)
            .OrderByDescending(m => m.StartAtUtc)
            .ToListAsync();

        // Batch load profile details for participants
        var participantUserIds = meetings
            .Select(m => m.RequesterUserId)
            .Concat(meetings.Select(m => m.RecipientUserId))
            .Distinct()
            .ToList();

        var profiles = await _dbContext.UserProfiles
            .AsNoTracking()
            .Where(p => participantUserIds.Contains(p.UserId))
            .ToDictionaryAsync(p => p.UserId);

        var dtos = meetings.Select(m =>
        {
            profiles.TryGetValue(m.RequesterUserId, out var reqProfile);
            profiles.TryGetValue(m.RecipientUserId, out var recProfile);

            return new MeetingResponse
            {
                Id = m.Id,
                RequesterUserId = m.RequesterUserId,
                RequesterName = reqProfile?.FullName ?? string.Empty,
                RequesterPhotoUrl = reqProfile?.ProfilePhotoUrl,
                RecipientUserId = m.RecipientUserId,
                RecipientName = recProfile?.FullName ?? string.Empty,
                RecipientPhotoUrl = recProfile?.ProfilePhotoUrl,
                StartAtUtc = m.StartAtUtc,
                EndAtUtc = m.EndAtUtc,
                Title = m.Title,
                Note = m.Note,
                Status = m.Status.ToString(),
                CreatedAtUtc = m.CreatedAtUtc,
                UpdatedAtUtc = m.UpdatedAtUtc
            };
        }).ToList();

        var now = DateTime.UtcNow;

        return new MeetingListResponse
        {
            Upcoming = dtos
                .Where(m => m.Status == MeetingStatus.Accepted.ToString() && m.EndAtUtc > now)
                .OrderBy(m => m.StartAtUtc)
                .ToList(),
            Requests = dtos
                .Where(m => m.Status == MeetingStatus.Pending.ToString())
                .OrderBy(m => m.StartAtUtc)
                .ToList(),
            History = dtos
                .Where(m => m.Status == MeetingStatus.Rejected.ToString() ||
                            m.Status == MeetingStatus.Cancelled.ToString() ||
                            (m.Status == MeetingStatus.Accepted.ToString() && m.EndAtUtc <= now))
                .OrderByDescending(m => m.StartAtUtc)
                .ToList()
        };
    }

    public async Task<(bool Success, MeetingResponse? Response, string? Error, int StatusCode)> GetMeetingByIdAsync(
        string userId, Guid meetingId)
    {
        if (string.IsNullOrWhiteSpace(userId))
        {
            return (false, null, "Invalid user context.", 401);
        }

        var meeting = await _dbContext.MeetingRequests
            .AsNoTracking()
            .FirstOrDefaultAsync(m => m.Id == meetingId &&
                (m.RequesterUserId == userId || m.RecipientUserId == userId));

        if (meeting == null)
        {
            return (false, null, "Meeting not found.", 404);
        }

        var reqProfile = await _dbContext.UserProfiles
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.UserId == meeting.RequesterUserId);

        var recProfile = await _dbContext.UserProfiles
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.UserId == meeting.RecipientUserId);

        var response = new MeetingResponse
        {
            Id = meeting.Id,
            RequesterUserId = meeting.RequesterUserId,
            RequesterName = reqProfile?.FullName ?? string.Empty,
            RequesterPhotoUrl = reqProfile?.ProfilePhotoUrl,
            RecipientUserId = meeting.RecipientUserId,
            RecipientName = recProfile?.FullName ?? string.Empty,
            RecipientPhotoUrl = recProfile?.ProfilePhotoUrl,
            StartAtUtc = meeting.StartAtUtc,
            EndAtUtc = meeting.EndAtUtc,
            Title = meeting.Title,
            Note = meeting.Note,
            Status = meeting.Status.ToString(),
            CreatedAtUtc = meeting.CreatedAtUtc,
            UpdatedAtUtc = meeting.UpdatedAtUtc
        };

        return (true, response, null, 200);
    }

    public async Task<(bool Success, MeetingResponse? Response, string? Error, int StatusCode)> AcceptMeetingAsync(
        string userId, Guid meetingId)
    {
        if (string.IsNullOrWhiteSpace(userId))
        {
            return (false, null, "Invalid user context.", 401);
        }

        var meeting = await _dbContext.MeetingRequests
            .FirstOrDefaultAsync(m => m.Id == meetingId);

        if (meeting == null)
        {
            return (false, null, "Meeting not found.", 404);
        }

        // Only recipient can accept
        if (meeting.RecipientUserId != userId)
        {
            return (false, null, "Only the meeting recipient can accept this request.", 403);
        }

        if (meeting.Status != MeetingStatus.Pending)
        {
            return (false, null, $"Cannot accept meeting with status '{meeting.Status}'. Only pending requests can be accepted.", 400);
        }

        // Revalidate recipient availability
        var settings = await _dbContext.AvailabilitySettings
            .AsNoTracking()
            .FirstOrDefaultAsync(s => s.UserId == meeting.RecipientUserId);

        var tzId = settings?.TimeZoneId;
        var localStart = _timeZoneService.ConvertTimeFromUtc(meeting.StartAtUtc, tzId);
        var localEnd = _timeZoneService.ConvertTimeFromUtc(meeting.EndAtUtc, tzId);

        var slots = await _dbContext.AvailabilitySlots
            .AsNoTracking()
            .Where(s => s.UserId == meeting.RecipientUserId && s.DayOfWeek == localStart.DayOfWeek)
            .ToListAsync();

        var insideSlot = slots.Any(s => s.StartTime <= localStart.TimeOfDay && s.EndTime >= localEnd.TimeOfDay);
        if (!insideSlot)
        {
            return (false, null, "Meeting time no longer falls within recipient availability.", 400);
        }

        // Recheck conflict against other accepted meetings
        var conflict = await _dbContext.MeetingRequests
            .AsNoTracking()
            .AnyAsync(m =>
                m.Id != meeting.Id &&
                (m.RecipientUserId == meeting.RecipientUserId || m.RequesterUserId == meeting.RecipientUserId) &&
                m.Status == MeetingStatus.Accepted &&
                meeting.StartAtUtc < m.EndAtUtc &&
                meeting.EndAtUtc > m.StartAtUtc);

        if (conflict)
        {
            return (false, null, "That time is no longer available.", 409);
        }

        meeting.Status = MeetingStatus.Accepted;
        meeting.UpdatedAtUtc = DateTime.UtcNow;

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Meeting {MeetingId} accepted by {UserId}", meetingId, userId);

        var reqProfile = await _dbContext.UserProfiles
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.UserId == meeting.RequesterUserId);

        var recProfile = await _dbContext.UserProfiles
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.UserId == meeting.RecipientUserId);

        var response = new MeetingResponse
        {
            Id = meeting.Id,
            RequesterUserId = meeting.RequesterUserId,
            RequesterName = reqProfile?.FullName ?? string.Empty,
            RequesterPhotoUrl = reqProfile?.ProfilePhotoUrl,
            RecipientUserId = meeting.RecipientUserId,
            RecipientName = recProfile?.FullName ?? string.Empty,
            RecipientPhotoUrl = recProfile?.ProfilePhotoUrl,
            StartAtUtc = meeting.StartAtUtc,
            EndAtUtc = meeting.EndAtUtc,
            Title = meeting.Title,
            Note = meeting.Note,
            Status = meeting.Status.ToString(),
            CreatedAtUtc = meeting.CreatedAtUtc,
            UpdatedAtUtc = meeting.UpdatedAtUtc
        };

        return (true, response, null, 200);
    }

    public async Task<(bool Success, MeetingResponse? Response, string? Error, int StatusCode)> RejectMeetingAsync(
        string userId, Guid meetingId)
    {
        if (string.IsNullOrWhiteSpace(userId))
        {
            return (false, null, "Invalid user context.", 401);
        }

        var meeting = await _dbContext.MeetingRequests
            .FirstOrDefaultAsync(m => m.Id == meetingId);

        if (meeting == null)
        {
            return (false, null, "Meeting not found.", 404);
        }

        // Only recipient can reject
        if (meeting.RecipientUserId != userId)
        {
            return (false, null, "Only the meeting recipient can reject this request.", 403);
        }

        if (meeting.Status != MeetingStatus.Pending)
        {
            return (false, null, $"Cannot reject meeting with status '{meeting.Status}'. Only pending requests can be rejected.", 400);
        }

        meeting.Status = MeetingStatus.Rejected;
        meeting.UpdatedAtUtc = DateTime.UtcNow;

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Meeting {MeetingId} rejected by {UserId}", meetingId, userId);

        var reqProfile = await _dbContext.UserProfiles
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.UserId == meeting.RequesterUserId);

        var recProfile = await _dbContext.UserProfiles
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.UserId == meeting.RecipientUserId);

        var response = new MeetingResponse
        {
            Id = meeting.Id,
            RequesterUserId = meeting.RequesterUserId,
            RequesterName = reqProfile?.FullName ?? string.Empty,
            RequesterPhotoUrl = reqProfile?.ProfilePhotoUrl,
            RecipientUserId = meeting.RecipientUserId,
            RecipientName = recProfile?.FullName ?? string.Empty,
            RecipientPhotoUrl = recProfile?.ProfilePhotoUrl,
            StartAtUtc = meeting.StartAtUtc,
            EndAtUtc = meeting.EndAtUtc,
            Title = meeting.Title,
            Note = meeting.Note,
            Status = meeting.Status.ToString(),
            CreatedAtUtc = meeting.CreatedAtUtc,
            UpdatedAtUtc = meeting.UpdatedAtUtc
        };

        return (true, response, null, 200);
    }

    public async Task<(bool Success, MeetingResponse? Response, string? Error, int StatusCode)> CancelMeetingAsync(
        string userId, Guid meetingId)
    {
        if (string.IsNullOrWhiteSpace(userId))
        {
            return (false, null, "Invalid user context.", 401);
        }

        var meeting = await _dbContext.MeetingRequests
            .FirstOrDefaultAsync(m => m.Id == meetingId);

        if (meeting == null)
        {
            return (false, null, "Meeting not found.", 404);
        }

        // Only participants can cancel
        if (meeting.RequesterUserId != userId && meeting.RecipientUserId != userId)
        {
            return (false, null, "You are not a participant in this meeting.", 403);
        }

        if (meeting.Status == MeetingStatus.Cancelled || meeting.Status == MeetingStatus.Rejected)
        {
            return (false, null, $"Meeting is already {meeting.Status.ToString().ToLowerInvariant()}.", 400);
        }

        meeting.Status = MeetingStatus.Cancelled;
        meeting.UpdatedAtUtc = DateTime.UtcNow;

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Meeting {MeetingId} cancelled by {UserId}", meetingId, userId);

        var reqProfile = await _dbContext.UserProfiles
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.UserId == meeting.RequesterUserId);

        var recProfile = await _dbContext.UserProfiles
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.UserId == meeting.RecipientUserId);

        var response = new MeetingResponse
        {
            Id = meeting.Id,
            RequesterUserId = meeting.RequesterUserId,
            RequesterName = reqProfile?.FullName ?? string.Empty,
            RequesterPhotoUrl = reqProfile?.ProfilePhotoUrl,
            RecipientUserId = meeting.RecipientUserId,
            RecipientName = recProfile?.FullName ?? string.Empty,
            RecipientPhotoUrl = recProfile?.ProfilePhotoUrl,
            StartAtUtc = meeting.StartAtUtc,
            EndAtUtc = meeting.EndAtUtc,
            Title = meeting.Title,
            Note = meeting.Note,
            Status = meeting.Status.ToString(),
            CreatedAtUtc = meeting.CreatedAtUtc,
            UpdatedAtUtc = meeting.UpdatedAtUtc
        };

        return (true, response, null, 200);
    }
}
