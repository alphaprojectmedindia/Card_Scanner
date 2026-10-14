using System.Security.Claims;
using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.DTOs.ImportedContacts;
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
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(ImportedContactResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> SaveContact([FromBody] SaveImportedContactRequest request)
    {
        var userId = GetCurrentUserId();
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized(new ErrorResponse("Unauthorized user context."));
        }

        if (string.IsNullOrWhiteSpace(request.FullName) &&
            string.IsNullOrWhiteSpace(request.Company) &&
            !request.PhoneNumbers.Any() &&
            !request.EmailAddresses.Any())
        {
            return BadRequest(new ErrorResponse("Cannot save an empty contact."));
        }

        var result = await _importedContactService.SaveContactAsync(userId, request);
        return CreatedAtAction(nameof(GetContactById), new { id = result.Id }, result);
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
    /// Retrieve a single imported business card by its unique identifier.
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
    /// Update details and child phones/emails for a saved imported business card.
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

        var updated = await _importedContactService.UpdateContactAsync(userId, id, request);
        if (updated == null)
        {
            return NotFound(new ErrorResponse("Imported business card not found."));
        }

        return Ok(updated);
    }

    /// <summary>
    /// Delete a saved imported business card and all associated phone/email children.
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
        return User.FindFirstValue(ClaimTypes.NameIdentifier)
               ?? User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)?.Value;
    }
}
