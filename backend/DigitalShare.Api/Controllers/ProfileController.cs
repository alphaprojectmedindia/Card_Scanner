using System.Security.Claims;
using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.DTOs.Profile;
using DigitalShare.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DigitalShare.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[Produces("application/json")]
public class ProfileController : ControllerBase
{
    private readonly IProfileService _profileService;

    public ProfileController(IProfileService profileService)
    {
        _profileService = profileService;
    }

    /// <summary>
    /// Retrieve the currently authenticated user's profile.
    /// </summary>
    [HttpGet("me")]
    [ProducesResponseType(typeof(ProfileResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetMyProfile()
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var profile = await _profileService.GetProfileByUserIdAsync(userId);
        if (profile == null)
        {
            return NotFound(new ErrorResponse("Profile not found."));
        }

        return Ok(profile);
    }

    /// <summary>
    /// Update the currently authenticated user's profile.
    /// </summary>
    [HttpPut("me")]
    [ProducesResponseType(typeof(ProfileResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> UpdateMyProfile([FromBody] UpdateProfileRequest request)
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

        var (success, response, error) = await _profileService.UpdateProfileAsync(userId, request);
        if (!success)
        {
            return NotFound(new ErrorResponse(error ?? "Profile not found."));
        }

        return Ok(response);
    }

    /// <summary>
    /// Upload a new profile picture for the currently authenticated user.
    /// Supports JPEG, PNG, WebP, and GIF up to 5 MB.
    /// </summary>
    [HttpPost("photo")]
    [Consumes("multipart/form-data")]
    [ProducesResponseType(typeof(ProfileResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> UploadProfilePhoto(IFormFile? file)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        if (file == null || file.Length == 0)
        {
            return BadRequest(new ErrorResponse("Please select an image file to upload."));
        }

        var (success, response, error, statusCode) = await _profileService.UploadProfilePhotoAsync(userId, file);
        if (!success)
        {
            return statusCode switch
            {
                StatusCodes.Status400BadRequest => BadRequest(new ErrorResponse(error ?? "Invalid image upload.")),
                StatusCodes.Status404NotFound => NotFound(new ErrorResponse(error ?? "Profile not found.")),
                StatusCodes.Status401Unauthorized => Unauthorized(new ErrorResponse(error ?? "Unauthorized.")),
                _ => StatusCode(statusCode, new ErrorResponse(error ?? "Failed to upload photo."))
            };
        }

        return Ok(response);
    }

    /// <summary>
    /// Retrieve the current user's account visibility (Public vs Private).
    /// </summary>
    [HttpGet("visibility")]
    [ProducesResponseType(typeof(AccountVisibilityDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetVisibility()
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var (success, response, error) = await _profileService.GetVisibilityAsync(userId);
        if (!success)
        {
            return NotFound(new ErrorResponse(error ?? "Profile not found."));
        }

        return Ok(response);
    }

    /// <summary>
    /// Update the current user's account visibility (Public vs Private).
    /// </summary>
    [HttpPut("visibility")]
    [ProducesResponseType(typeof(AccountVisibilityDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> UpdateVisibility([FromBody] AccountVisibilityDto dto)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var (success, response, error) = await _profileService.UpdateVisibilityAsync(userId, dto.IsPublic);
        if (!success)
        {
            return NotFound(new ErrorResponse(error ?? "Profile not found."));
        }

        return Ok(response);
    }

    /// <summary>
    /// Search for discoverable public profiles.
    /// Strictly filters out Private accounts and only returns public allowlist fields.
    /// </summary>
    [HttpGet("search")]
    [ProducesResponseType(typeof(IEnumerable<PublicProfileSearchResultDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> SearchProfiles([FromQuery] string? q, [FromQuery] int limit = 20)
    {
        var results = await _profileService.SearchPublicProfilesAsync(q, limit);
        return Ok(results);
    }

    private string? GetCurrentUserId()
    {
        return User.FindFirstValue(ClaimTypes.NameIdentifier)
               ?? User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)?.Value;
    }
}
