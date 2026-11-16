using System.Security.Claims;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Common;
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
        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var (success, response, error) = await _authService.LoginAsync(request);
        if (!success)
        {
            return Unauthorized(new ErrorResponse(error ?? "Invalid email or password."));
        }

        return Ok(response);
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
}
