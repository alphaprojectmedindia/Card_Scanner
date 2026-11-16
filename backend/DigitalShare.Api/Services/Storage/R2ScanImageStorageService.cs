using System.Net;
using Amazon.S3;
using Amazon.S3.Model;
using DigitalShare.Api.Configuration;
using Microsoft.Extensions.Options;

namespace DigitalShare.Api.Services.Storage;

/// <summary>
/// Cloudflare R2 implementation of <see cref="IScanImageStorageService"/> using the Amazon S3-compatible SDK.
/// Provides secure, private, stream-based object storage for temporary business-card scan images.
/// </summary>
public class R2ScanImageStorageService : IScanImageStorageService
{
    private readonly IAmazonS3 _s3Client;
    private readonly R2StorageOptions _options;
    private readonly long _maxSizeBytes;
    private readonly ILogger<R2ScanImageStorageService> _logger;

    private static readonly HashSet<string> AllowedContentTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/webp"
    };

    public R2ScanImageStorageService(
        IAmazonS3 s3Client,
        IOptions<StorageOptions> options,
        ILogger<R2ScanImageStorageService> logger)
    {
        _s3Client = s3Client ?? throw new ArgumentNullException(nameof(s3Client));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));

        ArgumentNullException.ThrowIfNull(options);
        _options = options.Value.R2 ?? throw new ArgumentException("R2 storage options must be configured.", nameof(options));
        _options.Validate();

        _maxSizeBytes = (_options.MaxFileSizeMb <= 0 ? 20 : _options.MaxFileSizeMb) * 1024L * 1024L;
    }

    public async Task<string> UploadScanImageAsync(
        Stream stream,
        string contentType,
        long? contentLength = null,
        CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(stream);

        if (string.IsNullOrWhiteSpace(contentType) || !AllowedContentTypes.Contains(contentType))
        {
            throw new ArgumentException(
                $"Unsupported or missing content type '{contentType}'. Allowed types: image/jpeg, image/png, image/webp.",
                nameof(contentType));
        }

        if (contentLength.HasValue && contentLength.Value > _maxSizeBytes)
        {
            throw new ArgumentException(
                $"Content length ({contentLength.Value} bytes) exceeds maximum allowed size ({_maxSizeBytes} bytes).",
                nameof(contentLength));
        }

        var extension = GetExtensionForContentType(contentType);
        var datePrefix = DateTime.UtcNow.ToString("yyyy/MM/dd");
        var fileId = Guid.NewGuid().ToString("N");
        var storageKey = $"scans/{datePrefix}/{fileId}{extension}";

        var putRequest = new PutObjectRequest
        {
            BucketName = _options.BucketName,
            Key = storageKey,
            InputStream = stream,
            ContentType = contentType,
            AutoCloseStream = false,
            DisablePayloadSigning = true
        };

        try
        {
            await _s3Client.PutObjectAsync(putRequest, ct);

            _logger.LogInformation(
                "Uploaded temporary scan image to R2 bucket '{Bucket}' with key '{StorageKey}'",
                _options.BucketName, storageKey);

            return storageKey;
        }
        catch (AmazonS3Exception ex)
        {
            _logger.LogError(
                "Failed to upload scan image to R2. Bucket: '{Bucket}', StatusCode: {StatusCode}, ErrorCode: {ErrorCode}",
                _options.BucketName, ex.StatusCode, ex.ErrorCode);
            throw new InvalidOperationException($"Cloudflare R2 storage upload failed: {ex.Message}", ex);
        }
    }

    public async Task<Stream?> GetScanImageStreamAsync(string storageKey, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(storageKey))
        {
            return null;
        }

        var getRequest = new GetObjectRequest
        {
            BucketName = _options.BucketName,
            Key = storageKey
        };

        try
        {
            var response = await _s3Client.GetObjectAsync(getRequest, ct);
            return response.ResponseStream;
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == HttpStatusCode.NotFound || ex.ErrorCode == "NoSuchKey")
        {
            _logger.LogDebug("R2 object with key '{StorageKey}' not found in bucket '{Bucket}'", storageKey, _options.BucketName);
            return null;
        }
        catch (AmazonS3Exception ex)
        {
            _logger.LogError(
                "Failed to retrieve scan image from R2. Bucket: '{Bucket}', Key: '{StorageKey}', StatusCode: {StatusCode}",
                _options.BucketName, storageKey, ex.StatusCode);
            throw new InvalidOperationException($"Cloudflare R2 storage retrieval failed: {ex.Message}", ex);
        }
    }

    public async Task<bool> DeleteScanImageAsync(string storageKey, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(storageKey))
        {
            return false;
        }

        var deleteRequest = new DeleteObjectRequest
        {
            BucketName = _options.BucketName,
            Key = storageKey
        };

        try
        {
            await _s3Client.DeleteObjectAsync(deleteRequest, ct);
            _logger.LogInformation("Deleted temporary scan image from R2 with key '{StorageKey}'", storageKey);
            return true;
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == HttpStatusCode.NotFound || ex.ErrorCode == "NoSuchKey")
        {
            _logger.LogDebug("R2 object with key '{StorageKey}' not found during deletion", storageKey);
            return false;
        }
        catch (AmazonS3Exception ex)
        {
            _logger.LogWarning(
                ex, "Failed to delete scan image from R2. Bucket: '{Bucket}', Key: '{StorageKey}', StatusCode: {StatusCode}",
                _options.BucketName, storageKey, ex.StatusCode);
            return false;
        }
    }

    public Task<string> GetPresignedReadUrlAsync(string storageKey, TimeSpan expiry)
    {
        if (string.IsNullOrWhiteSpace(storageKey))
        {
            throw new ArgumentException("Storage key cannot be empty.", nameof(storageKey));
        }

        var clampedMinutes = Math.Clamp((int)expiry.TotalMinutes, 1, 60);

        var preSignedRequest = new GetPreSignedUrlRequest
        {
            BucketName = _options.BucketName,
            Key = storageKey,
            Expires = DateTime.UtcNow.AddMinutes(clampedMinutes),
            Verb = HttpVerb.GET
        };

        var presignedUrl = _s3Client.GetPreSignedURL(preSignedRequest);
        return Task.FromResult(presignedUrl);
    }

    private static string GetExtensionForContentType(string contentType)
    {
        return contentType.ToLowerInvariant() switch
        {
            "image/jpeg" or "image/jpg" => ".jpg",
            "image/png" => ".png",
            "image/webp" => ".webp",
            _ => ".jpg"
        };
    }
}
