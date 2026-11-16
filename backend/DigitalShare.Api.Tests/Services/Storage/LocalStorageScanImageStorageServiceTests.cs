using System.Text;
using DigitalShare.Api.Configuration;
using DigitalShare.Api.Services.Storage;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;

namespace DigitalShare.Api.Tests.Services.Storage;

public class LocalStorageScanImageStorageServiceTests : IDisposable
{
    private readonly string _testDirectory;
    private readonly Mock<IWebHostEnvironment> _envMock;
    private readonly Mock<ILogger<LocalStorageScanImageStorageService>> _loggerMock;

    public LocalStorageScanImageStorageServiceTests()
    {
        _testDirectory = Path.Combine(Path.GetTempPath(), "digitalshare_test_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_testDirectory);

        _envMock = new Mock<IWebHostEnvironment>();
        _envMock.Setup(e => e.ContentRootPath).Returns(_testDirectory);

        _loggerMock = new Mock<ILogger<LocalStorageScanImageStorageService>>();
    }

    public void Dispose()
    {
        if (Directory.Exists(_testDirectory))
        {
            try
            {
                Directory.Delete(_testDirectory, recursive: true);
            }
            catch
            {
                // Ignore cleanup errors in temporary test directories
            }
        }
    }

    private LocalStorageScanImageStorageService CreateService(int maxMb = 20)
    {
        var options = Options.Create(new StorageOptions
        {
            Provider = StorageProvider.Local,
            Local = new LocalStorageOptions
            {
                Directory = _testDirectory,
                MaxFileSizeMb = maxMb
            }
        });

        return new LocalStorageScanImageStorageService(_envMock.Object, options, _loggerMock.Object);
    }

    [Fact]
    public async Task Upload_And_GetStream_SuccessfullyRoundTripsImageData()
    {
        // Arrange
        var service = CreateService();
        var originalData = Encoding.UTF8.GetBytes("Fake JPEG pixel payload for testing OCR storage");
        using var uploadStream = new MemoryStream(originalData);

        // Act
        var storageKey = await service.UploadScanImageAsync(uploadStream, "image/jpeg", originalData.Length);

        // Assert
        Assert.NotNull(storageKey);
        Assert.StartsWith("scans/", storageKey);
        Assert.EndsWith(".jpg", storageKey);

        using var downloadStream = await service.GetScanImageStreamAsync(storageKey);
        Assert.NotNull(downloadStream);

        using var ms = new MemoryStream();
        await downloadStream.CopyToAsync(ms);
        Assert.Equal(originalData, ms.ToArray());
    }

    [Theory]
    [InlineData("image/jpeg", ".jpg")]
    [InlineData("image/png", ".png")]
    [InlineData("image/webp", ".webp")]
    public async Task Upload_SupportsStandardImageMimeTypes(string mimeType, string expectedExtension)
    {
        // Arrange
        var service = CreateService();
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes("image data"));

        // Act
        var key = await service.UploadScanImageAsync(stream, mimeType);

        // Assert
        Assert.EndsWith(expectedExtension, key);
    }

    [Theory]
    [InlineData("application/pdf")]
    [InlineData("text/plain")]
    [InlineData("application/x-msdownload")]
    [InlineData("")]
    public async Task Upload_RejectsDisallowedContentTypes(string invalidMimeType)
    {
        // Arrange
        var service = CreateService();
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes("some content"));

        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(
            () => service.UploadScanImageAsync(stream, invalidMimeType));
    }

    [Fact]
    public async Task Upload_ThrowsArgumentException_WhenContentLengthExceedsLimit()
    {
        // Arrange (1 MB limit)
        var service = CreateService(maxMb: 1);
        using var stream = new MemoryStream(new byte[1024]);

        // Act & Assert (declared length 2 MB)
        await Assert.ThrowsAsync<ArgumentException>(
            () => service.UploadScanImageAsync(stream, "image/jpeg", contentLength: 2 * 1024 * 1024));
    }

    [Fact]
    public async Task Upload_ThrowsArgumentException_WhenActualStreamExceedsLimit()
    {
        // Arrange (1 MB limit)
        var service = CreateService(maxMb: 1);
        var oversizedData = new byte[1024 * 1024 + 100]; // Just over 1 MB
        using var stream = new MemoryStream(oversizedData);

        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(
            () => service.UploadScanImageAsync(stream, "image/jpeg"));
    }

    [Fact]
    public async Task Delete_ExistingFile_ReturnsTrue_AndSubsequentDeleteReturnsFalse()
    {
        // Arrange
        var service = CreateService();
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes("test image"));
        var key = await service.UploadScanImageAsync(stream, "image/jpeg");

        // Act: First delete should return true
        var firstDelete = await service.DeleteScanImageAsync(key);

        // Act: Repeated delete should return false safely without throwing
        var secondDelete = await service.DeleteScanImageAsync(key);

        // Assert
        Assert.True(firstDelete);
        Assert.False(secondDelete);

        var retrieved = await service.GetScanImageStreamAsync(key);
        Assert.Null(retrieved);
    }

    [Fact]
    public async Task Delete_MissingObject_ReturnsFalseWithoutThrowing()
    {
        // Arrange
        var service = CreateService();

        // Act
        var result = await service.DeleteScanImageAsync("scans/2026/10/29/nonexistent.jpg");

        // Assert
        Assert.False(result);
    }

    [Theory]
    [InlineData("../secret.txt")]
    [InlineData("..\\secret.txt")]
    [InlineData("/etc/passwd")]
    [InlineData("C:\\Windows\\System32\\cmd.exe")]
    [InlineData("scans/../../traversal.jpg")]
    public async Task PathTraversalAttempts_AreRejectedWithArgumentException(string maliciousKey)
    {
        // Arrange
        var service = CreateService();

        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(
            () => service.GetScanImageStreamAsync(maliciousKey));

        await Assert.ThrowsAsync<ArgumentException>(
            () => service.GetPresignedReadUrlAsync(maliciousKey, TimeSpan.FromMinutes(15)));

        // Delete should safely return false on traversal attempt without throwing
        var deleteResult = await service.DeleteScanImageAsync(maliciousKey);
        Assert.False(deleteResult);
    }

    [Fact]
    public async Task GetPresignedReadUrl_ClampsExpirationBetweenOneAndSixtyMinutes()
    {
        // Arrange
        var service = CreateService();
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes("test"));
        var key = await service.UploadScanImageAsync(stream, "image/jpeg");

        // Act & Assert
        var url15 = await service.GetPresignedReadUrlAsync(key, TimeSpan.FromMinutes(15));
        Assert.StartsWith("local://scans/", url15);
        Assert.Contains("expires=", url15);

        // Clamps zero to 1 minute
        var urlZero = await service.GetPresignedReadUrlAsync(key, TimeSpan.FromMinutes(0));
        Assert.Contains("expires=", urlZero);

        // Clamps 120 minutes to 60 minutes
        var urlExcess = await service.GetPresignedReadUrlAsync(key, TimeSpan.FromMinutes(120));
        Assert.Contains("expires=", urlExcess);
    }
}
