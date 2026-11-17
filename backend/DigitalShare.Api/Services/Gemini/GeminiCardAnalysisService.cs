using System.Diagnostics;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization.Metadata;
using DigitalShare.Api.Configuration;
using DigitalShare.Api.DTOs.CardAnalysis;
using DigitalShare.Api.Models;
using DigitalShare.Api.Services.Storage;
using Microsoft.Extensions.Options;

namespace DigitalShare.Api.Services.Gemini;

public class GeminiCardAnalysisService : IGeminiCardAnalysisService
{
    private readonly HttpClient _httpClient;
    private readonly GeminiOptions _options;
    private readonly IScanImageStorageService _storageService;
    private readonly CardAnalysisSemanticValidator _validator;
    private readonly CardAnalysisIdempotencyManager _idempotencyManager;
    private readonly ILogger<GeminiCardAnalysisService> _logger;

    private static readonly JsonSerializerOptions PayloadSerializerOptions = new()
    {
        WriteIndented = false,
        TypeInfoResolver = new DefaultJsonTypeInfoResolver()
    };

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        TypeInfoResolver = new DefaultJsonTypeInfoResolver()
    };

    public GeminiCardAnalysisService(
        HttpClient httpClient,
        IOptions<GeminiOptions> options,
        IScanImageStorageService storageService,
        CardAnalysisSemanticValidator validator,
        CardAnalysisIdempotencyManager idempotencyManager,
        ILogger<GeminiCardAnalysisService> logger)
    {
        _httpClient = httpClient;
        _options = options.Value;
        _storageService = storageService;
        _validator = validator;
        _idempotencyManager = idempotencyManager;
        _logger = logger;
    }

    public async Task<AnalyzeBusinessCardResponse> AnalyzeCardAsync(
        string userId,
        AnalyzeBusinessCardRequest request,
        CancellationToken ct = default)
    {
        var stopwatch = Stopwatch.StartNew();

        // 1. Check feature flag & API key presence
        if (!_options.Enabled || string.IsNullOrWhiteSpace(_options.ApiKey))
        {
            var fallbackStatus = !_options.Enabled ? "FallbackServiceDisabled" : "FallbackApiKeyMissing";
            _logger.LogWarning("Gemini AI analysis requested but service is disabled or API key is missing ({Reason}). Falling back to local baseline.", fallbackStatus);
            var fallback = BuildFallbackFromBaseline(request, $"Gemini service is disabled or unconfigured ({fallbackStatus}).", stopwatch.ElapsedMilliseconds);
            fallback.GeminiApiExecuted = false;
            fallback.GeminiExecutionStatus = fallbackStatus;
            fallback.ModelId = _options.ModelId;
            return fallback;
        }

        // 2. Compute canonical cache key
        var cacheKey = _idempotencyManager.ComputeAnalysisCacheKey(userId, request, _options.ModelId);

        // 3. Check persistent cache in ScanJobs
        var cached = await _idempotencyManager.TryGetCompletedResultAsync(userId, cacheKey, ct);
        if (cached != null)
        {
            cached.ClientRequestId = request.ClientRequestId;
            cached.ProcessingDurationMs = stopwatch.ElapsedMilliseconds;
            cached.GeminiApiExecuted = false; // Served from local/persistent idempotency cache
            cached.GeminiExecutionStatus = "ServedFromIdempotentCache";
            return cached;
        }

        // 4. Concurrency & distributed lease acquisition
        var workerInstanceId = Environment.MachineName + "_" + Guid.NewGuid().ToString("N")[..8];
        var (leaseResult, job) = await _idempotencyManager.TryAcquireLeaseAsync(
            userId,
            cacheKey,
            workerInstanceId,
            request,
            TimeSpan.FromSeconds(_options.TimeoutSeconds * 2),
            ct);

        if (leaseResult == LeaseAcquisitionResult.AlreadyCompleted)
        {
            var completedCached = await _idempotencyManager.TryGetCompletedResultAsync(userId, cacheKey, ct);
            if (completedCached != null)
            {
                completedCached.ClientRequestId = request.ClientRequestId;
                completedCached.GeminiApiExecuted = false;
                completedCached.GeminiExecutionStatus = "ServedFromCompletedLeaseCache";
                return completedCached;
            }
        }

        if (leaseResult == LeaseAcquisitionResult.LockedByAnotherWorker)
        {
            _logger.LogInformation("Job {CacheKey} is in-flight on another instance. Awaiting shared result.", cacheKey);
            var inFlightResult = await _idempotencyManager.AwaitInFlightJobAsync(
                userId, cacheKey, TimeSpan.FromSeconds(_options.TimeoutSeconds), ct);

            if (inFlightResult != null)
            {
                inFlightResult.ClientRequestId = request.ClientRequestId;
                inFlightResult.GeminiApiExecuted = true;
                inFlightResult.GeminiExecutionStatus = "ExecutedByPeerWorker";
                return inFlightResult;
            }
        }

        // 5. Execute Gemini REST call with Polly / bounded retries
        try
        {
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(_options.TimeoutSeconds));

            var rawAnalysisResponse = await ExecuteGeminiCallWithRetriesAsync(request, timeoutCts.Token);

            rawAnalysisResponse.ClientRequestId = request.ClientRequestId;
            rawAnalysisResponse.AnalysisCacheKey = cacheKey;
            rawAnalysisResponse.ModelId = _options.ModelId;
            rawAnalysisResponse.ProcessingDurationMs = stopwatch.ElapsedMilliseconds;
            rawAnalysisResponse.GeminiApiExecuted = true;
            rawAnalysisResponse.GeminiExecutionStatus = "ExecutedSuccessfully";
            rawAnalysisResponse.FrontImageReceived = rawAnalysisResponse.FrontImageVerified;
            rawAnalysisResponse.BackImageReceived = rawAnalysisResponse.BackImageVerified;

            // 6. Evidence-based semantic validation
            var validatedResponse = _validator.ValidateAndNormalize(rawAnalysisResponse, request);

            // 7. Persist completed result in ScanJobs
            await _idempotencyManager.CompleteJobAsync(job, validatedResponse, ct);

            _logger.LogInformation(
                "[Gemini Execution Audit] Scan/ClientRequestId={RequestId}, UserId={UserId}, ApiExecuted={Executed}, Model={Model}, FrontImg={Front}, BackImg={Back}, Status={Status}, PromptTokens={Prompt}, CandidateTokens={Candidate}, Duration={Duration}ms",
                request.ClientRequestId, userId, validatedResponse.GeminiApiExecuted, validatedResponse.ModelId, validatedResponse.FrontImageReceived, validatedResponse.BackImageReceived, validatedResponse.GeminiExecutionStatus, validatedResponse.UsageMetadata?.PromptTokenCount ?? 0, validatedResponse.UsageMetadata?.CandidatesTokenCount ?? 0, stopwatch.ElapsedMilliseconds);

            return validatedResponse;
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            _logger.LogWarning("Gemini API call timed out after {Timeout}s. Falling back to local OCR baseline.", _options.TimeoutSeconds);
            await _idempotencyManager.FailJobAsync(job, "Request timed out.", ct);
            var fallback = BuildFallbackFromBaseline(request, "Gemini API timed out; defaulted to local OCR draft.", stopwatch.ElapsedMilliseconds);
            fallback.GeminiApiExecuted = true; // request was attempted/sent to Google
            fallback.GeminiExecutionStatus = "FallbackTimeout";
            fallback.ModelId = _options.ModelId;
            return fallback;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Gemini API call failed for user {UserId}. Falling back to local OCR baseline.", userId);
            await _idempotencyManager.FailJobAsync(job, ex.Message, ct);
            var fallback = BuildFallbackFromBaseline(request, $"Gemini analysis error: {ex.Message}", stopwatch.ElapsedMilliseconds);
            fallback.GeminiApiExecuted = false;
            fallback.GeminiExecutionStatus = $"FallbackError: {ex.Message}";
            fallback.ModelId = _options.ModelId;
            return fallback;
        }
    }

    internal async Task<AnalyzeBusinessCardResponse> ExecuteGeminiCallWithRetriesAsync(
        AnalyzeBusinessCardRequest request,
        CancellationToken ct)
    {
        var modelId = _options.ModelId;
        var encodedKey = Uri.EscapeDataString(_options.ApiKey);
        var url = string.Format(_options.EndpointTemplate, modelId) + $"?key={encodedKey}";

        var (payload, frontRetrieved, backRetrieved, retrievalFailure) = await BuildGeminiRestPayloadWithImageStatusAsync(request, ct);

        HttpResponseMessage? response = null;
        var attempts = 0;
        var maxAttempts = Math.Max(1, _options.MaxRetries + 1);

        while (attempts < maxAttempts)
        {
            attempts++;
            try
            {
                using var requestMessage = new HttpRequestMessage(HttpMethod.Post, url)
                {
                    Content = new StringContent(payload, Encoding.UTF8, "application/json")
                };
                requestMessage.Headers.TryAddWithoutValidation("x-goog-api-key", _options.ApiKey);

                response = await _httpClient.SendAsync(requestMessage, ct);

                if (response.IsSuccessStatusCode)
                {
                    break;
                }

                var statusCode = (int)response.StatusCode;
                var isTransient = response.StatusCode == HttpStatusCode.TooManyRequests ||
                                  (statusCode >= 500 && statusCode <= 599);

                if (isTransient && attempts < maxAttempts)
                {
                    var backoffMs = (int)(Math.Pow(2, attempts) * 500);
                    _logger.LogWarning("Gemini API returned {StatusCode}. Retrying in {Backoff}ms (attempt {Attempt}/{Max})",
                        response.StatusCode, backoffMs, attempts, maxAttempts);
                    await Task.Delay(backoffMs, ct);
                    continue;
                }

                var errorText = await response.Content.ReadAsStringAsync(ct);
                throw new InvalidOperationException($"Gemini API error ({response.StatusCode}): {errorText}");
            }
            catch (InvalidOperationException)
            {
                // Permanent failure (e.g. 400 Bad Request, 401 Unauthorized, 403 Forbidden) must not be retried.
                throw;
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex) when (attempts < maxAttempts && !ct.IsCancellationRequested)
            {
                _logger.LogWarning(ex, "Gemini API request failed with network/transient exception. Retrying attempt {Attempt}/{Max}",
                    attempts, maxAttempts);
                await Task.Delay(500 * attempts, ct);
            }
        }

        if (response == null || !response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"Gemini API call failed after {attempts} attempts.");
        }

        var responseBody = await response.Content.ReadAsStringAsync(ct);
        return ParseGeminiResponse(responseBody, request, frontRetrieved, backRetrieved, retrievalFailure);
    }

    public async Task<string> BuildGeminiRestPayloadAsync(
        AnalyzeBusinessCardRequest request,
        CancellationToken ct = default)
    {
        var (payload, _, _, _) = await BuildGeminiRestPayloadWithImageStatusAsync(request, ct);
        return payload;
    }

    public async Task<(string Payload, bool FrontRetrieved, bool BackRetrieved, string? RetrievalFailure)> BuildGeminiRestPayloadWithImageStatusAsync(
        AnalyzeBusinessCardRequest request,
        CancellationToken ct = default)
    {
        var partsList = new JsonArray();
        bool isMultimodal = string.Equals(request.AnalysisMode, "MultimodalVision", StringComparison.OrdinalIgnoreCase);
        bool frontRetrieved = false;
        bool backRetrieved = false;
        string? retrievalFailure = null;

        // Path B: If MultimodalVision is requested, retrieve and encode both front and back images
        if (isMultimodal)
        {
            if (!string.IsNullOrWhiteSpace(request.FrontImageStorageKey))
            {
                try
                {
                    var frontStream = await _storageService.GetScanImageStreamAsync(request.FrontImageStorageKey, ct);
                    if (frontStream != null)
                    {
                        using (frontStream)
                        using (var ms = new MemoryStream())
                        {
                            await frontStream.CopyToAsync(ms, ct);
                            if (ms.Length > 0)
                            {
                                var base64Data = Convert.ToBase64String(ms.ToArray());
                                partsList.Add(new JsonObject
                                {
                                    ["inlineData"] = new JsonObject
                                    {
                                        ["mimeType"] = "image/jpeg",
                                        ["data"] = base64Data
                                    }
                                });
                                frontRetrieved = true;
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to retrieve front image {Key} from storage", request.FrontImageStorageKey);
                }
            }

            if (!string.IsNullOrWhiteSpace(request.BackImageStorageKey))
            {
                try
                {
                    var backStream = await _storageService.GetScanImageStreamAsync(request.BackImageStorageKey, ct);
                    if (backStream != null)
                    {
                        using (backStream)
                        using (var ms = new MemoryStream())
                        {
                            await backStream.CopyToAsync(ms, ct);
                            if (ms.Length > 0)
                            {
                                var backBase64Data = Convert.ToBase64String(ms.ToArray());
                                partsList.Add(new JsonObject
                                {
                                    ["inlineData"] = new JsonObject
                                    {
                                        ["mimeType"] = "image/jpeg",
                                        ["data"] = backBase64Data
                                    }
                                });
                                backRetrieved = true;
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to retrieve back image {Key} from storage", request.BackImageStorageKey);
                }
            }

            if (!frontRetrieved && !backRetrieved)
            {
                retrievalFailure = "Card image(s) requested for multimodal visual verification could not be retrieved from storage.";
            }
        }

        // Text prompt with 2D spatial layout, observations, and strict integrity rules
        var sb = new StringBuilder();
        sb.AppendLine("You are the AI Business Card Intelligence Engine for Digital Share.");
        sb.AppendLine("TASK: Multimodal visual verification, error reconciliation, and evidence-grounded parsing of business card details.");
        sb.AppendLine("Ground every extracted or corrected field strictly in visible card pixels and provided source observation IDs.");
        sb.AppendLine("Reasoning context for invocation: " + request.InvocationReason);
        sb.AppendLine();
        sb.AppendLine("CRITICAL DATA INTEGRITY & VISUAL VERIFICATION RULES (STRICT NEGATIVE CONSTRAINTS):");
        sb.AppendLine("1. NEVER invent, hallucinate, or extrapolate missing information that is absent from the card.");
        sb.AppendLine("2. If a field is not present on the card, set its verificationStatus to 'notFound', value to null, and proposedValue to null. Do NOT manufacture data.");
        sb.AppendLine("3. If text is blurry, occluded, or unreadable, mark isGenuinelyReadable = false, verificationStatus = 'reviewRequired', and set confidence < 0.70. Do NOT guess unreadable characters.");
        sb.AppendLine("4. NEVER infer a person's name from an email address or website domain name (e.g. do not infer 'John Doe' from 'johndoe@company.com').");
        sb.AppendLine("5. NEVER assume or invent a company name from a logo icon or artwork unless readable company text is clearly visible.");
        sb.AppendLine("6. NEVER assign an organization, corporate entity, or company name (e.g. 'Apex Healthcare', 'Summit Consulting') to the fullName field.");
        sb.AppendLine("7. NEVER assign a job title, occupational designation, or physical address line to the company field.");
        sb.AppendLine("8. NEVER move candidate values across fields without direct visual and OCR evidence.");
        sb.AppendLine("9. Ground every field in sourceObservationIds referencing the exact observation IDs provided.");
        sb.AppendLine("10. Front card observations and front image pixels must ONLY support front-side fields; back observations and back image pixels must ONLY support back-side fields.");
        sb.AppendLine("11. Provide field-level structured output with verificationStatus ('verified', 'probable', 'reviewRequired', 'rejected', 'notFound'), isVisuallyVerified (true only if image is readable and verified against pixels), proposedValue, originalLocalParserValue, supportingCardSide, and visualEvidenceDescription.");
        sb.AppendLine("12. PERSON NAME VS. COMPANY/ORGANIZATION DISAMBIGUATION: The first or most prominent text at the top of a card is frequently a Company or Brand name, NOT a Person's Name. If text represents an organization, business entity, brand, or contains corporate terms (e.g., Solutions, Technologies, Services, Enterprises, Labs, Consulting, Systems, Industries, Healthcare, Studio, Agency, Group), it MUST be assigned to 'company' and NEVER to 'fullName'. A person's name is typically adjacent to a job title (e.g., Director, Manager, Engineer, Founder) or preceded by honorifics (Dr., Prof., Mr., Ms.). If NO individual human person's name exists on the card, set fullName verificationStatus to 'notFound', value to null, and proposedValue to null. NEVER copy or leave a company name as fullName.");
        sb.AppendLine();

        if (request.UncertainFields != null && request.UncertainFields.Any())
        {
            sb.AppendLine("[UNCERTAIN FIELDS REQUIRING TARGETED VERIFICATION]");
            foreach (var uf in request.UncertainFields)
            {
                sb.AppendLine($"- {uf}");
            }
            sb.AppendLine();
        }

        if (request.LocalFieldEvidence != null && request.LocalFieldEvidence.Any())
        {
            sb.AppendLine("[LOCAL FIELD EVIDENCE FROM STAGE 3 RECONCILIATION]");
            foreach (var (fName, ev) in request.LocalFieldEvidence)
            {
                sb.AppendLine($"- Field: {fName} | RawOcr: '{ev.OriginalOcrText}' | Normalized: '{ev.NormalizedValue}' | Engine: {ev.SourceEngine} | Status: {ev.VerificationStatus} | UserApproved: '{ev.UserApprovedValue}'");
            }
            sb.AppendLine();
        }

        if (!string.IsNullOrWhiteSpace(request.PaddleOcrRawText) || !string.IsNullOrWhiteSpace(request.MlKitRawText))
        {
            sb.AppendLine("[MULTI-ENGINE OCR RAW TEXT]");
            if (!string.IsNullOrWhiteSpace(request.PaddleOcrRawText))
            {
                sb.AppendLine("--- PaddleOCR Raw Text ---");
                sb.AppendLine(request.PaddleOcrRawText.Trim());
            }
            if (!string.IsNullOrWhiteSpace(request.MlKitRawText))
            {
                sb.AppendLine("--- Google ML Kit Raw Text ---");
                sb.AppendLine(request.MlKitRawText.Trim());
            }
            sb.AppendLine();
        }

        sb.AppendLine("[OCR OBSERVATIONS]");
        foreach (var obs in request.OcrObservations)
        {
            var b = obs.BoundingBox;
            sb.AppendLine($"- ID: {obs.Id} | Engine: {obs.Engine} | Side: {obs.CardSide} | Conf: {obs.Confidence:F2} | Box: [{b.Top:F3}, {b.Left:F3}, {b.Bottom:F3}, {b.Right:F3}] | Text: {obs.Text}");
        }

        if (request.LocalBaseline != null)
        {
            sb.AppendLine();
            sb.AppendLine("[LOCAL PARSER BASELINE (May have errors, verify with observations and image)]");
            if (!string.IsNullOrEmpty(request.LocalBaseline.FullName)) sb.AppendLine($"Baseline Name: {request.LocalBaseline.FullName}");
            if (!string.IsNullOrEmpty(request.LocalBaseline.Company)) sb.AppendLine($"Baseline Company: {request.LocalBaseline.Company}");
            if (!string.IsNullOrEmpty(request.LocalBaseline.JobTitle)) sb.AppendLine($"Baseline JobTitle: {request.LocalBaseline.JobTitle}");
            if (!string.IsNullOrEmpty(request.LocalBaseline.Address)) sb.AppendLine($"Baseline Address: {request.LocalBaseline.Address}");
        }

        sb.AppendLine();
        sb.AppendLine($"[METADATA & VERSIONS] ScanId: {request.ScanId ?? request.ClientRequestId} | Pipeline: {request.PipelineVersion} | Parser: {request.ParserVersion} | OcrModel: {request.OcrModelVersion} | PromptVersion: {request.GeminiPromptVersion}");

        partsList.Add(new JsonObject
        {
            ["text"] = sb.ToString()
        });

        var schema = BuildGeminiJsonSchema();

        var root = new JsonObject
        {
            ["contents"] = new JsonArray
            {
                new JsonObject
                {
                    ["role"] = "user",
                    ["parts"] = partsList
                }
            },
            ["generationConfig"] = new JsonObject
            {
                ["responseFormat"] = new JsonObject
                {
                    ["text"] = new JsonObject
                    {
                        ["mimeType"] = "APPLICATION_JSON",
                        ["schema"] = schema
                    }
                }
            }
        };

        var payload = root.ToJsonString(PayloadSerializerOptions);
        return (payload, frontRetrieved, backRetrieved, retrievalFailure);
    }

    public JsonObject BuildGeminiJsonSchema()
    {
        JsonObject BuildFieldSchema() => new()
        {
            ["type"] = "OBJECT",
            ["required"] = new JsonArray { "value", "confidence", "sourceObservationIds" },
            ["properties"] = new JsonObject
            {
                ["value"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                ["confidence"] = new JsonObject { ["type"] = "NUMBER" },
                ["rawEvidence"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                ["sourceObservationIds"] = new JsonObject { ["type"] = "ARRAY", ["items"] = new JsonObject { ["type"] = "STRING" } },
                ["wasCorrected"] = new JsonObject { ["type"] = "BOOLEAN" },
                ["reviewRequired"] = new JsonObject { ["type"] = "BOOLEAN" },
                ["proposedValue"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                ["originalLocalParserValue"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                ["supportingCardSide"] = new JsonObject { ["type"] = "STRING" },
                ["visualEvidenceDescription"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                ["verificationStatus"] = new JsonObject { ["type"] = "STRING" },
                ["correctionReason"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                ["isGenuinelyReadable"] = new JsonObject { ["type"] = "BOOLEAN" },
                ["isVisuallyVerified"] = new JsonObject { ["type"] = "BOOLEAN" }
            }
        };

        return new JsonObject
        {
            ["type"] = "OBJECT",
            ["required"] = new JsonArray { "fullName", "company", "jobTitle", "phoneNumbers", "emailAddresses", "websites", "address", "overallConfidence", "requiresManualReview" },
            ["properties"] = new JsonObject
            {
                ["fullName"] = BuildFieldSchema(),
                ["company"] = BuildFieldSchema(),
                ["jobTitle"] = BuildFieldSchema(),
                ["phoneNumbers"] = new JsonObject
                {
                    ["type"] = "ARRAY",
                    ["items"] = new JsonObject
                    {
                        ["type"] = "OBJECT",
                        ["required"] = new JsonArray { "number", "label", "confidence", "sourceObservationIds" },
                        ["properties"] = new JsonObject
                        {
                            ["number"] = new JsonObject { ["type"] = "STRING" },
                            ["label"] = new JsonObject { ["type"] = "STRING" },
                            ["confidence"] = new JsonObject { ["type"] = "NUMBER" },
                            ["rawEvidence"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["sourceObservationIds"] = new JsonObject { ["type"] = "ARRAY", ["items"] = new JsonObject { ["type"] = "STRING" } },
                            ["reviewRequired"] = new JsonObject { ["type"] = "BOOLEAN" },
                            ["proposedValue"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["originalLocalParserValue"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["supportingCardSide"] = new JsonObject { ["type"] = "STRING" },
                            ["visualEvidenceDescription"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["verificationStatus"] = new JsonObject { ["type"] = "STRING" },
                            ["correctionReason"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["isGenuinelyReadable"] = new JsonObject { ["type"] = "BOOLEAN" },
                            ["isVisuallyVerified"] = new JsonObject { ["type"] = "BOOLEAN" }
                        }
                    }
                },
                ["emailAddresses"] = new JsonObject
                {
                    ["type"] = "ARRAY",
                    ["items"] = new JsonObject
                    {
                        ["type"] = "OBJECT",
                        ["required"] = new JsonArray { "email", "label", "confidence", "sourceObservationIds" },
                        ["properties"] = new JsonObject
                        {
                            ["email"] = new JsonObject { ["type"] = "STRING" },
                            ["label"] = new JsonObject { ["type"] = "STRING" },
                            ["confidence"] = new JsonObject { ["type"] = "NUMBER" },
                            ["rawEvidence"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["sourceObservationIds"] = new JsonObject { ["type"] = "ARRAY", ["items"] = new JsonObject { ["type"] = "STRING" } },
                            ["reviewRequired"] = new JsonObject { ["type"] = "BOOLEAN" },
                            ["proposedValue"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["originalLocalParserValue"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["supportingCardSide"] = new JsonObject { ["type"] = "STRING" },
                            ["visualEvidenceDescription"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["verificationStatus"] = new JsonObject { ["type"] = "STRING" },
                            ["correctionReason"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["isGenuinelyReadable"] = new JsonObject { ["type"] = "BOOLEAN" },
                            ["isVisuallyVerified"] = new JsonObject { ["type"] = "BOOLEAN" }
                        }
                    }
                },
                ["websites"] = new JsonObject
                {
                    ["type"] = "ARRAY",
                    ["items"] = new JsonObject
                    {
                        ["type"] = "OBJECT",
                        ["required"] = new JsonArray { "url", "confidence", "sourceObservationIds" },
                        ["properties"] = new JsonObject
                        {
                            ["url"] = new JsonObject { ["type"] = "STRING" },
                            ["confidence"] = new JsonObject { ["type"] = "NUMBER" },
                            ["rawEvidence"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["sourceObservationIds"] = new JsonObject { ["type"] = "ARRAY", ["items"] = new JsonObject { ["type"] = "STRING" } },
                            ["proposedValue"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["originalLocalParserValue"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["supportingCardSide"] = new JsonObject { ["type"] = "STRING" },
                            ["visualEvidenceDescription"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["verificationStatus"] = new JsonObject { ["type"] = "STRING" },
                            ["correctionReason"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                            ["isGenuinelyReadable"] = new JsonObject { ["type"] = "BOOLEAN" },
                            ["isVisuallyVerified"] = new JsonObject { ["type"] = "BOOLEAN" }
                        }
                    }
                },
                ["address"] = new JsonObject
                {
                    ["type"] = "OBJECT",
                    ["required"] = new JsonArray { "fullAddress", "confidence", "sourceObservationIds" },
                    ["properties"] = new JsonObject
                    {
                        ["fullAddress"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                        ["street"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                        ["city"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                        ["state"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                        ["postalCode"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                        ["country"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                        ["confidence"] = new JsonObject { ["type"] = "NUMBER" },
                        ["sourceObservationIds"] = new JsonObject { ["type"] = "ARRAY", ["items"] = new JsonObject { ["type"] = "STRING" } },
                        ["reviewRequired"] = new JsonObject { ["type"] = "BOOLEAN" },
                        ["proposedValue"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                        ["originalLocalParserValue"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                        ["supportingCardSide"] = new JsonObject { ["type"] = "STRING" },
                        ["visualEvidenceDescription"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                        ["verificationStatus"] = new JsonObject { ["type"] = "STRING" },
                        ["correctionReason"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                        ["isGenuinelyReadable"] = new JsonObject { ["type"] = "BOOLEAN" },
                        ["isVisuallyVerified"] = new JsonObject { ["type"] = "BOOLEAN" }
                    }
                },
                ["department"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                ["credentials"] = new JsonObject { ["type"] = "STRING", ["nullable"] = true },
                ["overallConfidence"] = new JsonObject { ["type"] = "NUMBER" },
                ["requiresManualReview"] = new JsonObject { ["type"] = "BOOLEAN" },
                ["reviewWarnings"] = new JsonObject { ["type"] = "ARRAY", ["items"] = new JsonObject { ["type"] = "STRING" } }
            }
        };
    }

    private AnalyzeBusinessCardResponse ParseGeminiResponse(
        string responseBody,
        AnalyzeBusinessCardRequest request,
        bool frontRetrieved,
        bool backRetrieved,
        string? retrievalFailure)
    {
        using var doc = JsonDocument.Parse(responseBody);
        var candidates = doc.RootElement.GetProperty("candidates");
        if (candidates.GetArrayLength() == 0)
        {
            throw new InvalidOperationException("Gemini returned zero response candidates.");
        }

        var firstCandidate = candidates[0];
        var parts = firstCandidate.GetProperty("content").GetProperty("parts");
        if (parts.GetArrayLength() == 0)
        {
            throw new InvalidOperationException("Gemini returned empty parts.");
        }

        var textJson = parts[0].GetProperty("text").GetString();
        if (string.IsNullOrWhiteSpace(textJson))
        {
            throw new InvalidOperationException("Gemini returned empty text payload.");
        }

        var response = JsonSerializer.Deserialize<AnalyzeBusinessCardResponse>(textJson, JsonOptions);
        if (response == null)
        {
            throw new InvalidOperationException("Failed to deserialize structured Gemini JSON response.");
        }

        var isMultimodal = string.Equals(request.AnalysisMode, "MultimodalVision", StringComparison.OrdinalIgnoreCase);
        if (isMultimodal && (frontRetrieved || backRetrieved))
        {
            response.VisualVerificationPerformed = true;
            response.FrontImageVerified = frontRetrieved;
            response.BackImageVerified = backRetrieved;
            response.ImageVerificationFailureReason = null;
        }
        else if (isMultimodal)
        {
            response.VisualVerificationPerformed = false;
            response.FrontImageVerified = false;
            response.BackImageVerified = false;
            response.ImageVerificationFailureReason = retrievalFailure ?? "Card image retrieval failed.";
        }
        else
        {
            response.VisualVerificationPerformed = false;
            response.FrontImageVerified = false;
            response.BackImageVerified = false;
            response.ImageVerificationFailureReason = null;
        }

        PopulateFieldVerifications(response, request);

        if (doc.RootElement.TryGetProperty("usageMetadata", out var usageElem))
        {
            var promptTokens = usageElem.TryGetProperty("promptTokenCount", out var pt) ? pt.GetInt32() : 0;
            var candidateTokens = usageElem.TryGetProperty("candidatesTokenCount", out var ct) ? ct.GetInt32() : 0;
            var totalTokens = usageElem.TryGetProperty("totalTokenCount", out var tt) ? tt.GetInt32() : 0;

            // Pricing configured via GeminiOptions (explicitly flagged as non-billing estimate)
            var inputRate = _options.InputPricePerMillionTokens / 1_000_000m;
            var outputRate = _options.OutputPricePerMillionTokens / 1_000_000m;
            decimal cost = (promptTokens * inputRate) + (candidateTokens * outputRate);

            response.UsageMetadata = new GeminiUsageMetadataDto
            {
                PromptTokenCount = promptTokens,
                CandidatesTokenCount = candidateTokens,
                TotalTokenCount = totalTokens,
                EstimatedCostUsd = Math.Round(cost, 6),
                IsEstimatedCost = true,
                CostCalculationNotes = $"Estimated using configured rates: ${_options.InputPricePerMillionTokens}/1M input, ${_options.OutputPricePerMillionTokens}/1M output."
            };

            _logger.LogInformation("Gemini API Usage Tracked: PromptTokens={Prompt}, CandidateTokens={Candidate}, TotalTokens={Total}, EstimatedCostUsd=${Cost:F6}",
                promptTokens, candidateTokens, totalTokens, cost);
        }

        return response;
    }

    private static void PopulateFieldVerifications(
        AnalyzeBusinessCardResponse response,
        AnalyzeBusinessCardRequest request)
    {
        response.FieldVerifications ??= new();

        void AddFieldVerification(string fieldName, ExtractedFieldDto field, string? localBaseline)
        {
            var isVisual = response.VisualVerificationPerformed && field.IsVisuallyVerified;
            var status = isVisual
                ? (field.VerificationStatus ?? "verified")
                : (field.ReviewRequired ? "reviewRequired" : (field.VerificationStatus == "verified" ? "probable" : (field.VerificationStatus ?? "probable")));

            if (string.IsNullOrWhiteSpace(field.Value))
            {
                status = "notFound";
            }

            response.FieldVerifications[fieldName] = new FieldVerificationDto
            {
                FieldName = fieldName,
                ProposedValue = field.ProposedValue ?? field.Value,
                OriginalLocalParserValue = field.OriginalLocalParserValue ?? localBaseline,
                SupportingCardSide = field.SupportingCardSide ?? "front",
                VisualEvidenceDescription = field.VisualEvidenceDescription,
                VerificationStatus = status,
                CorrectionReason = field.CorrectionReason,
                IsGenuinelyReadable = field.IsGenuinelyReadable,
                IsVisuallyVerified = isVisual,
                Confidence = field.Confidence,
                SourceObservationIds = field.SourceObservationIds,
                WasCorrected = field.WasCorrected,
                ReviewRequired = field.ReviewRequired
            };
        }

        AddFieldVerification("fullName", response.FullName, request.LocalBaseline?.FullName);
        AddFieldVerification("company", response.Company, request.LocalBaseline?.Company);
        AddFieldVerification("jobTitle", response.JobTitle, request.LocalBaseline?.JobTitle);

        if (response.Address != null)
        {
            var isVisual = response.VisualVerificationPerformed && response.Address.IsVisuallyVerified;
            var status = isVisual
                ? (response.Address.VerificationStatus ?? "verified")
                : (response.Address.ReviewRequired ? "reviewRequired" : (response.Address.VerificationStatus == "verified" ? "probable" : (response.Address.VerificationStatus ?? "probable")));

            if (string.IsNullOrWhiteSpace(response.Address.FullAddress))
            {
                status = "notFound";
            }

            response.FieldVerifications["address"] = new FieldVerificationDto
            {
                FieldName = "address",
                ProposedValue = response.Address.ProposedValue ?? response.Address.FullAddress,
                OriginalLocalParserValue = response.Address.OriginalLocalParserValue ?? request.LocalBaseline?.Address,
                SupportingCardSide = response.Address.SupportingCardSide ?? "front",
                VisualEvidenceDescription = response.Address.VisualEvidenceDescription,
                VerificationStatus = status,
                CorrectionReason = response.Address.CorrectionReason,
                IsGenuinelyReadable = response.Address.IsGenuinelyReadable,
                IsVisuallyVerified = isVisual,
                Confidence = response.Address.Confidence,
                SourceObservationIds = response.Address.SourceObservationIds,
                WasCorrected = response.Address.WasCorrected,
                ReviewRequired = response.Address.ReviewRequired
            };
        }

        if (response.PhoneNumbers != null && response.PhoneNumbers.Any())
        {
            var firstPhone = response.PhoneNumbers[0];
            var isVisual = response.VisualVerificationPerformed && firstPhone.IsVisuallyVerified;
            response.FieldVerifications["phone"] = new FieldVerificationDto
            {
                FieldName = "phone",
                ProposedValue = firstPhone.ProposedValue ?? firstPhone.Number,
                OriginalLocalParserValue = firstPhone.OriginalLocalParserValue ?? request.LocalBaseline?.PhoneNumbers.FirstOrDefault(),
                SupportingCardSide = firstPhone.SupportingCardSide ?? "front",
                VisualEvidenceDescription = firstPhone.VisualEvidenceDescription,
                VerificationStatus = isVisual ? (firstPhone.VerificationStatus ?? "verified") : (firstPhone.ReviewRequired ? "reviewRequired" : "probable"),
                CorrectionReason = firstPhone.CorrectionReason,
                IsGenuinelyReadable = firstPhone.IsGenuinelyReadable,
                IsVisuallyVerified = isVisual,
                Confidence = firstPhone.Confidence,
                SourceObservationIds = firstPhone.SourceObservationIds,
                WasCorrected = firstPhone.WasCorrected,
                ReviewRequired = firstPhone.ReviewRequired
            };
        }
        else
        {
            response.FieldVerifications["phone"] = new FieldVerificationDto
            {
                FieldName = "phone",
                VerificationStatus = "notFound",
                Confidence = 0.0
            };
        }

        if (response.EmailAddresses != null && response.EmailAddresses.Any())
        {
            var firstEmail = response.EmailAddresses[0];
            var isVisual = response.VisualVerificationPerformed && firstEmail.IsVisuallyVerified;
            response.FieldVerifications["email"] = new FieldVerificationDto
            {
                FieldName = "email",
                ProposedValue = firstEmail.ProposedValue ?? firstEmail.Email,
                OriginalLocalParserValue = firstEmail.OriginalLocalParserValue ?? request.LocalBaseline?.EmailAddresses.FirstOrDefault(),
                SupportingCardSide = firstEmail.SupportingCardSide ?? "front",
                VisualEvidenceDescription = firstEmail.VisualEvidenceDescription,
                VerificationStatus = isVisual ? (firstEmail.VerificationStatus ?? "verified") : (firstEmail.ReviewRequired ? "reviewRequired" : "probable"),
                CorrectionReason = firstEmail.CorrectionReason,
                IsGenuinelyReadable = firstEmail.IsGenuinelyReadable,
                IsVisuallyVerified = isVisual,
                Confidence = firstEmail.Confidence,
                SourceObservationIds = firstEmail.SourceObservationIds,
                WasCorrected = firstEmail.WasCorrected,
                ReviewRequired = firstEmail.ReviewRequired
            };
        }
        else
        {
            response.FieldVerifications["email"] = new FieldVerificationDto
            {
                FieldName = "email",
                VerificationStatus = "notFound",
                Confidence = 0.0
            };
        }

        if (response.Websites != null && response.Websites.Any())
        {
            var firstSite = response.Websites[0];
            var isVisual = response.VisualVerificationPerformed && firstSite.IsVisuallyVerified;
            response.FieldVerifications["website"] = new FieldVerificationDto
            {
                FieldName = "website",
                ProposedValue = firstSite.ProposedValue ?? firstSite.Url,
                OriginalLocalParserValue = firstSite.OriginalLocalParserValue ?? request.LocalBaseline?.Website,
                SupportingCardSide = firstSite.SupportingCardSide ?? "front",
                VisualEvidenceDescription = firstSite.VisualEvidenceDescription,
                VerificationStatus = isVisual ? (firstSite.VerificationStatus ?? "verified") : "probable",
                CorrectionReason = firstSite.CorrectionReason,
                IsGenuinelyReadable = firstSite.IsGenuinelyReadable,
                IsVisuallyVerified = isVisual,
                Confidence = firstSite.Confidence,
                SourceObservationIds = firstSite.SourceObservationIds,
                WasCorrected = firstSite.WasCorrected
            };
        }
        else
        {
            response.FieldVerifications["website"] = new FieldVerificationDto
            {
                FieldName = "website",
                VerificationStatus = "notFound",
                Confidence = 0.0
            };
        }
    }

    private AnalyzeBusinessCardResponse BuildFallbackFromBaseline(
        AnalyzeBusinessCardRequest request,
        string warningReason,
        long durationMs)
    {
        var baseline = request.LocalBaseline;
        var fallback = new AnalyzeBusinessCardResponse
        {
            ClientRequestId = request.ClientRequestId,
            ModelId = "local-parser-fallback",
            ProcessingDurationMs = durationMs,
            FallbackToLocalBaseline = true,
            RequiresManualReview = true,
            ReviewWarnings = new List<string> { warningReason },
            OverallConfidence = 0.50,
            VisualVerificationPerformed = false,
            FrontImageVerified = false,
            BackImageVerified = false,
            ImageVerificationFailureReason = warningReason,
            FullName = new ExtractedFieldDto
            {
                Value = baseline?.FullName,
                Confidence = 0.50,
                RawEvidence = baseline?.FullName,
                VerificationStatus = string.IsNullOrWhiteSpace(baseline?.FullName) ? "notFound" : "reviewRequired",
                IsVisuallyVerified = false,
                ReviewRequired = true
            },
            Company = new ExtractedFieldDto
            {
                Value = baseline?.Company,
                Confidence = 0.50,
                RawEvidence = baseline?.Company,
                VerificationStatus = string.IsNullOrWhiteSpace(baseline?.Company) ? "notFound" : "reviewRequired",
                IsVisuallyVerified = false,
                ReviewRequired = true
            },
            JobTitle = new ExtractedFieldDto
            {
                Value = baseline?.JobTitle,
                Confidence = 0.50,
                RawEvidence = baseline?.JobTitle,
                VerificationStatus = string.IsNullOrWhiteSpace(baseline?.JobTitle) ? "notFound" : "reviewRequired",
                IsVisuallyVerified = false,
                ReviewRequired = true
            },
            Address = new ExtractedAddressDto
            {
                FullAddress = baseline?.Address,
                Confidence = 0.50,
                VerificationStatus = string.IsNullOrWhiteSpace(baseline?.Address) ? "notFound" : "reviewRequired",
                IsVisuallyVerified = false,
                ReviewRequired = true
            },
            PhoneNumbers = (baseline?.PhoneNumbers ?? new List<string>())
                .Select(p => new ExtractedPhoneDto
                {
                    Number = p,
                    NormalizedNumber = ContactNormalizationHelper.NormalizePhone(p),
                    Confidence = 0.50,
                    RawEvidence = p,
                    VerificationStatus = "reviewRequired",
                    IsVisuallyVerified = false,
                    ReviewRequired = true
                }).ToList(),
            EmailAddresses = (baseline?.EmailAddresses ?? new List<string>())
                .Select(e => new ExtractedEmailDto
                {
                    Email = e,
                    NormalizedEmail = ContactNormalizationHelper.NormalizeEmail(e),
                    Confidence = 0.50,
                    RawEvidence = e,
                    VerificationStatus = "reviewRequired",
                    IsVisuallyVerified = false,
                    ReviewRequired = true
                }).ToList(),
            Websites = !string.IsNullOrWhiteSpace(baseline?.Website)
                ? new List<ExtractedWebsiteDto>
                {
                    new()
                    {
                        Url = baseline.Website,
                        Confidence = 0.50,
                        VerificationStatus = "reviewRequired",
                        IsVisuallyVerified = false
                    }
                }
                : new List<ExtractedWebsiteDto>(),
            UnclassifiedLines = baseline?.UnclassifiedLines ?? new List<string>()
        };

        PopulateFieldVerifications(fallback, request);
        return fallback;
    }
}

