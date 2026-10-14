using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.Models;
using Microsoft.AspNetCore.Identity;

namespace DigitalShare.Api.Services;

public class AuthService : IAuthService
{
    private readonly UserManager<ApplicationUser> _userManager;
    private readonly ApplicationDbContext _dbContext;
    private readonly IJwtTokenGenerator _jwtTokenGenerator;
    private readonly IShareIdGenerator _shareIdGenerator;
    private readonly ILogger<AuthService> _logger;

    public AuthService(
        UserManager<ApplicationUser> userManager,
        ApplicationDbContext dbContext,
        IJwtTokenGenerator jwtTokenGenerator,
        IShareIdGenerator shareIdGenerator,
        ILogger<AuthService> logger)
    {
        _userManager = userManager;
        _dbContext = dbContext;
        _jwtTokenGenerator = jwtTokenGenerator;
        _shareIdGenerator = shareIdGenerator;
        _logger = logger;
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
        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Successfully registered user {UserId} with email {Email} and ShareId {ShareId}", user.Id, user.Email, profile.ShareId);

        var (token, expirationUtc) = _jwtTokenGenerator.GenerateToken(user);
        var response = new AuthResponse
        {
            Token = token,
            ExpirationUtc = expirationUtc,
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

        var (token, expirationUtc) = _jwtTokenGenerator.GenerateToken(user);
        var response = new AuthResponse
        {
            Token = token,
            ExpirationUtc = expirationUtc,
            UserId = user.Id,
            Email = user.Email ?? normalizedEmail
        };

        _logger.LogInformation("User {UserId} logged in successfully", user.Id);

        return (true, response, null);
    }
}
