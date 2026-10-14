import '../config/api_config.dart';
import '../models/saved_connection.dart';
import 'api_client.dart';

class ConnectionService {
  final ApiClient _apiClient;

  ConnectionService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

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
  Future<List<SavedConnection>> getConnections() async {
    final response = await _apiClient.get(
      ApiConfig.connectionsEndpoint,
      requiresAuth: true,
    );

    if (response is List) {
      return response
          .map((item) => SavedConnection.fromJson(item as Map<String, dynamic>))
          .toList();
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
