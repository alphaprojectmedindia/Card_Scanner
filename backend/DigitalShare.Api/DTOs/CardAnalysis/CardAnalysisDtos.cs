using System.ComponentModel.DataAnnotations;

namespace DigitalShare.Api.DTOs.CardAnalysis;

public class AnalyzeBusinessCardRequest
{
    [Required]
    [MaxLength(64)]
    public string ClientRequestId { get; set; } = string.Empty;

    [Required]
    [MaxLength(64)]
    public string ScanContentHash { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? FrontImageStorageKey { get; set; }

    [MaxLength(500)]
    public string? BackImageStorageKey { get; set; }

    [Required]
    [MaxLength(150)]
    public string InvocationReason { get; set; } = string.Empty;

    [Required]
    [MaxLength(50)]
    public string AnalysisMode { get; set; } = "TextAndLayout"; // TextAndLayout or MultimodalVision

    [MaxLength(64)]
    public string? FrontImageSha256 { get; set; }

    [MaxLength(64)]
    public string? BackImageSha256 { get; set; }

    public List<string> UncertainFields { get; set; } = new();

    public Dictionary<string, FieldEvidenceDto>? LocalFieldEvidence { get; set; }

    public ImageDimensionsDto? ImageDimensions { get; set; }

    public List<OcrObservationDto> OcrObservations { get; set; } = new();

    public LocalParserBaselineDto? LocalBaseline { get; set; }

    public string? PaddleOcrRawText { get; set; }

    public string? MlKitRawText { get; set; }

    public string? ScanId { get; set; }

    public string PipelineVersion { get; set; } = "2.0.0";

    public string ParserVersion { get; set; } = "5.0.0";

    public string OcrModelVersion { get; set; } = "PP-OCRv5";

    public string GeminiPromptVersion { get; set; } = "3.0.0";
}

public class ImageDimensionsDto
{
    public int Width { get; set; }
    public int Height { get; set; }
}

public class OcrObservationDto
{
    [Required]
    public string Id { get; set; } = string.Empty;

    [Required]
    public string Text { get; set; } = string.Empty;

    [Required]
    public string Engine { get; set; } = string.Empty;

    public string CardSide { get; set; } = "front";

    public int LineIndex { get; set; }

    public double Confidence { get; set; } = 1.0;

    public string? Region { get; set; }

    [Required]
    public NormalizedBoundingBoxDto BoundingBox { get; set; } = new();
}

public class NormalizedBoundingBoxDto
{
    public double Top { get; set; }
    public double Left { get; set; }
    public double Bottom { get; set; }
    public double Right { get; set; }
}

public class LocalParserBaselineDto
{
    public string? FullName { get; set; }
    public string? Company { get; set; }
    public string? JobTitle { get; set; }
    public string? Website { get; set; }
    public string? Address { get; set; }
    public List<string> PhoneNumbers { get; set; } = new();
    public List<string> EmailAddresses { get; set; } = new();
    public List<string> UnclassifiedLines { get; set; } = new();
}

public class AnalyzeBusinessCardResponse
{
    public string ClientRequestId { get; set; } = string.Empty;
    public string AnalysisCacheKey { get; set; } = string.Empty;

    public ExtractedFieldDto FullName { get; set; } = new();
    public ExtractedFieldDto Company { get; set; } = new();
    public ExtractedFieldDto JobTitle { get; set; } = new();
    public ExtractedAddressDto Address { get; set; } = new();

    public List<ExtractedPhoneDto> PhoneNumbers { get; set; } = new();
    public List<ExtractedEmailDto> EmailAddresses { get; set; } = new();
    public List<ExtractedWebsiteDto> Websites { get; set; } = new();

    public string? Department { get; set; }
    public string? Credentials { get; set; }
    public List<string> UnclassifiedLines { get; set; } = new();

    public double OverallConfidence { get; set; }
    public bool RequiresManualReview { get; set; }
    public List<string> ReviewWarnings { get; set; } = new();

    public string ModelId { get; set; } = string.Empty;
    public bool FromCache { get; set; } = false;
    public long ProcessingDurationMs { get; set; }
    public bool FallbackToLocalBaseline { get; set; } = false;
    public GeminiUsageMetadataDto? UsageMetadata { get; set; }

    public bool VisualVerificationPerformed { get; set; } = false;
    public bool FrontImageVerified { get; set; } = false;
    public bool BackImageVerified { get; set; } = false;
    public string? ImageVerificationFailureReason { get; set; }
    public Dictionary<string, FieldVerificationDto> FieldVerifications { get; set; } = new();

    /// <summary>
    /// Indicates whether the Google Gemini API REST request was actually executed over HTTP,
    /// distinguishing real API execution from decision-only or local fallback.
    /// </summary>
    public bool GeminiApiExecuted { get; set; } = false;

    /// <summary>
    /// Detailed execution status (e.g. ExecutedSuccessfully, FallbackServiceDisabled, FallbackApiKeyMissing, FallbackTimeout, FallbackError).
    /// </summary>
    public string GeminiExecutionStatus { get; set; } = string.Empty;

    /// <summary>
    /// Indicates whether the backend successfully retrieved the front card image from storage.
    /// </summary>
    public bool FrontImageReceived { get; set; } = false;

    /// <summary>
    /// Indicates whether the backend successfully retrieved the back card image from storage.
    /// </summary>
    public bool BackImageReceived { get; set; } = false;
}

public class FieldEvidenceDto
{
    public string FieldName { get; set; } = string.Empty;
    public string OriginalOcrText { get; set; } = string.Empty;
    public string NormalizedValue { get; set; } = string.Empty;
    public string SourceEngine { get; set; } = string.Empty;
    public List<string> SourceObservationIds { get; set; } = new();
    public double OcrConfidence { get; set; } = 1.0;
    public double ParserConfidence { get; set; } = 1.0;
    public string VerificationStatus { get; set; } = "probable"; // verified, probable, reviewRequired, rejected, notFound
    public string? UserApprovedValue { get; set; }
    public string VerificationSource { get; set; } = "ocrBaseline";
    public string? UncertaintyReason { get; set; }
    public string CardSide { get; set; } = "front";
}

public class FieldVerificationDto
{
    public string FieldName { get; set; } = string.Empty;
    public string? ProposedValue { get; set; }
    public string? OriginalLocalParserValue { get; set; }
    public string SupportingCardSide { get; set; } = "front"; // front, back, both, none
    public string? VisualEvidenceDescription { get; set; }
    public string VerificationStatus { get; set; } = "probable"; // verified, probable, reviewRequired, rejected, notFound
    public string? CorrectionReason { get; set; }
    public bool IsGenuinelyReadable { get; set; } = true;
    public bool IsVisuallyVerified { get; set; } = false;
    public double Confidence { get; set; } = 1.0;
    public List<string> SourceObservationIds { get; set; } = new();
    public bool WasCorrected { get; set; } = false;
    public bool ReviewRequired { get; set; } = false;
}

public class GeminiUsageMetadataDto
{
    public int PromptTokenCount { get; set; }
    public int CandidatesTokenCount { get; set; }
    public int TotalTokenCount { get; set; }
    public decimal EstimatedCostUsd { get; set; }
    public bool IsEstimatedCost { get; set; } = true;
    public string CostCalculationNotes { get; set; } = string.Empty;
}

public class ExtractedFieldDto
{
    public string? Value { get; set; }
    public double Confidence { get; set; }
    public string? RawEvidence { get; set; }
    public List<string> SourceObservationIds { get; set; } = new();
    public bool WasCorrected { get; set; }
    public bool ReviewRequired { get; set; }

    public string? ProposedValue { get; set; }
    public string? OriginalLocalParserValue { get; set; }
    public string SupportingCardSide { get; set; } = "front"; // front, back, both, none
    public string? VisualEvidenceDescription { get; set; }
    public string VerificationStatus { get; set; } = "probable"; // verified, probable, reviewRequired, rejected, notFound
    public string? CorrectionReason { get; set; }
    public bool IsGenuinelyReadable { get; set; } = true;
    public bool IsVisuallyVerified { get; set; } = false;
}

public class ExtractedPhoneDto
{
    public string Number { get; set; } = string.Empty;
    public string NormalizedNumber { get; set; } = string.Empty;
    public string Label { get; set; } = "Mobile";
    public double Confidence { get; set; }
    public string? RawEvidence { get; set; }
    public List<string> SourceObservationIds { get; set; } = new();
    public bool ReviewRequired { get; set; }

    public string? ProposedValue { get; set; }
    public string? OriginalLocalParserValue { get; set; }
    public string SupportingCardSide { get; set; } = "front";
    public string? VisualEvidenceDescription { get; set; }
    public string VerificationStatus { get; set; } = "probable";
    public string? CorrectionReason { get; set; }
    public bool IsGenuinelyReadable { get; set; } = true;
    public bool IsVisuallyVerified { get; set; } = false;
    public bool WasCorrected { get; set; } = false;
}

public class ExtractedEmailDto
{
    public string Email { get; set; } = string.Empty;
    public string NormalizedEmail { get; set; } = string.Empty;
    public string Label { get; set; } = "Work";
    public double Confidence { get; set; }
    public string? RawEvidence { get; set; }
    public List<string> SourceObservationIds { get; set; } = new();
    public bool ReviewRequired { get; set; }

    public string? ProposedValue { get; set; }
    public string? OriginalLocalParserValue { get; set; }
    public string SupportingCardSide { get; set; } = "front";
    public string? VisualEvidenceDescription { get; set; }
    public string VerificationStatus { get; set; } = "probable";
    public string? CorrectionReason { get; set; }
    public bool IsGenuinelyReadable { get; set; } = true;
    public bool IsVisuallyVerified { get; set; } = false;
    public bool WasCorrected { get; set; } = false;
}

public class ExtractedWebsiteDto
{
    public string Url { get; set; } = string.Empty;
    public double Confidence { get; set; }
    public string? RawEvidence { get; set; }
    public List<string> SourceObservationIds { get; set; } = new();

    public string? ProposedValue { get; set; }
    public string? OriginalLocalParserValue { get; set; }
    public string SupportingCardSide { get; set; } = "front";
    public string? VisualEvidenceDescription { get; set; }
    public string VerificationStatus { get; set; } = "probable";
    public string? CorrectionReason { get; set; }
    public bool IsGenuinelyReadable { get; set; } = true;
    public bool IsVisuallyVerified { get; set; } = false;
    public bool WasCorrected { get; set; } = false;
}

public class ExtractedAddressDto
{
    public string? FullAddress { get; set; }
    public string? Street { get; set; }
    public string? City { get; set; }
    public string? State { get; set; }
    public string? PostalCode { get; set; }
    public string? Country { get; set; }
    public double Confidence { get; set; }
    public List<string> SourceObservationIds { get; set; } = new();
    public bool ReviewRequired { get; set; }

    public string? ProposedValue { get; set; }
    public string? OriginalLocalParserValue { get; set; }
    public string SupportingCardSide { get; set; } = "front";
    public string? VisualEvidenceDescription { get; set; }
    public string VerificationStatus { get; set; } = "probable";
    public string? CorrectionReason { get; set; }
    public bool IsGenuinelyReadable { get; set; } = true;
    public bool IsVisuallyVerified { get; set; } = false;
    public bool WasCorrected { get; set; } = false;
}

public class ImageUploadResponse
{
    public string StorageKey { get; set; } = string.Empty;
    public string CardSide { get; set; } = "front";
    public long FileSizeBytes { get; set; }
    public DateTime UploadedAtUtc { get; set; } = DateTime.UtcNow;
}

