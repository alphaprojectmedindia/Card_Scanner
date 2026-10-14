using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using DigitalShare.Api.Configuration;
using DigitalShare.Api.Models;
using DigitalShare.Api.Services;
using Microsoft.Extensions.Options;

namespace DigitalShare.Api.Tests.Services;

public class JwtTokenGeneratorTests
{
    [Fact]
    public void GenerateToken_ReturnsValidJwt_WithExpectedClaims()
    {
        // Arrange
        var jwtOptions = Options.Create(new JwtOptions
        {
            Issuer = "DigitalShare.Test",
            Audience = "DigitalShare.Audience",
            SecretKey = "SuperSecretTestKeyForJwtGenerationThatIsLongEnough!",
            ExpiryMinutes = 30
        });

        var generator = new JwtTokenGenerator(jwtOptions);
        var user = new ApplicationUser
        {
            Id = Guid.NewGuid().ToString(),
            Email = "testuser@example.com",
            UserName = "testuser@example.com"
        };

        // Act
        var (token, expirationUtc) = generator.GenerateToken(user);

        // Assert
        Assert.NotEmpty(token);
        Assert.True(expirationUtc > DateTime.UtcNow);

        var handler = new JwtSecurityTokenHandler();
        Assert.True(handler.CanReadToken(token));

        var jwt = handler.ReadJwtToken(token);
        Assert.Equal("DigitalShare.Test", jwt.Issuer);
        Assert.Contains("DigitalShare.Audience", jwt.Audiences);

        var subClaim = jwt.Claims.FirstOrDefault(c => c.Type == JwtRegisteredClaimNames.Sub || c.Type == ClaimTypes.NameIdentifier);
        Assert.NotNull(subClaim);
        Assert.Equal(user.Id, subClaim.Value);

        var emailClaim = jwt.Claims.FirstOrDefault(c => c.Type == JwtRegisteredClaimNames.Email || c.Type == ClaimTypes.Email);
        Assert.NotNull(emailClaim);
        Assert.Equal(user.Email, emailClaim.Value);
    }
}
