import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:digital_share/services/location/location_service.dart';

Position createTestPosition({
  double latitude = 13.0827,
  double longitude = 80.2707,
  double accuracy = 5.0,
  DateTime? timestamp,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp ?? DateTime.now(),
    accuracy: accuracy,
    altitude: 10.0,
    altitudeAccuracy: 1.0,
    heading: 0.0,
    headingAccuracy: 1.0,
    speed: 0.0,
    speedAccuracy: 0.0,
  );
}

void main() {
  group('GeolocatorCurrentLocationProvider Unit Tests', () {
    test('1. Returns servicesDisabled when location service is turned off', () async {
      int checkPermissionCalls = 0;
      final provider = GeolocatorCurrentLocationProvider(
        isLocationServiceEnabledFn: () async => false,
        checkPermissionFn: () async {
          checkPermissionCalls++;
          return LocationPermission.whileInUse;
        },
      );

      final result = await provider.getCurrentLocation();
      expect(result.status, equals(CurrentLocationStatus.servicesDisabled));
      expect(result.message, equals('Location services are turned off.'));
      expect(checkPermissionCalls, equals(0)); // Did not check permission when service is disabled
    });

    test('2. Requests permission if denied, returns permissionDenied if user denies', () async {
      int requestPermissionCalls = 0;
      final provider = GeolocatorCurrentLocationProvider(
        isLocationServiceEnabledFn: () async => true,
        checkPermissionFn: () async => LocationPermission.denied,
        requestPermissionFn: () async {
          requestPermissionCalls++;
          return LocationPermission.denied;
        },
      );

      final result = await provider.getCurrentLocation();
      expect(result.status, equals(CurrentLocationStatus.permissionDenied));
      expect(result.message, contains('Location permission was denied'));
      expect(requestPermissionCalls, equals(1));
    });

    test('3. Returns permissionPermanentlyDenied immediately if deniedForever without re-prompting', () async {
      int requestPermissionCalls = 0;
      final provider = GeolocatorCurrentLocationProvider(
        isLocationServiceEnabledFn: () async => true,
        checkPermissionFn: () async => LocationPermission.deniedForever,
        requestPermissionFn: () async {
          requestPermissionCalls++;
          return LocationPermission.deniedForever;
        },
      );

      final result = await provider.getCurrentLocation();
      expect(result.status, equals(CurrentLocationStatus.permissionPermanentlyDenied));
      expect(result.message, contains('permanently denied'));
      expect(requestPermissionCalls, equals(0)); // Never prompts system dialog when permanently denied
    });

    test('4. Returns permissionPermanentlyDenied if requestPermission returns deniedForever', () async {
      int requestPermissionCalls = 0;
      final provider = GeolocatorCurrentLocationProvider(
        isLocationServiceEnabledFn: () async => true,
        checkPermissionFn: () async => LocationPermission.denied,
        requestPermissionFn: () async {
          requestPermissionCalls++;
          return LocationPermission.deniedForever;
        },
      );

      final result = await provider.getCurrentLocation();
      expect(result.status, equals(CurrentLocationStatus.permissionPermanentlyDenied));
      expect(requestPermissionCalls, equals(1));
    });

    test('5. Returns success with exact latitude/longitude when permission granted', () async {
      final pos = createTestPosition(latitude: 37.7749, longitude: -122.4194, accuracy: 4.5);
      final provider = GeolocatorCurrentLocationProvider(
        isLocationServiceEnabledFn: () async => true,
        checkPermissionFn: () async => LocationPermission.whileInUse,
        getCurrentPositionFn: ({desiredAccuracy, timeLimit}) async => pos,
      );

      final result = await provider.getCurrentLocation();
      expect(result.status, equals(CurrentLocationStatus.success));
      expect(result.latitude, closeTo(37.7749, 0.0001));
      expect(result.longitude, closeTo(-122.4194, 0.0001));
      expect(result.accuracy, closeTo(4.5, 0.0001));
      expect(result.timestamp, isNotNull);
    });

    test('6. Approximate location (coarse accuracy) is accepted without rejection', () async {
      // Coarse location accuracy (e.g. 500 meters)
      final pos = createTestPosition(latitude: 40.7128, longitude: -74.0060, accuracy: 500.0);
      final provider = GeolocatorCurrentLocationProvider(
        isLocationServiceEnabledFn: () async => true,
        checkPermissionFn: () async => LocationPermission.whileInUse,
        getCurrentPositionFn: ({desiredAccuracy, timeLimit}) async => pos,
      );

      final result = await provider.getCurrentLocation();
      expect(result.status, equals(CurrentLocationStatus.success));
      expect(result.latitude, closeTo(40.7128, 0.0001));
      expect(result.longitude, closeTo(-74.0060, 0.0001));
      expect(result.accuracy, equals(500.0));
    });

    test('7. Fresh position timeout falls back to recent cached position within maxStaleAge', () async {
      final cachedPos = createTestPosition(
        latitude: 51.5074,
        longitude: -0.1278,
        timestamp: DateTime.now().subtract(const Duration(minutes: 3)), // 3 mins old (fresh)
      );

      final provider = GeolocatorCurrentLocationProvider(
        isLocationServiceEnabledFn: () async => true,
        checkPermissionFn: () async => LocationPermission.whileInUse,
        getCurrentPositionFn: ({desiredAccuracy, timeLimit}) async {
          throw TimeoutException('GPS timeout');
        },
        getLastKnownPositionFn: () async => cachedPos,
        maxStaleAge: const Duration(minutes: 10),
      );

      final result = await provider.getCurrentLocation();
      expect(result.status, equals(CurrentLocationStatus.success));
      expect(result.latitude, closeTo(51.5074, 0.0001));
      expect(result.longitude, closeTo(-0.1278, 0.0001));
      expect(result.message, contains('recent location fix'));
    });

    test('8. Fresh position timeout rejects very stale cached position', () async {
      final stalePos = createTestPosition(
        latitude: 51.5074,
        longitude: -0.1278,
        timestamp: DateTime.now().subtract(const Duration(hours: 2)), // 2 hours old (stale)
      );

      final provider = GeolocatorCurrentLocationProvider(
        isLocationServiceEnabledFn: () async => true,
        checkPermissionFn: () async => LocationPermission.whileInUse,
        getCurrentPositionFn: ({desiredAccuracy, timeLimit}) async {
          throw TimeoutException('GPS timeout');
        },
        getLastKnownPositionFn: () async => stalePos,
        maxStaleAge: const Duration(minutes: 10),
      );

      final result = await provider.getCurrentLocation();
      expect(result.status, equals(CurrentLocationStatus.timeout));
      expect(result.message, contains('timed out'));
    });

    test('9. Fresh position timeout with no cached position returns timeout', () async {
      final provider = GeolocatorCurrentLocationProvider(
        isLocationServiceEnabledFn: () async => true,
        checkPermissionFn: () async => LocationPermission.whileInUse,
        getCurrentPositionFn: ({desiredAccuracy, timeLimit}) async {
          throw TimeoutException('GPS timeout');
        },
        getLastKnownPositionFn: () async => null,
      );

      final result = await provider.getCurrentLocation();
      expect(result.status, equals(CurrentLocationStatus.timeout));
      expect(result.message, contains('timed out'));
    });

    test('10. Catches unexpected exceptions and returns unavailable', () async {
      final provider = GeolocatorCurrentLocationProvider(
        isLocationServiceEnabledFn: () async => throw Exception('Hardware failure'),
      );

      final result = await provider.getCurrentLocation();
      expect(result.status, equals(CurrentLocationStatus.unavailable));
      expect(result.message, contains('Hardware failure'));
    });

    test('11. openAppSettings and openLocationSettings delegates execute cleanly', () async {
      bool appSettingsOpened = false;
      bool locationSettingsOpened = false;

      final provider = GeolocatorCurrentLocationProvider(
        openAppSettingsFn: () async {
          appSettingsOpened = true;
          return true;
        },
        openLocationSettingsFn: () async {
          locationSettingsOpened = true;
          return true;
        },
      );

      expect(await provider.openAppSettings(), isTrue);
      expect(appSettingsOpened, isTrue);

      expect(await provider.openLocationSettings(), isTrue);
      expect(locationSettingsOpened, isTrue);
    });
  });
}
