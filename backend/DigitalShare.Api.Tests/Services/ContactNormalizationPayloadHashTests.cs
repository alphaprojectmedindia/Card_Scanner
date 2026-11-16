using DigitalShare.Api.DTOs.ImportedContacts;
using DigitalShare.Api.Services;
using Xunit;

namespace DigitalShare.Api.Tests.Services;

public class ContactNormalizationPayloadHashTests
{
    [Fact]
    public void ComputePayloadHash_IdenticalPayloads_ProduceIdenticalHashes()
    {
        var req1 = new SaveImportedContactRequest
        {
            FullName = "Jane Doe",
            Company = "Acme Corp",
            JobTitle = "CTO",
            Website = "https://acme.org",
            Address = "123 Main St",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+1 555 123 4567", Label = "Mobile" }
            },
            EmailAddresses = new List<ImportedContactEmailDto>
            {
                new() { Email = "jane@acme.org", Label = "Work" }
            }
        };

        var req2 = new SaveImportedContactRequest
        {
            FullName = "Jane Doe",
            Company = "Acme Corp",
            JobTitle = "CTO",
            Website = "https://acme.org",
            Address = "123 Main St",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+1 555 123 4567", Label = "Mobile" }
            },
            EmailAddresses = new List<ImportedContactEmailDto>
            {
                new() { Email = "jane@acme.org", Label = "Work" }
            }
        };

        var hash1 = ContactNormalizationHelper.ComputePayloadHash(req1);
        var hash2 = ContactNormalizationHelper.ComputePayloadHash(req2);

        Assert.NotNull(hash1);
        Assert.Equal(64, hash1.Length);
        Assert.Equal(hash1, hash2);
    }

    [Fact]
    public void ComputePayloadHash_DifferentOrderOfPhonesOrEmails_ProducesSameHash()
    {
        var req1 = new SaveImportedContactRequest
        {
            FullName = "Jane Doe",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+1 555 111", Label = "A" },
                new() { Number = "+1 555 222", Label = "B" }
            },
            EmailAddresses = new List<ImportedContactEmailDto>
            {
                new() { Email = "a@acme.org", Label = "Work" },
                new() { Email = "b@acme.org", Label = "Personal" }
            }
        };

        var req2 = new SaveImportedContactRequest
        {
            FullName = "Jane Doe",
            PhoneNumbers = new List<ImportedContactPhoneDto>
            {
                new() { Number = "+1 555 222", Label = "B" },
                new() { Number = "+1 555 111", Label = "A" }
            },
            EmailAddresses = new List<ImportedContactEmailDto>
            {
                new() { Email = "b@acme.org", Label = "Personal" },
                new() { Email = "a@acme.org", Label = "Work" }
            }
        };

        var hash1 = ContactNormalizationHelper.ComputePayloadHash(req1);
        var hash2 = ContactNormalizationHelper.ComputePayloadHash(req2);

        Assert.Equal(hash1, hash2);
    }

    [Fact]
    public void ComputePayloadHash_DifferentFields_ProducesDifferentHashes()
    {
        var req1 = new SaveImportedContactRequest
        {
            FullName = "Jane Doe",
            Company = "Acme Corp"
        };

        var req2 = new SaveImportedContactRequest
        {
            FullName = "Jane Doe",
            Company = "Beta Corp"
        };

        var hash1 = ContactNormalizationHelper.ComputePayloadHash(req1);
        var hash2 = ContactNormalizationHelper.ComputePayloadHash(req2);

        Assert.NotEqual(hash1, hash2);
    }

    [Fact]
    public void ComputePayloadHash_TrimmingAndCaseInsensitivityForEmail_ProducesIdenticalHash()
    {
        var req1 = new SaveImportedContactRequest
        {
            FullName = "Jane Doe",
            EmailAddresses = new List<ImportedContactEmailDto>
            {
                new() { Email = "JANE@ACME.ORG", Label = "Work" }
            }
        };

        var req2 = new SaveImportedContactRequest
        {
            FullName = "  Jane Doe  ",
            EmailAddresses = new List<ImportedContactEmailDto>
            {
                new() { Email = "  jane@acme.org  ", Label = "work" }
            }
        };

        var hash1 = ContactNormalizationHelper.ComputePayloadHash(req1);
        var hash2 = ContactNormalizationHelper.ComputePayloadHash(req2);

        Assert.Equal(hash1, hash2);
    }
}
