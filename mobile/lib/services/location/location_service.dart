import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'geolocator_current_location_provider.dart';

export 'geolocator_current_location_provider.dart';

/// Status for obtaining device current location.
enum CurrentLocationStatus {
  success,
  permissionDenied,
  permissionPermanentlyDenied,
  servicesDisabled,
  timeout,
  unavailable,
}

/// Result returned from requesting device current location.
class CurrentLocationResult {
  final CurrentLocationStatus status;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final String? message;
  final DateTime? timestamp;

  const CurrentLocationResult({
    required this.status,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.message,
    this.timestamp,
  });
}

/// Pluggable provider for fetching the device's current location fix.
abstract class CurrentLocationProvider {
  Future<CurrentLocationResult> getCurrentLocation();
  Future<bool> openAppSettings() async => false;
  Future<bool> openLocationSettings() async => false;
}

/// Default provider used when no native geolocator package is installed.
class DefaultCurrentLocationProvider implements CurrentLocationProvider {
  const DefaultCurrentLocationProvider();

  @override
  Future<CurrentLocationResult> getCurrentLocation() async {
    return const CurrentLocationResult(
      status: CurrentLocationStatus.unavailable,
      message:
          'Device GPS integration is not configured. Please search or select your location on the map.',
    );
  }

  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;
}

/// Structured location search result.
class LocationSearchResult {
  final String placeName;
  final String formattedAddress;
  final double latitude;
  final double longitude;

  const LocationSearchResult({
    required this.placeName,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
  });

  @override
  String toString() => '$placeName ($latitude, $longitude)';
}

/// Pure, robust service for searching places, reverse geocoding, and obtaining location.
class LocationService {
  final http.Client? httpClient;
  final CurrentLocationProvider _currentLocationProvider;

  LocationService({
    this.httpClient,
    CurrentLocationProvider? currentLocationProvider,
  })  : _currentLocationProvider = currentLocationProvider ??
            const GeolocatorCurrentLocationProvider();

  /// Opens the device settings for the application.
  Future<bool> openAppSettings() => _currentLocationProvider.openAppSettings();

  /// Opens the device location/GPS settings.
  Future<bool> openLocationSettings() =>
      _currentLocationProvider.openLocationSettings();

  /// Searches for places/addresses using OpenStreetMap Nominatim.
  Future<List<LocationSearchResult>> searchPlaces(
    String query, {
    http.Client? client,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    final activeClient = client ?? httpClient ?? http.Client();
    final shouldCloseClient = client == null && httpClient == null;

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(cleanQuery)}&format=json&limit=5&addressdetails=1',
      );

      final response = await activeClient
          .get(
            uri,
            headers: const {
              'User-Agent': 'DigitalShare/1.0 (mobile-app)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return const [];
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];

      final results = <LocationSearchResult>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;

        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lon = double.tryParse(item['lon']?.toString() ?? '');
        if (lat == null || lon == null) continue;
        if (lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0) continue;

        final rawName = item['name']?.toString().trim();
        final rawDisplay = item['display_name']?.toString().trim() ?? '';

        final placeName = (rawName != null && rawName.isNotEmpty)
            ? rawName
            : (rawDisplay.isNotEmpty
                ? rawDisplay.split(',').first.trim()
                : 'Location');

        results.add(
          LocationSearchResult(
            placeName: placeName,
            formattedAddress: rawDisplay,
            latitude: lat,
            longitude: lon,
          ),
        );
      }

      return results;
    } catch (_) {
      return const [];
    } finally {
      if (shouldCloseClient) {
        activeClient.close();
      }
    }
  }

  /// Reverse geocodes coordinates to a human-readable place name and address.
  Future<LocationSearchResult?> reverseGeocode(
    double latitude,
    double longitude, {
    http.Client? client,
  }) async {
    if (latitude < -90.0 ||
        latitude > 90.0 ||
        longitude < -180.0 ||
        longitude > 180.0) {
      return null;
    }

    final activeClient = client ?? httpClient ?? http.Client();
    final shouldCloseClient = client == null && httpClient == null;

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$latitude&lon=$longitude&format=json&addressdetails=1',
      );

      final response = await activeClient
          .get(
            uri,
            headers: const {
              'User-Agent': 'DigitalShare/1.0 (mobile-app)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return null;
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final rawName = decoded['name']?.toString().trim();
      final rawDisplay = decoded['display_name']?.toString().trim() ?? '';

      final placeName = (rawName != null && rawName.isNotEmpty)
          ? rawName
          : (rawDisplay.isNotEmpty
              ? rawDisplay.split(',').first.trim()
              : 'Selected Location');

      return LocationSearchResult(
        placeName: placeName,
        formattedAddress: rawDisplay,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (_) {
      return null;
    } finally {
      if (shouldCloseClient) {
        activeClient.close();
      }
    }
  }

  /// Requests the single current location fix safely.
  Future<CurrentLocationResult> getCurrentLocation() async {
    try {
      return await _currentLocationProvider
          .getCurrentLocation()
          .timeout(const Duration(seconds: 16));
    } on TimeoutException {
      return const CurrentLocationResult(
        status: CurrentLocationStatus.timeout,
        message: 'Location request timed out. Please select from the map.',
      );
    } catch (e) {
      return CurrentLocationResult(
        status: CurrentLocationStatus.unavailable,
        message: 'Unable to get location: $e',
      );
    }
  }
}
