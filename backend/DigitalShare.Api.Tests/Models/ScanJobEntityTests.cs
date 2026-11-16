using DigitalShare.Api.Data;
using DigitalShare.Api.Models;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace DigitalShare.Api.Tests.Models;

public class ScanJobEntityTests
{
    [Fact]
    public void ScanJob_DefaultPropertyValues_AreValid()
    {
        var job = new ScanJob
        {
            UserId = "user-123",
            ClientJobId = "job-abc",
            FrontImageStorageKey = "uploads/temp-scans/front.jpg"
        };

        Assert.NotEqual(Guid.Empty, job.Id);
        Assert.Equal(ScanJobStatus.Queued, job.Status);
        Assert.Equal(0, job.RetryCount);
        Assert.Null(job.BackImageStorageKey);
        Assert.Null(job.ImageSha256Checksum);
        Assert.Null(job.LocalOcrDraftJson);
        Assert.Null(job.ReconciledResultJson);
        Assert.Null(job.ErrorMessage);
        Assert.Null(job.WorkerInstanceId);
        Assert.Null(job.LockedUntilUtc);
        Assert.True(job.CreatedAtUtc <= DateTime.UtcNow);
        Assert.True(job.UpdatedAtUtc <= DateTime.UtcNow);
        Assert.True(job.ExpiresAtUtc > DateTime.UtcNow);
    }

    [Fact]
    public void ScanJobStatus_ContainsAllExpectedStates()
    {
        Assert.True(Enum.IsDefined(typeof(ScanJobStatus), ScanJobStatus.Queued));
        Assert.True(Enum.IsDefined(typeof(ScanJobStatus), ScanJobStatus.Processing));
        Assert.True(Enum.IsDefined(typeof(ScanJobStatus), ScanJobStatus.Completed));
        Assert.True(Enum.IsDefined(typeof(ScanJobStatus), ScanJobStatus.Failed));
        Assert.True(Enum.IsDefined(typeof(ScanJobStatus), ScanJobStatus.Cancelled));
    }

    [Fact]
    public void ApplicationDbContext_ScanJobMetadata_IsConfiguredCorrectly()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(databaseName: "ScanJobMetadataDb_" + Guid.NewGuid())
            .Options;

        using var dbContext = new ApplicationDbContext(options);
        var entityType = dbContext.Model.FindEntityType(typeof(ScanJob));

        Assert.NotNull(entityType);
        Assert.Equal("ScanJobs", entityType.GetTableName());

        // Key
        var primaryKey = entityType.FindPrimaryKey();
        Assert.NotNull(primaryKey);
        Assert.Single(primaryKey.Properties);
        Assert.Equal("Id", primaryKey.Properties[0].Name);

        // Required and MaxLengths
        var clientJobIdProp = entityType.FindProperty(nameof(ScanJob.ClientJobId));
        Assert.NotNull(clientJobIdProp);
        Assert.False(clientJobIdProp.IsNullable);
        Assert.Equal(64, clientJobIdProp.GetMaxLength());

        var frontKeyProp = entityType.FindProperty(nameof(ScanJob.FrontImageStorageKey));
        Assert.NotNull(frontKeyProp);
        Assert.False(frontKeyProp.IsNullable);
        Assert.Equal(500, frontKeyProp.GetMaxLength());

        var backKeyProp = entityType.FindProperty(nameof(ScanJob.BackImageStorageKey));
        Assert.NotNull(backKeyProp);
        Assert.True(backKeyProp.IsNullable);
        Assert.Equal(500, backKeyProp.GetMaxLength());

        var checksumProp = entityType.FindProperty(nameof(ScanJob.ImageSha256Checksum));
        Assert.NotNull(checksumProp);
        Assert.True(checksumProp.IsNullable);
        Assert.Equal(64, checksumProp.GetMaxLength());

        var statusProp = entityType.FindProperty(nameof(ScanJob.Status));
        Assert.NotNull(statusProp);
        Assert.Equal(20, statusProp.GetMaxLength());

        // Indexes
        var indexes = entityType.GetIndexes().ToList();
        Assert.Contains(indexes, i => i.Properties.Select(p => p.Name).SequenceEqual(new[] { "UserId", "ClientJobId" }) && i.IsUnique);
        Assert.Contains(indexes, i => i.Properties.Select(p => p.Name).SequenceEqual(new[] { "UserId", "Status" }));
        Assert.Contains(indexes, i => i.Properties.Select(p => p.Name).SequenceEqual(new[] { "ExpiresAtUtc" }));
        Assert.Contains(indexes, i => i.Properties.Select(p => p.Name).SequenceEqual(new[] { "Status", "LockedUntilUtc" }));
    }

    [Fact]
    public void ApplicationDbContext_ImportedBusinessCardMetadata_ContainsIdempotencyColumnsAndIndex()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(databaseName: "ImportedCardMetadataDb_" + Guid.NewGuid())
            .Options;

        using var dbContext = new ApplicationDbContext(options);
        var entityType = dbContext.Model.FindEntityType(typeof(ImportedBusinessCard));

        Assert.NotNull(entityType);

        var clientRequestIdProp = entityType.FindProperty(nameof(ImportedBusinessCard.ClientRequestId));
        Assert.NotNull(clientRequestIdProp);
        Assert.True(clientRequestIdProp.IsNullable);
        Assert.Equal(64, clientRequestIdProp.GetMaxLength());

        var hashProp = entityType.FindProperty(nameof(ImportedBusinessCard.RequestPayloadHash));
        Assert.NotNull(hashProp);
        Assert.True(hashProp.IsNullable);
        Assert.Equal(64, hashProp.GetMaxLength());

        var uniqueIndex = entityType.GetIndexes().FirstOrDefault(i =>
            i.Properties.Select(p => p.Name).SequenceEqual(new[] { "OwnerUserId", "ClientRequestId" }));

        Assert.NotNull(uniqueIndex);
        Assert.True(uniqueIndex.IsUnique);
        Assert.Equal("\"ClientRequestId\" IS NOT NULL", uniqueIndex.GetFilter());
    }
}
