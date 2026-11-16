namespace DigitalShare.Api.Configuration;

public class StorageOptions
{
    public const string SectionName = "Storage";

    public StorageProvider Provider { get; set; } = StorageProvider.Local;

    public LocalStorageOptions Local { get; set; } = new();

    public R2StorageOptions R2 { get; set; } = new();
}

public enum StorageProvider
{
    Local,
    R2
}

public class LocalStorageOptions
{
    public string Directory { get; set; } = "uploads/temp-scans";

    public int MaxFileSizeMb { get; set; } = 20;
}

public class R2StorageOptions
{
    public string? AccountId { get; set; }

    public string? AccessKeyId { get; set; }

    public string? SecretAccessKey { get; set; }

    public string? BucketName { get; set; }

    public string? ServiceUrl { get; set; }

    public int PresignedExpiryMinutes { get; set; } = 15;

    public int MaxFileSizeMb { get; set; } = 20;

    /// <summary>
    /// Validates that all required parameters for Cloudflare R2 are present.
    /// </summary>
    public void Validate()
    {
        if (string.IsNullOrWhiteSpace(BucketName))
        {
            throw new InvalidOperationException("R2 Storage configuration error: 'Storage:R2:BucketName' must be provided.");
        }

        if (string.IsNullOrWhiteSpace(AccessKeyId))
        {
            throw new InvalidOperationException("R2 Storage configuration error: 'Storage:R2:AccessKeyId' must be provided.");
        }

        if (string.IsNullOrWhiteSpace(SecretAccessKey))
        {
            throw new InvalidOperationException("R2 Storage configuration error: 'Storage:R2:SecretAccessKey' must be provided.");
        }

        if (string.IsNullOrWhiteSpace(ServiceUrl) && string.IsNullOrWhiteSpace(AccountId))
        {
            throw new InvalidOperationException("R2 Storage configuration error: Either 'Storage:R2:ServiceUrl' or 'Storage:R2:AccountId' must be provided.");
        }
    }

    /// <summary>
    /// Computes the Cloudflare R2 S3-compatible service URL.
    /// </summary>
    public string ResolveServiceUrl()
    {
        if (!string.IsNullOrWhiteSpace(ServiceUrl))
        {
            return ServiceUrl.Trim();
        }

        return $"https://{AccountId!.Trim()}.r2.cloudflarestorage.com";
    }
}
