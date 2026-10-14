import '../config/api_config.dart';
import '../models/update_profile_request.dart';
import '../models/user_profile.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

class ProfileService {
  final ApiClient _apiClient;

  ProfileService({ApiClient? apiClient, SecureStorageService? storageService})
      : _apiClient = apiClient ?? ApiClient(storageService: storageService);

  Future<UserProfile> getMyProfile() async {
    final response = await _apiClient.get(
      ApiConfig.profileMeEndpoint,
      requiresAuth: true,
    );

    return UserProfile.fromJson(response as Map<String, dynamic>);
  }

  Future<UserProfile> updateMyProfile(UpdateProfileRequest request) async {
    final response = await _apiClient.put(
      ApiConfig.profileMeEndpoint,
      body: request.toJson(),
      requiresAuth: true,
    );

    return UserProfile.fromJson(response as Map<String, dynamic>);
  }

  Future<UserProfile> uploadProfilePhoto({
    String? filePath,
    List<int>? fileBytes,
    String? filename,
    String contentType = 'image/jpeg',
  }) async {
    final response = await _apiClient.postMultipart(
      ApiConfig.uploadProfilePhotoEndpoint,
      fieldName: 'file',
      filePath: filePath,
      fileBytes: fileBytes,
      filename: filename,
      contentType: contentType,
      requiresAuth: true,
    );

    return UserProfile.fromJson(response as Map<String, dynamic>);
  }
}
