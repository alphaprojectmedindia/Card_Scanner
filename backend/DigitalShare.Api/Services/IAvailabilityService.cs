using DigitalShare.Api.DTOs.Availability;

namespace DigitalShare.Api.Services;

public interface IAvailabilityService
{
    Task<AvailabilityResponse> GetAvailabilityAsync(string userId);

    Task<(bool Success, AvailabilityResponse? Response, string? Error, int StatusCode)> UpdateAvailabilityAsync(
        string userId, UpdateAvailabilityRequest request);

    Task<(bool Success, PublicAvailabilityResponse? Response, string? Error, int StatusCode)> GetPublicAvailabilityAsync(
        string requesterUserId, string targetUserId);
}
