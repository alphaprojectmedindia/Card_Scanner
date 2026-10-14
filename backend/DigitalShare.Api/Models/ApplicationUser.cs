using Microsoft.AspNetCore.Identity;

namespace DigitalShare.Api.Models;

public class ApplicationUser : IdentityUser
{
    public virtual UserProfile? Profile { get; set; }
}
