using DigitalShare.Api.DTOs.Consent;
using DigitalShare.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DigitalShare.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class LegalController : ControllerBase
{
    private readonly ILegalDocumentService _legalService;

    public LegalController(ILegalDocumentService legalService)
    {
        _legalService = legalService;
    }

    /// <summary>
    /// Returns jurisdiction-aware Terms of Service, Privacy Policy, and Cookie Policy.
    /// Supports India (DPDP Act, IT Act), EU (GDPR), UK (UK GDPR, PECR), US (CCPA), and Global.
    /// </summary>
    [HttpGet("documents")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(LegalDocumentResponse), StatusCodes.Status200OK)]
    public IActionResult GetLegalDocuments([FromQuery] string? jurisdiction = null)
    {
        var documents = _legalService.GetLegalDocuments(jurisdiction);
        return Ok(documents);
    }
}

