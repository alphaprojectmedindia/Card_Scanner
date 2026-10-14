using DigitalShare.Api.DTOs.ImportedContacts;

namespace DigitalShare.Api.Services;

public interface IImportedContactService
{
    Task<CheckDuplicateResponse> CheckDuplicateAsync(string ownerUserId, CheckDuplicateRequest request);
    Task<ImportedContactResponse> SaveContactAsync(string ownerUserId, SaveImportedContactRequest request);
    Task<IEnumerable<ImportedContactResponse>> GetContactsAsync(string ownerUserId);
    Task<ImportedContactResponse?> GetContactByIdAsync(string ownerUserId, Guid id);
    Task<ImportedContactResponse?> UpdateContactAsync(string ownerUserId, Guid id, UpdateImportedContactRequest request);
    Task<bool> DeleteContactAsync(string ownerUserId, Guid id);
}
