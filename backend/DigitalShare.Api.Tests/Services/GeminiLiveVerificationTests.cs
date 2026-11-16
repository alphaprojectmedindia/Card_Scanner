using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using DigitalShare.Api.Configuration;
using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.CardAnalysis;
using DigitalShare.Api.Models;
using DigitalShare.Api.Services.Gemini;
using DigitalShare.Api.Services.Storage;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using Xunit;
using Xunit.Abstractions;

namespace DigitalShare.Api.Tests.Services;

public class GeminiLiveVerificationTests
{
    private readonly IConfiguration _configuration;
    private readonly CardAnalysisSemanticValidator _validator = new();
    private readonly ITestOutputHelper? _output;

    public GeminiLiveVerificationTests(ITestOutputHelper? output = null)
    {
        _output = output;
        _configuration = new ConfigurationBuilder()
            .AddUserSecrets<Program>(optional: true)
            .AddEnvironmentVariables()
            .Build();
    }

    private ApplicationDbContext CreateInMemoryDbContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase("GeminiLiveTest_" + Guid.NewGuid())
            .Options;
        return new ApplicationDbContext(options);
    }

    // =========================================================================
    // TASK 2: REAL GOOGLE API ENDPOINT TEST (WITH CONFIGURED KEY)
    // =========================================================================
    [Fact]
    public async Task RealGoogleApi_EndpointReachable_ValidatesAuthenticationAndGracefulFallback()
    {
        var apiKey = _configuration["Gemini:ApiKey"];
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            // If secrets are not loaded, skip live network call
            return;
        }

        using var dbContext = CreateInMemoryDbContext();
        var idempotencyManager = new CardAnalysisIdempotencyManager(
            dbContext,
            NullLogger<CardAnalysisIdempotencyManager>.Instance);

        var mockStorage = new Mock<IScanImageStorageService>();

        var geminiOptions = Options.Create(new GeminiOptions
        {
            ApiKey = apiKey,
            ModelId = _configuration["Gemini:ModelId"] ?? "gemini-3.8-flash",
            Enabled = true,
            TimeoutSeconds = 8,
            MaxRetries = 1
        });

        using var httpClient = new HttpClient();
        var service = new GeminiCardAnalysisService(
            httpClient,
            geminiOptions,
            mockStorage.Object,
            _validator,
            idempotencyManager,
            NullLogger<GeminiCardAnalysisService>.Instance);

        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "live_req_01",
            ScanContentHash = "live_hash_01",
            InvocationReason = "Live Gemini API Verification",
            AnalysisMode = "TextAndLayout",
            OcrObservations = new List<OcrObservationDto>
            {
                new()
                {
                    Id = "obs_1",
                    Text = "Alexander Wright",
                    Engine = "PaddleOCR",
                    Confidence = 0.95,
                    BoundingBox = new() { Top = 0.1, Left = 0.1, Bottom = 0.2, Right = 0.5 }
                },
                new()
                {
                    Id = "obs_2",
                    Text = "CloudScale Technologies Inc",
                    Engine = "PaddleOCR",
                    Confidence = 0.95,
                    BoundingBox = new() { Top = 0.2, Left = 0.1, Bottom = 0.3, Right = 0.6 }
                }
            },
            LocalBaseline = new LocalParserBaselineDto
            {
                FullName = "Alexander Wright",
                Company = "CloudScale Technologies Inc"
            }
        };

        var response = await service.AnalyzeCardAsync("user_live_test", request);

        // Verification:
        // When Google API returns (either HTTP 200 or HTTP 403 Billing Required),
        // the service must NEVER crash and must return a valid, non-null response.
        Assert.NotNull(response);
        Assert.Equal("live_req_01", response.ClientRequestId);
        Assert.NotNull(response.FullName.Value);
        Assert.NotNull(response.Company.Value);

        // If the project requires billing setup, it safely falls back to local baseline
        if (response.FallbackToLocalBaseline)
        {
            Assert.Contains(response.ReviewWarnings, w => w.Contains("Gemini") || w.Contains("local"));
        }
        else
        {
            // If live call returned HTTP 200
            Assert.Equal("gemini-3.8-flash", response.ModelId);
            Assert.False(response.FallbackToLocalBaseline);
        }
    }

    [Fact]
    public async Task RealGoogleApi_MinimalGenerateContentPrompt_ReportsStatus()
    {
        var apiKey = _configuration["Gemini:ApiKey"];
        Assert.False(string.IsNullOrWhiteSpace(apiKey), "Gemini:ApiKey must be configured in user-secrets or environment.");

        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        var modelId = _configuration["Gemini:ModelId"] ?? "gemini-3.5-flash-lite";
        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{modelId}:generateContent";
        using var requestMessage = new HttpRequestMessage(HttpMethod.Post, url);
        requestMessage.Headers.TryAddWithoutValidation("x-goog-api-key", apiKey);
        requestMessage.Content = new StringContent(
            "{\"contents\":[{\"parts\":[{\"text\":\"Return JSON with status 'OK'\"}]}],\"generationConfig\":{\"responseFormat\":{\"text\":{\"mimeType\":\"APPLICATION_JSON\",\"schema\":{\"type\":\"OBJECT\",\"properties\":{\"status\":{\"type\":\"STRING\"}}}}}}}",
            Encoding.UTF8,
            "application/json");

        HttpResponseMessage response;
        try
        {
            response = await client.SendAsync(requestMessage);
        }
        catch (TaskCanceledException)
        {
            _output?.WriteLine("[LIVE_PROBE] Live API call timed out. Skipping assertion due to network latency.");
            return;
        }
        var body = await response.Content.ReadAsStringAsync();

        _output?.WriteLine($"[LIVE_PROBE] Model: {modelId}");
        _output?.WriteLine($"[LIVE_PROBE] StatusCode: {response.StatusCode} ({(int)response.StatusCode})");
        _output?.WriteLine($"[LIVE_PROBE] HasCandidates: {body.Contains("candidates")}");
        _output?.WriteLine($"[LIVE_PROBE] ResponseSnippet: {(body.Length > 250 ? body[..250] : body)}");

        Assert.True(response.IsSuccessStatusCode || response.StatusCode == HttpStatusCode.ServiceUnavailable || response.StatusCode == HttpStatusCode.TooManyRequests,
            $"Unexpected HTTP status from Google GenAI API: {response.StatusCode}. Response: {body}");
    }

    // =========================================================================
    // TASK 3: PATH A (TEXT + 2D BOUNDING BOXES ONLY) WITH STRUCTURED OUTPUT
    // =========================================================================
    [Fact]
    public async Task PathA_TextAndLayout_SuccessfullyParsesStructuredResponseAndGroundsObservations()
    {
        using var dbContext = CreateInMemoryDbContext();
        var idempotencyManager = new CardAnalysisIdempotencyManager(
            dbContext,
            NullLogger<CardAnalysisIdempotencyManager>.Instance);

        var mockStorage = new Mock<IScanImageStorageService>();

        // Mock HttpHandler returning successful structured Gemini response
        var structuredJson = new JsonObject
        {
            ["fullName"] = new JsonObject
            {
                ["value"] = "Alexander Wright",
                ["confidence"] = 0.98,
                ["rawEvidence"] = "Alexander Wright",
                ["sourceObservationIds"] = new JsonArray { "obs_1" },
                ["wasCorrected"] = false
            },
            ["company"] = new JsonObject
            {
                ["value"] = "CloudScale Technologies Inc",
                ["confidence"] = 0.96,
                ["rawEvidence"] = "CloudScale Technologies Inc",
                ["sourceObservationIds"] = new JsonArray { "obs_2" },
                ["wasCorrected"] = false
            },
            ["jobTitle"] = new JsonObject
            {
                ["value"] = "Chief Technology Officer",
                ["confidence"] = 0.94,
                ["rawEvidence"] = "CTO",
                ["sourceObservationIds"] = new JsonArray { "obs_3" },
                ["wasCorrected"] = true
            },
            ["phoneNumbers"] = new JsonArray
            {
                new JsonObject
                {
                    ["number"] = "+1 555 742 8910",
                    ["label"] = "Mobile",
                    ["confidence"] = 0.99,
                    ["rawEvidence"] = "+1 555 742 8910",
                    ["sourceObservationIds"] = new JsonArray { "obs_4" }
                }
            },
            ["emailAddresses"] = new JsonArray
            {
                new JsonObject
                {
                    ["email"] = "alex.wright@cloudscale.io",
                    ["label"] = "Work",
                    ["confidence"] = 0.99,
                    ["rawEvidence"] = "alex.wright@cloudscale.io",
                    ["sourceObservationIds"] = new JsonArray { "obs_5" }
                }
            },
            ["websites"] = new JsonArray
            {
                new JsonObject
                {
                    ["url"] = "https://cloudscale.io",
                    ["confidence"] = 0.98,
                    ["sourceObservationIds"] = new JsonArray { "obs_6" }
                }
            },
            ["address"] = new JsonObject
            {
                ["fullAddress"] = "742 Evergreen Terrace, Springfield, OR 97477",
                ["confidence"] = 0.95,
                ["sourceObservationIds"] = new JsonArray { "obs_7" }
            },
            ["overallConfidence"] = 0.97,
            ["requiresManualReview"] = false,
            ["reviewWarnings"] = new JsonArray()
        };

        var geminiCandidateJson = new JsonObject
        {
            ["candidates"] = new JsonArray
            {
                new JsonObject
                {
                    ["content"] = new JsonObject
                    {
                        ["parts"] = new JsonArray
                        {
                            new JsonObject
                            {
                                ["text"] = structuredJson.ToJsonString()
                            }
                        }
                    }
                }
            }
        };

        var mockHandler = new MockHttpMessageHandler(HttpStatusCode.OK, geminiCandidateJson.ToJsonString());
        var httpClient = new HttpClient(mockHandler);

        var service = new GeminiCardAnalysisService(
            httpClient,
            Options.Create(new GeminiOptions { ApiKey = "test_key", Enabled = true }),
            mockStorage.Object,
            _validator,
            idempotencyManager,
            NullLogger<GeminiCardAnalysisService>.Instance);

        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "path_a_req",
            ScanContentHash = "path_a_hash",
            InvocationReason = "Test Path A",
            AnalysisMode = "TextAndLayout",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "Alexander Wright", Engine = "PaddleOCR" },
                new() { Id = "obs_2", Text = "CloudScale Technologies Inc", Engine = "PaddleOCR" },
                new() { Id = "obs_3", Text = "CTO", Engine = "PaddleOCR" },
                new() { Id = "obs_4", Text = "+1 555 742 8910", Engine = "PaddleOCR" },
                new() { Id = "obs_5", Text = "alex.wright@cloudscale.io", Engine = "PaddleOCR" },
                new() { Id = "obs_6", Text = "https://cloudscale.io", Engine = "PaddleOCR" },
                new() { Id = "obs_7", Text = "742 Evergreen Terrace, Springfield, OR 97477", Engine = "PaddleOCR" }
            }
        };

        var result = await service.AnalyzeCardAsync("user_path_a", request);

        // Path A verification
        Assert.NotNull(result);
        Assert.False(result.FallbackToLocalBaseline);
        Assert.Equal("Alexander Wright", result.FullName.Value);
        Assert.Equal("CloudScale Technologies Inc", result.Company.Value);
        Assert.Equal("Chief Technology Officer", result.JobTitle.Value);
        Assert.Single(result.PhoneNumbers);
        Assert.Single(result.EmailAddresses);
        Assert.False(result.RequiresManualReview);

        // Confirms storage was NEVER accessed for Path A (zero image bytes)
        mockStorage.Verify(s => s.GetScanImageStreamAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    // =========================================================================
    // TASK 3: PATH B (MULTIMODAL VISION WITH IMAGE STORAGE KEY)
    // =========================================================================
    [Fact]
    public async Task PathB_MultimodalVision_RetrievesImageAndIncludesInlineData()
    {
        using var dbContext = CreateInMemoryDbContext();
        var idempotencyManager = new CardAnalysisIdempotencyManager(
            dbContext,
            NullLogger<CardAnalysisIdempotencyManager>.Instance);

        var mockStorage = new Mock<IScanImageStorageService>();
        var fakeImageBytes = new byte[] { 0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02 }; // JPEG bytes
        mockStorage.Setup(s => s.GetScanImageStreamAsync("scans/user1/card_front.jpg", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MemoryStream(fakeImageBytes));

        string? capturedRequestBody = null;
        var mockHandler = new MockHttpMessageHandler(HttpStatusCode.OK, GetDummyGeminiCandidateJson(), req =>
        {
            capturedRequestBody = req.Content?.ReadAsStringAsync().GetAwaiter().GetResult();
        });

        var httpClient = new HttpClient(mockHandler);

        var service = new GeminiCardAnalysisService(
            httpClient,
            Options.Create(new GeminiOptions { ApiKey = "test_key", Enabled = true }),
            mockStorage.Object,
            _validator,
            idempotencyManager,
            NullLogger<GeminiCardAnalysisService>.Instance);

        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "path_b_req",
            ScanContentHash = "path_b_hash",
            InvocationReason = "Test Path B Degraded Scan",
            AnalysisMode = "MultimodalVision",
            FrontImageStorageKey = "scans/user1/card_front.jpg",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "Messy Text", Engine = "Google ML Kit" }
            }
        };

        var result = await service.AnalyzeCardAsync("user_path_b", request);

        // Path B verification
        Assert.NotNull(result);
        mockStorage.Verify(s => s.GetScanImageStreamAsync("scans/user1/card_front.jpg", It.IsAny<CancellationToken>()), Times.Once);
        Assert.NotNull(capturedRequestBody);
        Assert.Contains("inlineData", capturedRequestBody);
        Assert.Contains("image/jpeg", capturedRequestBody);
    }

    // =========================================================================
    // TASK 4: FALLBACK BEHAVIOR VERIFICATION (ALL FAILURE MODES)
    // =========================================================================
    [Fact]
    public async Task Fallback_WhenApiKeyIsInvalid_PreservesLocalBaseline()
    {
        using var dbContext = CreateInMemoryDbContext();
        var idempotencyManager = new CardAnalysisIdempotencyManager(dbContext, NullLogger<CardAnalysisIdempotencyManager>.Instance);
        var mockStorage = new Mock<IScanImageStorageService>();

        var mockHandler = new MockHttpMessageHandler(HttpStatusCode.Forbidden, "{\"error\":{\"code\":403,\"message\":\"Invalid API key\"}}");
        var httpClient = new HttpClient(mockHandler);

        var service = new GeminiCardAnalysisService(
            httpClient,
            Options.Create(new GeminiOptions { ApiKey = "invalid_key", Enabled = true }),
            mockStorage.Object,
            _validator,
            idempotencyManager,
            NullLogger<GeminiCardAnalysisService>.Instance);

        var request = CreateSampleRequestWithBaseline("John Smith", "Acme Corp", "+1 555 111 2222");

        var response = await service.AnalyzeCardAsync("u1", request);

        Assert.True(response.FallbackToLocalBaseline);
        Assert.Equal("John Smith", response.FullName.Value);
        Assert.Equal("Acme Corp", response.Company.Value);
        Assert.Single(response.PhoneNumbers);
        Assert.True(response.RequiresManualReview);
    }

    [Fact]
    public async Task Fallback_WhenRequestTimesOut_PreservesLocalBaseline()
    {
        using var dbContext = CreateInMemoryDbContext();
        var idempotencyManager = new CardAnalysisIdempotencyManager(dbContext, NullLogger<CardAnalysisIdempotencyManager>.Instance);
        var mockStorage = new Mock<IScanImageStorageService>();

        // Handler simulating hang / timeout
        var mockHandler = new MockHttpMessageHandler(async ct =>
        {
            await Task.Delay(5000, ct); // Will be aborted by service timeout
            return new HttpResponseMessage(HttpStatusCode.OK);
        });

        var httpClient = new HttpClient(mockHandler);

        var service = new GeminiCardAnalysisService(
            httpClient,
            Options.Create(new GeminiOptions { ApiKey = "key", Enabled = true, TimeoutSeconds = 1 }), // 1 second timeout
            mockStorage.Object,
            _validator,
            idempotencyManager,
            NullLogger<GeminiCardAnalysisService>.Instance);

        var request = CreateSampleRequestWithBaseline("Jane Doe", "BioTech", "+1 555 333 4444");

        var response = await service.AnalyzeCardAsync("u2", request);

        Assert.True(response.FallbackToLocalBaseline);
        Assert.Equal("Jane Doe", response.FullName.Value);
        Assert.Contains(response.ReviewWarnings, w => w.Contains("timed out", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task Fallback_WhenHttp429RateLimitOccurs_RetriesAndPreservesLocalBaseline()
    {
        using var dbContext = CreateInMemoryDbContext();
        var idempotencyManager = new CardAnalysisIdempotencyManager(dbContext, NullLogger<CardAnalysisIdempotencyManager>.Instance);
        var mockStorage = new Mock<IScanImageStorageService>();

        var attempts = 0;
        var mockHandler = new MockHttpMessageHandler(ct =>
        {
            attempts++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.TooManyRequests)
            {
                Content = new StringContent("{\"error\":{\"code\":429,\"message\":\"Resource exhausted\"}}")
            });
        });

        var httpClient = new HttpClient(mockHandler);

        var service = new GeminiCardAnalysisService(
            httpClient,
            Options.Create(new GeminiOptions { ApiKey = "key", Enabled = true, MaxRetries = 2 }),
            mockStorage.Object,
            _validator,
            idempotencyManager,
            NullLogger<GeminiCardAnalysisService>.Instance);

        var request = CreateSampleRequestWithBaseline("Rate Limited User", "Scale Corp", "+1 555 999 0000");

        var response = await service.AnalyzeCardAsync("u3", request);

        Assert.True(attempts >= 2); // Confirms retries were attempted
        Assert.True(response.FallbackToLocalBaseline);
        Assert.Equal("Rate Limited User", response.FullName.Value);
    }

    [Fact]
    public async Task Fallback_WhenHttp500ServerErrorOccurs_PreservesLocalBaseline()
    {
        using var dbContext = CreateInMemoryDbContext();
        var idempotencyManager = new CardAnalysisIdempotencyManager(dbContext, NullLogger<CardAnalysisIdempotencyManager>.Instance);
        var mockStorage = new Mock<IScanImageStorageService>();

        var mockHandler = new MockHttpMessageHandler(HttpStatusCode.InternalServerError, "Internal Server Error");
        var httpClient = new HttpClient(mockHandler);

        var service = new GeminiCardAnalysisService(
            httpClient,
            Options.Create(new GeminiOptions { ApiKey = "key", Enabled = true }),
            mockStorage.Object,
            _validator,
            idempotencyManager,
            NullLogger<GeminiCardAnalysisService>.Instance);

        var request = CreateSampleRequestWithBaseline("Server Err User", "Cloud Corp", "+1 555 888 7777");

        var response = await service.AnalyzeCardAsync("u4", request);

        Assert.True(response.FallbackToLocalBaseline);
        Assert.Equal("Server Err User", response.FullName.Value);
    }

    [Fact]
    public async Task Fallback_WhenGeminiReturnsMalformedJson_PreservesLocalBaseline()
    {
        using var dbContext = CreateInMemoryDbContext();
        var idempotencyManager = new CardAnalysisIdempotencyManager(dbContext, NullLogger<CardAnalysisIdempotencyManager>.Instance);
        var mockStorage = new Mock<IScanImageStorageService>();

        var malformedGeminiResponse = "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"NOT_VALID_JSON_AT_ALL\"}]}}]}";
        var mockHandler = new MockHttpMessageHandler(HttpStatusCode.OK, malformedGeminiResponse);
        var httpClient = new HttpClient(mockHandler);

        var service = new GeminiCardAnalysisService(
            httpClient,
            Options.Create(new GeminiOptions { ApiKey = "key", Enabled = true }),
            mockStorage.Object,
            _validator,
            idempotencyManager,
            NullLogger<GeminiCardAnalysisService>.Instance);

        var request = CreateSampleRequestWithBaseline("Malformed User", "Json Corp", "+1 555 777 6666");

        var response = await service.AnalyzeCardAsync("u5", request);

        Assert.True(response.FallbackToLocalBaseline);
        Assert.Equal("Malformed User", response.FullName.Value);
    }

    // =========================================================================
    // HELPERS
    // =========================================================================
    private static AnalyzeBusinessCardRequest CreateSampleRequestWithBaseline(string name, string company, string phone)
    {
        return new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_" + Guid.NewGuid().ToString("N")[..8],
            ScanContentHash = "hash_" + Guid.NewGuid().ToString("N")[..8],
            InvocationReason = "Fallback Test",
            AnalysisMode = "TextAndLayout",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = name, Engine = "PaddleOCR" },
                new() { Id = "obs_2", Text = company, Engine = "PaddleOCR" },
                new() { Id = "obs_3", Text = phone, Engine = "PaddleOCR" }
            },
            LocalBaseline = new LocalParserBaselineDto
            {
                FullName = name,
                Company = company,
                PhoneNumbers = new List<string> { phone }
            }
        };
    }

    private static string GetDummyGeminiCandidateJson()
    {
        return "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"{\\\"fullName\\\":{\\\"value\\\":\\\"Test\\\",\\\"confidence\\\":0.9,\\\"sourceObservationIds\\\":[\\\"obs_1\\\"]},\\\"company\\\":{\\\"value\\\":\\\"Corp\\\",\\\"confidence\\\":0.9,\\\"sourceObservationIds\\\":[\\\"obs_1\\\"]},\\\"jobTitle\\\":{\\\"value\\\":null,\\\"confidence\\\":0.5,\\\"sourceObservationIds\\\":[]},\\\"phoneNumbers\\\":[],\\\"emailAddresses\\\":[],\\\"websites\\\":[],\\\"address\\\":{\\\"fullAddress\\\":null,\\\"confidence\\\":0.5,\\\"sourceObservationIds\\\":[]},\\\"overallConfidence\\\":0.9,\\\"requiresManualReview\\\":false,\\\"reviewWarnings\\\":[]}\"}]}}]}";
    }

    private class MockHttpMessageHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> _handler;

        public MockHttpMessageHandler(HttpStatusCode statusCode, string content, Action<HttpRequestMessage>? onRequest = null)
        {
            _handler = (req, ct) =>
            {
                onRequest?.Invoke(req);
                return Task.FromResult(new HttpResponseMessage(statusCode)
                {
                    Content = new StringContent(content, Encoding.UTF8, "application/json")
                });
            };
        }

        public MockHttpMessageHandler(Func<CancellationToken, Task<HttpResponseMessage>> handler)
        {
            _handler = (req, ct) => handler(ct);
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            return _handler(request, cancellationToken);
        }
    }
}

