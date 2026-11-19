using DigitalShare.Api.Data;
using DigitalShare.Api.DTOs.ImportedContacts;
using DigitalShare.Api.Exceptions;
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

    public Task<ImportedContactResponse> SaveContactAsync(
        string ownerUserId,
        SaveImportedContactRequest request) => SaveContactAsync(ownerUserId, request, null);

    public async Task<ImportedContactResponse> SaveContactAsync(
        string ownerUserId,
        SaveImportedContactRequest request,
        string? clientRequestId)
    {
        var normalizedClientRequestId = string.IsNullOrWhiteSpace(clientRequestId)
            ? null
            : clientRequestId.Trim();

        string? payloadHash = null;
        if (normalizedClientRequestId != null)
        {
            payloadHash = ContactNormalizationHelper.ComputePayloadHash(request);

            var existingCard = await _dbContext.ImportedBusinessCards
                .Include(c => c.PhoneNumbers)
                .Include(c => c.EmailAddresses)
                .FirstOrDefaultAsync(c => c.OwnerUserId == ownerUserId && c.ClientRequestId == normalizedClientRequestId);

            if (existingCard != null)
            {
                if (existingCard.RequestPayloadHash != payloadHash)
                {
                    _logger.LogWarning(
                        "Idempotency conflict for user {UserId} with clientRequestId {ClientRequestId}",
                        ownerUserId, normalizedClientRequestId);
                    throw new IdempotencyConflictException("Idempotency key has already been used with a different request payload.");
                }

                _logger.LogInformation(
                    "Idempotent hit for user {UserId} with clientRequestId {ClientRequestId}, returning card {CardId}",
                    ownerUserId, normalizedClientRequestId, existingCard.Id);
                return MapToResponse(existingCard);
            }
        }

        var effectiveMemory = !string.IsNullOrWhiteSpace(request.RememberThisContact)
            ? request.RememberThisContact.Trim()
            : (!string.IsNullOrWhiteSpace(request.PersonalRemark) ? request.PersonalRemark.Trim() : null);

        var card = new ImportedBusinessCard
        {
            OwnerUserId = ownerUserId,
            ClientRequestId = normalizedClientRequestId,
            RequestPayloadHash = payloadHash,
            FullName = request.FullName?.Trim(),
            Company = request.Company?.Trim(),
            JobTitle = request.JobTitle?.Trim(),
            Website = request.Website?.Trim(),
            Address = request.Address?.Trim(),
            RememberThisContact = effectiveMemory,
            PersonalRemark = effectiveMemory,
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

        try
        {
            await _dbContext.SaveChangesAsync();
        }
        catch (DbUpdateException ex)
        {
            if (normalizedClientRequestId != null)
            {
                // In case of a race condition between two concurrent requests with the same clientRequestId
                var concurrentWinner = await _dbContext.ImportedBusinessCards
                    .AsNoTracking()
                    .Include(c => c.PhoneNumbers)
                    .Include(c => c.EmailAddresses)
                    .FirstOrDefaultAsync(c => c.OwnerUserId == ownerUserId && c.ClientRequestId == normalizedClientRequestId);

                if (concurrentWinner != null)
                {
                    if (concurrentWinner.RequestPayloadHash != payloadHash)
                    {
                        _logger.LogWarning(
                            "Concurrent race idempotency conflict for user {UserId} with clientRequestId {ClientRequestId}",
                            ownerUserId, normalizedClientRequestId);
                        throw new IdempotencyConflictException("Idempotency key has already been used with a different request payload.");
                    }

                    _logger.LogInformation(
                        "Concurrent race resolved: user {UserId} with clientRequestId {ClientRequestId} returning card {CardId}",
                        ownerUserId, normalizedClientRequestId, concurrentWinner.Id);
                    return MapToResponse(concurrentWinner);
                }
            }

            _logger.LogError(ex, "Error occurred while saving imported contact for user {UserId}", ownerUserId);
            throw;
        }

        _logger.LogInformation(
            "User {UserId} saved imported business card {CardId}",
            ownerUserId, card.Id);

        return MapToResponse(card);
    }

    public async Task<IEnumerable<ImportedContactResponse>> GetContactsAsync(string ownerUserId, string? search = null)
    {
        var query = _dbContext.ImportedBusinessCards
            .AsNoTracking()
            .Where(c => c.OwnerUserId == ownerUserId);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var trimmedSearch = search.Trim();
            if (_dbContext.Database.IsRelational())
            {
                var pattern = $"%{trimmedSearch}%";
                query = query.Where(c =>
                    (c.FullName != null && EF.Functions.Like(c.FullName, pattern)) ||
                    (c.Company != null && EF.Functions.Like(c.Company, pattern)) ||
                    (c.JobTitle != null && EF.Functions.Like(c.JobTitle, pattern)) ||
                    (c.Address != null && EF.Functions.Like(c.Address, pattern)) ||
                    (c.RememberThisContact != null && EF.Functions.Like(c.RememberThisContact, pattern)) ||
                    (c.PersonalRemark != null && EF.Functions.Like(c.PersonalRemark, pattern)) ||
                    c.PhoneNumbers.Any(p => EF.Functions.Like(p.Number, pattern) || EF.Functions.Like(p.NormalizedNumber, pattern)) ||
                    c.EmailAddresses.Any(e => EF.Functions.Like(e.Email, pattern) || EF.Functions.Like(e.NormalizedEmail, pattern)));
            }
            else
            {
                var lower = trimmedSearch.ToLower();
                query = query.Where(c =>
                    (c.FullName != null && c.FullName.ToLower().Contains(lower)) ||
                    (c.Company != null && c.Company.ToLower().Contains(lower)) ||
                    (c.JobTitle != null && c.JobTitle.ToLower().Contains(lower)) ||
                    (c.Address != null && c.Address.ToLower().Contains(lower)) ||
                    (c.RememberThisContact != null && c.RememberThisContact.ToLower().Contains(lower)) ||
                    (c.PersonalRemark != null && c.PersonalRemark.ToLower().Contains(lower)) ||
                    c.PhoneNumbers.Any(p => p.Number.ToLower().Contains(lower) || p.NormalizedNumber.ToLower().Contains(lower)) ||
                    c.EmailAddresses.Any(e => e.Email.ToLower().Contains(lower) || e.NormalizedEmail.ToLower().Contains(lower)));
            }
        }

        var cards = await query
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
        if (request.RememberThisContact != null || request.PersonalRemark != null)
        {
            var memoryValue = request.RememberThisContact ?? request.PersonalRemark;
            var trimmedMemory = string.IsNullOrWhiteSpace(memoryValue) ? null : memoryValue.Trim();
            card.RememberThisContact = trimmedMemory;
            card.PersonalRemark = trimmedMemory;
        }
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

    public async Task<ImportedContactResponse?> UpdateMemoryAsync(string ownerUserId, Guid id, string? memory)
    {
        var card = await _dbContext.ImportedBusinessCards
            .Where(c => c.Id == id && c.OwnerUserId == ownerUserId)
            .Include(c => c.PhoneNumbers)
            .Include(c => c.EmailAddresses)
            .FirstOrDefaultAsync();

        if (card == null) return null;

        var trimmed = string.IsNullOrWhiteSpace(memory) ? null : memory.Trim();
        card.RememberThisContact = trimmed;
        card.PersonalRemark = trimmed;
        card.UpdatedAtUtc = DateTime.UtcNow;

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("User {UserId} updated memory on business card {CardId}", ownerUserId, id);

        return MapToResponse(card);
    }

    public Task<ImportedContactResponse?> ClearMemoryAsync(string ownerUserId, Guid id)
    {
        return UpdateMemoryAsync(ownerUserId, id, null);
    }

    public Task<ImportedContactResponse?> UpdateRemarkAsync(string ownerUserId, Guid id, string? remark)
    {
        return UpdateMemoryAsync(ownerUserId, id, remark);
    }

    public Task<ImportedContactResponse?> ClearRemarkAsync(string ownerUserId, Guid id)
    {
        return ClearMemoryAsync(ownerUserId, id);
    }

    public async Task<UnifiedContactsPagedResponse> GetUnifiedContactsAsync(
        string ownerUserId,
        string? search = null,
        string? source = null,
        int page = 1,
        int pageSize = 50)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var term = search?.Trim().ToLowerInvariant();
        var normalizedSource = source?.Trim().ToLowerInvariant();

        var unifiedList = new List<UnifiedContactResponse>();

        // 1. Fetch & Map Imported Business Cards
        if (string.IsNullOrEmpty(normalizedSource) || normalizedSource == "all" || normalizedSource == "businesscard")
        {
            var cardsQuery = _dbContext.ImportedBusinessCards
                .Where(c => c.OwnerUserId == ownerUserId)
                .Include(c => c.PhoneNumbers)
                .Include(c => c.EmailAddresses)
                .AsQueryable();

            if (!string.IsNullOrEmpty(term))
            {
                cardsQuery = cardsQuery.Where(c =>
                    (c.FullName != null && c.FullName.ToLower().Contains(term)) ||
                    (c.Company != null && c.Company.ToLower().Contains(term)) ||
                    (c.JobTitle != null && c.JobTitle.ToLower().Contains(term)) ||
                    (c.Address != null && c.Address.ToLower().Contains(term)) ||
                    (c.Website != null && c.Website.ToLower().Contains(term)) ||
                    (c.RememberThisContact != null && c.RememberThisContact.ToLower().Contains(term)) ||
                    (c.PersonalRemark != null && c.PersonalRemark.ToLower().Contains(term)) ||
                    c.PhoneNumbers.Any(p => p.Number.ToLower().Contains(term) || (p.NormalizedNumber != null && p.NormalizedNumber.Contains(term))) ||
                    c.EmailAddresses.Any(e => e.Email.ToLower().Contains(term) || (e.NormalizedEmail != null && e.NormalizedEmail.Contains(term)))
                );
            }

            var cards = await cardsQuery.ToListAsync();
            foreach (var c in cards)
            {
                var memory = c.RememberThisContact ?? c.PersonalRemark;
                unifiedList.Add(new UnifiedContactResponse
                {
                    Id = c.Id.ToString(),
                    Source = "BusinessCard",
                    FullName = c.FullName ?? "Unnamed Contact",
                    JobTitle = c.JobTitle,
                    Company = c.Company,
                    PhoneNumber = c.PhoneNumbers.FirstOrDefault()?.Number,
                    Email = c.EmailAddresses.FirstOrDefault()?.Email,
                    Address = c.Address,
                    Website = c.Website,
                    Remarks = memory,
                    ProfilePhotoUrl = null,
                    ShareId = null,
                    CreatedAtUtc = c.CreatedAtUtc
                });
            }
        }

        // 2. Fetch & Map QR Code Connections
        if (string.IsNullOrEmpty(normalizedSource) || normalizedSource == "all" || normalizedSource == "qrcodescan")
        {
            var connsQuery = _dbContext.Connections
                .Where(c => c.OwnerUserId == ownerUserId)
                .Include(c => c.SavedProfile)
                .AsQueryable();

            if (!string.IsNullOrEmpty(term))
            {
                connsQuery = connsQuery.Where(c =>
                    c.SavedProfile != null && (
                        (c.SavedProfile.FullName != null && c.SavedProfile.FullName.ToLower().Contains(term)) ||
                        (c.SavedProfile.Company != null && c.SavedProfile.Company.ToLower().Contains(term)) ||
                        (c.SavedProfile.JobTitle != null && c.SavedProfile.JobTitle.ToLower().Contains(term)) ||
                        (c.SavedProfile.Address != null && c.SavedProfile.Address.ToLower().Contains(term)) ||
                        (c.SavedProfile.Website != null && c.SavedProfile.Website.ToLower().Contains(term)) ||
                        (c.SavedProfile.PhoneNumber != null && c.SavedProfile.PhoneNumber.ToLower().Contains(term)) ||
                        (c.SavedProfile.Email != null && c.SavedProfile.Email.ToLower().Contains(term)) ||
                        (c.SavedProfile.ShareId != null && c.SavedProfile.ShareId.ToLower().Contains(term)) ||
                        (c.SavedProfile.Bio != null && c.SavedProfile.Bio.ToLower().Contains(term))
                    )
                );
            }

            var conns = await connsQuery.ToListAsync();
            foreach (var conn in conns)
            {
                var profile = conn.SavedProfile;
                if (profile == null) continue;

                unifiedList.Add(new UnifiedContactResponse
                {
                    Id = conn.Id.ToString(),
                    Source = "QrCodeScan",
                    FullName = profile.FullName ?? "Digital Share User",
                    JobTitle = profile.JobTitle,
                    Company = profile.Company,
                    PhoneNumber = profile.PhoneNumber,
                    Email = profile.Email,
                    Address = profile.Address,
                    Website = profile.Website,
                    Remarks = null,
                    ProfilePhotoUrl = profile.ProfilePhotoUrl,
                    ShareId = profile.ShareId,
                    CreatedAtUtc = conn.CreatedAtUtc
                });
            }
        }

        var businessCardsCount = unifiedList.Count(x => x.Source == "BusinessCard");
        var qrConnectionsCount = unifiedList.Count(x => x.Source == "QrCodeScan");
        var totalCount = unifiedList.Count;

        // Sort newest first
        var pagedItems = unifiedList
            .OrderByDescending(x => x.CreatedAtUtc)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToList();

        return new UnifiedContactsPagedResponse
        {
            Items = pagedItems,
            TotalCount = totalCount,
            Page = page,
            PageSize = pageSize,
            BusinessCardsCount = businessCardsCount,
            QrConnectionsCount = qrConnectionsCount
        };
    }

    private static ImportedContactResponse MapToResponse(ImportedBusinessCard card)
    {
        var memory = card.RememberThisContact ?? card.PersonalRemark;
        return new ImportedContactResponse
        {
            Id = card.Id,
            ClientRequestId = card.ClientRequestId,
            FullName = card.FullName,
            Company = card.Company,
            JobTitle = card.JobTitle,
            Website = card.Website,
            Address = card.Address,
            RememberThisContact = memory,
            PersonalRemark = memory,
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
