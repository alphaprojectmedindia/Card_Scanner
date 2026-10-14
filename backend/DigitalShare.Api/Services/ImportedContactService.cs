using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.ImportedContacts;
using DigitalShare.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace DigitalShare.Api.Services;

public class ImportedContactService : IImportedContactService
{
    private readonly ApplicationDbContext _dbContext;
    private readonly ILogger<ImportedContactService> _logger;

    public ImportedContactService(
        ApplicationDbContext dbContext,
        ILogger<ImportedContactService> logger)
    {
        _dbContext = dbContext;
        _logger = logger;
    }

    public async Task<CheckDuplicateResponse> CheckDuplicateAsync(
        string ownerUserId,
        CheckDuplicateRequest request)
    {
        if (string.IsNullOrWhiteSpace(ownerUserId))
        {
            return new CheckDuplicateResponse { IsDuplicate = false };
        }

        var normalizedReqEmails = request.EmailAddresses
            .Select(ContactNormalizationHelper.NormalizeEmail)
            .Where(e => !string.IsNullOrEmpty(e))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var reqPhones = request.PhoneNumbers
            .Where(p => !string.IsNullOrWhiteSpace(p))
            .ToList();

        // Query existing contacts owned by this user
        var existingCards = await _dbContext.ImportedBusinessCards
            .AsNoTracking()
            .Where(c => c.OwnerUserId == ownerUserId)
            .Include(c => c.PhoneNumbers)
            .Include(c => c.EmailAddresses)
            .ToListAsync();

        foreach (var card in existingCards)
        {
            // 1. Check matching email
            foreach (var cardEmail in card.EmailAddresses)
            {
                if (normalizedReqEmails.Contains(cardEmail.NormalizedEmail))
                {
                    _logger.LogInformation(
                        "Duplicate detected for user {UserId} via email match on card {CardId}",
                        ownerUserId, card.Id);

                    return new CheckDuplicateResponse
                    {
                        IsDuplicate = true,
                        ExistingContact = MapToResponse(card),
                        MatchedBy = "Email"
                    };
                }
            }

            // 2. Check matching phone number
            foreach (var reqPhone in reqPhones)
            {
                foreach (var cardPhone in card.PhoneNumbers)
                {
                    if (ContactNormalizationHelper.ArePhonesMatching(reqPhone, cardPhone.Number) ||
                        ContactNormalizationHelper.ArePhonesMatching(reqPhone, cardPhone.NormalizedNumber))
                    {
                        _logger.LogInformation(
                            "Duplicate detected for user {UserId} via phone match on card {CardId}",
                            ownerUserId, card.Id);

                        return new CheckDuplicateResponse
                        {
                            IsDuplicate = true,
                            ExistingContact = MapToResponse(card),
                            MatchedBy = "Phone"
                        };
                    }
                }
            }
        }

        return new CheckDuplicateResponse { IsDuplicate = false };
    }

    public async Task<ImportedContactResponse> SaveContactAsync(
        string ownerUserId,
        SaveImportedContactRequest request)
    {
        var card = new ImportedBusinessCard
        {
            OwnerUserId = ownerUserId,
            FullName = request.FullName?.Trim(),
            Company = request.Company?.Trim(),
            JobTitle = request.JobTitle?.Trim(),
            Website = request.Website?.Trim(),
            Address = request.Address?.Trim(),
            CreatedAtUtc = DateTime.UtcNow,
            UpdatedAtUtc = DateTime.UtcNow,
        };

        foreach (var phoneDto in request.PhoneNumbers)
        {
            if (string.IsNullOrWhiteSpace(phoneDto.Number)) continue;
            card.PhoneNumbers.Add(new ImportedBusinessCardPhone
            {
                Number = phoneDto.Number.Trim(),
                NormalizedNumber = ContactNormalizationHelper.NormalizePhone(phoneDto.Number),
                Label = phoneDto.Label?.Trim()
            });
        }

        foreach (var emailDto in request.EmailAddresses)
        {
            if (string.IsNullOrWhiteSpace(emailDto.Email)) continue;
            card.EmailAddresses.Add(new ImportedBusinessCardEmail
            {
                Email = emailDto.Email.Trim(),
                NormalizedEmail = ContactNormalizationHelper.NormalizeEmail(emailDto.Email),
                Label = emailDto.Label?.Trim()
            });
        }

        _dbContext.ImportedBusinessCards.Add(card);
        await _dbContext.SaveChangesAsync();

        _logger.LogInformation(
            "User {UserId} saved imported business card {CardId}",
            ownerUserId, card.Id);

        return MapToResponse(card);
    }

    public async Task<IEnumerable<ImportedContactResponse>> GetContactsAsync(string ownerUserId)
    {
        var cards = await _dbContext.ImportedBusinessCards
            .AsNoTracking()
            .Where(c => c.OwnerUserId == ownerUserId)
            .Include(c => c.PhoneNumbers)
            .Include(c => c.EmailAddresses)
            .OrderByDescending(c => c.CreatedAtUtc)
            .ToListAsync();

        return cards.Select(MapToResponse);
    }

    public async Task<ImportedContactResponse?> GetContactByIdAsync(string ownerUserId, Guid id)
    {
        var card = await _dbContext.ImportedBusinessCards
            .AsNoTracking()
            .Where(c => c.Id == id && c.OwnerUserId == ownerUserId)
            .Include(c => c.PhoneNumbers)
            .Include(c => c.EmailAddresses)
            .FirstOrDefaultAsync();

        return card == null ? null : MapToResponse(card);
    }

    public async Task<ImportedContactResponse?> UpdateContactAsync(
        string ownerUserId,
        Guid id,
        UpdateImportedContactRequest request)
    {
        var card = await _dbContext.ImportedBusinessCards
            .Where(c => c.Id == id && c.OwnerUserId == ownerUserId)
            .Include(c => c.PhoneNumbers)
            .Include(c => c.EmailAddresses)
            .FirstOrDefaultAsync();

        if (card == null) return null;

        card.FullName = request.FullName?.Trim();
        card.Company = request.Company?.Trim();
        card.JobTitle = request.JobTitle?.Trim();
        card.Website = request.Website?.Trim();
        card.Address = request.Address?.Trim();
        card.UpdatedAtUtc = DateTime.UtcNow;

        // Remove existing phone and email children
        _dbContext.ImportedBusinessCardPhones.RemoveRange(card.PhoneNumbers);
        _dbContext.ImportedBusinessCardEmails.RemoveRange(card.EmailAddresses);

        // Add updated phone numbers
        var newPhones = new List<ImportedBusinessCardPhone>();
        foreach (var phoneDto in request.PhoneNumbers)
        {
            if (string.IsNullOrWhiteSpace(phoneDto.Number)) continue;
            newPhones.Add(new ImportedBusinessCardPhone
            {
                ImportedBusinessCardId = card.Id,
                Number = phoneDto.Number.Trim(),
                NormalizedNumber = ContactNormalizationHelper.NormalizePhone(phoneDto.Number),
                Label = phoneDto.Label?.Trim()
            });
        }
        await _dbContext.ImportedBusinessCardPhones.AddRangeAsync(newPhones);
        card.PhoneNumbers = newPhones;

        // Add updated email addresses
        var newEmails = new List<ImportedBusinessCardEmail>();
        foreach (var emailDto in request.EmailAddresses)
        {
            if (string.IsNullOrWhiteSpace(emailDto.Email)) continue;
            newEmails.Add(new ImportedBusinessCardEmail
            {
                ImportedBusinessCardId = card.Id,
                Email = emailDto.Email.Trim(),
                NormalizedEmail = ContactNormalizationHelper.NormalizeEmail(emailDto.Email),
                Label = emailDto.Label?.Trim()
            });
        }
        await _dbContext.ImportedBusinessCardEmails.AddRangeAsync(newEmails);
        card.EmailAddresses = newEmails;

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation(
            "User {UserId} updated imported business card {CardId}",
            ownerUserId, card.Id);

        return MapToResponse(card);
    }

    public async Task<bool> DeleteContactAsync(string ownerUserId, Guid id)
    {
        var card = await _dbContext.ImportedBusinessCards
            .Where(c => c.Id == id && c.OwnerUserId == ownerUserId)
            .FirstOrDefaultAsync();

        if (card == null) return false;

        _dbContext.ImportedBusinessCards.Remove(card);
        await _dbContext.SaveChangesAsync();

        _logger.LogInformation(
            "User {UserId} deleted imported business card {CardId}",
            ownerUserId, id);

        return true;
    }

    private static ImportedContactResponse MapToResponse(ImportedBusinessCard card)
    {
        return new ImportedContactResponse
        {
            Id = card.Id,
            FullName = card.FullName,
            Company = card.Company,
            JobTitle = card.JobTitle,
            Website = card.Website,
            Address = card.Address,
            CreatedAtUtc = card.CreatedAtUtc,
            UpdatedAtUtc = card.UpdatedAtUtc,
            PhoneNumbers = card.PhoneNumbers.Select(p => new ImportedContactPhoneResponse
            {
                Id = p.Id,
                Number = p.Number,
                NormalizedNumber = p.NormalizedNumber,
                Label = p.Label
            }).ToList(),
            EmailAddresses = card.EmailAddresses.Select(e => new ImportedContactEmailResponse
            {
                Id = e.Id,
                Email = e.Email,
                NormalizedEmail = e.NormalizedEmail,
                Label = e.Label
            }).ToList(),
        };
    }
}
