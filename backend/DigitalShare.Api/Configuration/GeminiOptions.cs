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
    /// Configurable Gemini model identifier. Use a model that supports multimodal image input and
    /// structured JSON output (responseMimeType). Supported: "gemini-2.0-flash", "gemini-2.5-flash",
    /// "gemini-1.5-flash", "gemini-1.5-pro". Avoid non-existent aliases like "gemini-3.8-flash".
    /// </summary>
    public string ModelId { get; set; } = "gemini-2.0-flash";

    /// <summary>
    /// Optional lighter/faster fallback model identifier used when the primary model fails or is
    /// rate-limited. Supported: "gemini-2.0-flash-lite", "gemini-1.5-flash-8b".
    /// </summary>
    public string FallbackModelId { get; set; } = "gemini-2.0-flash-lite";

    /// <summary>
    /// REST endpoint format for Google GenAI v1beta generateContent.
    /// Format: https://generativelanguage.googleapis.com/v1beta/models/{0}:generateContent
    /// </summary>
    public string EndpointTemplate { get; set; } = "https://generativelanguage.googleapis.com/v1beta/models/{0}:generateContent";

    /// <summary>
    /// Total request timeout in seconds for text-only Gemini requests.
    /// </summary>
    public int TimeoutSeconds { get; set; } = 30;

    /// <summary>
    /// Total request timeout in seconds for multimodal (image+text) Gemini requests.
    /// Multimodal calls are slower due to image tokenization; use a longer timeout.
    /// </summary>
    public int TimeoutSecondsMultimodal { get; set; } = 45;

    /// <summary>
    /// Bounded retry count for transient HTTP 429 and 503 errors.
    /// </summary>
    public int MaxRetries { get; set; } = 2;

    /// <summary>
    /// Master feature flag to enable/disable Gemini AI enhancement globally.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// Configurable cost per 1M input/prompt tokens in USD (e.g. 0.10 for gemini-2.0-flash).
    /// Used for non-billing cost estimations only; actual billing is via Google Cloud Console.
    /// </summary>
    public decimal InputPricePerMillionTokens { get; set; } = 0.10m;

    /// <summary>
    /// Configurable cost per 1M output/candidate tokens in USD (e.g. 0.40 for gemini-2.0-flash).
    /// Used for non-billing cost estimations only; actual billing is via Google Cloud Console.
    /// </summary>
    public decimal OutputPricePerMillionTokens { get; set; } = 0.40m;
}

