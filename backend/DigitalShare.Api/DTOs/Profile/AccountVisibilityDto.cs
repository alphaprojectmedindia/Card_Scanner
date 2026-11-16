using System.ComponentModel.DataAnnotations;

namespace DigitalShare.Api.DTOs.Profile;

public class AccountVisibilityDto
{
    [Required]
    public bool IsPublic { get; set; }
}

