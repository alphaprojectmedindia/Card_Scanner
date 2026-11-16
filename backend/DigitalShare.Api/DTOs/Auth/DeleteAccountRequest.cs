using System.ComponentModel.DataAnnotations;

namespace DigitalShare.Api.DTOs.Auth;

public class DeleteAccountRequest
{
    /// <summary>
    /// Current account password required for reauthentication before permanent account deletion.
    /// </summary>
    [Required(ErrorMessage = "Password is required for reauthentication.")]
    public string Password { get; set; } = string.Empty;
}

