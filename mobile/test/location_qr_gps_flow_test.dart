import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:digital_share/screens/scan/create_qr_screen.dart';
import 'package:digital_share/services/location/location_service.dart';
import 'package:digital_share/services/qr/qr_content_parser.dart';
import 'package:digital_share/models/qr/qr_content_type.dart';
import 'package:digital_share/models/qr/qr_scan_models.dart';

/// Mock provider that tracks invocation count and behavior for testing
class MockTrackingLocationProvider implements CurrentLocationProvider {
  int getCurrentLocationCalls = 0;
  int openAppSettingsCalls = 0;
  int openLocationSettingsCalls = 0;

  final CurrentLocationResult Function()? onGetCurrentLocation;
  final Completer<CurrentLocationResult>? delayedCompleter;

  MockTrackingLocationProvider({
    this.onGetCurrentLocation,
    this.delayedCompleter,
  });

  @override
  Future<CurrentLocationResult> getCurrentLocation() async {
    getCurrentLocationCalls++;
    if (delayedCompleter != null) {
      return delayedCompleter!.future;
    }
    if (onGetCurrentLocation != null) {
      return onGetCurrentLocation!();
    }
    return const CurrentLocationResult(
      status: CurrentLocationStatus.success,
      latitude: 13.0827,
      longitude: 80.2707,
    );
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalls++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    openLocationSettingsCalls++;
    return true;
  }
}

/// Fake LocationService instrumented for widget tests
class TrackingLocationService extends LocationService {
  final MockTrackingLocationProvider trackingProvider;
  final List<LocationSearchResult> searchResults;
  final LocationSearchResult? reverseGeocodeResult;
  final bool simulateReverseGeocodeFailure;
  int reverseGeocodeCalls = 0;
  int searchPlacesCalls = 0;

  TrackingLocationService({
    required this.trackingProvider,
    this.searchResults = const [],
    this.reverseGeocodeResult,
    this.simulateReverseGeocodeFailure = false,
  }) : super(currentLocationProvider: trackingProvider);

  @override
  Future<List<LocationSearchResult>> searchPlaces(
    String query, {
    http.Client? client,
  }) async {
    searchPlacesCalls++;
    return searchResults;
  }

  @override
  Future<LocationSearchResult?> reverseGeocode(
    double latitude,
    double longitude, {
    http.Client? client,
  }) async {
    reverseGeocodeCalls++;
    if (simulateReverseGeocodeFailure) {
      return null;
    }
    return reverseGeocodeResult ??
        LocationSearchResult(
          placeName: 'Reverse Geocoded Place',
          formattedAddress: '123 Main Street, City, Country',
          latitude: latitude,
          longitude: longitude,
        );
  }
}

Future<void> pumpQrScreen(
  WidgetTester tester, {
  LocationService? locationService,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: CreateQrScreen(locationService: locationService),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> selectLocationType(WidgetTester tester) async {
  final chipFinder = find.byKey(const Key('create_type_location'));
  await tester.ensureVisible(chipFinder);
  await tester.tap(chipFinder);
  await tester.pumpAndSettle();
}

void main() {
  group('Location QR & Device GPS Integration - 19 Verification Requirements', () {
    testWidgets('1. Location permission / GPS is NOT requested when screen opens', (tester) async {
      final mockProvider = MockTrackingLocationProvider();
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);

      // Verify zero location requests occurred on app launch or screen open
      expect(mockProvider.getCurrentLocationCalls, equals(0));

      // Switch to Location tab
      await selectLocationType(tester);

      // Still zero location requests
      expect(mockProvider.getCurrentLocationCalls, equals(0));
    });

    testWidgets('2. Permission / GPS is requested ONLY after Use Current Location is tapped', (tester) async {
      final mockProvider = MockTrackingLocationProvider();
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      expect(mockProvider.getCurrentLocationCalls, equals(0));

      // Explicitly tap Use Current Location button
      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      expect(mockProvider.getCurrentLocationCalls, equals(1));
    });

    testWidgets('3. Location services disabled displays user-friendly message with action', (tester) async {
      final mockProvider = MockTrackingLocationProvider(
        onGetCurrentLocation: () => const CurrentLocationResult(
          status: CurrentLocationStatus.servicesDisabled,
          message: 'Location services are turned off.',
        ),
      );
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      expect(find.text('Location services are turned off.'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);

      // Tap settings action and verify provider openLocationSettings is invoked
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(mockProvider.openLocationSettingsCalls, equals(1));
    });

    testWidgets('4. Permission denied shows non-blocking explanation message', (tester) async {
      final mockProvider = MockTrackingLocationProvider(
        onGetCurrentLocation: () => const CurrentLocationResult(
          status: CurrentLocationStatus.permissionDenied,
          message: 'Location permission was denied.',
        ),
      );
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Location permission was denied. You can search, pick a location from the map, or enter coordinates manually.',
        ),
        findsOneWidget,
      );

      // Verify Pick from Map, Search, and Manual entry remain completely usable
      expect(find.byKey(const Key('location_search_input')), findsOneWidget);
      expect(find.byKey(const Key('interactive_map_canvas')), findsOneWidget);
      expect(find.text('Enter Manually'), findsOneWidget);
    });

    testWidgets('5. Permission permanently denied shows message with Open Settings action', (tester) async {
      final mockProvider = MockTrackingLocationProvider(
        onGetCurrentLocation: () => const CurrentLocationResult(
          status: CurrentLocationStatus.permissionPermanentlyDenied,
          message: 'Location permission is permanently denied.',
        ),
      );
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Location permission is permanently denied. You can select your location on the map.',
        ),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsOneWidget);

      // Tap settings action and verify provider openAppSettings is invoked
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(mockProvider.openAppSettingsCalls, equals(1));
    });

    testWidgets('6. Permission granted returns latitude + longitude', (tester) async {
      final mockProvider = MockTrackingLocationProvider(
        onGetCurrentLocation: () => const CurrentLocationResult(
          status: CurrentLocationStatus.success,
          latitude: 13.0827,
          longitude: 80.2707,
          accuracy: 5.0,
        ),
      );
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('13.0827'), findsWidgets);
      expect(find.textContaining('80.2707'), findsWidgets);
    });

    testWidgets('7. Approximate location (coarse accuracy) is accepted seamlessly', (tester) async {
      final mockProvider = MockTrackingLocationProvider(
        onGetCurrentLocation: () => const CurrentLocationResult(
          status: CurrentLocationStatus.success,
          latitude: 28.6139,
          longitude: 77.2090,
          accuracy: 650.0, // Coarse/approximate location
        ),
      );
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      // Verified location accepted without rejection or error
      expect(find.byKey(const Key('selected_location_card')), findsOneWidget);
      expect(find.textContaining('28.6139'), findsWidgets);
      expect(find.textContaining('77.2090'), findsWidgets);
    });

    testWidgets('8. Successful GPS coordinates update selected location card and map', (tester) async {
      final mockProvider = MockTrackingLocationProvider(
        onGetCurrentLocation: () => const CurrentLocationResult(
          status: CurrentLocationStatus.success,
          latitude: 37.7749,
          longitude: -122.4194,
        ),
      );
      final service = TrackingLocationService(
        trackingProvider: mockProvider,
        reverseGeocodeResult: const LocationSearchResult(
          placeName: 'San Francisco Ferry Building',
          formattedAddress: '1 Ferry Building, San Francisco, CA 94111, USA',
          latitude: 37.7749,
          longitude: -122.4194,
        ),
      );

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      expect(find.text('San Francisco Ferry Building'), findsWidgets);
      expect(find.text('1 Ferry Building, San Francisco, CA 94111, USA'), findsOneWidget);
    });

    testWidgets('9. Successful GPS coordinates regenerate QR code preview', (tester) async {
      final mockProvider = MockTrackingLocationProvider(
        onGetCurrentLocation: () => const CurrentLocationResult(
          status: CurrentLocationStatus.success,
          latitude: 48.8584,
          longitude: 2.2945,
        ),
      );
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      // QrImageView rendered with geo payload
      expect(find.byType(QrImageView), findsOneWidget);
      final state = tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      expect(state.generatedPayload, startsWith('geo:48.858400,2.294500'));
    });

    testWidgets('10. Reverse geocoding success displays readable address', (tester) async {
      final mockProvider = MockTrackingLocationProvider(
        onGetCurrentLocation: () => const CurrentLocationResult(
          status: CurrentLocationStatus.success,
          latitude: 51.5007,
          longitude: -0.1246,
        ),
      );
      final service = TrackingLocationService(
        trackingProvider: mockProvider,
        reverseGeocodeResult: const LocationSearchResult(
          placeName: 'Big Ben',
          formattedAddress: 'Westminster, London SW1A 0AA, UK',
          latitude: 51.5007,
          longitude: -0.1246,
        ),
      );

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      expect(find.text('Big Ben'), findsWidgets);
      expect(find.text('Westminster, London SW1A 0AA, UK'), findsOneWidget);
      expect(service.reverseGeocodeCalls, equals(1));
    });

    testWidgets('11. Reverse geocoding failure still preserves GPS coordinates and generates QR', (tester) async {
      final mockProvider = MockTrackingLocationProvider(
        onGetCurrentLocation: () => const CurrentLocationResult(
          status: CurrentLocationStatus.success,
          latitude: 35.6895,
          longitude: 139.6917,
        ),
      );
      final service = TrackingLocationService(
        trackingProvider: mockProvider,
        simulateReverseGeocodeFailure: true, // Nominatim times out / network offline
      );

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      // Coordinates MUST NOT be discarded
      expect(find.textContaining('35.6895'), findsWidgets);
      expect(find.textContaining('139.6917'), findsWidgets);

      // QR Code must still be generated with raw coordinates
      expect(find.byType(QrImageView), findsOneWidget);
      final state = tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      expect(state.generatedPayload, startsWith('geo:35.689500,139.691700'));
    });

    testWidgets('12. GPS timeout handled safely with SnackBar', (tester) async {
      final mockProvider = MockTrackingLocationProvider(
        onGetCurrentLocation: () => const CurrentLocationResult(
          status: CurrentLocationStatus.timeout,
          message: 'Location request timed out. Please pick a location from the map.',
        ),
      );
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Location request timed out. Please pick a location from the map.'),
        findsOneWidget,
      );
    });

    testWidgets('13. Duplicate button taps do not create multiple requests', (tester) async {
      final completer = Completer<CurrentLocationResult>();
      final mockProvider = MockTrackingLocationProvider(
        delayedCompleter: completer,
      );
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      // First tap
      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pump(); // Enter loading state

      // Verify UI shows loading indicator and text
      expect(find.text('Getting your location...'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // Attempt second tap while in progress
      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pump();

      // Verify provider was called only ONCE
      expect(mockProvider.getCurrentLocationCalls, equals(1));

      // Complete request
      completer.complete(
        const CurrentLocationResult(
          status: CurrentLocationStatus.success,
          latitude: 12.9716,
          longitude: 77.5946,
        ),
      );
      await tester.pumpAndSettle();

      // Verify button restored
      expect(find.text('Pan or tap map to pick'), findsOneWidget);
    });

    testWidgets('14. No background location behavior: only single foreground fix obtained', (tester) async {
      final mockProvider = MockTrackingLocationProvider();
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      expect(mockProvider.getCurrentLocationCalls, equals(1));

      // Advance time by 30 seconds
      await tester.pump(const Duration(seconds: 30));

      // Verify no recurring background stream or periodic polling
      expect(mockProvider.getCurrentLocationCalls, equals(1));
    });

    testWidgets('15. Existing map search remains functional', (tester) async {
      final mockProvider = MockTrackingLocationProvider();
      final service = TrackingLocationService(
        trackingProvider: mockProvider,
        searchResults: const [
          LocationSearchResult(
            placeName: 'Gateway of India',
            formattedAddress: 'Apollo Bandar, Colaba, Mumbai, Maharashtra 400001',
            latitude: 18.9220,
            longitude: 72.8347,
          ),
        ],
      );

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.enterText(
        find.byKey(const Key('location_search_input')),
        'Gateway of India',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search_result_item_0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('search_result_item_0')));
      await tester.pumpAndSettle();

      expect(find.text('Gateway of India'), findsWidgets);
    });

    testWidgets('16. Existing map tap/pan selection remains functional', (tester) async {
      final mockProvider = MockTrackingLocationProvider();
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      final mapCenter = tester.getCenter(find.byKey(const Key('interactive_map_canvas')));
      await tester.tapAt(mapCenter + const Offset(15, -15));
      await tester.pumpAndSettle();

      final state = tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      expect(state.generatedPayload, startsWith('geo:'));
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('17. Existing manual coordinate mode remains functional', (tester) async {
      final mockProvider = MockTrackingLocationProvider();
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.tap(find.text('Enter Manually'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('input_location_lat')), '12.9716');
      await tester.enterText(find.byKey(const Key('input_location_lng')), '77.5946');
      await tester.enterText(find.byKey(const Key('input_location_label')), 'Bengaluru HQ');
      await tester.pumpAndSettle();

      final state = tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      expect(state.generatedPayload, startsWith('geo:12.971600,77.594600'));
      expect(state.generatedPayload, contains('Bengaluru%20HQ'));
    });

    testWidgets('18. Existing Location QR parser remains compatible', (tester) async {
      final mockProvider = MockTrackingLocationProvider();
      final service = TrackingLocationService(trackingProvider: mockProvider);

      await pumpQrScreen(tester, locationService: service);
      await selectLocationType(tester);

      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      final state = tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      final parsed = QrContentParser.parse(state.generatedPayload);
      expect(parsed.type, equals(QrContentType.geo));
      final geoData = parsed.dataAs<GeoQrData>();
      expect(geoData.latitude, closeTo(13.0827, 0.001));
      expect(geoData.longitude, closeTo(80.2707, 0.001));
    });

    testWidgets('19. Other QR generator types remain unchanged', (tester) async {
      await pumpQrScreen(tester);

      final state = tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));

      // Test Website QR
      await tester.enterText(find.byKey(const Key('input_website_url')), 'https://digitalshare.app');
      await tester.pumpAndSettle();
      expect(state.generatedPayload, equals('https://digitalshare.app'));
    });
  });
}
