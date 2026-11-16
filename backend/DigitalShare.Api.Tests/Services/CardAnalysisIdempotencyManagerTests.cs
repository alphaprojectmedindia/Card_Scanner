using DigitalShare.Api.DTOs.CardAnalysis;
using DigitalShare.Api.Services.Gemini;
using Xunit;

namespace DigitalShare.Api.Tests.Services;

public class CardAnalysisIdempotencyManagerTests
{
    private readonly CardAnalysisIdempotencyManager _manager = new(null!, null!);

    [Fact]
    public void ComputeAnalysisCacheKey_IsDeterministicForSameParameters()
    {
        var req1 = new AnalyzeBusinessCardRequest
        {
            ScanContentHash = "hash_abc",
            AnalysisMode = "TextAndLayout"
        };

        var req2 = new AnalyzeBusinessCardRequest
        {
            ScanContentHash = "hash_abc",
            AnalysisMode = "TextAndLayout"
        };

        var key1 = _manager.ComputeAnalysisCacheKey("user_123", req1, "gemini-3.8-flash");
        var key2 = _manager.ComputeAnalysisCacheKey("user_123", req2, "gemini-3.8-flash");

        Assert.NotEmpty(key1);
        Assert.Equal(key1, key2);
        Assert.Equal(32, key1.Length); // Fits safely within ScanJob.AnalysisKey constraint
    }

    [Fact]
    public void ComputeAnalysisCacheKey_DifferentiatesAcrossUsersAndModes()
    {
        var reqText = new AnalyzeBusinessCardRequest
        {
            ScanContentHash = "hash_abc",
            AnalysisMode = "TextAndLayout"
        };

        var reqMultimodal = new AnalyzeBusinessCardRequest
        {
            ScanContentHash = "hash_abc",
            AnalysisMode = "MultimodalVision",
            FrontImageStorageKey = "r2/key.jpg"
        };

        var keyUser1 = _manager.ComputeAnalysisCacheKey("user_1", reqText, "gemini-3.8-flash");
        var keyUser2 = _manager.ComputeAnalysisCacheKey("user_2", reqText, "gemini-3.8-flash");
        var keyMultimodal = _manager.ComputeAnalysisCacheKey("user_1", reqMultimodal, "gemini-3.8-flash");

        Assert.NotEqual(keyUser1, keyUser2);
        Assert.NotEqual(keyUser1, keyMultimodal);
    }
}
