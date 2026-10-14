namespace DigitalShare.Api.DTOs.Connections;

/// <summary>
/// Response representing a saved Digital Share contact connection.
/// Contains the live profile fields of the saved user and the saved timestamp.
/// Excludes internal database IDs, OwnerUserId, SavedProfileId, and identity details.
/// </summary>
public class ConnectionResponse
{
    public string ShareId { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string? PhoneNumber { get; set; }
    public string? Email { get; set; }
    public string? JobTitle { get; set; }
    public string? Company { get; set; }
    public string? Website { get; set; }
    public string? Address { get; set; }
    public string? Bio { get; set; }
    public string? ProfilePhotoUrl { get; set; }
    public DateTime SavedAtUtc { get; set; }
}
