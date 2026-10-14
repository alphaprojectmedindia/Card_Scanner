using DigitalShare.Api.DTOs.Connections;

namespace DigitalShare.Api.Services;

public interface IConnectionService
{
    Task<(bool Success, ConnectionResponse? Response, string? Error, int StatusCode)> SaveConnectionAsync(string ownerUserId, string shareId);
    Task<IEnumerable<ConnectionResponse>> GetConnectionsAsync(string ownerUserId);
    Task<bool> DeleteConnectionAsync(string ownerUserId, string shareId);
}
