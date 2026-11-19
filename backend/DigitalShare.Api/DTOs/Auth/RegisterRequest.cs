using System.ComponentModel.DataAnnotations;

namespace DigitalShare.Api.DTOs.Auth;

public class RegisterRequest
{
    [Required(ErrorMessage = "Email is required.")]
    [EmailAddress(ErrorMessage = "A valid email address is required.")]
    [MaxLength(256)]
    public string Email { get; set; } = string.Empty;

    [Required(ErrorMessage = "Password is required.")]
    [MinLength(6, ErrorMessage = "Password must be at least 6 characters long.")]
    [MaxLength(100)]
    public string Password { get; set; } = string.Empty;

    [Required(ErrorMessage = "Confirm password is required.")]
    [Compare(nameof(Password), ErrorMessage = "Passwords do not match.")]
    public string ConfirmPassword { get; set; } = string.Empty;

    [Phone(ErrorMessage = "Please provide a valid phone number.")]
    [MaxLength(30)]
    public string? PhoneNumber { get; set; }

    public bool TermsAccepted { get; set; } = true;

    [MaxLength(20)]
    public string? Jurisdiction { get; set; } = "IN";

    public bool AnalyticsAccepted { get; set; } = false;
}
