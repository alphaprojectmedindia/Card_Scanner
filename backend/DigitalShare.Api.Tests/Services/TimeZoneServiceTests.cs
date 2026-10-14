using DigitalShare.Api.Services;
using Microsoft.Extensions.Logging.Abstractions;

namespace DigitalShare.Api.Tests.Services;

public class TimeZoneServiceTests
{
    private readonly TimeZoneService _service;

    public TimeZoneServiceTests()
    {
        _service = new TimeZoneService(NullLogger<TimeZoneService>.Instance);
    }

    [Theory]
    [InlineData("Asia/Kolkata")]
    [InlineData("America/New_York")]
    [InlineData("Europe/London")]
    [InlineData("Asia/Dubai")]
    [InlineData("Asia/Singapore")]
    [InlineData("Australia/Sydney")]
    [InlineData("UTC")]
    [InlineData("India Standard Time")]
    [InlineData("Eastern Standard Time")]
    public void IsValidTimeZone_RecognizedTimeZones_ReturnsTrue(string timeZoneId)
    {
        var isValid = _service.IsValidTimeZone(timeZoneId);
        Assert.True(isValid, $"Expected '{timeZoneId}' to be recognized as valid.");
    }

    [Theory]
    [InlineData("Invalid/TimeZone")]
    [InlineData("Mars/Crater")]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(null)]
    public void IsValidTimeZone_InvalidOrEmpty_ReturnsFalse(string? timeZoneId)
    {
        var isValid = _service.IsValidTimeZone(timeZoneId);
        Assert.False(isValid, $"Expected '{timeZoneId}' to be invalid.");
    }

    [Fact]
    public void TryResolveTimeZone_ValidIana_ResolvesSuccessfully()
    {
        var success = _service.TryResolveTimeZone("America/New_York", out var tz);
        Assert.True(success);
        Assert.NotNull(tz);
    }

    [Fact]
    public void GetTimeZoneInfo_InvalidOrNull_FallsBackToUtcSafely()
    {
        var tzNull = _service.GetTimeZoneInfo(null);
        var tzInvalid = _service.GetTimeZoneInfo("NonExistent/Zone");

        Assert.Equal(TimeZoneInfo.Utc, tzNull);
        Assert.Equal(TimeZoneInfo.Utc, tzInvalid);
    }

    [Fact]
    public void ConvertTimeFromUtc_AsiaKolkata_ConvertsCorrectly()
    {
        // 2026-06-15 12:00:00 UTC -> 17:30:00 IST (+05:30)
        var utc = new DateTime(2026, 6, 15, 12, 0, 0, DateTimeKind.Utc);
        var local = _service.ConvertTimeFromUtc(utc, "Asia/Kolkata");

        Assert.Equal(new DateTime(2026, 6, 15, 17, 30, 0), local);
    }

    [Fact]
    public void ConvertTimeToUtc_AsiaKolkata_ConvertsCorrectly()
    {
        // 17:30:00 IST -> 12:00:00 UTC
        var local = new DateTime(2026, 6, 15, 17, 30, 0, DateTimeKind.Unspecified);
        var utc = _service.ConvertTimeToUtc(local, "Asia/Kolkata");

        Assert.Equal(new DateTime(2026, 6, 15, 12, 0, 0, DateTimeKind.Utc), utc);
    }

    [Fact]
    public void AmericaNewYork_DaylightSavingTime_HandlesSummerAndWinterCorrectly()
    {
        // Summer (EDT is UTC-4)
        var summerUtc = new DateTime(2026, 7, 1, 14, 0, 0, DateTimeKind.Utc);
        var summerLocal = _service.ConvertTimeFromUtc(summerUtc, "America/New_York");
        Assert.Equal(new DateTime(2026, 7, 1, 10, 0, 0), summerLocal);

        var convertedBackSummerUtc = _service.ConvertTimeToUtc(summerLocal, "America/New_York");
        Assert.Equal(summerUtc, convertedBackSummerUtc);

        // Winter (EST is UTC-5)
        var winterUtc = new DateTime(2026, 1, 15, 14, 0, 0, DateTimeKind.Utc);
        var winterLocal = _service.ConvertTimeFromUtc(winterUtc, "America/New_York");
        Assert.Equal(new DateTime(2026, 1, 15, 9, 0, 0), winterLocal);

        var convertedBackWinterUtc = _service.ConvertTimeToUtc(winterLocal, "America/New_York");
        Assert.Equal(winterUtc, convertedBackWinterUtc);
    }

    [Fact]
    public void EuropeLondon_DaylightSavingTime_HandlesSummerAndWinterCorrectly()
    {
        // Summer (BST is UTC+1)
        var summerUtc = new DateTime(2026, 7, 1, 12, 0, 0, DateTimeKind.Utc);
        var summerLocal = _service.ConvertTimeFromUtc(summerUtc, "Europe/London");
        Assert.Equal(new DateTime(2026, 7, 1, 13, 0, 0), summerLocal);

        // Winter (GMT is UTC+0)
        var winterUtc = new DateTime(2026, 1, 15, 12, 0, 0, DateTimeKind.Utc);
        var winterLocal = _service.ConvertTimeFromUtc(winterUtc, "Europe/London");
        Assert.Equal(new DateTime(2026, 1, 15, 12, 0, 0), winterLocal);
    }

    [Fact]
    public void AsiaDubai_NoDst_OffsetIsAlwaysPlusFour()
    {
        // Dubai (UTC+4 year-round)
        var utc = new DateTime(2026, 7, 1, 10, 0, 0, DateTimeKind.Utc);
        var local = _service.ConvertTimeFromUtc(utc, "Asia/Dubai");
        Assert.Equal(new DateTime(2026, 7, 1, 14, 0, 0), local);
    }

    [Theory]
    [InlineData("America/New_York", "America/New_York")]
    [InlineData("Asia/Kolkata", "Asia/Kolkata")]
    [InlineData("UTC", "UTC")]
    [InlineData("Eastern Standard Time", "America/New_York")]
    [InlineData("India Standard Time", "Asia/Kolkata")]
    public void NormalizeToIana_ReturnsCanonicalIanaId(string input, string expectedIana)
    {
        var normalized = _service.NormalizeToIana(input);
        Assert.Equal(expectedIana, normalized);
    }
}
