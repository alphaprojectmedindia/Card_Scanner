using System.ComponentModel.DataAnnotations;

namespace DigitalShare.Api.DTOs.Auth;

public class ForgotPasswordRequest
{
    [Required(ErrorMessage = "Email address is required.")]
    [EmailAddress(ErrorMessage = "Please enter a valid email address.")]
    public string Email { get; set; } = string.Empty;

    public string? ClientResetBaseUrl { get; set; }
}

public class ResetPasswordRequest
{
    [Required(ErrorMessage = "Email address is required.")]
    [EmailAddress(ErrorMessage = "Please enter a valid email address.")]
    public string Email { get; set; } = string.Empty;

    [Required(ErrorMessage = "Password reset token is required.")]
    public string Token { get; set; } = string.Empty;

    [Required(ErrorMessage = "New password is required.")]
    [MinLength(6, ErrorMessage = "Password must be at least 6 characters.")]
    public string NewPassword { get; set; } = string.Empty;

    [Required(ErrorMessage = "Please confirm your new password.")]
    [Compare(nameof(NewPassword), ErrorMessage = "The password and confirmation password do not match.")]
    public string ConfirmPassword { get; set; } = string.Empty;
}
