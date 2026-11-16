using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.CardAnalysis;
using DigitalShare.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace DigitalShare.Api.Services.Gemini;

public enum LeaseAcquisitionResult
{
    AcquiredNew,
    AcquiredAbandoned,
    AlreadyCompleted,
    LockedByAnotherWorker
}

public class CardAnalysisIdempotencyManager
{
    private readonly ApplicationDbContext _dbContext;
    private readonly ILogger<CardAnalysisIdempotencyManager> _logger;
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public CardAnalysisIdempotencyManager(
        ApplicationDbContext dbContext,
        ILogger<CardAnalysisIdempotencyManager> logger)
    {
        _dbContext = dbContext;
        _logger = logger;
    }

    /// <summary>
    /// Computes a deterministic canonical cache key spanning user, scan content, mode, model, and schema.
    /// Invalidation occurs automatically if the model ID, schema version, or OCR observations change.
    /// </summary>
    public string ComputeAnalysisCacheKey(
        string userId,
        AnalyzeBusinessCardRequest request,
        string modelId,
        string schemaVersion = "v1")
    {
        using var sha256 = SHA256.Create();
        var sb = new StringBuilder();

        sb.Append(userId.Trim()).Append('|');
        sb.Append(request.ScanContentHash.Trim()).Append('|');
        sb.Append(request.AnalysisMode.Trim().ToLowerInvariant()).Append('|');
        sb.Append(modelId.Trim().ToLowerInvariant()).Append('|');
        sb.Append(schemaVersion.Trim()).Append('|');
        sb.Append(request.PipelineVersion.Trim()).Append('|');
        sb.Append(request.ParserVersion.Trim()).Append('|');
        sb.Append(request.OcrModelVersion.Trim()).Append('|');
        sb.Append(request.GeminiPromptVersion.Trim()).Append('|');

        if (!string.IsNullOrWhiteSpace(request.FrontImageStorageKey))
        {
            sb.Append(request.FrontImageStorageKey.Trim()).Append('|');
        }

        if (!string.IsNullOrWhiteSpace(request.BackImageStorageKey))
        {
            sb.Append(request.BackImageStorageKey.Trim()).Append('|');
        }

        if (!string.IsNullOrWhiteSpace(request.FrontImageSha256))
        {
            sb.Append(request.FrontImageSha256.Trim()).Append('|');
        }

        if (!string.IsNullOrWhiteSpace(request.BackImageSha256))
        {
            sb.Append(request.BackImageSha256.Trim()).Append('|');
        }

        // Sort observations deterministically by ID to ensure stable hash
        var sortedObs = request.OcrObservations
            .OrderBy(o => o.Id, StringComparer.Ordinal)
            .ToList();

        foreach (var obs in sortedObs)
        {
            sb.Append(obs.Id).Append(':').Append(obs.Text.Trim()).Append(';');
        }

        var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(sb.ToString()));
        return Convert.ToHexString(hashBytes).ToLowerInvariant()[..32];
    }

    /// <summary>
    /// Retrieves a completed analysis result from the persistent ScanJobs cache if valid and unexpired.
    /// </summary>
    public async Task<AnalyzeBusinessCardResponse?> TryGetCompletedResultAsync(
        string userId,
        string cacheKey,
        CancellationToken ct = default)
    {
        var existingJob = await _dbContext.ScanJobs
            .AsNoTracking()
            .FirstOrDefaultAsync(j => j.UserId == userId && j.ClientJobId == cacheKey, ct);

        if (existingJob != null &&
            existingJob.Status == ScanJobStatus.Completed &&
            existingJob.ExpiresAtUtc > DateTime.UtcNow &&
            !string.IsNullOrWhiteSpace(existingJob.ReconciledResultJson))
        {
            try
            {
                var cached = JsonSerializer.Deserialize<AnalyzeBusinessCardResponse>(
                    existingJob.ReconciledResultJson, JsonOptions);

                if (cached != null)
                {
                    cached.FromCache = true;
                    _logger.LogInformation(
                        "Cache HIT for user {UserId} with cacheKey {CacheKey}. Returning stored analysis.",
                        userId, cacheKey);
                    return cached;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to deserialize cached ScanJob JSON for key {CacheKey}", cacheKey);
            }
        }

        return null;
    }

    /// <summary>
    /// Atomically attempts to acquire a processing lease on the ScanJobs table.
    /// Concurrency-safe across multiple container instances on Render.
    /// </summary>
    public async Task<(LeaseAcquisitionResult Result, ScanJob Job)> TryAcquireLeaseAsync(
        string userId,
        string cacheKey,
        string workerInstanceId,
        AnalyzeBusinessCardRequest request,
        TimeSpan leaseDuration,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var existingJob = await _dbContext.ScanJobs
            .FirstOrDefaultAsync(j => j.UserId == userId && j.ClientJobId == cacheKey, ct);

        if (existingJob == null)
        {
            var newJob = new ScanJob
            {
                UserId = userId,
                ClientJobId = cacheKey,
                Status = ScanJobStatus.Processing,
                FrontImageStorageKey = request.FrontImageStorageKey ?? "text-only-spatial-scan",
                BackImageStorageKey = request.BackImageStorageKey,
                ImageSha256Checksum = request.ScanContentHash,
                WorkerInstanceId = workerInstanceId,
                LockedUntilUtc = now.Add(leaseDuration),
                RetryCount = 0,
                CreatedAtUtc = now,
                UpdatedAtUtc = now,
                ExpiresAtUtc = now.AddDays(7)
            };

            _dbContext.ScanJobs.Add(newJob);
            try
            {
                await _dbContext.SaveChangesAsync(ct);
                return (LeaseAcquisitionResult.AcquiredNew, newJob);
            }
            catch (DbUpdateException)
            {
                // Unique constraint race condition with another backend instance
                _dbContext.ChangeTracker.Clear();
                existingJob = await _dbContext.ScanJobs
                    .FirstOrDefaultAsync(j => j.UserId == userId && j.ClientJobId == cacheKey, ct);
            }
        }

        if (existingJob != null)
        {
            if (existingJob.Status == ScanJobStatus.Completed &&
                existingJob.ExpiresAtUtc > now &&
                !string.IsNullOrWhiteSpace(existingJob.ReconciledResultJson))
            {
                return (LeaseAcquisitionResult.AlreadyCompleted, existingJob);
            }

            // Check if lease is currently active on another worker
            if (existingJob.Status == ScanJobStatus.Processing &&
                existingJob.LockedUntilUtc.HasValue &&
                existingJob.LockedUntilUtc.Value > now)
            {
                return (LeaseAcquisitionResult.LockedByAnotherWorker, existingJob);
            }

            // Lease is abandoned or previously failed -> take over lease
            existingJob.Status = ScanJobStatus.Processing;
            existingJob.WorkerInstanceId = workerInstanceId;
            existingJob.LockedUntilUtc = now.Add(leaseDuration);
            existingJob.RetryCount += 1;
            existingJob.UpdatedAtUtc = now;

            await _dbContext.SaveChangesAsync(ct);
            return (LeaseAcquisitionResult.AcquiredAbandoned, existingJob);
        }

        throw new InvalidOperationException("Unreachable state in lease acquisition.");
    }

    /// <summary>
    /// Waits for an active in-flight analysis job being processed by another backend instance.
    /// </summary>
    public async Task<AnalyzeBusinessCardResponse?> AwaitInFlightJobAsync(
        string userId,
        string cacheKey,
        TimeSpan maxWaitTime,
        CancellationToken ct = default)
    {
        var deadline = DateTime.UtcNow.Add(maxWaitTime);
        while (DateTime.UtcNow < deadline && !ct.IsCancellationRequested)
        {
            await Task.Delay(400, ct);

            var job = await _dbContext.ScanJobs
                .AsNoTracking()
                .FirstOrDefaultAsync(j => j.UserId == userId && j.ClientJobId == cacheKey, ct);

            if (job == null) return null;

            if (job.Status == ScanJobStatus.Completed && !string.IsNullOrWhiteSpace(job.ReconciledResultJson))
            {
                try
                {
                    var response = JsonSerializer.Deserialize<AnalyzeBusinessCardResponse>(
                        job.ReconciledResultJson, JsonOptions);
                    if (response != null)
                    {
                        response.FromCache = true;
                        return response;
                    }
                }
                catch (Exception) {}
            }

            if (job.Status == ScanJobStatus.Failed || (job.LockedUntilUtc.HasValue && job.LockedUntilUtc.Value <= DateTime.UtcNow))
            {
                // In-flight worker failed or timed out
                return null;
            }
        }

        return null;
    }

    /// <summary>
    /// Marks the analysis job as successfully completed with the serialized JSON payload.
    /// </summary>
    public async Task CompleteJobAsync(
        ScanJob job,
        AnalyzeBusinessCardResponse response,
        CancellationToken ct = default)
    {
        job.Status = ScanJobStatus.Completed;
        job.ReconciledResultJson = JsonSerializer.Serialize(response, JsonOptions);
        job.LockedUntilUtc = null;
        job.UpdatedAtUtc = DateTime.UtcNow;
        job.ErrorMessage = null;

        await _dbContext.SaveChangesAsync(ct);
    }

    /// <summary>
    /// Records an error on the analysis job so retries or fallbacks can take over cleanly.
    /// </summary>
    public async Task FailJobAsync(
        ScanJob job,
        string errorMessage,
        CancellationToken ct = default)
    {
        job.Status = ScanJobStatus.Failed;
        job.ErrorMessage = errorMessage.Length > 500 ? errorMessage[..500] : errorMessage;
        job.LockedUntilUtc = null;
        job.UpdatedAtUtc = DateTime.UtcNow;

        await _dbContext.SaveChangesAsync(ct);
    }
}

