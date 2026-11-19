using DigitalShare.Api.DTOs.Consent;

namespace DigitalShare.Api.Services;

public interface ILegalDocumentService
{
    LegalDocumentResponse GetLegalDocuments(string? jurisdiction);
}

