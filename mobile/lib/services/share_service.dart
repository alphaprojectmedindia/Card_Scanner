import '../config/api_config.dart';
import '../models/shared_profile.dart';
import 'api_client.dart';

class ShareService {
  final ApiClient _apiClient;

  ShareService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// Fetches a publicly shared digital card by its permanent ShareId.
  /// Does not require authentication.
  Future<SharedProfile> getSharedProfile(String shareId) async {
    final response = await _apiClient.get(
      ApiConfig.getShareEndpoint(shareId),
      requiresAuth: false,
    );

    return SharedProfile.fromJson(response as Map<String, dynamic>);
  }
}
