using System.Security.Cryptography;
using System.Text;
using DigitalShare.Api.DTOs.ImportedContacts;

namespace DigitalShare.Api.Services;

/// <summary>
/// Helper providing phone and email normalization, payload hashing, and conservative matching algorithms.
/// </summary>
public static class ContactNormalizationHelper
{
    public static string ComputePayloadHash(SaveImportedContactRequest request)
    {
        var normalizedFullName = request.FullName?.Trim() ?? string.Empty;
        var normalizedCompany = request.Company?.Trim() ?? string.Empty;
        var normalizedJobTitle = request.JobTitle?.Trim() ?? string.Empty;
        var normalizedWebsite = request.Website?.Trim() ?? string.Empty;
        var normalizedAddress = request.Address?.Trim() ?? string.Empty;

        var sortedPhones = (request.PhoneNumbers ?? Enumerable.Empty<ImportedContactPhoneDto>())
            .Where(p => !string.IsNullOrWhiteSpace(p.Number))
            .Select(p => $"{NormalizePhone(p.Number)}|{p.Label?.Trim().ToLowerInvariant()}")
            .OrderBy(p => p, StringComparer.Ordinal)
            .ToList();

        var sortedEmails = (request.EmailAddresses ?? Enumerable.Empty<ImportedContactEmailDto>())
            .Where(e => !string.IsNullOrWhiteSpace(e.Email))
            .Select(e => $"{NormalizeEmail(e.Email)}|{e.Label?.Trim().ToLowerInvariant()}")
            .OrderBy(e => e, StringComparer.Ordinal)
            .ToList();

        var canonical = string.Join(";",
            $"fn:{normalizedFullName}",
            $"cp:{normalizedCompany}",
            $"jt:{normalizedJobTitle}",
            $"ws:{normalizedWebsite}",
            $"ad:{normalizedAddress}",
            $"ph:{string.Join(",", sortedPhones)}",
            $"em:{string.Join(",", sortedEmails)}"
        );

        var bytes = Encoding.UTF8.GetBytes(canonical);
        var hashBytes = SHA256.HashData(bytes);
        return Convert.ToHexString(hashBytes).ToLowerInvariant();
    }

    public static string NormalizeEmail(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return string.Empty;
        return raw.Trim().ToLowerInvariant();
    }

    public static string NormalizePhone(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return string.Empty;
        var trimmed = raw.Trim();
        var hasPlus = trimmed.StartsWith("+");
        var digitsOnly = new string(trimmed.Where(char.IsDigit).ToArray());
        return hasPlus ? $"+{digitsOnly}" : digitsOnly;
    }

    public static bool ArePhonesMatching(string? phone1, string? phone2)
    {
        if (string.IsNullOrWhiteSpace(phone1) || string.IsNullOrWhiteSpace(phone2))
            return false;

        var norm1 = NormalizePhone(phone1);
        var norm2 = NormalizePhone(phone2);

        if (string.Equals(norm1, norm2, StringComparison.OrdinalIgnoreCase))
            return true;

        var d1 = new string(norm1.Where(char.IsDigit).ToArray());
        var d2 = new string(norm2.Where(char.IsDigit).ToArray());

        if (d1.Length == 0 || d2.Length == 0) return false;
        if (d1 == d2) return true;

        // Indian 10-digit mobile vs 12-digit with 91 country code
        if (d1.Length == 10 && d2.Length == 12 && d2.StartsWith("91") && d2.EndsWith(d1))
            return true;
        if (d2.Length == 10 && d1.Length == 12 && d1.StartsWith("91") && d1.EndsWith(d2))
            return true;

        // Leading 0 national prefix (e.g., 04423456789 vs 4423456789)
        if (d1.StartsWith("0") && d1.Length > 1 && d1.Substring(1) == d2)
            return true;
        if (d2.StartsWith("0") && d2.Length > 1 && d2.Substring(1) == d1)
            return true;

        return false;
    }
}
