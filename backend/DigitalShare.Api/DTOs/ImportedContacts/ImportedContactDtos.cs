namespace DigitalShare.Api.DTOs.ImportedContacts;

public class ImportedContactPhoneDto
{
    public string Number { get; set; } = string.Empty;
    public string? Label { get; set; }
}

public class ImportedContactEmailDto
{
    public string Email { get; set; } = string.Empty;
    public string? Label { get; set; }
}

public class SaveImportedContactRequest
{
    public string? FullName { get; set; }
    public string? Company { get; set; }
    public string? JobTitle { get; set; }
    public string? Website { get; set; }
    public string? Address { get; set; }

    public List<ImportedContactPhoneDto> PhoneNumbers { get; set; } = new();
    public List<ImportedContactEmailDto> EmailAddresses { get; set; } = new();
}

public class UpdateImportedContactRequest
{
    public string? FullName { get; set; }
    public string? Company { get; set; }
    public string? JobTitle { get; set; }
    public string? Website { get; set; }
    public string? Address { get; set; }

    public List<ImportedContactPhoneDto> PhoneNumbers { get; set; } = new();
    public List<ImportedContactEmailDto> EmailAddresses { get; set; } = new();
}

public class CheckDuplicateRequest
{
    public List<string> PhoneNumbers { get; set; } = new();
    public List<string> EmailAddresses { get; set; } = new();
}

public class CheckDuplicateResponse
{
    public bool IsDuplicate { get; set; }
    public ImportedContactResponse? ExistingContact { get; set; }
    public string? MatchedBy { get; set; }
}

public class ImportedContactResponse
{
    public Guid Id { get; set; }
    public string? FullName { get; set; }
    public string? Company { get; set; }
    public string? JobTitle { get; set; }
    public string? Website { get; set; }
    public string? Address { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public DateTime UpdatedAtUtc { get; set; }

    public List<ImportedContactPhoneResponse> PhoneNumbers { get; set; } = new();
    public List<ImportedContactEmailResponse> EmailAddresses { get; set; } = new();
}

public class ImportedContactPhoneResponse
{
    public Guid Id { get; set; }
    public string Number { get; set; } = string.Empty;
    public string NormalizedNumber { get; set; } = string.Empty;
    public string? Label { get; set; }
}

public class ImportedContactEmailResponse
{
    public Guid Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string NormalizedEmail { get; set; } = string.Empty;
    public string? Label { get; set; }
}
