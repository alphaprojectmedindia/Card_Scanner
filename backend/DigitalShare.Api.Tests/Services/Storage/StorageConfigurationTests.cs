using Amazon.S3;
using DigitalShare.Api.Configuration;
using DigitalShare.Api.Services.Storage;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Moq;

namespace DigitalShare.Api.Tests.Services.Storage;

public class StorageConfigurationTests
{
    private readonly Mock<IWebHostEnvironment> _envMock;

    public StorageConfigurationTests()
    {
        _envMock = new Mock<IWebHostEnvironment>();
        _envMock.Setup(e => e.ContentRootPath).Returns(Path.GetTempPath());
    }

    [Fact]
    public void DI_ResolvesLocalStorageService_WhenProviderIsLocal()
    {
        // Arrange
        var inMemorySettings = new Dictionary<string, string?>
        {
            ["Storage:Provider"] = "Local",
            ["Storage:Local:Directory"] = "uploads/temp-scans"
        };

        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(inMemorySettings)
            .Build();

        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton(_envMock.Object);
        services.Configure<StorageOptions>(configuration.GetSection(StorageOptions.SectionName));

        var storageOptions = configuration.GetSection(StorageOptions.SectionName).Get<StorageOptions>() ?? new StorageOptions();

        if (storageOptions.Provider == StorageProvider.Local)
        {
            services.AddSingleton<IScanImageStorageService, LocalStorageScanImageStorageService>();
        }

        var provider = services.BuildServiceProvider();

        // Act
        var service = provider.GetService<IScanImageStorageService>();

        // Assert
        Assert.NotNull(service);
        Assert.IsType<LocalStorageScanImageStorageService>(service);
    }

    [Fact]
    public void DI_ResolvesR2StorageService_WhenProviderIsR2AndValid()
    {
        // Arrange
        var inMemorySettings = new Dictionary<string, string?>
        {
            ["Storage:Provider"] = "R2",
            ["Storage:R2:AccountId"] = "account-123",
            ["Storage:R2:AccessKeyId"] = "access-key-abc",
            ["Storage:R2:SecretAccessKey"] = "secret-key-xyz",
            ["Storage:R2:BucketName"] = "digitalshare-scans-dev"
        };

        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(inMemorySettings)
            .Build();

        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton(_envMock.Object);
        services.AddSingleton(new Mock<IAmazonS3>().Object);
        services.Configure<StorageOptions>(configuration.GetSection(StorageOptions.SectionName));

        var storageOptions = configuration.GetSection(StorageOptions.SectionName).Get<StorageOptions>() ?? new StorageOptions();

        if (storageOptions.Provider == StorageProvider.R2)
        {
            storageOptions.R2.Validate();
            services.AddSingleton<IScanImageStorageService, R2ScanImageStorageService>();
        }

        var provider = services.BuildServiceProvider();

        // Act
        var service = provider.GetService<IScanImageStorageService>();

        // Assert
        Assert.NotNull(service);
        Assert.IsType<R2ScanImageStorageService>(service);
    }

    [Fact]
    public void DI_ThrowsInvalidOperationException_WhenProviderIsR2AndCredentialsMissing()
    {
        // Arrange (R2 chosen but no credentials)
        var inMemorySettings = new Dictionary<string, string?>
        {
            ["Storage:Provider"] = "R2",
            ["Storage:R2:BucketName"] = "digitalshare-scans-dev"
        };

        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(inMemorySettings)
            .Build();

        var storageOptions = configuration.GetSection(StorageOptions.SectionName).Get<StorageOptions>() ?? new StorageOptions();

        // Act & Assert
        Assert.Equal(StorageProvider.R2, storageOptions.Provider);
        var ex = Assert.Throws<InvalidOperationException>(() => storageOptions.R2.Validate());
        Assert.Contains("Storage:R2:AccessKeyId", ex.Message);
    }

    [Fact]
    public void Production_ThrowsInvalidOperationException_WhenR2Misconfigured_NeverSilentFallback()
    {
        // Arrange
        var inMemorySettings = new Dictionary<string, string?>
        {
            ["Storage:Provider"] = "R2"
            // Missing all R2 keys
        };

        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(inMemorySettings)
            .Build();

        var isProduction = true;
        var storageOptions = configuration.GetSection(StorageOptions.SectionName).Get<StorageOptions>() ?? new StorageOptions();

        // Act & Assert
        Assert.Throws<InvalidOperationException>(() =>
        {
            if (storageOptions.Provider == StorageProvider.R2)
            {
                storageOptions.R2.Validate();
            }
            else if (isProduction && string.Equals(configuration["Storage:Provider"], "R2", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("Production configuration error: Storage:Provider was set to R2 but R2 credentials or configuration failed validation.");
            }
        });
    }

    [Fact]
    public void ValidationException_DoesNotExposeSecretAccessKeyInMessage()
    {
        // Arrange
        var options = new R2StorageOptions
        {
            SecretAccessKey = "SUPER_SECRET_VALUE_12345"
            // Missing other required fields
        };

        // Act
        var ex = Assert.Throws<InvalidOperationException>(() => options.Validate());

        // Assert
        Assert.DoesNotContain("SUPER_SECRET_VALUE_12345", ex.Message);
    }
}
