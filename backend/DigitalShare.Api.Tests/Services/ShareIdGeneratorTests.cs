using System.Text.RegularExpressions;
using DigitalShare.Api.Services;

namespace DigitalShare.Api.Tests.Services;

public class ShareIdGeneratorTests
{
    [Fact]
    public void GenerateShareId_GeneratesUniqueCryptographicallySecureValues()
    {
        var generator = new ShareIdGenerator();
        var generatedIds = new HashSet<string>();

        // Generate 1,000 ShareIds and ensure no collisions occur
        for (int i = 0; i < 1000; i++)
        {
            var shareId = generator.GenerateShareId();
            Assert.NotEmpty(shareId);
            Assert.DoesNotContain('+', shareId);
            Assert.DoesNotContain('/', shareId);
            Assert.DoesNotContain('=', shareId);
            Assert.True(generatedIds.Add(shareId), "ShareId collision detected!");
        }
    }

    [Fact]
    public void GenerateShareId_HasExpectedLengthAndUrlSafeFormat()
    {
        var generator = new ShareIdGenerator();
        var shareId = generator.GenerateShareId();

        // 18 bytes base64url encoded is 24 URL-safe characters (144 bits of entropy)
        Assert.Equal(24, shareId.Length);
        Assert.Matches(new Regex("^[a-zA-Z0-9_-]+$"), shareId);
    }
}
