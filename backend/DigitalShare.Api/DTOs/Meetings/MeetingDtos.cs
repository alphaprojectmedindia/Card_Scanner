using System.ComponentModel.DataAnnotations;

namespace DigitalShare.Api.DTOs.Meetings;

public class CreateMeetingRequest
{
    [Required]
    public string RecipientUserId { get; set; } = string.Empty;

    [Required]
    public DateTime StartAtUtc { get; set; }

    [Required]
    public DateTime EndAtUtc { get; set; }

    [MaxLength(200)]
    public string? Title { get; set; }

    [MaxLength(2000)]
    public string? Note { get; set; }
}

public class MeetingResponse
{
    public Guid Id { get; set; }
    public string RequesterUserId { get; set; } = string.Empty;
    public string RequesterName { get; set; } = string.Empty;
    public string? RequesterPhotoUrl { get; set; }

    public string RecipientUserId { get; set; } = string.Empty;
    public string RecipientName { get; set; } = string.Empty;
    public string? RecipientPhotoUrl { get; set; }

    public DateTime StartAtUtc { get; set; }
    public DateTime EndAtUtc { get; set; }

    public string? Title { get; set; }
    public string? Note { get; set; }
    public string Status { get; set; } = string.Empty;

    public DateTime CreatedAtUtc { get; set; }
    public DateTime UpdatedAtUtc { get; set; }
}

public class MeetingListResponse
{
    public List<MeetingResponse> Upcoming { get; set; } = new();
    public List<MeetingResponse> Requests { get; set; } = new();
    public List<MeetingResponse> History { get; set; } = new();
}
