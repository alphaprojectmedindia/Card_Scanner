namespace DigitalShare.Api.DTOs.Profile;

/// <summary>
/// Public search/discovery projection.
/// Strictly restricted to non-sensitive public profile fields only.
/// </summary>
public class PublicProfileSearchResultDto
{
    public string ShareId { get; set; } = string.Empty;
    public string? FullName { get; set; }
    public string? Company { get; set; }
    public string? JobTitle { get; set; }
    public string? ProfilePhotoUrl { get; set; }
}

