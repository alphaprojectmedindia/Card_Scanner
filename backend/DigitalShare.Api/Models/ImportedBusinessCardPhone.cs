using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DigitalShare.Api.Models;

/// <summary>
/// Represents a phone number associated with an imported physical business card.
/// Stores both the original display number and normalized number for duplicate matching.
/// </summary>
public class ImportedBusinessCardPhone
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public Guid ImportedBusinessCardId { get; set; }

    [ForeignKey(nameof(ImportedBusinessCardId))]
    public virtual ImportedBusinessCard? ImportedBusinessCard { get; set; }

    [Required]
    [MaxLength(50)]
    public string Number { get; set; } = string.Empty;

    [Required]
    [MaxLength(50)]
    public string NormalizedNumber { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? Label { get; set; }
}
