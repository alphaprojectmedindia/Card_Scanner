using System.Security.Claims;
using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.DTOs.ImportedContacts;
using DigitalShare.Api.Exceptions;
using DigitalShare.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DigitalShare.Api.Controllers;

[ApiController]
[Route("api/imported-contacts")]
[Authorize]
[Produces("application/json")]
public class ImportedContactsController : ControllerBase
{
    private readonly IImportedContactService _importedContactService;

    public ImportedContactsController(IImportedContactService importedContactService)
    {
        _importedContactService = importedContactService;
    }

    /// <summary>
    /// Checks if a business card with any matching phone number or email address is already saved
    /// by the authenticated user.
    /// </summary>
    [HttpPost("check-duplicate")]
    [ProducesResponseType(typeof(CheckDuplicateResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> CheckDuplicate([FromBody] CheckDuplicateRequest request)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var result = await _importedContactService.CheckDuplicateAsync(userId, request);
        return Ok(result);
    }

    /// <summary>
    /// Save an imported physical business card for the authenticated user.
    /// Supports idempotency via Idempotency-Key header or ClientRequestId in body.
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(ImportedContactResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> SaveContact(
        [FromBody] SaveImportedContactRequest request,
        [FromHeader(Name = "Idempotency-Key")] string? idempotencyKeyHeader = null)
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

        var clientRequestId = !string.IsNullOrWhiteSpace(idempotencyKeyHeader)
            ? idempotencyKeyHeader.Trim()
            : request.ClientRequestId?.Trim();

        if (!string.IsNullOrEmpty(clientRequestId) && clientRequestId.Length > 64)
        {
            return BadRequest(new ErrorResponse("Idempotency key cannot exceed 64 characters."));
        }

        if (string.IsNullOrWhiteSpace(request.FullName) &&
            string.IsNullOrWhiteSpace(request.Company) &&
            !request.PhoneNumbers.Any(p => !string.IsNullOrWhiteSpace(p.Number)) &&
            !request.EmailAddresses.Any(e => !string.IsNullOrWhiteSpace(e.Email)))
        {
            return BadRequest(new ErrorResponse("Cannot save an empty contact."));
        }

        try
        {
            var result = await _importedContactService.SaveContactAsync(userId, request, clientRequestId);
            return CreatedAtAction(nameof(GetContactById), new { id = result.Id }, result);
        }
        catch (IdempotencyConflictException ex)
        {
            return Conflict(new ErrorResponse(ex.Message));
        }
    }

    /// <summary>
    /// Retrieve all imported business cards saved by the authenticated user, newest first.
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<ImportedContactResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> GetContacts()
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var contacts = await _importedContactService.GetContactsAsync(userId);
        return Ok(contacts);
    }

    /// <summary>
    /// Retrieve a specific imported business card by its unique ID.
    /// </summary>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(ImportedContactResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetContactById(Guid id)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var contact = await _importedContactService.GetContactByIdAsync(userId, id);
        if (contact == null)
        {
            return NotFound(new ErrorResponse("Imported business card not found."));
        }

        return Ok(contact);
    }

    /// <summary>
    /// Update an existing imported business card.
    /// Replaces child phone numbers and email addresses completely.
    /// </summary>
    [HttpPut("{id:guid}")]
    [ProducesResponseType(typeof(ImportedContactResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> UpdateContact(Guid id, [FromBody] UpdateImportedContactRequest request)
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

        if (string.IsNullOrWhiteSpace(request.FullName) &&
            string.IsNullOrWhiteSpace(request.Company) &&
            !request.PhoneNumbers.Any(p => !string.IsNullOrWhiteSpace(p.Number)) &&
            !request.EmailAddresses.Any(e => !string.IsNullOrWhiteSpace(e.Email)))
        {
            return BadRequest(new ErrorResponse("Cannot update to an empty contact."));
        }

        var updated = await _importedContactService.UpdateContactAsync(userId, id, request);
        if (updated == null)
        {
            return NotFound(new ErrorResponse("Imported business card not found."));
        }

        return Ok(updated);
    }

    /// <summary>
    /// Update or add a private personal remark on an imported business card.
    /// Strictly authorized: only the owner can modify their remark.
    /// </summary>
    [HttpPut("{id:guid}/remark")]
    [ProducesResponseType(typeof(ImportedContactResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> UpdateRemark(Guid id, [FromBody] UpdateContactRemarkRequest request)
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

        var updated = await _importedContactService.UpdateRemarkAsync(userId, id, request.Remark);
        if (updated == null)
        {
            return NotFound(new ErrorResponse("Imported business card not found."));
        }

        return Ok(updated);
    }

    /// <summary>
    /// Clear a private personal remark from an imported business card.
    /// </summary>
    [HttpDelete("{id:guid}/remark")]
    [ProducesResponseType(typeof(ImportedContactResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> ClearRemark(Guid id)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var updated = await _importedContactService.ClearRemarkAsync(userId, id);
        if (updated == null)
        {
            return NotFound(new ErrorResponse("Imported business card not found."));
        }

        return Ok(updated);
    }

    /// <summary>
    /// Permanently delete an imported business card.
    /// Cascades to associated phone numbers and email addresses.
    /// </summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DeleteContact(Guid id)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        var deleted = await _importedContactService.DeleteContactAsync(userId, id);
        if (!deleted)
        {
            return NotFound(new ErrorResponse("Imported business card not found."));
        }

        return NoContent();
    }

    private string? GetCurrentUserId()
    {
        return User.FindFirstValue(ClaimTypes.NameIdentifier);
    }
}
