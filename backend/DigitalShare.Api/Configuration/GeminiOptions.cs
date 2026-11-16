namespace DigitalShare.Api.Configuration;

/// <summary>
/// Configuration settings for Google Gemini API integration.
/// API keys must be provided via environment variables (e.g. Gemini__ApiKey) or secret store.
/// </summary>
public class GeminiOptions
{
    public const string SectionName = "Gemini";

    /// <summary>
    /// Google GenAI API key. Kept exclusively on the backend.
    /// </summary>
    public string ApiKey { get; set; } = string.Empty;

    /// <summary>
    /// Configurable Gemini model identifier (e.g. "gemini-3.8-flash", "gemini-3.5-flash-lite", "gemini-2.5-flash").
    /// </summary>
    public string ModelId { get; set; } = "gemini-3.8-flash";

    /// <summary>
    /// Optional lighter/faster fallback model identifier.
    /// </summary>
    public string FallbackModelId { get; set; } = "gemini-3.5-flash-lite";

    /// <summary>
    /// REST endpoint format for Google GenAI v1beta generateContent.
    /// Format: https://generativelanguage.googleapis.com/v1beta/models/{0}:generateContent
    /// </summary>
    public string EndpointTemplate { get; set; } = "https://generativelanguage.googleapis.com/v1beta/models/{0}:generateContent";

    /// <summary>
    /// Total request timeout in seconds before failing soft to local OCR.
    /// </summary>
    public int TimeoutSeconds { get; set; } = 8;

    /// <summary>
    /// Bounded retry count for transient HTTP 429 and 503 errors.
    /// </summary>
    public int MaxRetries { get; set; } = 2;

    /// <summary>
    /// Master feature flag to enable/disable Gemini AI enhancement globally.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// Configurable cost per 1M input/prompt tokens in USD (e.g. 0.15 for gemini-3.8-flash).
    /// Used for non-billing cost estimations.
    /// </summary>
    public decimal InputPricePerMillionTokens { get; set; } = 0.15m;

    /// <summary>
    /// Configurable cost per 1M output/candidate tokens in USD (e.g. 0.60 for gemini-3.8-flash).
    /// Used for non-billing cost estimations.
    /// </summary>
    public decimal OutputPricePerMillionTokens { get; set; } = 0.60m;
}

