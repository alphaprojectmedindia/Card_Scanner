using System.Security.Cryptography;
using System.Text;
using DigitalShare.Api.Configuration;
using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Consent;
using DigitalShare.Api.Models;
using DigitalShare.Api.Services.Storage;
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
    private readonly IScanImageStorageService? _scanStorageService;
    private readonly IFileStorageService? _fileStorageService;

    public AuthService(
        UserManager<ApplicationUser> userManager,
        ApplicationDbContext dbContext,
        IJwtTokenGenerator jwtTokenGenerator,
        IShareIdGenerator shareIdGenerator,
        ILogger<AuthService> logger,
        IOptions<JwtOptions>? jwtOptions = null,
        IScanImageStorageService? scanStorageService = null,
        IFileStorageService? fileStorageService = null)
    {
        _userManager = userManager;
        _dbContext = dbContext;
        _jwtTokenGenerator = jwtTokenGenerator;
        _shareIdGenerator = shareIdGenerator;
        _logger = logger;
        _jwtOptions = jwtOptions?.Value ?? new JwtOptions();
        _scanStorageService = scanStorageService;
        _fileStorageService = fileStorageService;
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
        if (!request.TermsAccepted)
        {
            return (false, null, new[] { "Accepting the Terms and Conditions and Privacy Policy is required." });
        }

        var normalizedEmail = request.Email.Trim().ToLowerInvariant();
        var existingUser = await _userManager.FindByEmailAsync(normalizedEmail);
        if (existingUser != null)
        {
            return (false, null, new[] { "A user with this email address already exists." });
        }

        if (!string.IsNullOrWhiteSpace(request.PhoneNumber))
        {
            var normalizedPhone = request.PhoneNumber.Trim();
            var existingPhoneUser = await _userManager.Users.FirstOrDefaultAsync(u => u.PhoneNumber == normalizedPhone);
            if (existingPhoneUser != null)
            {
                return (false, null, new[] { "An account with this mobile number already exists." });
            }
        }

        var user = new ApplicationUser
        {
            UserName = normalizedEmail,
            Email = normalizedEmail,
            PhoneNumber = !string.IsNullOrWhiteSpace(request.PhoneNumber) ? request.PhoneNumber.Trim() : null
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
            PhoneNumber = !string.IsNullOrWhiteSpace(request.PhoneNumber) ? request.PhoneNumber.Trim() : null,
            CreatedAtUtc = now,
            UpdatedAtUtc = now
        };

        _dbContext.UserProfiles.Add(profile);

        // Record initial mandatory legal consent
        var initialConsent = new UserConsent
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            TermsVersion = "2026.1",
            PrivacyPolicyVersion = "2026.1",
            CookiePolicyVersion = "2026.1",
            Jurisdiction = !string.IsNullOrWhiteSpace(request.Jurisdiction) ? request.Jurisdiction.Trim().ToUpperInvariant() : "IN",
            EssentialAccepted = true,
            AnalyticsAccepted = request.AnalyticsAccepted,
            ConsentTimestampUtc = now,
            Status = "Active"
        };
        _dbContext.UserConsents.Add(initialConsent);

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
        ApplicationUser? user = null;

        if (!string.IsNullOrWhiteSpace(request.PhoneNumber))
        {
            var normalizedPhone = request.PhoneNumber.Trim();
            user = await _userManager.Users.FirstOrDefaultAsync(u => u.PhoneNumber == normalizedPhone);
        }

        if (user == null && !string.IsNullOrWhiteSpace(request.Email))
        {
            var normalizedEmail = request.Email.Trim().ToLowerInvariant();
            user = await _userManager.FindByEmailAsync(normalizedEmail);
        }

        if (user == null)
        {
            return (false, null, "Invalid mobile number, email, or password.");
        }

        var isPasswordValid = await _userManager.CheckPasswordAsync(user, request.Password);
        if (!isPasswordValid)
        {
            return (false, null, "Invalid mobile number, email, or password.");
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
            Email = user.Email ?? request.Email ?? string.Empty
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

    public async Task<(bool Success, string? Error)> DeleteAccountAsync(string userId, string password)
    {
        if (string.IsNullOrWhiteSpace(userId))
        {
            return (false, "User context is required.");
        }

        if (string.IsNullOrWhiteSpace(password))
        {
            return (false, "Password is required for reauthentication.");
        }

        var user = await _userManager.FindByIdAsync(userId);
        if (user == null)
        {
            return (false, "User account not found.");
        }

        var passwordValid = await _userManager.CheckPasswordAsync(user, password);
        if (!passwordValid)
        {
            _logger.LogWarning("Account deletion reauthentication failed for user {UserId}", userId);
            return (false, "Invalid password. Reauthentication failed.");
        }

        // Collect storage files before DB records are deleted
        var profile = await _dbContext.UserProfiles.FirstOrDefaultAsync(p => p.UserId == userId);
        var profilePhotoUrl = profile?.ProfilePhotoUrl;
        var profileId = profile?.Id;

        var scanJobs = await _dbContext.ScanJobs
            .Where(j => j.UserId == userId)
            .ToListAsync();

        var storageKeys = scanJobs
            .SelectMany(j => new[] { j.FrontImageStorageKey, j.BackImageStorageKey })
            .Where(k => !string.IsNullOrWhiteSpace(k))
            .Distinct()
            .ToList();

        // Entity cascade logic
        async Task ExecuteCascadeAsync()
        {
            // 1. Meeting requests where user is requester or recipient (restrict constraint)
            var meetings = await _dbContext.MeetingRequests
                .Where(m => m.RequesterUserId == userId || m.RecipientUserId == userId)
                .ToListAsync();
            if (meetings.Count != 0)
            {
                _dbContext.MeetingRequests.RemoveRange(meetings);
            }

            // 2. Availability slots & settings
            var slots = await _dbContext.AvailabilitySlots
                .Where(s => s.UserId == userId)
                .ToListAsync();
            if (slots.Count != 0)
            {
                _dbContext.AvailabilitySlots.RemoveRange(slots);
            }

            var availability = await _dbContext.AvailabilitySettings
                .Where(s => s.UserId == userId)
                .ToListAsync();
            if (availability.Count != 0)
            {
                _dbContext.AvailabilitySettings.RemoveRange(availability);
            }

            // 3. In-app connections owned by user or pointing to user's profile
            var connections = await _dbContext.Connections
                .Where(c => c.OwnerUserId == userId || (profileId != null && c.SavedProfileId == profileId.Value))
                .ToListAsync();
            if (connections.Count != 0)
            {
                _dbContext.Connections.RemoveRange(connections);
            }

            // 4. User-owned imported business cards
            var cards = await _dbContext.ImportedBusinessCards
                .Include(c => c.PhoneNumbers)
                .Include(c => c.EmailAddresses)
                .Where(c => c.OwnerUserId == userId)
                .ToListAsync();
            if (cards.Count != 0)
            {
                _dbContext.ImportedBusinessCards.RemoveRange(cards);
            }

            // 5. Scan jobs
            if (scanJobs.Count != 0)
            {
                _dbContext.ScanJobs.RemoveRange(scanJobs);
            }

            // 6. Refresh tokens
            var tokens = await _dbContext.RefreshTokens
                .Where(r => r.UserId == userId)
                .ToListAsync();
            if (tokens.Count != 0)
            {
                _dbContext.RefreshTokens.RemoveRange(tokens);
            }

            // 7. User profile
            if (profile != null)
            {
                _dbContext.UserProfiles.Remove(profile);
            }

            // 8. Identity user
            _dbContext.Users.Remove(user);

            await _dbContext.SaveChangesAsync();
            _logger.LogInformation("Database records permanently deleted for user {UserId}", userId);
        }

        if (_dbContext.Database.IsRelational())
        {
            var strategy = _dbContext.Database.CreateExecutionStrategy();
            await strategy.ExecuteAsync(async () =>
            {
                using var transaction = await _dbContext.Database.BeginTransactionAsync();
                try
                {
                    await ExecuteCascadeAsync();
                    await transaction.CommitAsync();
                }
                catch (Exception ex)
                {
                    await transaction.RollbackAsync();
                    _logger.LogError(ex, "Transaction rolled back during account deletion for user {UserId}", userId);
                    throw;
                }
            });
        }
        else
        {
            await ExecuteCascadeAsync();
        }

        // 9. Post-transaction file storage cleanup (fail-soft outside DB transaction)
        if (_scanStorageService != null && storageKeys.Count != 0)
        {
            foreach (var key in storageKeys)
            {
                try
                {
                    await _scanStorageService.DeleteScanImageAsync(key!);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to clean up scan image file {Key} for deleted user {UserId}", key, userId);
                }
            }
        }

        if (_fileStorageService != null && !string.IsNullOrWhiteSpace(profilePhotoUrl))
        {
            try
            {
                await _fileStorageService.DeleteProfilePhotoAsync(profilePhotoUrl);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to clean up profile photo {Url} for deleted user {UserId}", profilePhotoUrl, userId);
            }
        }

        _logger.LogInformation("Account and associated data completely and permanently deleted for user {UserId}", userId);
        return (true, null);
    }

    public async Task<ConsentStatusResponse> GetConsentStatusAsync(string userId)
    {
        const string currentTerms = "2026.1";
        const string currentPrivacy = "2026.1";
        const string currentCookies = "2026.1";

        var latestConsent = await _dbContext.UserConsents
            .Where(c => c.UserId == userId && c.Status == "Active")
            .OrderByDescending(c => c.ConsentTimestampUtc)
            .FirstOrDefaultAsync();

        if (latestConsent == null)
        {
            return new ConsentStatusResponse
            {
                HasAcceptedCurrentTerms = false,
                CurrentTermsVersion = currentTerms,
                CurrentPrivacyPolicyVersion = currentPrivacy,
                CurrentCookiePolicyVersion = currentCookies,
                Jurisdiction = "IN",
                EssentialAccepted = false,
                AnalyticsAccepted = false,
                ConsentTimestampUtc = null
            };
        }

        var isUpToDate = latestConsent.TermsVersion == currentTerms &&
                         latestConsent.PrivacyPolicyVersion == currentPrivacy;

        return new ConsentStatusResponse
        {
            HasAcceptedCurrentTerms = isUpToDate,
            CurrentTermsVersion = currentTerms,
            CurrentPrivacyPolicyVersion = currentPrivacy,
            CurrentCookiePolicyVersion = currentCookies,
            UserTermsVersion = latestConsent.TermsVersion,
            UserPrivacyPolicyVersion = latestConsent.PrivacyPolicyVersion,
            Jurisdiction = latestConsent.Jurisdiction,
            EssentialAccepted = latestConsent.EssentialAccepted,
            AnalyticsAccepted = latestConsent.AnalyticsAccepted,
            ConsentTimestampUtc = latestConsent.ConsentTimestampUtc
        };
    }

    public async Task<ConsentStatusResponse> RecordConsentAsync(
        string userId,
        RecordConsentRequest request,
        string? ipAddress = null,
        string? userAgent = null)
    {
        var now = DateTime.UtcNow;
        var jurisdiction = !string.IsNullOrWhiteSpace(request.Jurisdiction)
            ? request.Jurisdiction.Trim().ToUpperInvariant()
            : "IN";

        var consent = new UserConsent
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            TermsVersion = string.IsNullOrWhiteSpace(request.TermsVersion) ? "2026.1" : request.TermsVersion.Trim(),
            PrivacyPolicyVersion = string.IsNullOrWhiteSpace(request.PrivacyPolicyVersion) ? "2026.1" : request.PrivacyPolicyVersion.Trim(),
            CookiePolicyVersion = string.IsNullOrWhiteSpace(request.CookiePolicyVersion) ? "2026.1" : request.CookiePolicyVersion.Trim(),
            Jurisdiction = jurisdiction,
            EssentialAccepted = true,
            AnalyticsAccepted = request.AnalyticsAccepted,
            ConsentTimestampUtc = now,
            Status = "Active",
            IpAddress = ipAddress,
            UserAgent = userAgent
        };

        _dbContext.UserConsents.Add(consent);
        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Recorded legal consent for user {UserId} in jurisdiction {Jurisdiction}", userId, jurisdiction);

        return await GetConsentStatusAsync(userId);
    }
}
