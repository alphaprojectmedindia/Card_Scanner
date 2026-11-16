using System.Security.Claims;
using DigitalShare.Api.DTOs.CardAnalysis;
using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.Services.Gemini;
using DigitalShare.Api.Services.Storage;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DigitalShare.Api.Controllers;

[ApiController]
[Route("api/business-cards")]
[Authorize]
[Produces("application/json")]
public class CardAnalysisController : ControllerBase
{
    private readonly IGeminiCardAnalysisService _geminiService;
    private readonly IScanImageStorageService _storageService;
    private readonly ILogger<CardAnalysisController> _logger;

    private static readonly HashSet<string> AllowedMimeTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/webp"
    };

    public CardAnalysisController(
        IGeminiCardAnalysisService geminiService,
        IScanImageStorageService storageService,
        ILogger<CardAnalysisController> logger)
    {
        _geminiService = geminiService;
        _storageService = storageService;
        _logger = logger;
    }

    /// <summary>
    /// Authenticated upload endpoint for business-card scan images.
    /// Stores the image safely in R2/storage and returns a storage key scoped to the user.
    /// </summary>
    [HttpPost("images")]
    [Consumes("multipart/form-data")]
    [ProducesResponseType(typeof(ImageUploadResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> UploadCardImage(
        [FromForm] IFormFile file,
        [FromForm] string cardSide = "front",
        CancellationToken ct = default)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        if (file == null || file.Length == 0)
        {
            return BadRequest(new ErrorResponse("No image file was provided."));
        }

        if (file.Length > 10 * 1024 * 1024)
        {
            return BadRequest(new ErrorResponse("Image size exceeds maximum allowed size of 10MB."));
        }

        var contentType = file.ContentType?.Trim().ToLowerInvariant() ?? string.Empty;
        if (!AllowedMimeTypes.Contains(contentType))
        {
            return BadRequest(new ErrorResponse($"Invalid image content type '{contentType}'. Allowed types: image/jpeg, image/png, image/webp."));
        }

        try
        {
            await using var stream = file.OpenReadStream();
            var storageKey = await _storageService.UploadScanImageAsync(stream, contentType, file.Length, ct);

            _logger.LogInformation(
                "Uploaded scan image for user {UserId} ({CardSide}, {Size} bytes, key: {StorageKey})",
                userId, cardSide, file.Length, storageKey);

            return Ok(new ImageUploadResponse
            {
                StorageKey = storageKey,
                CardSide = string.Equals(cardSide, "back", StringComparison.OrdinalIgnoreCase) ? "back" : "front",
                FileSizeBytes = file.Length,
                UploadedAtUtc = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to upload business card image for user {UserId}", userId);
            return StatusCode(StatusCodes.Status500InternalServerError, new ErrorResponse("Image upload failed."));
        }
    }

    /// <summary>
    /// Analyzes business card OCR observations and layout geometry using Google Gemini.
    /// Supports idempotency, distributed caching, and non-destructive semantic validation.
    /// </summary>
    [HttpPost("analyze")]
    [ProducesResponseType(typeof(AnalyzeBusinessCardResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> AnalyzeCard(
        [FromBody] AnalyzeBusinessCardRequest request,
        CancellationToken ct = default)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        if (request.OcrObservations.Count == 0 && string.IsNullOrWhiteSpace(request.FrontImageStorageKey))
        {
            return BadRequest(new ErrorResponse("Cannot analyze card without OCR observations or an image reference."));
        }

        try
        {
            var result = await _geminiService.AnalyzeCardAsync(userId, request, ct);
            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error analyzing card for user {UserId}", userId);
            return StatusCode(StatusCodes.Status500InternalServerError, new ErrorResponse("AI card interpretation encountered an internal error."));
        }
    }

    private string? GetCurrentUserId()
    {
        return User.FindFirstValue(ClaimTypes.NameIdentifier);
    }
}

