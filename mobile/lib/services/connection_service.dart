import '../config/api_config.dart';
import '../models/saved_connection.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

class ConnectionService {
  final ApiClient _apiClient;
  final SecureStorageService _storageService;

  ConnectionService({ApiClient? apiClient, SecureStorageService? storageService})
      : _storageService = storageService ?? SecureStorageService(),
        _apiClient = apiClient ?? ApiClient(storageService: storageService);

  /// Loads locally cached connections count immediately for offline dashboard rendering.
  Future<int> getCachedConnectionsCount() async {
    try {
      return await _storageService.getCachedConnectionsCount();
    } catch (_) {
      return 0;
    }
  }

  /// Save another user's shared profile to the authenticated user's in-app connections.
  Future<SavedConnection> saveConnection(String shareId) async {
    final response = await _apiClient.post(
      ApiConfig.connectionsEndpoint,
      body: {'shareId': shareId.trim()},
      requiresAuth: true,
    );

    if (response is Map<String, dynamic>) {
      return SavedConnection.fromJson(response);
    }

    throw ApiException('Unexpected response from server while saving connection.');
  }

  /// Retrieve all in-app connections saved by the authenticated user, newest first.
  /// On success, caches connection count locally for offline viewing.
  Future<List<SavedConnection>> getConnections() async {
    final response = await _apiClient.get(
      ApiConfig.connectionsEndpoint,
      requiresAuth: true,
      timeout: const Duration(seconds: 10),
    );

    if (response is List) {
      final list = response
          .map((item) => SavedConnection.fromJson(item as Map<String, dynamic>))
          .toList();
      try {
        await _storageService.saveCachedConnectionsCount(list.length);
      } catch (_) {}
      return list;
    }

    return [];
  }

  /// Remove a saved connection by the contact's ShareId.
  Future<void> deleteConnection(String shareId) async {
    await _apiClient.delete(
      ApiConfig.deleteConnectionEndpoint(shareId.trim()),
      requiresAuth: true,
    );
  }
}
