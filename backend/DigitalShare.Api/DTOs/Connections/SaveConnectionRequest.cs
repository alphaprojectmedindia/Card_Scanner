using System.ComponentModel.DataAnnotations;

namespace DigitalShare.Api.DTOs.Connections;

/// <summary>
/// Request to save another Digital Share user's profile to the authenticated user's in-app connections.
/// </summary>
public class SaveConnectionRequest
{
    [Required(ErrorMessage = "ShareId is required.")]
    [MaxLength(50, ErrorMessage = "ShareId cannot exceed 50 characters.")]
    public string ShareId { get; set; } = string.Empty;
}
