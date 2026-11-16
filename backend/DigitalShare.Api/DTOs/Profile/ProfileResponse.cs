namespace DigitalShare.Api.DTOs.Profile;

public class ProfileResponse
{
    public Guid Id { get; set; }
    public string UserId { get; set; } = string.Empty;
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
    public bool IsPublic { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public DateTime UpdatedAtUtc { get; set; }
}
