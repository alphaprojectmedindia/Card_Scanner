using DigitalShare.Api.Models;

namespace DigitalShare.Api.Services;

public interface IJwtTokenGenerator
{
    (string Token, DateTime ExpirationUtc) GenerateToken(ApplicationUser user);
}
