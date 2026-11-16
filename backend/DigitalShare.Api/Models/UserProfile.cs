using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DigitalShare.Api.Models;

public class UserProfile
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public string UserId { get; set; } = string.Empty;

    [ForeignKey(nameof(UserId))]
    public virtual ApplicationUser? User { get; set; }

    /// <summary>
    /// Permanent cryptographically-strong public sharing identifier used for QR sharing.
    /// </summary>
    [Required]
    [MaxLength(50)]
    public string ShareId { get; set; } = string.Empty;

    [MaxLength(100)]
    public string? FullName { get; set; }

    [MaxLength(30)]
    public string? PhoneNumber { get; set; }

    [Required]
    [MaxLength(256)]
    public string Email { get; set; } = string.Empty;

    [MaxLength(100)]
    public string? JobTitle { get; set; }

    [MaxLength(100)]
    public string? Company { get; set; }

    [MaxLength(256)]
    public string? Website { get; set; }

    [MaxLength(256)]
    public string? Address { get; set; }

    [MaxLength(1000)]
    public string? Bio { get; set; }

    [MaxLength(500)]
    public string? ProfilePhotoUrl { get; set; }

    /// <summary>
    /// Account visibility: true for Public (discoverable via search), false for Private (hidden from public discovery).
    /// Defaults to false (Private).
    /// </summary>
    public bool IsPublic { get; set; } = false;

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;

    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;
}
