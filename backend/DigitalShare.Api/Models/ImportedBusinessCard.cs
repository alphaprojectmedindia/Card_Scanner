using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DigitalShare.Api.Models;

/// <summary>
/// Represents a physical business card or imported contact saved by a Digital Share user.
/// Stored independently from Digital Share user profiles or connections.
/// </summary>
public class ImportedBusinessCard
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public string OwnerUserId { get; set; } = string.Empty;

    [ForeignKey(nameof(OwnerUserId))]
    public virtual ApplicationUser? OwnerUser { get; set; }

    [MaxLength(64)]
    public string? ClientRequestId { get; set; }

    [MaxLength(64)]
    public string? RequestPayloadHash { get; set; }

    [MaxLength(100)]
    public string? FullName { get; set; }

    [MaxLength(100)]
    public string? Company { get; set; }

    [MaxLength(100)]
    public string? JobTitle { get; set; }

    [MaxLength(256)]
    public string? Website { get; set; }

    [MaxLength(500)]
    public string? Address { get; set; }

    /// <summary>
    /// Optional private personal remark/nickname/note added by the card owner. Max 2,000 characters.
    /// Strictly private to the owner user; NEVER shared in public or cross-user responses.
    /// </summary>
    [MaxLength(2000)]
    public string? PersonalRemark { get; set; }

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;

    public virtual ICollection<ImportedBusinessCardPhone> PhoneNumbers { get; set; } = new List<ImportedBusinessCardPhone>();
    public virtual ICollection<ImportedBusinessCardEmail> EmailAddresses { get; set; } = new List<ImportedBusinessCardEmail>();
}
