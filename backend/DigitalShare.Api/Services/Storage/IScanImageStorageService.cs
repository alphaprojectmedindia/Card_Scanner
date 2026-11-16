namespace DigitalShare.Api.Services.Storage;

/// <summary>
/// Storage abstraction for temporary business-card scan images.
/// Supports local filesystem storage for testing/development and Cloudflare R2 for cloud storage.
/// </summary>
public interface IScanImageStorageService
{
    /// <summary>
    /// Uploads a temporary scan image stream to storage and returns an opaque server-generated storage key.
    /// Does not trust client-supplied filenames or paths.
    /// </summary>
    /// <param name="stream">The image data stream.</param>
    /// <param name="contentType">The MIME content type (e.g., image/jpeg, image/png, image/webp).</param>
    /// <param name="contentLength">Optional declared length of the stream in bytes.</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>An opaque storage key referencing the stored object.</returns>
    Task<string> UploadScanImageAsync(
        Stream stream,
        string contentType,
        long? contentLength = null,
        CancellationToken ct = default);

    /// <summary>
    /// Retrieves a readable stream for a previously stored scan image.
    /// Returns null if the object does not exist.
    /// </summary>
    /// <param name="storageKey">The opaque storage key.</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>A readable Stream of image data, or null if not found.</returns>
    Task<Stream?> GetScanImageStreamAsync(
        string storageKey,
        CancellationToken ct = default);

    /// <summary>
    /// Safely and idempotently deletes a stored scan image.
    /// Does not throw if the file or object does not exist.
    /// </summary>
    /// <param name="storageKey">The opaque storage key.</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>True if the object was deleted; false if it did not exist.</returns>
    Task<bool> DeleteScanImageAsync(
        string storageKey,
        CancellationToken ct = default);

    /// <summary>
    /// Generates a short-lived presigned read URL with bounded expiration.
    /// </summary>
    /// <param name="storageKey">The opaque storage key.</param>
    /// <param name="expiry">Requested duration of the presigned URL (clamped between 1 and 60 minutes).</param>
    /// <returns>A presigned HTTPS read URL.</returns>
    Task<string> GetPresignedReadUrlAsync(
        string storageKey,
        TimeSpan expiry);
}
