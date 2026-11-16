using DigitalShare.Api.DTOs.ImportedContacts;

namespace DigitalShare.Api.Services;

public interface IImportedContactService
{
    Task<CheckDuplicateResponse> CheckDuplicateAsync(string ownerUserId, CheckDuplicateRequest request);
    Task<ImportedContactResponse> SaveContactAsync(string ownerUserId, SaveImportedContactRequest request) => SaveContactAsync(ownerUserId, request, null);
    Task<ImportedContactResponse> SaveContactAsync(string ownerUserId, SaveImportedContactRequest request, string? clientRequestId);
    Task<IEnumerable<ImportedContactResponse>> GetContactsAsync(string ownerUserId);
    Task<ImportedContactResponse?> GetContactByIdAsync(string ownerUserId, Guid id);
    Task<ImportedContactResponse?> UpdateContactAsync(string ownerUserId, Guid id, UpdateImportedContactRequest request);
    Task<ImportedContactResponse?> UpdateRemarkAsync(string ownerUserId, Guid id, string? remark);
    Task<ImportedContactResponse?> ClearRemarkAsync(string ownerUserId, Guid id);
    Task<bool> DeleteContactAsync(string ownerUserId, Guid id);
}
