using System.Text.Json.Nodes;
using DigitalShare.Api.Configuration;
using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.CardAnalysis;
using DigitalShare.Api.Services.Gemini;
using DigitalShare.Api.Services.Storage;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using Xunit;

namespace DigitalShare.Api.Tests.Services;

public class GeminiCardAnalysisNameDisambiguationTests
{
    private readonly CardAnalysisSemanticValidator _validator = new();

    private ApplicationDbContext CreateInMemoryDbContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase("GeminiDisambiguationTest_" + Guid.NewGuid())
            .Options;
        return new ApplicationDbContext(options);
    }

    [Theory]
    [InlineData("Apex Healthcare")]
    [InlineData("Blue Horizon Technologies")]
    [InlineData("Summit Consulting")]
    [InlineData("Global Business Solutions")]
    [InlineData("Quantum Dynamics Systems")]
    public void FullName_ContainingCorporateEntitySuffix_DemotedToLowConfidenceReviewRequired(string corporateName)
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_corp_name",
            ScanContentHash = "hash_corp_name",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = corporateName, Engine = "PaddleOCR", Confidence = 0.98 }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            FullName = new ExtractedFieldDto
            {
                Value = corporateName,
                Confidence = 0.98,
                SourceObservationIds = new() { "obs_1" }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        Assert.NotNull(result.FullName);
        Assert.True(result.FullName.ReviewRequired);
        Assert.True(result.FullName.Confidence <= 0.30);
        Assert.True(result.RequiresManualReview);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("corporate or organizational entity"));
    }

    [Theory]
    [InlineData("Dr. Antony Lobo")]
    [InlineData("Prof. Charles Xavier")]
    [InlineData("Mr. John Smith")]
    [InlineData("Adv. Priya Sharma")]
    public void Company_StartingWithPersonalHonorific_DemotedToLowConfidenceReviewRequired(string personNameWithHonorific)
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_person_as_company",
            ScanContentHash = "hash_person_as_company",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = personNameWithHonorific, Engine = "PaddleOCR", Confidence = 0.95 }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            Company = new ExtractedFieldDto
            {
                Value = personNameWithHonorific,
                Confidence = 0.95,
                SourceObservationIds = new() { "obs_1" }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        Assert.NotNull(result.Company);
        Assert.True(result.Company.ReviewRequired);
        Assert.True(result.Company.Confidence <= 0.25);
        Assert.True(result.RequiresManualReview);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("personal honorific title"));
    }

    [Fact]
    public async Task BuildGeminiRestPayload_IncludesRule12ForPersonNameVsCompanyDisambiguation()
    {
        using var dbContext = CreateInMemoryDbContext();
        var idempotencyManager = new CardAnalysisIdempotencyManager(
            dbContext,
            NullLogger<CardAnalysisIdempotencyManager>.Instance);

        var storageMock = new Mock<IScanImageStorageService>();
        var geminiOptions = Options.Create(new GeminiOptions
        {
            ApiKey = "test-api-key",
            ModelId = "gemini-2.5-flash",
            Enabled = true
        });

        using var httpClient = new HttpClient();
        var service = new GeminiCardAnalysisService(
            httpClient,
            geminiOptions,
            storageMock.Object,
            _validator,
            idempotencyManager,
            NullLogger<GeminiCardAnalysisService>.Instance);

        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_rule12_test",
            ScanContentHash = "hash_rule12",
            AnalysisMode = "TextAndLayout",
            InvocationReason = "Ambiguous person/company assignment with uncertain confidence",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "Blue Horizon Technologies", Engine = "PaddleOCR" },
                new() { Id = "obs_2", Text = "Angela Davies", Engine = "PaddleOCR" },
                new() { Id = "obs_3", Text = "Director", Engine = "PaddleOCR" }
            },
            LocalBaseline = new LocalParserBaselineDto
            {
                FullName = "Blue Horizon Technologies",
                Company = "Angela Davies",
                JobTitle = "Director"
            }
        };

        var (payload, frontRetrieved, backRetrieved, failure) = await service.BuildGeminiRestPayloadWithImageStatusAsync(request);

        Assert.Contains("12. PERSON NAME VS. COMPANY/ORGANIZATION DISAMBIGUATION", payload);
        Assert.Contains("NEVER copy or leave a company name as fullName", payload);
        Assert.Contains("Baseline Name: Blue Horizon Technologies", payload);
        Assert.Contains("Baseline Company: Angela Davies", payload);
        Assert.Contains("Baseline JobTitle: Director", payload);
    }

    [Fact]
    public async Task AnalyzeCardAsync_WhenServiceDisabled_ExplicitlySetsGeminiApiExecutedFalseAndFallbackStatus()
    {
        using var dbContext = CreateInMemoryDbContext();
        var idempotencyManager = new CardAnalysisIdempotencyManager(
            dbContext,
            NullLogger<CardAnalysisIdempotencyManager>.Instance);

        var storageMock = new Mock<IScanImageStorageService>();
        var geminiOptions = Options.Create(new GeminiOptions
        {
            ApiKey = "test-key",
            ModelId = "gemini-2.5-flash",
            Enabled = false // Disabled
        });

        using var httpClient = new HttpClient();
        var service = new GeminiCardAnalysisService(
            httpClient,
            geminiOptions,
            storageMock.Object,
            _validator,
            idempotencyManager,
            NullLogger<GeminiCardAnalysisService>.Instance);

        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_disabled_audit",
            ScanContentHash = "hash_disabled",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "John Smith", Engine = "PaddleOCR" }
            }
        };

        var response = await service.AnalyzeCardAsync("test_user_id", request);

        Assert.False(response.GeminiApiExecuted);
        Assert.Equal("FallbackServiceDisabled", response.GeminiExecutionStatus);
        Assert.True(response.FallbackToLocalBaseline);
    }
}
