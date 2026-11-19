using System.ComponentModel.DataAnnotations;

namespace DigitalShare.Api.DTOs.Auth;

public class LoginRequest
{
    [EmailAddress(ErrorMessage = "A valid email address is required.")]
    public string? Email { get; set; }

    [Phone(ErrorMessage = "Please provide a valid mobile number.")]
    public string? PhoneNumber { get; set; }

    [Required(ErrorMessage = "Password is required.")]
    public string Password { get; set; } = string.Empty;
}
