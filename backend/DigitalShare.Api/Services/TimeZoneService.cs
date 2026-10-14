using TimeZoneConverter;

namespace DigitalShare.Api.Services;

public class TimeZoneService : ITimeZoneService
{
    private readonly ILogger<TimeZoneService> _logger;

    public TimeZoneService(ILogger<TimeZoneService> logger)
    {
        _logger = logger;
    }

    public bool IsValidTimeZone(string? timeZoneId)
    {
        if (string.IsNullOrWhiteSpace(timeZoneId))
        {
            return false;
        }

        var trimmed = timeZoneId.Trim();
        if (trimmed.Equals("UTC", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Equals("GMT", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return TZConvert.TryGetTimeZoneInfo(trimmed, out _);
    }

    public bool TryResolveTimeZone(string? timeZoneId, out TimeZoneInfo timeZoneInfo)
    {
        if (string.IsNullOrWhiteSpace(timeZoneId))
        {
            timeZoneInfo = TimeZoneInfo.Utc;
            return false;
        }

        var trimmed = timeZoneId.Trim();
        if (trimmed.Equals("UTC", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Equals("GMT", StringComparison.OrdinalIgnoreCase))
        {
            timeZoneInfo = TimeZoneInfo.Utc;
            return true;
        }

        if (TZConvert.TryGetTimeZoneInfo(trimmed, out var tz))
        {
            timeZoneInfo = tz;
            return true;
        }

        timeZoneInfo = TimeZoneInfo.Utc;
        return false;
    }

    public TimeZoneInfo GetTimeZoneInfo(string? timeZoneId)
    {
        if (TryResolveTimeZone(timeZoneId, out var tz))
        {
            return tz;
        }

        _logger.LogWarning("Unknown timezone '{TimeZoneId}', falling back to UTC.", timeZoneId);
        return TimeZoneInfo.Utc;
    }

    public DateTime ConvertTimeFromUtc(DateTime utcDateTime, string? timeZoneId)
    {
        var tz = GetTimeZoneInfo(timeZoneId);
        var specifiedUtc = utcDateTime.Kind == DateTimeKind.Utc
            ? utcDateTime
            : DateTime.SpecifyKind(utcDateTime, DateTimeKind.Utc);

        return TimeZoneInfo.ConvertTimeFromUtc(specifiedUtc, tz);
    }

    public DateTime ConvertTimeToUtc(DateTime localDateTime, string? timeZoneId)
    {
        var tz = GetTimeZoneInfo(timeZoneId);
        var unspecified = DateTime.SpecifyKind(localDateTime, DateTimeKind.Unspecified);
        return TimeZoneInfo.ConvertTimeToUtc(unspecified, tz);
    }

    public string NormalizeToIana(string? timeZoneId)
    {
        if (string.IsNullOrWhiteSpace(timeZoneId))
        {
            return "UTC";
        }

        var trimmed = timeZoneId.Trim();
        if (trimmed.Equals("UTC", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Equals("GMT", StringComparison.OrdinalIgnoreCase))
        {
            return "UTC";
        }

        // If it is a Windows ID (e.g. "India Standard Time"), convert to canonical IANA ("Asia/Kolkata")
        if (TZConvert.TryWindowsToIana(trimmed, out var ianaFromWindows))
        {
            return ianaFromWindows;
        }

        // If it's already a valid IANA ID, return it trimmed
        if (TZConvert.TryGetTimeZoneInfo(trimmed, out _))
        {
            return trimmed;
        }

        return "UTC";
    }
}
