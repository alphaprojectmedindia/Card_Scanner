using DigitalShare.Api.DTOs.Meetings;

namespace DigitalShare.Api.Services;

public interface IMeetingService
{
    Task<(bool Success, MeetingResponse? Response, string? Error, int StatusCode)> CreateMeetingRequestAsync(
        string requesterUserId, CreateMeetingRequest request);

    Task<MeetingListResponse> GetMeetingsAsync(string userId);

    Task<(bool Success, MeetingResponse? Response, string? Error, int StatusCode)> GetMeetingByIdAsync(
        string userId, Guid meetingId);

    Task<(bool Success, MeetingResponse? Response, string? Error, int StatusCode)> AcceptMeetingAsync(
        string userId, Guid meetingId);

    Task<(bool Success, MeetingResponse? Response, string? Error, int StatusCode)> RejectMeetingAsync(
        string userId, Guid meetingId);

    Task<(bool Success, MeetingResponse? Response, string? Error, int StatusCode)> CancelMeetingAsync(
        string userId, Guid meetingId);
}
