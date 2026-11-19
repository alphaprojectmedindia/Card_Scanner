using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Consent;
using DigitalShare.Api.DTOs.ImportedContacts;
using DigitalShare.Api.Models;
using DigitalShare.Api.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace DigitalShare.Api.Tests.Services;

public class LegalConsentAndUnifiedContactsTests
{
    private ApplicationDbContext CreateInMemoryDbContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        return new ApplicationDbContext(options);
    }

    [Fact]
    public void LegalDocumentService_Returns_India_DPDP_Compliant_Documents()
    {
        var service = new LegalDocumentService();
        var docs = service.GetLegalDocuments("IN");

        Assert.Equal("IN", docs.Jurisdiction);
        Assert.Contains("Digital Personal Data Protection Act, 2023", docs.TermsAndConditionsMarkdown);
        Assert.Contains("Medindia4u.com", docs.TermsAndConditionsMarkdown);
        Assert.Contains("Grievance Officer", docs.TermsAndConditionsMarkdown);
        Assert.Contains("DPDP Act", docs.PrivacyPolicyMarkdown);
        Assert.Contains("Essential Authentication Tokens", docs.CookiePolicyMarkdown);
    }

    [Fact]
    public void LegalDocumentService_Returns_GDPR_Compliant_Documents_For_EU()
    {
        var service = new LegalDocumentService();
        var docs = service.GetLegalDocuments("EU");

        Assert.Equal("EU", docs.Jurisdiction);
        Assert.Contains("GDPR", docs.PrivacyPolicyMarkdown);
        Assert.Contains("Data Controller", docs.PrivacyPolicyMarkdown);
    }

    [Fact]
    public async Task GetConsentStatusAsync_Returns_Unaccepted_When_No_Record_Exists()
    {
        using var db = CreateInMemoryDbContext();
        var authService = new AuthService(
            null!,
            db,
            new FakeJwtTokenGenerator(),
            new FakeShareIdGenerator(),
            NullLogger<AuthService>.Instance
        );

        var status = await authService.GetConsentStatusAsync("user-123");

        Assert.False(status.HasAcceptedCurrentTerms);
        Assert.Equal("2026.1", status.CurrentTermsVersion);
        Assert.Null(status.UserTermsVersion);
    }

    [Fact]
    public async Task RecordConsentAsync_Stores_Auditable_Consent_Record()
    {
        using var db = CreateInMemoryDbContext();
        var authService = new AuthService(
            null!,
            db,
            new FakeJwtTokenGenerator(),
            new FakeShareIdGenerator(),
            NullLogger<AuthService>.Instance
        );

        var request = new RecordConsentRequest
        {
            TermsVersion = "2026.1",
            PrivacyPolicyVersion = "2026.1",
            CookiePolicyVersion = "2026.1",
            Jurisdiction = "IN",
            EssentialAccepted = true,
            AnalyticsAccepted = true
        };

        var status = await authService.RecordConsentAsync("user-123", request, "127.0.0.1", "TestAgent/1.0");

        Assert.True(status.HasAcceptedCurrentTerms);
        Assert.Equal("2026.1", status.UserTermsVersion);
        Assert.Equal("IN", status.Jurisdiction);
        Assert.True(status.AnalyticsAccepted);

        var dbRecords = await db.UserConsents.Where(c => c.UserId == "user-123").ToListAsync();
        Assert.Single(dbRecords);
        Assert.Equal("127.0.0.1", dbRecords[0].IpAddress);
    }

    [Fact]
    public async Task GetUnifiedContactsAsync_Combines_BusinessCards_And_QR_Connections()
    {
        using var db = CreateInMemoryDbContext();
        var userId = "owner-999";

        // Add an imported business card
        var card = new ImportedBusinessCard
        {
            Id = Guid.NewGuid(),
            OwnerUserId = userId,
            FullName = "Dr. Alice Sharma",
            Company = "Apex Healthcare",
            JobTitle = "Chief Cardiologist",
            CreatedAtUtc = DateTime.UtcNow.AddMinutes(-10),
            PhoneNumbers = new List<ImportedBusinessCardPhone>
            {
                new() { Number = "+91 98765 43210", NormalizedNumber = "+919876543210", Label = "Mobile" }
            },
            EmailAddresses = new List<ImportedBusinessCardEmail>
            {
                new() { Email = "alice@apex.org", NormalizedEmail = "alice@apex.org", Label = "Work" }
            }
        };
        db.ImportedBusinessCards.Add(card);

        // Add a saved QR code connection
        var profile = new UserProfile
        {
            Id = Guid.NewGuid(),
            UserId = "target-user-1",
            ShareId = "share_bob_123",
            FullName = "Bob Vance",
            Company = "Vance Refrigeration",
            JobTitle = "Owner",
            PhoneNumber = "555-0199",
            Email = "bob@vancerefrigeration.com",
            CreatedAtUtc = DateTime.UtcNow,
            UpdatedAtUtc = DateTime.UtcNow
        };
        db.UserProfiles.Add(profile);

        var connection = new Connection
        {
            Id = Guid.NewGuid(),
            OwnerUserId = userId,
            SavedProfileId = profile.Id,
            SavedProfile = profile,
            CreatedAtUtc = DateTime.UtcNow.AddMinutes(-5)
        };
        db.Connections.Add(connection);
        await db.SaveChangesAsync();

        var service = new ImportedContactService(
            db,
            NullLogger<ImportedContactService>.Instance
        );

        // Query all unified
        var all = await service.GetUnifiedContactsAsync(userId, null, "all");
        Assert.Equal(2, all.TotalCount);
        Assert.Equal(1, all.BusinessCardsCount);
        Assert.Equal(1, all.QrConnectionsCount);

        // Query by search
        var searchCard = await service.GetUnifiedContactsAsync(userId, "Cardiologist");
        Assert.Single(searchCard.Items);
        Assert.Equal("Dr. Alice Sharma", searchCard.Items[0].FullName);
        Assert.Equal("BusinessCard", searchCard.Items[0].Source);

        var searchQr = await service.GetUnifiedContactsAsync(userId, "Vance");
        Assert.Single(searchQr.Items);
        Assert.Equal("Bob Vance", searchQr.Items[0].FullName);
        Assert.Equal("QrCodeScan", searchQr.Items[0].Source);
    }

    private class FakeJwtTokenGenerator : IJwtTokenGenerator
    {
        public (string Token, DateTime ExpirationUtc) GenerateToken(ApplicationUser user)
            => ("fake-jwt-token", DateTime.UtcNow.AddHours(1));
    }

    private class FakeShareIdGenerator : IShareIdGenerator
    {
        public string GenerateShareId() => "fake_share_id";
    }
}

