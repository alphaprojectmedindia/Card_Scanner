namespace DigitalShare.Api.Models;

public class RefreshToken
{
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// Foreign key referencing the Identity user.
    /// </summary>
    public string UserId { get; set; } = string.Empty;

    /// <summary>
    /// SHA-256 cryptographic hash of the raw refresh token.
    /// RAW refresh tokens are NEVER stored in the database.
    /// </summary>
    public string TokenHash { get; set; } = string.Empty;

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;

    public DateTime ExpiresAtUtc { get; set; }

    public DateTime? RevokedAtUtc { get; set; }

    /// <summary>
    /// Points to the replacement token ID when this token was rotated.
    /// </summary>
    public Guid? ReplacedByTokenId { get; set; }

    public string? CreatedByIp { get; set; }

    public string? RevokedByIp { get; set; }

    public virtual ApplicationUser? User { get; set; }

    public bool IsExpired => DateTime.UtcNow >= ExpiresAtUtc;

    public bool IsRevoked => RevokedAtUtc != null;

    public bool IsActive => !IsRevoked && !IsExpired;
}
