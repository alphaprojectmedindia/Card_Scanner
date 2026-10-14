using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.DTOs.Share;
using DigitalShare.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DigitalShare.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class ShareController : ControllerBase
{
    private readonly IShareService _shareService;

    public ShareController(IShareService shareService)
    {
        _shareService = shareService;
    }

    /// <summary>
    /// Retrieve a user's publicly shareable digital contact card using their permanent ShareId.
    /// This endpoint is intentionally public (anonymous) to allow QR code scanning.
    /// </summary>
    [HttpGet("{shareId}")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(SharedProfileResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetSharedProfile(string shareId)
    {
        if (string.IsNullOrWhiteSpace(shareId))
        {
            return NotFound(new ErrorResponse("Invalid or missing ShareId."));
        }

        var profile = await _shareService.GetSharedProfileByShareIdAsync(shareId);
        if (profile == null)
        {
            return NotFound(new ErrorResponse("Shared profile not found."));
        }

        return Ok(profile);
    }
}
