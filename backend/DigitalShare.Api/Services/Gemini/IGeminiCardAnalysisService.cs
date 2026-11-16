using DigitalShare.Api.DTOs.CardAnalysis;

namespace DigitalShare.Api.Services.Gemini;

/// <summary>
/// Service contract for orchestrating Google Gemini AI-assisted business card interpretation.
/// </summary>
public interface IGeminiCardAnalysisService
{
    /// <summary>
    /// Analyzes business card OCR observations and optional images with Gemini.
    /// Handles distributed idempotency, caching, timeouts, and validation.
    /// </summary>
    Task<AnalyzeBusinessCardResponse> AnalyzeCardAsync(
        string userId,
        AnalyzeBusinessCardRequest request,
        CancellationToken ct = default);
}

