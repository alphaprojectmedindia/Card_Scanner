import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';

/// Concrete [CurrentLocationProvider] implementation powered by device GPS
/// via the maintained [geolocator] package.
class GeolocatorCurrentLocationProvider implements CurrentLocationProvider {
  final Future<bool> Function() isLocationServiceEnabledFn;
  final Future<LocationPermission> Function() checkPermissionFn;
  final Future<LocationPermission> Function() requestPermissionFn;
  final Future<Position> Function({
    LocationAccuracy? desiredAccuracy,
    Duration? timeLimit,
  }) getCurrentPositionFn;
  final Future<Position?> Function() getLastKnownPositionFn;
  final Future<bool> Function() openAppSettingsFn;
  final Future<bool> Function() openLocationSettingsFn;
  final Duration timeout;
  final Duration maxStaleAge;

  const GeolocatorCurrentLocationProvider({
    this.isLocationServiceEnabledFn = Geolocator.isLocationServiceEnabled,
    this.checkPermissionFn = Geolocator.checkPermission,
    this.requestPermissionFn = Geolocator.requestPermission,
    this.getCurrentPositionFn = _defaultGetCurrentPosition,
    this.getLastKnownPositionFn = Geolocator.getLastKnownPosition,
    this.openAppSettingsFn = Geolocator.openAppSettings,
    this.openLocationSettingsFn = Geolocator.openLocationSettings,
    this.timeout = const Duration(seconds: 12),
    this.maxStaleAge = const Duration(minutes: 10),
  });

  static Future<Position> _defaultGetCurrentPosition({
    LocationAccuracy? desiredAccuracy,
    Duration? timeLimit,
  }) {
    return Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: desiredAccuracy ?? LocationAccuracy.high,
        timeLimit: timeLimit,
      ),
    );
  }

  @override
  Future<CurrentLocationResult> getCurrentLocation() async {
    try {
      // 1. Verify device location services are enabled
      final isServiceEnabled = await isLocationServiceEnabledFn();
      if (!isServiceEnabled) {
        return const CurrentLocationResult(
          status: CurrentLocationStatus.servicesDisabled,
          message: 'Location services are turned off.',
        );
      }

      // 2. Check current permission status
      var permission = await checkPermissionFn();

      // If denied (first time or not yet granted), request permission
      if (permission == LocationPermission.denied) {
        permission = await requestPermissionFn();
      }

      if (permission == LocationPermission.denied) {
        return const CurrentLocationResult(
          status: CurrentLocationStatus.permissionDenied,
          message:
              'Location permission was denied. You can search, pick a location from the map, or enter coordinates manually.',
        );
      }

      if (permission == LocationPermission.deniedForever) {
        return const CurrentLocationResult(
          status: CurrentLocationStatus.permissionPermanentlyDenied,
          message:
              'Location permission is permanently denied. You can select your location on the map.',
        );
      }

      // 3. Permission granted (whileInUse, always, fine or approximate/coarse)
      // Request ONE single current location fix
      try {
        final position = await getCurrentPositionFn(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: timeout,
        );

        return CurrentLocationResult(
          status: CurrentLocationStatus.success,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          timestamp: position.timestamp,
        );
      } on TimeoutException {
        // Fallback: If fresh fix times out, check if a recent known position is available
        try {
          final lastKnown = await getLastKnownPositionFn();
          if (lastKnown != null) {
            final age = DateTime.now().difference(lastKnown.timestamp);
            if (age >= Duration.zero && age <= maxStaleAge) {
              return CurrentLocationResult(
                status: CurrentLocationStatus.success,
                latitude: lastKnown.latitude,
                longitude: lastKnown.longitude,
                accuracy: lastKnown.accuracy,
                timestamp: lastKnown.timestamp,
                message: 'Using recent location fix.',
              );
            }
          }
        } catch (_) {
          // Ignore cache fetch error and proceed to timeout result
        }

        return const CurrentLocationResult(
          status: CurrentLocationStatus.timeout,
          message:
              'Location request timed out. Please pick a location from the map.',
        );
      }
    } catch (e) {
      return CurrentLocationResult(
        status: CurrentLocationStatus.unavailable,
        message: 'Unable to get location: $e',
      );
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await openAppSettingsFn();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await openLocationSettingsFn();
    } catch (_) {
      return false;
    }
  }
}
