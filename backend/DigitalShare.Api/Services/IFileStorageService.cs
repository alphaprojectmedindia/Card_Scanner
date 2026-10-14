namespace DigitalShare.Api.Services;

/// <summary>
/// Storage abstraction for storing profile photos and media.
/// Can be implemented by local file storage in development or cloud/object storage in production.
/// </summary>
public interface IFileStorageService
{
    /// <summary>
    /// Saves a profile photo stream and returns the accessible relative/public URL.
    /// </summary>
    Task<string> SaveProfilePhotoAsync(Stream fileStream, string originalFileName, string contentType);

    /// <summary>
    /// Deletes a previously stored profile photo by its relative/public URL.
    /// </summary>
    Task<bool> DeleteProfilePhotoAsync(string relativeUrl);
}
