using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using DigitalShare.Api.Configuration;
using DigitalShare.Api.Models;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace DigitalShare.Api.Services;

public class JwtTokenGenerator : IJwtTokenGenerator
{
    private readonly JwtOptions _jwtOptions;

    public JwtTokenGenerator(IOptions<JwtOptions> jwtOptions)
    {
        _jwtOptions = jwtOptions.Value;
    }

    public (string Token, DateTime ExpirationUtc) GenerateToken(ApplicationUser user)
    {
        if (string.IsNullOrWhiteSpace(_jwtOptions.SecretKey))
        {
            throw new InvalidOperationException("JWT SecretKey is not configured.");
        }

        if (Encoding.UTF8.GetByteCount(_jwtOptions.SecretKey) < 32)
        {
            throw new InvalidOperationException("JWT SecretKey must be at least 256 bits (32 bytes) for HMAC-SHA256.");
        }

        var tokenHandler = new JwtSecurityTokenHandler();
        var key = Encoding.UTF8.GetBytes(_jwtOptions.SecretKey);
        var expirationUtc = DateTime.UtcNow.AddMinutes(_jwtOptions.ExpiryMinutes > 0 ? _jwtOptions.ExpiryMinutes : 60);

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id),
            new(ClaimTypes.NameIdentifier, user.Id),
            new(JwtRegisteredClaimNames.Email, user.Email ?? string.Empty),
            new(ClaimTypes.Email, user.Email ?? string.Empty),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };

        var tokenDescriptor = new SecurityTokenDescriptor
        {
            Subject = new ClaimsIdentity(claims),
            Expires = expirationUtc,
            Issuer = _jwtOptions.Issuer,
            Audience = _jwtOptions.Audience,
            SigningCredentials = new SigningCredentials(
                new SymmetricSecurityKey(key),
                SecurityAlgorithms.HmacSha256Signature)
        };

        var token = tokenHandler.CreateToken(tokenDescriptor);
        return (tokenHandler.WriteToken(token), expirationUtc);
    }
}
