using System.Security.Cryptography;
using System.Text;
using DigitalShare.Api.Configuration;
using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.Models;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace DigitalShare.Api.Services;

public class AuthService : IAuthService
{
    private readonly UserManager<ApplicationUser> _userManager;
    private readonly ApplicationDbContext _dbContext;
    private readonly IJwtTokenGenerator _jwtTokenGenerator;
    private readonly IShareIdGenerator _shareIdGenerator;
    private readonly ILogger<AuthService> _logger;
    private readonly JwtOptions _jwtOptions;

    public AuthService(
        UserManager<ApplicationUser> userManager,
        ApplicationDbContext dbContext,
        IJwtTokenGenerator jwtTokenGenerator,
        IShareIdGenerator shareIdGenerator,
        ILogger<AuthService> logger,
        IOptions<JwtOptions>? jwtOptions = null)
    {
        _userManager = userManager;
        _dbContext = dbContext;
        _jwtTokenGenerator = jwtTokenGenerator;
        _shareIdGenerator = shareIdGenerator;
        _logger = logger;
        _jwtOptions = jwtOptions?.Value ?? new JwtOptions();
    }

    /// <summary>
    /// Generates a cryptographically secure, high-entropy raw refresh token.
    /// </summary>
    public static string GenerateRawRefreshToken()
    {
        var randomBytes = RandomNumberGenerator.GetBytes(64);
        return Convert.ToBase64String(randomBytes)
            .Replace("+", "-")
            .Replace("/", "_")
            .TrimEnd('=');
    }

    /// <summary>
    /// Computes a one-way SHA-256 cryptographic hash of the raw token.
    /// RAW refresh tokens are NEVER stored in the database.
    /// </summary>
    public static string HashToken(string rawToken)
    {
        var bytes = Encoding.UTF8.GetBytes(rawToken);
        var hashBytes = SHA256.HashData(bytes);
        return Convert.ToHexString(hashBytes).ToLowerInvariant();
    }

    private (RefreshToken Entity, string RawToken) CreateRefreshTokenRecord(
        string userId,
        string? ipAddress = null)
    {
        var rawToken = GenerateRawRefreshToken();
        var tokenHash = HashToken(rawToken);
        var expiryDays = _jwtOptions.RefreshTokenExpiryDays > 0 ? _jwtOptions.RefreshTokenExpiryDays : 30;

        var entity = new RefreshToken
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            TokenHash = tokenHash,
            CreatedAtUtc = DateTime.UtcNow,
            ExpiresAtUtc = DateTime.UtcNow.AddDays(expiryDays),
            CreatedByIp = ipAddress
        };

        _dbContext.RefreshTokens.Add(entity);
        return (entity, rawToken);
    }

    public async Task<(bool Success, AuthResponse? Response, IEnumerable<string>? Errors)> RegisterAsync(RegisterRequest request)
    {
        var normalizedEmail = request.Email.Trim().ToLowerInvariant();
        var existingUser = await _userManager.FindByEmailAsync(normalizedEmail);
        if (existingUser != null)
        {
            return (false, null, new[] { "A user with this email address already exists." });
        }

        var user = new ApplicationUser
        {
            UserName = normalizedEmail,
            Email = normalizedEmail
        };

        var result = await _userManager.CreateAsync(user, request.Password);
        if (!result.Succeeded)
        {
            var errors = result.Errors.Select(e => e.Description);
            return (false, null, errors);
        }

        var now = DateTime.UtcNow;
        var profile = new UserProfile
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            ShareId = _shareIdGenerator.GenerateShareId(),
            Email = user.Email!,
            CreatedAtUtc = now,
            UpdatedAtUtc = now
        };

        _dbContext.UserProfiles.Add(profile);

        // Issue short-lived access JWT + rotating refresh token
        var (token, expirationUtc) = _jwtTokenGenerator.GenerateToken(user);
        var (refreshTokenEntity, rawRefreshToken) = CreateRefreshTokenRecord(user.Id);

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Successfully registered user {UserId} with email {Email} and ShareId {ShareId}", user.Id, user.Email, profile.ShareId);

        var response = new AuthResponse
        {
            Token = token,
            ExpirationUtc = expirationUtc,
            AccessToken = token,
            RefreshToken = rawRefreshToken,
            AccessTokenExpiresAt = expirationUtc,
            RefreshTokenExpiresAt = refreshTokenEntity.ExpiresAtUtc,
            UserId = user.Id,
            Email = user.Email!
        };

        return (true, response, null);
    }

    public async Task<(bool Success, AuthResponse? Response, string? Error)> LoginAsync(LoginRequest request)
    {
        var normalizedEmail = request.Email.Trim().ToLowerInvariant();
        var user = await _userManager.FindByEmailAsync(normalizedEmail);
        if (user == null)
        {
            return (false, null, "Invalid email or password.");
        }

        var isPasswordValid = await _userManager.CheckPasswordAsync(user, request.Password);
        if (!isPasswordValid)
        {
            return (false, null, "Invalid email or password.");
        }

        // Issue short-lived access JWT + rotating refresh token
        var (token, expirationUtc) = _jwtTokenGenerator.GenerateToken(user);
        var (refreshTokenEntity, rawRefreshToken) = CreateRefreshTokenRecord(user.Id);

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("User {UserId} logged in successfully", user.Id);

        var response = new AuthResponse
        {
            Token = token,
            ExpirationUtc = expirationUtc,
            AccessToken = token,
            RefreshToken = rawRefreshToken,
            AccessTokenExpiresAt = expirationUtc,
            RefreshTokenExpiresAt = refreshTokenEntity.ExpiresAtUtc,
            UserId = user.Id,
            Email = user.Email ?? normalizedEmail
        };

        return (true, response, null);
    }

    public async Task<(bool Success, AuthResponse? Response, string? Error)> RefreshTokenAsync(string rawRefreshToken, string? ipAddress = null)
    {
        if (string.IsNullOrWhiteSpace(rawRefreshToken))
        {
            return (false, null, "Refresh token is required.");
        }

        var tokenHash = HashToken(rawRefreshToken.Trim());

        var tokenRecord = await _dbContext.RefreshTokens
            .Include(r => r.User)
            .FirstOrDefaultAsync(r => r.TokenHash == tokenHash);

        if (tokenRecord == null)
        {
            _logger.LogWarning("Refresh rejected: invalid token");
            return (false, null, "Invalid refresh token.");
        }

        // Token Reuse / Replay Detection:
        // If a previously revoked/rotated refresh token is presented, someone may have compromised it.
        // In response, revoke all active refresh tokens for this user family.
        if (tokenRecord.IsRevoked)
        {
            _logger.LogWarning("Refresh reuse detected for user {UserId}. Revoking all active tokens.", tokenRecord.UserId);
            await RevokeAllUserRefreshTokensAsync(tokenRecord.UserId);
            return (false, null, "Refresh token has been revoked.");
        }

        if (tokenRecord.IsExpired)
        {
            _logger.LogInformation("Refresh rejected: expired for user {UserId}", tokenRecord.UserId);
            return (false, null, "Refresh token has expired.");
        }

        if (tokenRecord.User == null)
        {
            _logger.LogWarning("Refresh rejected: user not found for user {UserId}", tokenRecord.UserId);
            return (false, null, "User not found.");
        }

        // ROTATION:
        // 1. Generate NEW cryptographically secure refresh token
        // 2. Hash and store new refresh token
        // 3. Mark old refresh token revoked and link to replacement
        var (newEntity, newRawToken) = CreateRefreshTokenRecord(tokenRecord.UserId, ipAddress);

        tokenRecord.RevokedAtUtc = DateTime.UtcNow;
        tokenRecord.RevokedByIp = ipAddress;
        tokenRecord.ReplacedByTokenId = newEntity.Id;

        await _dbContext.SaveChangesAsync();

        // 4. Generate NEW JWT access token
        var (newAccessToken, accessExpiry) = _jwtTokenGenerator.GenerateToken(tokenRecord.User);

        _logger.LogInformation("Refresh succeeded for user {UserId}", tokenRecord.UserId);

        var response = new AuthResponse
        {
            Token = newAccessToken,
            ExpirationUtc = accessExpiry,
            AccessToken = newAccessToken,
            RefreshToken = newRawToken,
            AccessTokenExpiresAt = accessExpiry,
            RefreshTokenExpiresAt = newEntity.ExpiresAtUtc,
            UserId = tokenRecord.UserId,
            Email = tokenRecord.User.Email ?? string.Empty
        };

        return (true, response, null);
    }

    public async Task<bool> RevokeRefreshTokenAsync(string rawRefreshToken, string? ipAddress = null)
    {
        if (string.IsNullOrWhiteSpace(rawRefreshToken))
        {
            return false;
        }

        var tokenHash = HashToken(rawRefreshToken.Trim());
        var tokenRecord = await _dbContext.RefreshTokens.FirstOrDefaultAsync(r => r.TokenHash == tokenHash);
        if (tokenRecord == null)
        {
            return false;
        }

        if (!tokenRecord.IsRevoked)
        {
            tokenRecord.RevokedAtUtc = DateTime.UtcNow;
            tokenRecord.RevokedByIp = ipAddress;
            await _dbContext.SaveChangesAsync();
            _logger.LogInformation("Logout token revoked for user {UserId}", tokenRecord.UserId);
        }

        return true;
    }

    public async Task<bool> RevokeAllUserRefreshTokensAsync(string userId)
    {
        var activeTokens = await _dbContext.RefreshTokens
            .Where(r => r.UserId == userId && r.RevokedAtUtc == null && r.ExpiresAtUtc > DateTime.UtcNow)
            .ToListAsync();

        if (activeTokens.Count != 0)
        {
            var now = DateTime.UtcNow;
            foreach (var token in activeTokens)
            {
                token.RevokedAtUtc = now;
            }
            await _dbContext.SaveChangesAsync();
            _logger.LogInformation("Revoked all active tokens ({Count}) for user {UserId}", activeTokens.Count, userId);
        }

        return true;
    }
}
