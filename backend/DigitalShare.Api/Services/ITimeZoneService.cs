namespace DigitalShare.Api.Services;

public interface ITimeZoneService
{
    /// <summary>
    /// Validates whether the given timezone identifier is recognized cross-platform.
    /// Supports IANA identifiers (canonical) as well as existing Windows/UTC identifiers.
    /// </summary>
    bool IsValidTimeZone(string? timeZoneId);

    /// <summary>
    /// Attempts to resolve a TimeZoneInfo from the given timezone identifier.
    /// </summary>
    bool TryResolveTimeZone(string? timeZoneId, out TimeZoneInfo timeZoneInfo);

    /// <summary>
    /// Resolves a TimeZoneInfo from the given identifier. Falls back to UTC if invalid or unspecified.
    /// </summary>
    TimeZoneInfo GetTimeZoneInfo(string? timeZoneId);

    /// <summary>
    /// Converts a UTC DateTime to the user's local wall-clock time in their configured timezone.
    /// </summary>
    DateTime ConvertTimeFromUtc(DateTime utcDateTime, string? timeZoneId);

    /// <summary>
    /// Converts a local wall-clock DateTime in the given timezone to UTC.
    /// </summary>
    DateTime ConvertTimeToUtc(DateTime localDateTime, string? timeZoneId);

    /// <summary>
    /// Returns the canonical IANA timezone identifier, converting Windows IDs if applicable.
    /// Defaults to "UTC" if unspecified or unrecognized.
    /// </summary>
    string NormalizeToIana(string? timeZoneId);
}
