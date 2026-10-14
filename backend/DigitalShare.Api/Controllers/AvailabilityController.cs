using System.Security.Claims;
using DigitalShare.Api.DTOs.Availability;
using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DigitalShare.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[Produces("application/json")]
public class AvailabilityController : ControllerBase
{
    private readonly IAvailabilityService _availabilityService;

    public AvailabilityController(IAvailabilityService availabilityService)
    {
        _availabilityService = availabilityService;
    }

    /// <summary>
    /// Gets the current authenticated user's availability settings and slots.
    /// </summary>
    [HttpGet("me")]
    [ProducesResponseType(typeof(AvailabilityResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> GetMyAvailability()
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var response = await _availabilityService.GetAvailabilityAsync(userId);
        return Ok(response);
    }

    /// <summary>
    /// Updates the current authenticated user's availability settings and weekly slots.
    /// </summary>
    [HttpPut("me")]
    [ProducesResponseType(typeof(AvailabilityResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> UpdateMyAvailability([FromBody] UpdateAvailabilityRequest request)
    {
        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var (success, response, error, statusCode) = await _availabilityService.UpdateAvailabilityAsync(userId, request);

        if (!success)
        {
            return statusCode switch
            {
                StatusCodes.Status400BadRequest => BadRequest(new ErrorResponse(error ?? "Bad request.")),
                StatusCodes.Status401Unauthorized => Unauthorized(new ErrorResponse(error ?? "Unauthorized.")),
                _ => StatusCode(statusCode, new ErrorResponse(error ?? "An error occurred."))
            };
        }

        return Ok(response);
    }

    /// <summary>
    /// Gets a connected user's public availability schedule.
    /// Requires an active Digital Share connection.
    /// </summary>
    [HttpGet("{userId}")]
    [ProducesResponseType(typeof(PublicAvailabilityResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetUserAvailability(string userId)
    {
        var currentUserId = GetCurrentUserId();
        if (string.IsNullOrEmpty(currentUserId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var (success, response, error, statusCode) = await _availabilityService.GetPublicAvailabilityAsync(currentUserId, userId);

        if (!success)
        {
            return statusCode switch
            {
                StatusCodes.Status400BadRequest => BadRequest(new ErrorResponse(error ?? "Bad request.")),
                StatusCodes.Status403Forbidden => StatusCode(StatusCodes.Status403Forbidden, new ErrorResponse(error ?? "Forbidden.")),
                StatusCodes.Status404NotFound => NotFound(new ErrorResponse(error ?? "Not found.")),
                _ => StatusCode(statusCode, new ErrorResponse(error ?? "An error occurred."))
            };
        }

        return Ok(response);
    }

    private string? GetCurrentUserId()
    {
        return User.FindFirstValue(ClaimTypes.NameIdentifier)
               ?? User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)?.Value;
    }
}
