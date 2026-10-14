using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DigitalShare.Api.Models;

public class MeetingRequest
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public string RequesterUserId { get; set; } = string.Empty;

    [ForeignKey(nameof(RequesterUserId))]
    public virtual ApplicationUser? RequesterUser { get; set; }

    [Required]
    public string RecipientUserId { get; set; } = string.Empty;

    [ForeignKey(nameof(RecipientUserId))]
    public virtual ApplicationUser? RecipientUser { get; set; }

    [Required]
    public DateTime StartAtUtc { get; set; }

    [Required]
    public DateTime EndAtUtc { get; set; }

    [MaxLength(200)]
    public string? Title { get; set; }

    [MaxLength(2000)]
    public string? Note { get; set; }

    public MeetingStatus Status { get; set; } = MeetingStatus.Pending;

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;

    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;
}
