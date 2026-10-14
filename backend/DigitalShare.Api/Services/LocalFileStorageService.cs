namespace DigitalShare.Api.Services;

/// <summary>
/// Development local file storage implementation.
/// Stores uploaded profile photos on the server file system and returns relative web paths.
/// </summary>
public class LocalFileStorageService : IFileStorageService
{
    private readonly IWebHostEnvironment _environment;
    private readonly ILogger<LocalFileStorageService> _logger;
    private readonly string _storageDirectory;

    public const string UrlPrefix = "/uploads/profile-photos";

    public LocalFileStorageService(IWebHostEnvironment environment, ILogger<LocalFileStorageService> logger)
    {
        _environment = environment;
        _logger = logger;
        _storageDirectory = Path.Combine(_environment.ContentRootPath, "uploads", "profile-photos");

        if (!Directory.Exists(_storageDirectory))
        {
            Directory.CreateDirectory(_storageDirectory);
        }
    }

    public async Task<string> SaveProfilePhotoAsync(Stream fileStream, string originalFileName, string contentType)
    {
        var extension = GetSafeExtension(originalFileName, contentType);
        var safeFileName = $"{Guid.NewGuid():N}{extension}";
        var targetFilePath = Path.Combine(_storageDirectory, safeFileName);

        using (var outputStream = new FileStream(targetFilePath, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            await fileStream.CopyToAsync(outputStream);
        }

        _logger.LogInformation("Saved profile photo to {FilePath}", targetFilePath);
        return $"{UrlPrefix}/{safeFileName}";
    }

    public Task<bool> DeleteProfilePhotoAsync(string relativeUrl)
    {
        if (string.IsNullOrWhiteSpace(relativeUrl))
        {
            return Task.FromResult(false);
        }

        try
        {
            // Sanitize filename to prevent directory traversal
            var fileName = Path.GetFileName(relativeUrl);
            var filePath = Path.Combine(_storageDirectory, fileName);

            if (File.Exists(filePath))
            {
                File.Delete(filePath);
                _logger.LogInformation("Deleted old profile photo at {FilePath}", filePath);
                return Task.FromResult(true);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to delete profile photo for URL {RelativeUrl}", relativeUrl);
        }

        return Task.FromResult(false);
    }

    private static string GetSafeExtension(string originalFileName, string contentType)
    {
        var ext = Path.GetExtension(originalFileName)?.ToLowerInvariant();
        if (ext is ".jpg" or ".jpeg" or ".png" or ".webp" or ".gif")
        {
            return ext == ".jpeg" ? ".jpg" : ext;
        }

        return contentType.ToLowerInvariant() switch
        {
            "image/jpeg" => ".jpg",
            "image/jpg" => ".jpg",
            "image/png" => ".png",
            "image/webp" => ".webp",
            "image/gif" => ".gif",
            _ => ".jpg"
        };
    }
}
