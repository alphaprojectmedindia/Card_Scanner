using DigitalShare.Api.Configuration;
using Microsoft.Extensions.Options;

namespace DigitalShare.Api.Services.Storage;

/// <summary>
/// Local filesystem implementation of <see cref="IScanImageStorageService"/> for development and testing.
/// Stores temporary scan images in a private directory outside publicly served web roots.
/// </summary>
public class LocalStorageScanImageStorageService : IScanImageStorageService
{
    private readonly string _storageDirectory;
    private readonly long _maxSizeBytes;
    private readonly ILogger<LocalStorageScanImageStorageService> _logger;

    private static readonly HashSet<string> AllowedContentTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/webp"
    };

    public LocalStorageScanImageStorageService(
        IWebHostEnvironment environment,
        IOptions<StorageOptions> options,
        ILogger<LocalStorageScanImageStorageService> logger)
    {
        _logger = logger;
        var localOptions = options.Value.Local;

        var configuredDir = string.IsNullOrWhiteSpace(localOptions.Directory)
            ? "uploads/temp-scans"
            : localOptions.Directory;

        _storageDirectory = Path.IsPathRooted(configuredDir)
            ? Path.GetFullPath(configuredDir)
            : Path.GetFullPath(Path.Combine(environment.ContentRootPath, configuredDir));

        _maxSizeBytes = (localOptions.MaxFileSizeMb <= 0 ? 20 : localOptions.MaxFileSizeMb) * 1024L * 1024L;

        if (!Directory.Exists(_storageDirectory))
        {
            Directory.CreateDirectory(_storageDirectory);
        }
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

        var targetPath = ResolveAndValidatePath(storageKey);
        var targetDir = Path.GetDirectoryName(targetPath);
        if (!string.IsNullOrEmpty(targetDir) && !Directory.Exists(targetDir))
        {
            Directory.CreateDirectory(targetDir);
        }

        long totalBytesWritten = 0;
        try
        {
            await using (var outputStream = new FileStream(targetPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, useAsync: true))
            {
                var buffer = new byte[81920];
                int bytesRead;
                while ((bytesRead = await stream.ReadAsync(buffer, ct)) > 0)
                {
                    totalBytesWritten += bytesRead;
                    if (totalBytesWritten > _maxSizeBytes)
                    {
                        throw new ArgumentException(
                            $"Uploaded stream exceeded maximum allowed size ({_maxSizeBytes} bytes).");
                    }

                    await outputStream.WriteAsync(buffer.AsMemory(0, bytesRead), ct);
                }
            }

            _logger.LogInformation(
                "Stored temporary scan image locally at key {StorageKey} ({Bytes} bytes)",
                storageKey, totalBytesWritten);

            return storageKey;
        }
        catch
        {
            // Clean up partial file on failure
            if (File.Exists(targetPath))
            {
                try { File.Delete(targetPath); } catch { /* ignore */ }
            }
            throw;
        }
    }

    public Task<Stream?> GetScanImageStreamAsync(string storageKey, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(storageKey))
        {
            return Task.FromResult<Stream?>(null);
        }

        var filePath = ResolveAndValidatePath(storageKey);
        if (!File.Exists(filePath))
        {
            return Task.FromResult<Stream?>(null);
        }

        var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, useAsync: true);
        return Task.FromResult<Stream?>(stream);
    }

    public Task<bool> DeleteScanImageAsync(string storageKey, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(storageKey))
        {
            return Task.FromResult(false);
        }

        try
        {
            var filePath = ResolveAndValidatePath(storageKey);
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
                _logger.LogInformation("Deleted temporary scan image at key {StorageKey}", storageKey);
                return Task.FromResult(true);
            }
        }
        catch (ArgumentException)
        {
            // Invalid key format or traversal attempt - safe false return
            return Task.FromResult(false);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to delete local temporary scan image at key {StorageKey}", storageKey);
        }

        return Task.FromResult(false);
    }

    public Task<string> GetPresignedReadUrlAsync(string storageKey, TimeSpan expiry)
    {
        if (string.IsNullOrWhiteSpace(storageKey))
        {
            throw new ArgumentException("Storage key cannot be empty.", nameof(storageKey));
        }

        // Validate key to prevent traversal
        ResolveAndValidatePath(storageKey);

        var clampedExpiryMinutes = Math.Clamp((int)expiry.TotalMinutes, 1, 60);
        var expiresUnix = DateTimeOffset.UtcNow.AddMinutes(clampedExpiryMinutes).ToUnixTimeSeconds();
        return Task.FromResult($"local://{storageKey}?expires={expiresUnix}");
    }

    private string ResolveAndValidatePath(string storageKey)
    {
        if (string.IsNullOrWhiteSpace(storageKey))
        {
            throw new ArgumentException("Storage key cannot be empty.", nameof(storageKey));
        }

        // Prevent path traversal patterns
        if (storageKey.Contains("..") || storageKey.Contains(':') || storageKey.StartsWith('/') || storageKey.StartsWith('\\'))
        {
            throw new ArgumentException("Invalid storage key: path traversal sequences are not allowed.", nameof(storageKey));
        }

        var normalizedKey = storageKey.Replace('/', Path.DirectorySeparatorChar).Replace('\\', Path.DirectorySeparatorChar);
        var fullPath = Path.GetFullPath(Path.Combine(_storageDirectory, normalizedKey));

        // Ensure target is strictly within _storageDirectory
        var normalizedBase = _storageDirectory.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!fullPath.StartsWith(normalizedBase, StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("Access denied: storage key resolves outside designated storage directory.", nameof(storageKey));
        }

        return fullPath;
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
