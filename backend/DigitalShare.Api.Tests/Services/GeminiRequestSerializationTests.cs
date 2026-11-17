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
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using Xunit;

namespace DigitalShare.Api.Tests.Services;

public class GeminiRequestSerializationTests
{
    private readonly CardAnalysisSemanticValidator _validator = new();

    private ApplicationDbContext CreateInMemoryDbContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase("GeminiSerializationTest_" + Guid.NewGuid())
            .Options;
        return new ApplicationDbContext(options);
    }

    private GeminiCardAnalysisService CreateService(
        HttpMessageHandler handler,
        string modelId = "gemini-3.8-flash",
        int maxRetries = 2)
    {
        var httpClient = new HttpClient(handler);
        var geminiOptions = Options.Create(new GeminiOptions
        {
            Enabled = true,
            ApiKey = "test-api-key-12345",
            ModelId = modelId,
            MaxRetries = maxRetries
        });

        var dbContext = CreateInMemoryDbContext();
        var idempotencyManager = new CardAnalysisIdempotencyManager(
            dbContext,
            NullLogger<CardAnalysisIdempotencyManager>.Instance);

        var mockStorage = new Mock<IScanImageStorageService>();
        mockStorage.Setup(s => s.GetScanImageStreamAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(() => new MemoryStream(Encoding.UTF8.GetBytes("fake_image_bytes")));

        return new GeminiCardAnalysisService(
            httpClient,
            geminiOptions,
            mockStorage.Object,
            _validator,
            idempotencyManager,
            NullLogger<GeminiCardAnalysisService>.Instance);
    }

    private static AnalyzeBusinessCardRequest CreateSampleRequest()
    {
        return new AnalyzeBusinessCardRequest
        {
            AnalysisMode = "TextAndLayout",
            InvocationReason = "LowConfidenceParsing",
            OcrObservations = new List<OcrObservationDto>
            {
                new()
                {
                    Id = "obs_1",
                    Engine = "PaddleOCR",
                    CardSide = "Front",
                    Confidence = 0.95,
                    Text = "John Doe",
                    BoundingBox = new NormalizedBoundingBoxDto { Top = 0.1, Left = 0.1, Bottom = 0.15, Right = 0.5 }
                },
                new()
                {
                    Id = "obs_2",
                    Engine = "MLKit",
                    CardSide = "Front",
                    Confidence = 0.92,
                    Text = "Acme Corp",
                    BoundingBox = new NormalizedBoundingBoxDto { Top = 0.2, Left = 0.1, Bottom = 0.25, Right = 0.6 }
                }
            },
            LocalBaseline = new LocalParserBaselineDto
            {
                FullName = "John Doe",
                Company = "Acme Corp",
                JobTitle = "Senior Engineer"
            }
        };
    }

    // =========================================================================
    // 1. SERIALIZATION SCHEMA & RESPONSEFORMAT VERIFICATION
    // =========================================================================

    [Fact]
    public void ReproduceOriginalException_JsonSerializerOptionsWithoutResolver_MakeReadOnlyThrows()
    {
        var optionsWithoutResolver = new JsonSerializerOptions { WriteIndented = false };
        var ex = Assert.Throws<InvalidOperationException>(() => optionsWithoutResolver.MakeReadOnly());
        Assert.Contains("TypeInfoResolver", ex.Message);
    }

    [Fact]
    public async Task BuildGeminiRestPayload_Serializes_ResponseFormat_With_ApplicationJson_And_Schema()
    {
        var service = CreateService(new MockHttpMessageHandler(HttpStatusCode.OK, "{}"));
        var request = CreateSampleRequest();

        var payloadJson = await service.BuildGeminiRestPayloadAsync(request);
        var jsonDoc = JsonNode.Parse(payloadJson);

        Assert.NotNull(jsonDoc);
        var root = jsonDoc.AsObject();

        // 1. generationConfig must exist
        Assert.True(root.ContainsKey("generationConfig"), "Root JSON must contain 'generationConfig'");
        var genConfig = root["generationConfig"]!.AsObject();

        // 2. Deprecated responseSchema and responseMimeType must NOT be directly on generationConfig
        Assert.False(genConfig.ContainsKey("responseSchema"), "'responseSchema' is deprecated and must not be present directly under generationConfig.");
        Assert.False(genConfig.ContainsKey("responseMimeType"), "'responseMimeType' must not be present under generationConfig when using responseFormat.");

        // 3. responseFormat must be present
        Assert.True(genConfig.ContainsKey("responseFormat"), "generationConfig must contain 'responseFormat'");
        var responseFormat = genConfig["responseFormat"]!.AsObject();

        // 4. text format must be present inside responseFormat
        Assert.True(responseFormat.ContainsKey("text"), "responseFormat must contain 'text'");
        var textFormat = responseFormat["text"]!.AsObject();

        // 5. mimeType must be uppercase "APPLICATION_JSON" (required by Google GenAI Protobuf enum)
        Assert.True(textFormat.ContainsKey("mimeType"), "text format must contain 'mimeType'");
        Assert.Equal("APPLICATION_JSON", textFormat["mimeType"]!.GetValue<string>());

        // 6. schema must be inside textFormat
        Assert.True(textFormat.ContainsKey("schema"), "text format must contain 'schema'");
        var schema = textFormat["schema"]!.AsObject();

        Assert.Equal("OBJECT", schema["type"]!.GetValue<string>());
        var properties = schema["properties"]!.AsObject();

        Assert.True(properties.ContainsKey("fullName"));
        Assert.True(properties.ContainsKey("company"));
        Assert.True(properties.ContainsKey("jobTitle"));
        Assert.True(properties.ContainsKey("phoneNumbers"));
        Assert.True(properties.ContainsKey("emailAddresses"));
        Assert.True(properties.ContainsKey("websites"));
        Assert.True(properties.ContainsKey("address"));
        Assert.True(properties.ContainsKey("overallConfidence"));
        Assert.True(properties.ContainsKey("requiresManualReview"));
    }

    [Fact]
    public void BuildGeminiJsonSchema_Validates_AllSemanticFieldRules()
    {
        var service = CreateService(new MockHttpMessageHandler(HttpStatusCode.OK, "{}"));
        var schema = service.BuildGeminiJsonSchema();

        Assert.NotNull(schema);
        Assert.Equal("OBJECT", schema["type"]!.GetValue<string>());

        var requiredFields = schema["required"]!.AsArray().Select(v => v!.GetValue<string>()).ToList();
        Assert.Contains("fullName", requiredFields);
        Assert.Contains("company", requiredFields);
        Assert.Contains("jobTitle", requiredFields);
        Assert.Contains("phoneNumbers", requiredFields);
        Assert.Contains("emailAddresses", requiredFields);
        Assert.Contains("websites", requiredFields);
        Assert.Contains("address", requiredFields);
        Assert.Contains("overallConfidence", requiredFields);
        Assert.Contains("requiresManualReview", requiredFields);

        var props = schema["properties"]!.AsObject();

        // Validate fullName
        var fullNameProp = props["fullName"]!.AsObject();
        Assert.Equal("OBJECT", fullNameProp["type"]!.GetValue<string>());
        var nameProps = fullNameProp["properties"]!.AsObject();
        Assert.True(nameProps.ContainsKey("value"));
        Assert.True(nameProps.ContainsKey("confidence"));
        Assert.True(nameProps.ContainsKey("rawEvidence"));
        Assert.True(nameProps.ContainsKey("sourceObservationIds"));
        Assert.True(nameProps.ContainsKey("wasCorrected"));

        // Validate address
        var addressProp = props["address"]!.AsObject();
        var addressSubProps = addressProp["properties"]!.AsObject();
        Assert.True(addressSubProps.ContainsKey("fullAddress"));
        Assert.True(addressSubProps.ContainsKey("street"));
        Assert.True(addressSubProps.ContainsKey("city"));
        Assert.True(addressSubProps.ContainsKey("state"));
        Assert.True(addressSubProps.ContainsKey("postalCode"));
        Assert.True(addressSubProps.ContainsKey("country"));
        Assert.True(addressSubProps.ContainsKey("sourceObservationIds"));
    }

    // =========================================================================
    // 2. MODEL ENDPOINTS VERIFICATION (gemini-3.8-flash & gemini-3.5-flash-lite)
    // =========================================================================

    [Fact]
    public async Task OutgoingHttpRequest_TargetsGemini38Flash_WithProperEndpointAndBody()
    {
        HttpRequestMessage? capturedRequest = null;
        string? capturedBody = null;

        var handler = new MockHttpMessageHandler(
            HttpStatusCode.OK,
            GetValidGeminiResponseJson(),
            async req =>
            {
                capturedRequest = req;
                capturedBody = await req.Content!.ReadAsStringAsync();
            });

        var service = CreateService(handler, modelId: "gemini-3.8-flash");
        var request = CreateSampleRequest();

        await service.AnalyzeCardAsync("user_123", request);

        Assert.NotNull(capturedRequest);
        Assert.Contains("models/gemini-3.8-flash:generateContent", capturedRequest.RequestUri!.ToString());
        Assert.NotNull(capturedBody);

        var json = JsonNode.Parse(capturedBody)!;
        var mimeType = json["generationConfig"]?["responseFormat"]?["text"]?["mimeType"]?.GetValue<string>();
        Assert.Equal("APPLICATION_JSON", mimeType);
    }

    [Fact]
    public async Task OutgoingHttpRequest_TargetsGemini35FlashLite_WithProperEndpointAndBody()
    {
        HttpRequestMessage? capturedRequest = null;
        string? capturedBody = null;

        var handler = new MockHttpMessageHandler(
            HttpStatusCode.OK,
            GetValidGeminiResponseJson(),
            async req =>
            {
                capturedRequest = req;
                capturedBody = await req.Content!.ReadAsStringAsync();
            });

        var service = CreateService(handler, modelId: "gemini-3.5-flash-lite");
        var request = CreateSampleRequest();

        await service.AnalyzeCardAsync("user_123", request);

        Assert.NotNull(capturedRequest);
        Assert.Contains("models/gemini-3.5-flash-lite:generateContent", capturedRequest.RequestUri!.ToString());
        Assert.NotNull(capturedBody);

        var json = JsonNode.Parse(capturedBody)!;
        var mimeType = json["generationConfig"]?["responseFormat"]?["text"]?["mimeType"]?.GetValue<string>();
        Assert.Equal("APPLICATION_JSON", mimeType);
    }

    // =========================================================================
    // 3. RETRY LOGIC VERIFICATION: 400 & 403 NO RETRY, 429 & 503 DO RETRY
    // =========================================================================

    [Fact]
    public async Task GeminiApi_Http400BadRequest_FailsImmediatelyWithoutRetries()
    {
        var callCount = 0;
        var handler = new CountingHttpMessageHandler((req, ct) =>
        {
            callCount++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.BadRequest)
            {
                Content = new StringContent("{\"error\":{\"code\":400,\"message\":\"Invalid argument\"}}", Encoding.UTF8, "application/json")
            });
        });

        var service = CreateService(handler, maxRetries: 3);
        var request = CreateSampleRequest();

        // 1. Direct call: ExecuteGeminiCallWithRetriesAsync must throw immediately on 400
        var ex = await Assert.ThrowsAsync<InvalidOperationException>(
            () => service.ExecuteGeminiCallWithRetriesAsync(request, CancellationToken.None));

        Assert.Contains("400", ex.Message);
        Assert.Equal(1, callCount); // Must be strictly 1 attempt! No retries on 400!

        // 2. High-level call: AnalyzeCardAsync falls back to baseline without retrying
        callCount = 0;
        var response = await service.AnalyzeCardAsync("user_test", request);
        Assert.True(response.FallbackToLocalBaseline);
        Assert.Contains(response.ReviewWarnings, w => w.Contains("400"));
        Assert.Equal(1, callCount); // Must be strictly 1 attempt!
    }

    [Fact]
    public async Task GeminiApi_Http403Forbidden_FailsImmediatelyWithoutRetries()
    {
        var callCount = 0;
        var handler = new CountingHttpMessageHandler((req, ct) =>
        {
            callCount++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden)
            {
                Content = new StringContent("{\"error\":{\"code\":403,\"message\":\"API key not valid or billing required\"}}", Encoding.UTF8, "application/json")
            });
        });

        var service = CreateService(handler, maxRetries: 3);
        var request = CreateSampleRequest();

        // 1. Direct call: ExecuteGeminiCallWithRetriesAsync must throw immediately on 403
        var ex = await Assert.ThrowsAsync<InvalidOperationException>(
            () => service.ExecuteGeminiCallWithRetriesAsync(request, CancellationToken.None));

        Assert.Contains("403", ex.Message);
        Assert.Equal(1, callCount); // Must be strictly 1 attempt! No retries on 403!

        // 2. High-level call: AnalyzeCardAsync falls back to baseline without retrying
        callCount = 0;
        var response = await service.AnalyzeCardAsync("user_test", request);
        Assert.True(response.FallbackToLocalBaseline);
        Assert.Contains(response.ReviewWarnings, w => w.Contains("403"));
        Assert.Equal(1, callCount); // Must be strictly 1 attempt!
    }

    [Fact]
    public async Task GeminiApi_Http429TooManyRequests_RetriesAndRecovers()
    {
        var callCount = 0;
        var handler = new CountingHttpMessageHandler((req, ct) =>
        {
            callCount++;
            if (callCount < 3)
            {
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.TooManyRequests)
                {
                    Content = new StringContent("{\"error\":{\"code\":429,\"message\":\"Resource exhausted\"}}", Encoding.UTF8, "application/json")
                });
            }

            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(GetValidGeminiResponseJson(), Encoding.UTF8, "application/json")
            });
        });

        var service = CreateService(handler, maxRetries: 3);
        var request = CreateSampleRequest();

        var response = await service.AnalyzeCardAsync("user_test", request);

        Assert.NotNull(response);
        Assert.Equal("John Doe", response.FullName.Value);
        Assert.Equal(3, callCount); // Succeeded on attempt 3 after 2 retries
    }

    [Fact]
    public async Task GeminiApi_Http503ServiceUnavailable_RetriesAndRecovers()
    {
        var callCount = 0;
        var handler = new CountingHttpMessageHandler((req, ct) =>
        {
            callCount++;
            if (callCount < 2)
            {
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)
                {
                    Content = new StringContent("{\"error\":{\"code\":503,\"message\":\"The model is overloaded.\"}}", Encoding.UTF8, "application/json")
                });
            }

            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(GetValidGeminiResponseJson(), Encoding.UTF8, "application/json")
            });
        });

        var service = CreateService(handler, maxRetries: 3);
        var request = CreateSampleRequest();

        var response = await service.AnalyzeCardAsync("user_test", request);

        Assert.NotNull(response);
        Assert.Equal("John Doe", response.FullName.Value);
        Assert.Equal(2, callCount); // Succeeded on attempt 2 after 1 retry
    }

    // =========================================================================
    // HELPERS & MOCK HANDLERS
    // =========================================================================

    private static string GetValidGeminiResponseJson()
    {
        var cardJson = JsonSerializer.Serialize(new
        {
            fullName = new { value = "John Doe", confidence = 0.95, rawEvidence = "John Doe", sourceObservationIds = new[] { "obs_1" }, wasCorrected = false },
            company = new { value = "Acme Corp", confidence = 0.92, rawEvidence = "Acme Corp", sourceObservationIds = new[] { "obs_2" }, wasCorrected = false },
            jobTitle = new { value = "Senior Engineer", confidence = 0.88, rawEvidence = "Senior Engineer", sourceObservationIds = new[] { "obs_1" }, wasCorrected = false },
            phoneNumbers = Array.Empty<object>(),
            emailAddresses = Array.Empty<object>(),
            websites = Array.Empty<object>(),
            address = new { fullAddress = (string?)null, confidence = 0.5, sourceObservationIds = Array.Empty<string>() },
            overallConfidence = 0.93,
            requiresManualReview = false,
            reviewWarnings = Array.Empty<string>()
        });

        return $"{{\"candidates\":[{{\"content\":{{\"parts\":[{{\"text\":{JsonSerializer.Serialize(cardJson)}}}]}}]}}";
    }

    private class MockHttpMessageHandler : HttpMessageHandler
    {
        private readonly HttpStatusCode _statusCode;
        private readonly string _content;
        private readonly Action<HttpRequestMessage>? _onRequest;

        public MockHttpMessageHandler(HttpStatusCode statusCode, string content, Action<HttpRequestMessage>? onRequest = null)
        {
            _statusCode = statusCode;
            _content = content;
            _onRequest = onRequest;
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            _onRequest?.Invoke(request);
            return Task.FromResult(new HttpResponseMessage(_statusCode)
            {
                Content = new StringContent(_content, Encoding.UTF8, "application/json")
            });
        }
    }

    private class CountingHttpMessageHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> _handler;

        public CountingHttpMessageHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> handler)
        {
            _handler = handler;
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            return _handler(request, cancellationToken);
        }
    }

    [Fact]
    public async Task BuildGeminiRestPayload_MultimodalVision_IncludesBothFrontAndBackImages()
    {
        var service = CreateService(new MockHttpMessageHandler(HttpStatusCode.OK, "{}"));
        var request = CreateSampleRequest();
        request.AnalysisMode = "MultimodalVision";
        request.FrontImageStorageKey = "scans/front_card.jpg";
        request.BackImageStorageKey = "scans/back_card.jpg";
        request.UncertainFields = new List<string> { "phone", "email" };

        var (payload, frontRetrieved, backRetrieved, retrievalFailure) =
            await service.BuildGeminiRestPayloadWithImageStatusAsync(request);

        Assert.True(frontRetrieved);
        Assert.True(backRetrieved);
        Assert.Null(retrievalFailure);

        var doc = JsonNode.Parse(payload)!.AsObject();
        var parts = doc["contents"]![0]!["parts"]!.AsArray();

        // Must contain 2 inlineData parts (front and back) plus 1 text prompt part
        Assert.Equal(3, parts.Count);
        var inlineDataCount = parts.Count(p => p?["inlineData"] != null);
        Assert.Equal(2, inlineDataCount);

        var promptText = parts.First(p => p?["text"] != null)!["text"]!.GetValue<string>();
        Assert.Contains("[UNCERTAIN FIELDS REQUIRING TARGETED VERIFICATION]", promptText);
        Assert.Contains("CRITICAL DATA INTEGRITY & VISUAL VERIFICATION RULES", promptText);
    }

    [Fact]
    public async Task ExecuteGeminiCall_ImageRetrievalFailure_SetsVisualVerificationFalse()
    {
        var candidateTextJson = "{\"fullName\":{\"value\":\"John Doe\",\"confidence\":0.9,\"sourceObservationIds\":[\"obs_1\"]},\"company\":{\"value\":\"Acme\",\"confidence\":0.9,\"sourceObservationIds\":[\"obs_2\"]},\"jobTitle\":{\"value\":\"Eng\",\"confidence\":0.9,\"sourceObservationIds\":[]},\"phoneNumbers\":[],\"emailAddresses\":[],\"websites\":[],\"address\":{\"confidence\":0.9,\"sourceObservationIds\":[]},\"overallConfidence\":0.9,\"requiresManualReview\":false}";
        var geminiResponseEnvelope = "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":" + JsonSerializer.Serialize(candidateTextJson) + "}]}}]}";
        var httpClient = new HttpClient(new MockHttpMessageHandler(HttpStatusCode.OK, geminiResponseEnvelope));

        var geminiOptions = Options.Create(new GeminiOptions
        {
            Enabled = true,
            ApiKey = "test-key",
            ModelId = "gemini-3.8-flash"
        });

        using var dbContext = CreateInMemoryDbContext();
        var idempotencyManager = new CardAnalysisIdempotencyManager(
            dbContext,
            NullLogger<CardAnalysisIdempotencyManager>.Instance);

        var mockStorage = new Mock<IScanImageStorageService>();
        // Return null stream to simulate missing or corrupted image file
        mockStorage.Setup(s => s.GetScanImageStreamAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Stream?)null);

        var service = new GeminiCardAnalysisService(
            httpClient,
            geminiOptions,
            mockStorage.Object,
            _validator,
            idempotencyManager,
            NullLogger<GeminiCardAnalysisService>.Instance);

        var request = CreateSampleRequest();
        request.AnalysisMode = "MultimodalVision";
        request.FrontImageStorageKey = "scans/missing_image.jpg";

        var response = await service.ExecuteGeminiCallWithRetriesAsync(request, CancellationToken.None);

        Assert.False(response.VisualVerificationPerformed);
        Assert.False(response.FrontImageVerified);
        Assert.NotNull(response.ImageVerificationFailureReason);
        Assert.Contains("could not be retrieved", response.ImageVerificationFailureReason);
    }

    // =========================================================================
    // REGRESSION TEST SUITE: .NET 8 JSON SERIALIZATION FIX & VERIFICATION
    // =========================================================================

    [Fact]
    public async Task Regression_SerializeCompleteGeminiPayload_WithConfiguredResolver_Succeeds()
    {
        var service = CreateService(new MockHttpMessageHandler(HttpStatusCode.OK, "{}"));
        var request = CreateSampleRequest();
        request.AnalysisMode = "MultimodalVision";
        request.FrontImageStorageKey = "scans/front_card.jpg";
        request.BackImageStorageKey = "scans/back_card.jpg";

        // Must succeed without throwing System.InvalidOperationException
        var (payload, frontRetrieved, backRetrieved, failure) =
            await service.BuildGeminiRestPayloadWithImageStatusAsync(request);

        Assert.NotNull(payload);
        Assert.NotEmpty(payload);
        Assert.True(frontRetrieved);
        Assert.True(backRetrieved);
        Assert.Null(failure);
    }

    [Fact]
    public async Task Regression_SerializeCompleteGeminiPayload_RetainsImageDataAndBase64Encoding()
    {
        var service = CreateService(new MockHttpMessageHandler(HttpStatusCode.OK, "{}"));
        var request = CreateSampleRequest();
        request.AnalysisMode = "MultimodalVision";
        request.FrontImageStorageKey = "scans/front_card.jpg";
        request.BackImageStorageKey = "scans/back_card.jpg";

        var (payload, _, _, _) = await service.BuildGeminiRestPayloadWithImageStatusAsync(request);

        var json = JsonNode.Parse(payload)!.AsObject();
        var parts = json["contents"]![0]!["parts"]!.AsArray();

        // Expected base64 of "fake_image_bytes" set up in CreateService mock
        var expectedBase64 = Convert.ToBase64String(Encoding.UTF8.GetBytes("fake_image_bytes"));

        var inlineParts = parts.Where(p => p?["inlineData"] != null).ToList();
        Assert.Equal(2, inlineParts.Count);

        foreach (var inlinePart in inlineParts)
        {
            var data = inlinePart!["inlineData"]!["data"]!.GetValue<string>();
            Assert.Equal(expectedBase64, data);
        }
    }

    [Fact]
    public async Task Regression_SerializeCompleteGeminiPayload_RetainsMimeTypes()
    {
        var service = CreateService(new MockHttpMessageHandler(HttpStatusCode.OK, "{}"));
        var request = CreateSampleRequest();
        request.AnalysisMode = "MultimodalVision";
        request.FrontImageStorageKey = "scans/front_card.jpg";

        var (payload, _, _, _) = await service.BuildGeminiRestPayloadWithImageStatusAsync(request);

        var json = JsonNode.Parse(payload)!.AsObject();

        // 1. Verify image inlineData mimeType is image/jpeg
        var parts = json["contents"]![0]!["parts"]!.AsArray();
        var inlineData = parts.First(p => p?["inlineData"] != null)!["inlineData"]!.AsObject();
        Assert.Equal("image/jpeg", inlineData["mimeType"]!.GetValue<string>());

        // 2. Verify generationConfig responseFormat mimeType is APPLICATION_JSON
        var responseFormatText = json["generationConfig"]!["responseFormat"]!["text"]!.AsObject();
        Assert.Equal("APPLICATION_JSON", responseFormatText["mimeType"]!.GetValue<string>());
    }

    [Fact]
    public async Task Regression_SerializeCompleteGeminiPayload_CanBeParsedBackToJsonNode()
    {
        var service = CreateService(new MockHttpMessageHandler(HttpStatusCode.OK, "{}"));
        var request = CreateSampleRequest();
        request.AnalysisMode = "MultimodalVision";
        request.FrontImageStorageKey = "scans/front_card.jpg";
        request.BackImageStorageKey = "scans/back_card.jpg";

        var (payload, _, _, _) = await service.BuildGeminiRestPayloadWithImageStatusAsync(request);

        // Parsing back must succeed with standard JsonNode and JsonDocument
        var parsedNode = JsonNode.Parse(payload);
        Assert.NotNull(parsedNode);

        using var parsedDoc = JsonDocument.Parse(payload);

        // Verify root structure is preserved exactly
        Assert.Equal(JsonValueKind.Object, parsedDoc.RootElement.ValueKind);
        Assert.True(parsedDoc.RootElement.TryGetProperty("contents", out var contentsProp));
        Assert.True(parsedDoc.RootElement.TryGetProperty("generationConfig", out var genConfigProp));
        Assert.Equal(JsonValueKind.Array, contentsProp.ValueKind);
        Assert.Equal(JsonValueKind.Object, genConfigProp.ValueKind);
    }

    [Fact]
    public async Task Regression_ExecuteGeminiCall_WhenGeminiReturnsHttpError_FallsBackToLocalBaselineGracefully()
    {
        // Mock Gemini returning 500 Internal Server Error
        var service = CreateService(new MockHttpMessageHandler(HttpStatusCode.InternalServerError, "{\"error\":{\"code\":500,\"message\":\"Backend Error\"}}"));
        var request = CreateSampleRequest();
        request.LocalBaseline = new LocalParserBaselineDto
        {
            FullName = "Jane Smith",
            Company = "Apex Healthcare",
            JobTitle = "Chief Medical Officer",
            PhoneNumbers = new List<string> { "+1 555 987 6543" }
        };

        var response = await service.AnalyzeCardAsync("user_fallback_test", request, CancellationToken.None);

        Assert.NotNull(response);
        Assert.False(response.GeminiApiExecuted);
        Assert.True(response.FallbackToLocalBaseline);
        Assert.StartsWith("FallbackError", response.GeminiExecutionStatus);

        // Verify local baseline fields were preserved and restored into response
        Assert.Equal("Jane Smith", response.FullName?.Value);
        Assert.Equal("Apex Healthcare", response.Company?.Value);
        Assert.Equal("Chief Medical Officer", response.JobTitle?.Value);
        Assert.Single(response.PhoneNumbers);
        Assert.Equal("+1 555 987 6543", response.PhoneNumbers[0].Number);
    }
}

