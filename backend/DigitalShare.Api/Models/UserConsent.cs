using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DigitalShare.Api.Models;

/// <summary>
/// Auditable legal consent record capturing user acceptance of Terms of Service,
/// Privacy Policy, and Cookie preferences by jurisdiction.
/// Newer consents are appended without mutating or overwriting historical records.
/// </summary>
public class UserConsent
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public string UserId { get; set; } = string.Empty;

    [ForeignKey(nameof(UserId))]
    public virtual ApplicationUser? User { get; set; }

    [Required]
    [MaxLength(50)]
    public string TermsVersion { get; set; } = "2026.1";

    [Required]
    [MaxLength(50)]
    public string PrivacyPolicyVersion { get; set; } = "2026.1";

    [Required]
    [MaxLength(50)]
    public string CookiePolicyVersion { get; set; } = "2026.1";

    [Required]
    [MaxLength(20)]
    public string Jurisdiction { get; set; } = "IN";

    public bool EssentialAccepted { get; set; } = true;

    public bool AnalyticsAccepted { get; set; } = false;

    [Required]
    public DateTime ConsentTimestampUtc { get; set; } = DateTime.UtcNow;

    [Required]
    [MaxLength(30)]
    public string Status { get; set; } = "Active";

    [MaxLength(100)]
    public string? IpAddress { get; set; }

    [MaxLength(500)]
    public string? UserAgent { get; set; }
}

