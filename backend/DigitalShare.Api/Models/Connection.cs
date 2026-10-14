using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DigitalShare.Api.Models;

/// <summary>
/// Represents a saved Digital Share connection where OwnerUser saved SavedProfile.
/// The connection references the live UserProfile entity so updates made by the profile owner
/// are automatically reflected for connection owners without data duplication.
/// </summary>
public class Connection
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public string OwnerUserId { get; set; } = string.Empty;

    [ForeignKey(nameof(OwnerUserId))]
    public virtual ApplicationUser? OwnerUser { get; set; }

    [Required]
    public Guid SavedProfileId { get; set; }

    [ForeignKey(nameof(SavedProfileId))]
    public virtual UserProfile? SavedProfile { get; set; }

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
