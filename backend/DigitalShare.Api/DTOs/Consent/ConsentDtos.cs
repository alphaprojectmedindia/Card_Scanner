using System.ComponentModel.DataAnnotations;

namespace DigitalShare.Api.DTOs.Consent;

public class RecordConsentRequest
{
    [Required]
    [MaxLength(50)]
    public string TermsVersion { get; set; } = "2026.1";

    [Required]
    [MaxLength(50)]
    public string PrivacyPolicyVersion { get; set; } = "2026.1";

    [MaxLength(50)]
    public string CookiePolicyVersion { get; set; } = "2026.1";

    [Required]
    [MaxLength(20)]
    public string Jurisdiction { get; set; } = "IN";

    public bool EssentialAccepted { get; set; } = true;

    public bool AnalyticsAccepted { get; set; } = false;
}

public class ConsentStatusResponse
{
    public bool HasAcceptedCurrentTerms { get; set; }
    public string CurrentTermsVersion { get; set; } = "2026.1";
    public string CurrentPrivacyPolicyVersion { get; set; } = "2026.1";
    public string CurrentCookiePolicyVersion { get; set; } = "2026.1";
    public string? UserTermsVersion { get; set; }
    public string? UserPrivacyPolicyVersion { get; set; }
    public string Jurisdiction { get; set; } = "IN";
    public bool EssentialAccepted { get; set; }
    public bool AnalyticsAccepted { get; set; }
    public DateTime? ConsentTimestampUtc { get; set; }
}

public class LegalDocumentResponse
{
    public string Jurisdiction { get; set; } = "IN";
    public string TermsVersion { get; set; } = "2026.1";
    public string PrivacyPolicyVersion { get; set; } = "2026.1";
    public string CookiePolicyVersion { get; set; } = "2026.1";
    public string TermsAndConditionsMarkdown { get; set; } = string.Empty;
    public string PrivacyPolicyMarkdown { get; set; } = string.Empty;
    public string CookiePolicyMarkdown { get; set; } = string.Empty;
    public string GrievanceOfficer { get; set; } = "Grievance Officer, Medindia4u.com";
    public string ContactEmail { get; set; } = "privacy@medindia4u.com";
}

