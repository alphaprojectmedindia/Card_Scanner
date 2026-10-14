using System.Security.Claims;
using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.DTOs.Connections;
using DigitalShare.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DigitalShare.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[Produces("application/json")]
public class ConnectionsController : ControllerBase
{
    private readonly IConnectionService _connectionService;

    public ConnectionsController(IConnectionService connectionService)
    {
        _connectionService = connectionService;
    }

    /// <summary>
    /// Save a scanned user's profile to the authenticated user's in-app connections list.
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(ConnectionResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> SaveConnection([FromBody] SaveConnectionRequest request)
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

        var (success, response, error, statusCode) = await _connectionService.SaveConnectionAsync(userId, request.ShareId);

        if (!success)
        {
            return statusCode switch
            {
                StatusCodes.Status400BadRequest => BadRequest(new ErrorResponse(error ?? "Bad request.")),
                StatusCodes.Status404NotFound => NotFound(new ErrorResponse(error ?? "Profile not found.")),
                StatusCodes.Status409Conflict => Conflict(new ErrorResponse(error ?? "This profile is already saved.")),
                StatusCodes.Status401Unauthorized => Unauthorized(new ErrorResponse(error ?? "Unauthorized.")),
                _ => StatusCode(statusCode, new ErrorResponse(error ?? "An error occurred."))
            };
        }

        return StatusCode(StatusCodes.Status201Created, response);
    }

    /// <summary>
    /// List all in-app connections saved by the authenticated user, newest first.
    /// Returns live profile references.
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<ConnectionResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> GetConnections()
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var connections = await _connectionService.GetConnectionsAsync(userId);
        return Ok(connections);
    }

    /// <summary>
    /// Delete a saved in-app connection using the target's ShareId.
    /// </summary>
    [HttpDelete("{shareId}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DeleteConnection(string shareId)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var deleted = await _connectionService.DeleteConnectionAsync(userId, shareId);
        if (!deleted)
        {
            return NotFound(new ErrorResponse("Saved connection not found."));
        }

        return NoContent();
    }

    private string? GetCurrentUserId()
    {
        return User.FindFirstValue(ClaimTypes.NameIdentifier)
               ?? User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)?.Value;
    }
}
