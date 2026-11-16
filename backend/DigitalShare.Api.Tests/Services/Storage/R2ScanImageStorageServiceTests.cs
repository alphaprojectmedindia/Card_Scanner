using System.Net;
using System.Text;
using Amazon.S3;
using Amazon.S3.Model;
using DigitalShare.Api.Configuration;
using DigitalShare.Api.Services.Storage;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;

namespace DigitalShare.Api.Tests.Services.Storage;

public class R2ScanImageStorageServiceTests
{
    private readonly Mock<IAmazonS3> _s3Mock;
    private readonly Mock<ILogger<R2ScanImageStorageService>> _loggerMock;
    private readonly R2StorageOptions _validR2Options;

    public R2ScanImageStorageServiceTests()
    {
        _s3Mock = new Mock<IAmazonS3>();
        _loggerMock = new Mock<ILogger<R2ScanImageStorageService>>();

        _validR2Options = new R2StorageOptions
        {
            AccountId = "test-account-id-12345",
            AccessKeyId = "test-access-key-id",
            SecretAccessKey = "test-secret-key-super-confidential",
            BucketName = "digitalshare-scans-dev",
            PresignedExpiryMinutes = 15,
            MaxFileSizeMb = 20
        };
    }

    private R2ScanImageStorageService CreateService(R2StorageOptions? customOptions = null)
    {
        var options = Options.Create(new StorageOptions
        {
            Provider = StorageProvider.R2,
            R2 = customOptions ?? _validR2Options
        });

        return new R2ScanImageStorageService(_s3Mock.Object, options, _loggerMock.Object);
    }

    [Fact]
    public async Task Upload_ConstructsCorrectPutObjectRequest_AndReturnsOpaqueKey()
    {
        // Arrange
        PutObjectRequest? capturedRequest = null;
        _s3Mock.Setup(s => s.PutObjectAsync(It.IsAny<PutObjectRequest>(), It.IsAny<CancellationToken>()))
            .Callback<PutObjectRequest, CancellationToken>((req, _) => capturedRequest = req)
            .ReturnsAsync(new PutObjectResponse());

        var service = CreateService();
        var payload = Encoding.UTF8.GetBytes("JPEG image bytes for business card");
        using var stream = new MemoryStream(payload);

        // Act
        var key = await service.UploadScanImageAsync(stream, "image/jpeg", payload.Length);

        // Assert
        Assert.NotNull(key);
        Assert.StartsWith("scans/", key);
        Assert.EndsWith(".jpg", key);

        Assert.NotNull(capturedRequest);
        Assert.Equal("digitalshare-scans-dev", capturedRequest.BucketName);
        Assert.Equal(key, capturedRequest.Key);
        Assert.Equal("image/jpeg", capturedRequest.ContentType);
        Assert.True(capturedRequest.DisablePayloadSigning);
        Assert.False(capturedRequest.AutoCloseStream);
    }

    [Fact]
    public async Task Upload_ThrowsArgumentException_OnDisallowedContentType()
    {
        // Arrange
        var service = CreateService();
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes("not an image"));

        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(
            () => service.UploadScanImageAsync(stream, "application/zip"));
    }

    [Fact]
    public async Task Upload_ThrowsArgumentException_WhenContentLengthExceedsLimit()
    {
        // Arrange (1 MB limit)
        var options = new R2StorageOptions
        {
            AccountId = "acc",
            AccessKeyId = "key",
            SecretAccessKey = "sec",
            BucketName = "bkt",
            MaxFileSizeMb = 1
        };
        var service = CreateService(options);
        using var stream = new MemoryStream(new byte[100]);

        // Act & Assert (2 MB declared)
        await Assert.ThrowsAsync<ArgumentException>(
            () => service.UploadScanImageAsync(stream, "image/jpeg", contentLength: 2 * 1024 * 1024));
    }

    [Fact]
    public async Task GetStream_ReturnsStream_WhenObjectExists()
    {
        // Arrange
        var expectedBytes = Encoding.UTF8.GetBytes("Card image content");
        var getResponse = new GetObjectResponse
        {
            ResponseStream = new MemoryStream(expectedBytes)
        };

        _s3Mock.Setup(s => s.GetObjectAsync(It.IsAny<GetObjectRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(getResponse);

        var service = CreateService();

        // Act
        using var stream = await service.GetScanImageStreamAsync("scans/2026/10/29/card.jpg");

        // Assert
        Assert.NotNull(stream);
        using var ms = new MemoryStream();
        await stream.CopyToAsync(ms);
        Assert.Equal(expectedBytes, ms.ToArray());
    }

    [Fact]
    public async Task GetStream_ReturnsNull_WhenS3ThrowsNotFoundOrNoSuchKey()
    {
        // Arrange
        var notFoundEx = new AmazonS3Exception("The specified key does not exist.")
        {
            StatusCode = HttpStatusCode.NotFound,
            ErrorCode = "NoSuchKey"
        };

        _s3Mock.Setup(s => s.GetObjectAsync(It.IsAny<GetObjectRequest>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(notFoundEx);

        var service = CreateService();

        // Act
        var result = await service.GetScanImageStreamAsync("scans/2026/10/29/missing.jpg");

        // Assert
        Assert.Null(result);
    }

    [Fact]
    public async Task Delete_ReturnsTrue_OnSuccessfulS3Deletion()
    {
        // Arrange
        _s3Mock.Setup(s => s.DeleteObjectAsync(It.IsAny<DeleteObjectRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new DeleteObjectResponse());

        var service = CreateService();

        // Act
        var result = await service.DeleteScanImageAsync("scans/2026/10/29/existing.jpg");

        // Assert
        Assert.True(result);
    }

    [Fact]
    public async Task Delete_ReturnsFalseSafely_WhenObjectNotFound()
    {
        // Arrange
        var notFoundEx = new AmazonS3Exception("Not Found")
        {
            StatusCode = HttpStatusCode.NotFound,
            ErrorCode = "NoSuchKey"
        };

        _s3Mock.Setup(s => s.DeleteObjectAsync(It.IsAny<DeleteObjectRequest>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(notFoundEx);

        var service = CreateService();

        // Act
        var result = await service.DeleteScanImageAsync("scans/2026/10/29/missing.jpg");

        // Assert
        Assert.False(result);
    }

    [Fact]
    public async Task GetPresignedReadUrl_ClampsExpiryAndConstructsRequest()
    {
        // Arrange
        GetPreSignedUrlRequest? capturedRequest = null;
        _s3Mock.Setup(s => s.GetPreSignedURL(It.IsAny<GetPreSignedUrlRequest>()))
            .Callback<GetPreSignedUrlRequest>(req => capturedRequest = req)
            .Returns("https://test-account.r2.cloudflarestorage.com/presigned-token");

        var service = CreateService();

        // Act
        var url = await service.GetPresignedReadUrlAsync("scans/2026/10/29/sample.jpg", TimeSpan.FromMinutes(25));

        // Assert
        Assert.Equal("https://test-account.r2.cloudflarestorage.com/presigned-token", url);
        Assert.NotNull(capturedRequest);
        Assert.Equal("digitalshare-scans-dev", capturedRequest.BucketName);
        Assert.Equal("scans/2026/10/29/sample.jpg", capturedRequest.Key);
        Assert.Equal(HttpVerb.GET, capturedRequest.Verb);

        // Verification of expiry: within expected 25 minutes range
        Assert.True(capturedRequest.Expires > DateTime.UtcNow.AddMinutes(20));
        Assert.True(capturedRequest.Expires <= DateTime.UtcNow.AddMinutes(26));
    }

    [Fact]
    public void ConfigurationValidation_ThrowsInvalidOperationException_OnMissingSettings()
    {
        // Missing bucket
        var noBucket = new R2StorageOptions
        {
            AccountId = "acc",
            AccessKeyId = "key",
            SecretAccessKey = "sec"
        };
        Assert.Throws<InvalidOperationException>(() => noBucket.Validate());

        // Missing AccessKey
        var noAccessKey = new R2StorageOptions
        {
            BucketName = "bkt",
            AccountId = "acc",
            SecretAccessKey = "sec"
        };
        Assert.Throws<InvalidOperationException>(() => noAccessKey.Validate());

        // Missing SecretKey
        var noSecret = new R2StorageOptions
        {
            BucketName = "bkt",
            AccountId = "acc",
            AccessKeyId = "key"
        };
        Assert.Throws<InvalidOperationException>(() => noSecret.Validate());

        // Missing AccountId and ServiceUrl
        var noEndpoint = new R2StorageOptions
        {
            BucketName = "bkt",
            AccessKeyId = "key",
            SecretAccessKey = "sec"
        };
        Assert.Throws<InvalidOperationException>(() => noEndpoint.Validate());
    }

    [Fact]
    public void ResolveServiceUrl_UsesServiceUrlIfProvided_OrComputesFromAccountId()
    {
        var explicitUrl = new R2StorageOptions
        {
            ServiceUrl = "https://custom.endpoint.com"
        };
        Assert.Equal("https://custom.endpoint.com", explicitUrl.ResolveServiceUrl());

        var derivedUrl = new R2StorageOptions
        {
            AccountId = "my-account-999"
        };
        Assert.Equal("https://my-account-999.r2.cloudflarestorage.com", derivedUrl.ResolveServiceUrl());
    }
}
