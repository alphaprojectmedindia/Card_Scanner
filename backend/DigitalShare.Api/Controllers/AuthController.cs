using System.Security.Claims;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.DTOs.Consent;
using DigitalShare.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DigitalShare.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class AuthController : ControllerBase
{
    private readonly IAuthService _authService;

    public AuthController(IAuthService authService)
    {
        _authService = authService;
    }

    /// <summary>
    /// Register a new user account and initialize their basic profile.
    /// </summary>
    [HttpPost("register")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request)
    {
        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var (success, response, errors) = await _authService.RegisterAsync(request);
        if (!success)
        {
            var errorList = errors != null ? errors.ToArray() : new[] { "Registration failed." };
            if (errorList.Any(e => e.Contains("already exists", StringComparison.OrdinalIgnoreCase)))
            {
                return Conflict(new ErrorResponse("A user with this email address already exists."));
            }

            return BadRequest(new ErrorResponse("Registration failed.", new Dictionary<string, string[]>
            {
                { "Errors", errorList }
            }));
        }

        return CreatedAtAction(nameof(ProfileController.GetMyProfile), "Profile", null, response);
    }

    /// <summary>
    /// Authenticate a user and return a JWT access token and rotating refresh token.
    /// </summary>
    [HttpPost("login")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Email) && string.IsNullOrWhiteSpace(request.PhoneNumber))
        {
            return BadRequest(new ErrorResponse("A valid email address is required."));
        }

        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var (success, response, error) = await _authService.LoginAsync(request);
        if (!success)
        {
            return Unauthorized(new ErrorResponse(error ?? "Invalid email address or password."));
        }

        return Ok(response);
    }

    /// <summary>
    /// Initiate the password recovery workflow and send a reset token via Gmail SMTP.
    /// </summary>
    [HttpPost("forgot-password")]
    [AllowAnonymous]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequest request)
    {
        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var (success, message, debugToken) = await _authService.ForgotPasswordAsync(request);
        if (!success)
        {
            return BadRequest(new ErrorResponse(message));
        }

        return Ok(new
        {
            message,
            token = app_is_dev_or_test() ? debugToken : null
        });

        bool app_is_dev_or_test()
        {
            var env = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT");
            return string.Equals(env, "Development", StringComparison.OrdinalIgnoreCase) ||
                   string.IsNullOrWhiteSpace(env);
        }
    }

    /// <summary>
    /// Reset user password using the time-limited reset token.
    /// </summary>
    [HttpPost("reset-password")]
    [AllowAnonymous]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordRequest request)
    {
        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var (success, error) = await _authService.ResetPasswordAsync(request);
        if (!success)
        {
            return BadRequest(new ErrorResponse(error ?? "Password reset failed."));
        }

        return Ok(new { message = "Password has been reset successfully. Please log in with your new password." });
    }

    /// <summary>
    /// Rotate refresh token and issue a new short-lived access JWT + new rotating refresh token.
    /// </summary>
    [HttpPost("refresh")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Refresh([FromBody] RefreshTokenRequest request)
    {
        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var ipAddress = HttpContext.Connection.RemoteIpAddress?.ToString();
        var (success, response, error) = await _authService.RefreshTokenAsync(request.RefreshToken, ipAddress);
        if (!success)
        {
            return Unauthorized(new ErrorResponse(error ?? "Invalid refresh token."));
        }

        return Ok(response);
    }

    /// <summary>
    /// Revoke the submitted refresh token upon explicit logout.
    /// </summary>
    [HttpPost("logout")]
    [AllowAnonymous]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> Logout([FromBody] RevokeTokenRequest? request)
    {
        if (!string.IsNullOrWhiteSpace(request?.RefreshToken))
        {
            var ipAddress = HttpContext.Connection.RemoteIpAddress?.ToString();
            await _authService.RevokeRefreshTokenAsync(request.RefreshToken, ipAddress);
        }

        return Ok(new { message = "Logged out successfully." });
    }

    /// <summary>
    /// Revoke all active refresh tokens for the authenticated user across all devices/sessions.
    /// </summary>
    [HttpPost("logout-all")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> LogoutAll()
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub");
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized."));
        }

        await _authService.RevokeAllUserRefreshTokensAsync(userId);
        return Ok(new { message = "All active sessions revoked successfully." });
    }

    /// <summary>
    /// Permanently delete the authenticated user's account and all associated personal data.
    /// Strictly requires password reauthentication.
    /// </summary>
    [HttpPost("delete-account")]
    [HttpDelete("account")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> DeleteAccount([FromBody] DeleteAccountRequest request)
    {
        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub");
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var (success, error) = await _authService.DeleteAccountAsync(userId, request.Password);
        if (!success)
        {
            return BadRequest(new ErrorResponse(error ?? "Account deletion failed."));
        }

        return Ok(new { message = "Account and all associated personal data have been permanently deleted." });
    }

    /// <summary>
    /// Check whether the authenticated user has accepted the latest mandatory terms and privacy policies.
    /// </summary>
    [HttpGet("consent-status")]
    [Authorize]
    [ProducesResponseType(typeof(ConsentStatusResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> GetConsentStatus()
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub");
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var status = await _authService.GetConsentStatusAsync(userId);
        return Ok(status);
    }

    /// <summary>
    /// Record mandatory legal consent and cookie preferences for the authenticated user.
    /// </summary>
    [HttpPost("consent")]
    [Authorize]
    [ProducesResponseType(typeof(ConsentStatusResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> RecordConsent([FromBody] RecordConsentRequest request)
    {
        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub");
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var ipAddress = HttpContext.Connection.RemoteIpAddress?.ToString();
        var userAgent = Request.Headers.UserAgent.ToString();

        var status = await _authService.RecordConsentAsync(userId, request, ipAddress, userAgent);
        return Ok(status);
    }
}
