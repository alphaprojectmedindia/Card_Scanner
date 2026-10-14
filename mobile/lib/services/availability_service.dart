import '../config/api_config.dart';
import '../models/availability_settings.dart';
import '../models/public_availability.dart';
import 'api_client.dart';

class AvailabilityService {
  final ApiClient _apiClient;

  AvailabilityService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// Retrieve the authenticated user's availability settings and weekly slots.
  Future<AvailabilitySettings> getAvailability() async {
    final response = await _apiClient.get(
      ApiConfig.availabilityMeEndpoint,
      requiresAuth: true,
    );

    if (response is Map<String, dynamic>) {
      return AvailabilitySettings.fromJson(response);
    }

    throw ApiException("Couldn't load availability.");
  }

  /// Update the authenticated user's availability settings and weekly slots.
  Future<AvailabilitySettings> updateAvailability(
      AvailabilitySettings settings) async {
    final response = await _apiClient.put(
      ApiConfig.availabilityMeEndpoint,
      body: settings.toJson(),
      requiresAuth: true,
    );

    if (response is Map<String, dynamic>) {
      return AvailabilitySettings.fromJson(response);
    }

    throw ApiException('Failed to save availability settings.');
  }

  /// Retrieve a connected user's public availability schedule.
  Future<PublicAvailability> getUserAvailability(String userId) async {
    final response = await _apiClient.get(
      ApiConfig.availabilityUserEndpoint(userId.trim()),
      requiresAuth: true,
    );

    if (response is Map<String, dynamic>) {
      return PublicAvailability.fromJson(response);
    }

    throw ApiException("Couldn't load availability.");
  }
}
