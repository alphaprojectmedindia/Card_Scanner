using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.CardAnalysis;
using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.Tests.Helpers;
using Xunit;

namespace DigitalShare.Api.Tests.Controllers;

public class CardAnalysisControllerTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public CardAnalysisControllerTests(CustomWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
    }

    private async Task<string> RegisterAndGetTokenAsync()
    {
        var email = $"analysis_user_{Guid.NewGuid()}@example.com";
        var reg = new RegisterRequest
        {
            Email = email,
            Password = "Password123!",
            ConfirmPassword = "Password123!"
        };

        var response = await _client.PostAsJsonAsync("/api/auth/register", reg);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var auth = await response.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);
        return auth!.Token;
    }

    [Fact]
    public async Task UploadCardImage_WithoutToken_ReturnsUnauthorized()
    {
        using var content = new MultipartFormDataContent();
        content.Add(new ByteArrayContent(new byte[] { 1, 2, 3 }), "file", "card.jpg");

        var response = await _client.PostAsync("/api/business-cards/images", content);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task UploadCardImage_WithInvalidMimeType_ReturnsBadRequest()
    {
        var token = await RegisterAndGetTokenAsync();
        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/business-cards/images");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        using var content = new MultipartFormDataContent();
        var fileContent = new ByteArrayContent(new byte[] { 1, 2, 3 });
        fileContent.Headers.ContentType = new MediaTypeHeaderValue("application/pdf");
        content.Add(fileContent, "file", "card.pdf");
        request.Content = content;

        var response = await _client.SendAsync(request);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task UploadCardImage_WithValidImage_ReturnsOkWithStorageKey()
    {
        var token = await RegisterAndGetTokenAsync();
        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/business-cards/images");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        using var content = new MultipartFormDataContent();
        var fileContent = new ByteArrayContent(new byte[] { 0xFF, 0xD8, 0xFF, 0xE0 }); // JPEG header
        fileContent.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
        content.Add(fileContent, "file", "card.jpg");
        content.Add(new StringContent("front"), "cardSide");
        request.Content = content;

        var response = await _client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var result = await response.Content.ReadFromJsonAsync<ImageUploadResponse>();
        Assert.NotNull(result);
        Assert.NotEmpty(result!.StorageKey);
        Assert.Equal("front", result.CardSide);
    }

    [Fact]
    public async Task AnalyzeCard_WithoutToken_ReturnsUnauthorized()
    {
        var req = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_no_auth",
            ScanContentHash = "hash_no_auth",
            InvocationReason = "Test"
        };

        var response = await _client.PostAsJsonAsync("/api/business-cards/analyze", req);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task AnalyzeCard_WithEmptyObservationsAndNoImage_ReturnsBadRequest()
    {
        var token = await RegisterAndGetTokenAsync();
        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/business-cards/analyze");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var req = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_empty",
            ScanContentHash = "hash_empty",
            InvocationReason = "Test",
            OcrObservations = new List<OcrObservationDto>() // empty
        };
        request.Content = JsonContent.Create(req);

        var response = await _client.SendAsync(request);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task AnalyzeCard_WithValidObservations_FallsBackGracefullyToLocalBaselineWhenGeminiUnconfigured()
    {
        var token = await RegisterAndGetTokenAsync();
        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/business-cards/analyze");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var req = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_local_fallback",
            ScanContentHash = "hash_local_fallback",
            InvocationReason = "Test T1",
            AnalysisMode = "TextAndLayout",
            OcrObservations = new List<OcrObservationDto>
            {
                new()
                {
                    Id = "obs_1",
                    Text = "Acme Corp",
                    Engine = "PaddleOCR",
                    Confidence = 0.95,
                    BoundingBox = new() { Top = 0.1, Left = 0.1, Bottom = 0.2, Right = 0.5 }
                }
            },
            LocalBaseline = new LocalParserBaselineDto
            {
                Company = "Acme Corp",
                FullName = "John Doe",
                PhoneNumbers = new List<string> { "+1 555 123 4567" }
            }
        };
        request.Content = JsonContent.Create(req);

        var response = await _client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var result = await response.Content.ReadFromJsonAsync<AnalyzeBusinessCardResponse>();
        Assert.NotNull(result);
        Assert.Equal("req_local_fallback", result!.ClientRequestId);
        // Because Gemini API key is not configured in test environment, it safely falls back to local baseline
        Assert.True(result.FallbackToLocalBaseline);
        Assert.Equal("John Doe", result.FullName.Value);
        Assert.Equal("Acme Corp", result.Company.Value);
        Assert.Single(result.PhoneNumbers);
        Assert.Equal("+1 555 123 4567", result.PhoneNumbers[0].Number);
    }

    [Fact]
    public async Task AnalyzeCard_WithIdenticalRequest_DemonstratesIdempotency()
    {
        var token = await RegisterAndGetTokenAsync();

        var req = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_idempotent_1",
            ScanContentHash = "hash_idempotent_test",
            InvocationReason = "Testing Cache",
            AnalysisMode = "TextAndLayout",
            OcrObservations = new List<OcrObservationDto>
            {
                new()
                {
                    Id = "obs_1",
                    Text = "Tech Solutions",
                    Engine = "PaddleOCR",
                    Confidence = 0.90,
                    BoundingBox = new() { Top = 0.1, Left = 0.1, Bottom = 0.2, Right = 0.5 }
                }
            },
            LocalBaseline = new LocalParserBaselineDto
            {
                Company = "Tech Solutions"
            }
        };

        // First call
        using var request1 = new HttpRequestMessage(HttpMethod.Post, "/api/business-cards/analyze");
        request1.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request1.Content = JsonContent.Create(req);

        var response1 = await _client.SendAsync(request1);
        Assert.Equal(HttpStatusCode.OK, response1.StatusCode);
        var result1 = await response1.Content.ReadFromJsonAsync<AnalyzeBusinessCardResponse>();

        // Second call with same hash
        req.ClientRequestId = "req_idempotent_2";
        using var request2 = new HttpRequestMessage(HttpMethod.Post, "/api/business-cards/analyze");
        request2.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request2.Content = JsonContent.Create(req);

        var response2 = await _client.SendAsync(request2);
        Assert.Equal(HttpStatusCode.OK, response2.StatusCode);
        var result2 = await response2.Content.ReadFromJsonAsync<AnalyzeBusinessCardResponse>();

        Assert.NotNull(result1);
        Assert.NotNull(result2);
        Assert.Equal(result1!.Company.Value, result2!.Company.Value);
        Assert.Equal("req_idempotent_2", result2.ClientRequestId);
    }
}

