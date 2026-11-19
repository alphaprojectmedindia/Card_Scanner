using System.ComponentModel.DataAnnotations;

namespace DigitalShare.Api.DTOs.ImportedContacts;

public class ImportedContactPhoneDto
{
    [Required(ErrorMessage = "Phone number is required.")]
    [Phone(ErrorMessage = "Invalid phone number format.")]
    [MaxLength(50, ErrorMessage = "Phone number cannot exceed 50 characters.")]
    public string Number { get; set; } = string.Empty;

    [MaxLength(50, ErrorMessage = "Phone label cannot exceed 50 characters.")]
    public string? Label { get; set; }
}

public class ImportedContactEmailDto
{
    [Required(ErrorMessage = "Email address is required.")]
    [EmailAddress(ErrorMessage = "Invalid email address format.")]
    [MaxLength(256, ErrorMessage = "Email address cannot exceed 256 characters.")]
    public string Email { get; set; } = string.Empty;

    [MaxLength(50, ErrorMessage = "Email label cannot exceed 50 characters.")]
    public string? Label { get; set; }
}

public class SaveImportedContactRequest
{
    [MaxLength(64, ErrorMessage = "Client request ID cannot exceed 64 characters.")]
    public string? ClientRequestId { get; set; }

    [MaxLength(100, ErrorMessage = "Full name cannot exceed 100 characters.")]
    public string? FullName { get; set; }

    [MaxLength(100, ErrorMessage = "Company cannot exceed 100 characters.")]
    public string? Company { get; set; }

    [MaxLength(100, ErrorMessage = "Job title cannot exceed 100 characters.")]
    public string? JobTitle { get; set; }

    [MaxLength(256, ErrorMessage = "Website cannot exceed 256 characters.")]
    public string? Website { get; set; }

    [MaxLength(500, ErrorMessage = "Address cannot exceed 500 characters.")]
    public string? Address { get; set; }

    [MaxLength(2000, ErrorMessage = "Remember this contact memory cannot exceed 2,000 characters.")]
    public string? RememberThisContact { get; set; }

    [MaxLength(2000, ErrorMessage = "Personal remark cannot exceed 2,000 characters.")]
    public string? PersonalRemark { get; set; }

    public List<ImportedContactPhoneDto> PhoneNumbers { get; set; } = new();
    public List<ImportedContactEmailDto> EmailAddresses { get; set; } = new();
}

public class UpdateImportedContactRequest
{
    [MaxLength(100, ErrorMessage = "Full name cannot exceed 100 characters.")]
    public string? FullName { get; set; }

    [MaxLength(100, ErrorMessage = "Company cannot exceed 100 characters.")]
    public string? Company { get; set; }

    [MaxLength(100, ErrorMessage = "Job title cannot exceed 100 characters.")]
    public string? JobTitle { get; set; }

    [MaxLength(256, ErrorMessage = "Website cannot exceed 256 characters.")]
    public string? Website { get; set; }

    [MaxLength(500, ErrorMessage = "Address cannot exceed 500 characters.")]
    public string? Address { get; set; }

    [MaxLength(2000, ErrorMessage = "Remember this contact memory cannot exceed 2,000 characters.")]
    public string? RememberThisContact { get; set; }

    [MaxLength(2000, ErrorMessage = "Personal remark cannot exceed 2,000 characters.")]
    public string? PersonalRemark { get; set; }

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
    public string? ClientRequestId { get; set; }
    public string? FullName { get; set; }
    public string? Company { get; set; }
    public string? JobTitle { get; set; }
    public string? Website { get; set; }
    public string? Address { get; set; }
    public string? RememberThisContact { get; set; }
    public string? PersonalRemark { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public DateTime UpdatedAtUtc { get; set; }

    public List<ImportedContactPhoneResponse> PhoneNumbers { get; set; } = new();
    public List<ImportedContactEmailResponse> EmailAddresses { get; set; } = new();
}

public class UpdateContactRemarkRequest
{
    [MaxLength(2000, ErrorMessage = "Remember this contact memory cannot exceed 2,000 characters.")]
    public string? RememberThisContact { get; set; }

    [MaxLength(2000, ErrorMessage = "Personal remark cannot exceed 2,000 characters.")]
    public string? Remark { get; set; }
}

public class UpdateContactMemoryRequest
{
    [MaxLength(2000, ErrorMessage = "Remember this contact memory cannot exceed 2,000 characters.")]
    public string? Memory { get; set; }
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
