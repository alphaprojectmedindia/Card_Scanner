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
    /// Authenticate a user and return a JWT access token.
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
}
