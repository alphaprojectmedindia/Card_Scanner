using System.ComponentModel.DataAnnotations;

namespace DigitalShare.Api.DTOs.Profile;

public class UpdateProfileRequest
{
    [MaxLength(100, ErrorMessage = "Full name cannot exceed 100 characters.")]
    public string? FullName { get; set; }

    [MaxLength(30, ErrorMessage = "Phone number cannot exceed 30 characters.")]
    [Phone(ErrorMessage = "Invalid phone number format.")]
    public string? PhoneNumber { get; set; }

    [Required(ErrorMessage = "Email is required.")]
    [EmailAddress(ErrorMessage = "A valid email address is required.")]
    [MaxLength(256, ErrorMessage = "Email cannot exceed 256 characters.")]
    public string Email { get; set; } = string.Empty;

    [MaxLength(100, ErrorMessage = "Job title cannot exceed 100 characters.")]
    public string? JobTitle { get; set; }

    [MaxLength(100, ErrorMessage = "Company cannot exceed 100 characters.")]
    public string? Company { get; set; }

    [MaxLength(256, ErrorMessage = "Website cannot exceed 256 characters.")]
    [Url(ErrorMessage = "Invalid website URL format.")]
    public string? Website { get; set; }

    [MaxLength(256, ErrorMessage = "Address cannot exceed 256 characters.")]
    public string? Address { get; set; }

    [MaxLength(1000, ErrorMessage = "Bio cannot exceed 1000 characters.")]
    public string? Bio { get; set; }

    [MaxLength(500, ErrorMessage = "Profile photo URL cannot exceed 500 characters.")]
    public string? ProfilePhotoUrl { get; set; }

    /// <summary>
    /// Optional account visibility flag: true for Public, false for Private.
    /// </summary>
    public bool? IsPublic { get; set; }
}
