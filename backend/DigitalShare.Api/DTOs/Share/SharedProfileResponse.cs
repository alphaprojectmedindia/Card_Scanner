namespace DigitalShare.Api.DTOs.Share;

/// <summary>
/// Dedicated public response DTO representing a scanned/shared digital contact card.
/// SECURITY BOUNDARY: This DTO acts as the security boundary for publicly accessible QR-shared data.
/// It strictly excludes internal database identifiers, UserId, timestamps, and Identity security properties.
/// </summary>
public class SharedProfileResponse
{
    public string ShareId { get; set; } = string.Empty;
    public string? FullName { get; set; }
    public string? PhoneNumber { get; set; }
    public string Email { get; set; } = string.Empty;
    public string? JobTitle { get; set; }
    public string? Company { get; set; }
    public string? Website { get; set; }
    public string? Address { get; set; }
    public string? Bio { get; set; }
    public string? ProfilePhotoUrl { get; set; }
}
