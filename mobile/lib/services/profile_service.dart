import 'dart:convert';
import '../config/api_config.dart';
import '../models/update_profile_request.dart';
import '../models/user_profile.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

class ProfileService {
  final ApiClient _apiClient;
  final SecureStorageService _storageService;

  ProfileService({ApiClient? apiClient, SecureStorageService? storageService})
      : _storageService = storageService ?? SecureStorageService(),
        _apiClient = apiClient ?? ApiClient(storageService: storageService);

  /// Loads the locally cached user profile immediately for offline rendering.
  /// If no complete profile is cached, synthesizes a fallback profile using
  /// stored authentication credentials (userId and email).
  Future<UserProfile?> getCachedProfile() async {
    try {
      final jsonStr = await _storageService.getCachedProfile();
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return UserProfile.fromJson(map);
      }

      // Offline fallback: synthesize profile from locally stored auth user info
      final userId = await _storageService.getUserId();
      final email = await _storageService.getUserEmail();
      if (userId != null && email != null) {
        return UserProfile(
          id: userId,
          userId: userId,
          shareId: '',
          email: email,
          createdAtUtc: DateTime.now().toUtc(),
          updatedAtUtc: DateTime.now().toUtc(),
        );
      }
    } catch (_) {}
    return null;
  }

  /// Retrieves the current user's profile from the backend.
  /// On success, automatically persists it to local storage.
  /// On network or timeout failure, falls back to the locally cached profile.
  Future<UserProfile> getMyProfile() async {
    try {
      final response = await _apiClient.get(
        ApiConfig.profileMeEndpoint,
        requiresAuth: true,
        timeout: const Duration(seconds: 10),
      );

      final profile = UserProfile.fromJson(response as Map<String, dynamic>);
      await _cacheProfile(profile);
      return profile;
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      final cached = await getCachedProfile();
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  Future<void> _cacheProfile(UserProfile profile) async {
    try {
      await _storageService.saveCachedProfile(jsonEncode(profile.toJson()));
    } catch (_) {}
  }

  Future<UserProfile> updateMyProfile(UpdateProfileRequest request) async {
    final response = await _apiClient.put(
      ApiConfig.profileMeEndpoint,
      body: request.toJson(),
      requiresAuth: true,
    );

    final profile = UserProfile.fromJson(response as Map<String, dynamic>);
    await _cacheProfile(profile);
    return profile;
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

    final profile = UserProfile.fromJson(response as Map<String, dynamic>);
    await _cacheProfile(profile);
    return profile;
  }

  /// Retrieves the user's account visibility (true = Public, false = Private).
  Future<bool> getVisibility() async {
    final response = await _apiClient.get(
      ApiConfig.profileVisibilityEndpoint,
      requiresAuth: true,
    );
    if (response is Map<String, dynamic> && response.containsKey('isPublic')) {
      return response['isPublic'] as bool? ?? false;
    }
    return false;
  }

  /// Updates the user's account visibility.
  Future<bool> updateVisibility(bool isPublic) async {
    final response = await _apiClient.put(
      ApiConfig.profileVisibilityEndpoint,
      body: {'isPublic': isPublic},
      requiresAuth: true,
    );
    if (response is Map<String, dynamic> && response.containsKey('isPublic')) {
      return response['isPublic'] as bool? ?? isPublic;
    }
    return isPublic;
  }

  /// Searches publicly visible profiles by query. Private profiles are excluded by the backend.
  Future<List<Map<String, dynamic>>> searchPublicProfiles(String query, {int limit = 20}) async {
    final uri = Uri.parse(ApiConfig.profileSearchEndpoint).replace(queryParameters: {
      'q': query,
      'limit': limit.toString(),
    });
    final response = await _apiClient.get(
      uri.toString(),
      requiresAuth: true,
    );
    if (response is List) {
      return response.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
    return [];
  }
}
