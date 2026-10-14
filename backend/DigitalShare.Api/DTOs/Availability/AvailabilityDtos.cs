using System.ComponentModel.DataAnnotations;

namespace DigitalShare.Api.DTOs.Availability;

public class AvailabilitySlotDto
{
    public Guid? Id { get; set; }

    [Required]
    public DayOfWeek DayOfWeek { get; set; }

    /// <summary>
    /// Wall-clock start time in "hh:mm" format (e.g., "09:00").
    /// </summary>
    [Required]
    [RegularExpression(@"^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$", ErrorMessage = "StartTime must be in 'hh:mm' 24-hour format.")]
    public string StartTime { get; set; } = string.Empty;

    /// <summary>
    /// Wall-clock end time in "hh:mm" format (e.g., "17:00").
    /// </summary>
    [Required]
    [RegularExpression(@"^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$", ErrorMessage = "EndTime must be in 'hh:mm' 24-hour format.")]
    public string EndTime { get; set; } = string.Empty;
}

public class AvailabilityResponse
{
    public bool MeetingRequestsEnabled { get; set; } = true;
    public string TimeZoneId { get; set; } = "UTC";
    public List<AvailabilitySlotDto> Slots { get; set; } = new();
}

public class UpdateAvailabilityRequest
{
    public bool MeetingRequestsEnabled { get; set; } = true;

    [Required]
    [MaxLength(100)]
    public string TimeZoneId { get; set; } = "UTC";

    public List<AvailabilitySlotDto> Slots { get; set; } = new();
}

public class PublicAvailabilityResponse
{
    public string UserId { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string? ProfilePhotoUrl { get; set; }
    public bool MeetingRequestsEnabled { get; set; } = true;
    public string TimeZoneId { get; set; } = "UTC";
    public List<AvailabilitySlotDto> Slots { get; set; } = new();
}
