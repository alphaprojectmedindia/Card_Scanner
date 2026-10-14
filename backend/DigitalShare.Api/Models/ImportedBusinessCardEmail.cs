using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DigitalShare.Api.Models;

/// <summary>
/// Represents an email address associated with an imported physical business card.
/// Stores both the display email and normalized email for duplicate matching.
/// </summary>
public class ImportedBusinessCardEmail
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public Guid ImportedBusinessCardId { get; set; }

    [ForeignKey(nameof(ImportedBusinessCardId))]
    public virtual ImportedBusinessCard? ImportedBusinessCard { get; set; }

    [Required]
    [MaxLength(256)]
    public string Email { get; set; } = string.Empty;

    [Required]
    [MaxLength(256)]
    public string NormalizedEmail { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? Label { get; set; }
}
