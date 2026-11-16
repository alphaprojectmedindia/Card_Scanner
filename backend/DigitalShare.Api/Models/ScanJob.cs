using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DigitalShare.Api.Models;

/// <summary>
/// Represents a durable asynchronous business card scan job.
/// Tracks storage keys, checksums, OCR states, workers, and lifecycle.
/// </summary>
public class ScanJob
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public string UserId { get; set; } = string.Empty;

    [ForeignKey(nameof(UserId))]
    public virtual ApplicationUser? User { get; set; }

    [Required]
    [MaxLength(64)]
    public string ClientJobId { get; set; } = string.Empty;

    public ScanJobStatus Status { get; set; } = ScanJobStatus.Queued;

    [Required]
    [MaxLength(500)]
    public string FrontImageStorageKey { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? BackImageStorageKey { get; set; }

    [MaxLength(64)]
    public string? ImageSha256Checksum { get; set; }

    public string? LocalOcrDraftJson { get; set; }

    public string? ReconciledResultJson { get; set; }

    [MaxLength(500)]
    public string? ErrorMessage { get; set; }

    public int RetryCount { get; set; } = 0;

    [MaxLength(100)]
    public string? WorkerInstanceId { get; set; }

    public DateTime? LockedUntilUtc { get; set; }

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;

    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;

    public DateTime ExpiresAtUtc { get; set; } = DateTime.UtcNow.AddHours(48);
}
