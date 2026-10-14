using System.Security.Claims;
using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.DTOs.Meetings;
using DigitalShare.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DigitalShare.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[Produces("application/json")]
public class MeetingsController : ControllerBase
{
    private readonly IMeetingService _meetingService;

    public MeetingsController(IMeetingService meetingService)
    {
        _meetingService = meetingService;
    }

    /// <summary>
    /// Creates a new meeting request to a connected Digital Share user.
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(MeetingResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> CreateMeeting([FromBody] CreateMeetingRequest request)
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

        var (success, response, error, statusCode) = await _meetingService.CreateMeetingRequestAsync(userId, request);

        if (!success)
        {
            return statusCode switch
            {
                StatusCodes.Status400BadRequest => BadRequest(new ErrorResponse(error ?? "Bad request.")),
                StatusCodes.Status401Unauthorized => Unauthorized(new ErrorResponse(error ?? "Unauthorized.")),
                StatusCodes.Status403Forbidden => StatusCode(StatusCodes.Status403Forbidden, new ErrorResponse(error ?? "Forbidden.")),
                StatusCodes.Status404NotFound => NotFound(new ErrorResponse(error ?? "Recipient not found.")),
                StatusCodes.Status409Conflict => Conflict(new ErrorResponse(error ?? "Conflict.")),
                _ => StatusCode(statusCode, new ErrorResponse(error ?? "An error occurred."))
            };
        }

        return StatusCode(StatusCodes.Status201Created, response);
    }

    /// <summary>
    /// Lists all meetings for the current user categorized into Upcoming, Requests, and History.
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(MeetingListResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> GetMeetings()
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var response = await _meetingService.GetMeetingsAsync(userId);
        return Ok(response);
    }

    /// <summary>
    /// Gets details of a specific meeting where the user is a participant.
    /// </summary>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(MeetingResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetMeeting(Guid id)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var (success, response, error, statusCode) = await _meetingService.GetMeetingByIdAsync(userId, id);

        if (!success)
        {
            return statusCode switch
            {
                StatusCodes.Status404NotFound => NotFound(new ErrorResponse(error ?? "Meeting not found.")),
                _ => StatusCode(statusCode, new ErrorResponse(error ?? "An error occurred."))
            };
        }

        return Ok(response);
    }

    /// <summary>
    /// Accepts a pending meeting request (only recipient can accept).
    /// </summary>
    [HttpPost("{id:guid}/accept")]
    [ProducesResponseType(typeof(MeetingResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> AcceptMeeting(Guid id)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var (success, response, error, statusCode) = await _meetingService.AcceptMeetingAsync(userId, id);

        if (!success)
        {
            return statusCode switch
            {
                StatusCodes.Status400BadRequest => BadRequest(new ErrorResponse(error ?? "Bad request.")),
                StatusCodes.Status403Forbidden => StatusCode(StatusCodes.Status403Forbidden, new ErrorResponse(error ?? "Forbidden.")),
                StatusCodes.Status404NotFound => NotFound(new ErrorResponse(error ?? "Meeting not found.")),
                StatusCodes.Status409Conflict => Conflict(new ErrorResponse(error ?? "Conflict.")),
                _ => StatusCode(statusCode, new ErrorResponse(error ?? "An error occurred."))
            };
        }

        return Ok(response);
    }

    /// <summary>
    /// Rejects a pending meeting request (only recipient can reject).
    /// </summary>
    [HttpPost("{id:guid}/reject")]
    [ProducesResponseType(typeof(MeetingResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> RejectMeeting(Guid id)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var (success, response, error, statusCode) = await _meetingService.RejectMeetingAsync(userId, id);

        if (!success)
        {
            return statusCode switch
            {
                StatusCodes.Status400BadRequest => BadRequest(new ErrorResponse(error ?? "Bad request.")),
                StatusCodes.Status403Forbidden => StatusCode(StatusCodes.Status403Forbidden, new ErrorResponse(error ?? "Forbidden.")),
                StatusCodes.Status404NotFound => NotFound(new ErrorResponse(error ?? "Meeting not found.")),
                _ => StatusCode(statusCode, new ErrorResponse(error ?? "An error occurred."))
            };
        }

        return Ok(response);
    }

    /// <summary>
    /// Cancels a meeting (requester can cancel pending; either participant can cancel accepted).
    /// </summary>
    [HttpPost("{id:guid}/cancel")]
    [ProducesResponseType(typeof(MeetingResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> CancelMeeting(Guid id)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var (success, response, error, statusCode) = await _meetingService.CancelMeetingAsync(userId, id);

        if (!success)
        {
            return statusCode switch
            {
                StatusCodes.Status400BadRequest => BadRequest(new ErrorResponse(error ?? "Bad request.")),
                StatusCodes.Status403Forbidden => StatusCode(StatusCodes.Status403Forbidden, new ErrorResponse(error ?? "Forbidden.")),
                StatusCodes.Status404NotFound => NotFound(new ErrorResponse(error ?? "Meeting not found.")),
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
