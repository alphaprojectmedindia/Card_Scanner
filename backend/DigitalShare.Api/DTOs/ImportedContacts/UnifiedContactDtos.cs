namespace DigitalShare.Api.DTOs.ImportedContacts;

public class UnifiedContactResponse
{
    public string Id { get; set; } = string.Empty;
    public string Source { get; set; } = "BusinessCard"; // "BusinessCard" or "QrCodeScan"
    public string FullName { get; set; } = string.Empty;
    public string? JobTitle { get; set; }
    public string? Company { get; set; }
    public string? PhoneNumber { get; set; }
    public string? Email { get; set; }
    public string? Address { get; set; }
    public string? Website { get; set; }
    public string? Remarks { get; set; }
    public string? ProfilePhotoUrl { get; set; }
    public string? ShareId { get; set; }
    public DateTime CreatedAtUtc { get; set; }
}

public class UnifiedContactsPagedResponse
{
    public List<UnifiedContactResponse> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 50;
    public int BusinessCardsCount { get; set; }
    public int QrConnectionsCount { get; set; }
}

