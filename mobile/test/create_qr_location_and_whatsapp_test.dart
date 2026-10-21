import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:digital_share/screens/scan/create_qr_screen.dart';
import 'package:digital_share/services/location/location_service.dart';
import 'package:digital_share/services/qr/qr_content_parser.dart';
import 'package:digital_share/models/qr/qr_content_type.dart';
import 'package:digital_share/models/qr/qr_scan_models.dart';

/// Fake LocationService for deterministic widget and unit testing.
class FakeLocationService extends LocationService {
  final List<LocationSearchResult> searchResultsToReturn;
  final LocationSearchResult? reverseGeocodeToReturn;
  final CurrentLocationResult? currentLocationResultToReturn;

  FakeLocationService({
    this.searchResultsToReturn = const [],
    this.reverseGeocodeToReturn,
    this.currentLocationResultToReturn,
  });

  @override
  Future<List<LocationSearchResult>> searchPlaces(
    String query, {
    http.Client? client,
  }) async {
    return searchResultsToReturn;
  }

  @override
  Future<LocationSearchResult?> reverseGeocode(
    double latitude,
    double longitude, {
    http.Client? client,
  }) async {
    return reverseGeocodeToReturn ??
        LocationSearchResult(
          placeName: 'Sample Place',
          formattedAddress: 'Sample Street, City, Country',
          latitude: latitude,
          longitude: longitude,
        );
  }

  @override
  Future<CurrentLocationResult> getCurrentLocation() async {
    return currentLocationResultToReturn ??
        const CurrentLocationResult(
          status: CurrentLocationStatus.unavailable,
          message: 'GPS unavailable',
        );
  }
}

Future<void> pumpScreen(
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

Future<void> selectType(WidgetTester tester, CreateQrType type) async {
  final chipFinder = find.byKey(Key('create_type_${type.name}'));
  await tester.ensureVisible(chipFinder);
  await tester.tap(chipFinder);
  await tester.pumpAndSettle();
}

void main() {
  group('CreateQrScreen - WhatsApp Improvements', () {
    testWidgets('1. WhatsApp phone field initially empty', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, CreateQrType.whatsapp);

      final phoneFinder = find.byKey(const Key('input_whatsapp_phone'));
      expect(phoneFinder, findsOneWidget);

      final textField = tester.widget<TextField>(phoneFinder);
      expect(textField.controller?.text, isEmpty);
      expect(
        textField.decoration?.labelText,
        equals('Phone Number (with Country Code)'),
      );
      expect(
        textField.decoration?.hintText,
        equals('Enter phone number with country code'),
      );
    });

    testWidgets('2. No +91 automatically inserted', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, CreateQrType.whatsapp);

      final phoneFinder = find.byKey(const Key('input_whatsapp_phone'));
      final textField = tester.widget<TextField>(phoneFinder);

      expect(textField.controller?.text.contains('+91'), isFalse);
      expect(textField.controller?.text.contains('98765'), isFalse);
      expect(textField.decoration?.hintText?.contains('+91'), isFalse);
      expect(find.byType(QrImageView), findsNothing);

      final state =
          tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      expect(state.generatedPayload, isEmpty);
    });

    testWidgets(
        '3. User-entered international phone number generates correct WhatsApp QR',
        (tester) async {
      await pumpScreen(tester);
      await selectType(tester, CreateQrType.whatsapp);

      // Enter US international number (+1 415 555 2671)
      await tester.enterText(
        find.byKey(const Key('input_whatsapp_phone')),
        '+1 415 555 2671',
      );
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);

      final state =
          tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      expect(state.generatedPayload, equals('https://wa.me/14155552671'));
      expect(state.generatedPayload.contains('91'), isFalse);
    });

    testWidgets('4. WhatsApp optional message still works', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, CreateQrType.whatsapp);

      // Enter UK international number and message
      await tester.enterText(
        find.byKey(const Key('input_whatsapp_phone')),
        '+44 7911 123456',
      );
      await tester.enterText(
        find.byKey(const Key('input_whatsapp_message')),
        'Hello from Digital Share!',
      );
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);

      final state =
          tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      expect(
        state.generatedPayload,
        equals(
          'https://wa.me/447911123456?text=Hello%20from%20Digital%20Share!',
        ),
      );

      // Verify Universal QR parser can parse it
      final parsed = QrContentParser.parse(state.generatedPayload);
      expect(parsed.type, equals(QrContentType.whatsapp));
      final waData = parsed.dataAs<WhatsAppQrData>();
      expect(waData.phone, equals('447911123456'));
      expect(waData.message, equals('Hello from Digital Share!'));
    });
  });

  group('CreateQrScreen - Location QR UX Improvements', () {
    testWidgets('5. Location defaults to Pick from Map mode', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, CreateQrType.location);

      expect(find.text('Pick from Map'), findsOneWidget);
      expect(find.text('Enter Manually'), findsOneWidget);

      final segmented = tester.widget<SegmentedButton<LocationInputMode>>(
        find.byKey(const Key('location_mode_segmented_button')),
      );
      expect(segmented.selected, equals({LocationInputMode.mapPicker}));

      // Search and interactive canvas are visible
      expect(find.byKey(const Key('location_search_input')), findsOneWidget);
      expect(find.byKey(const Key('interactive_map_canvas')), findsOneWidget);
      expect(find.byKey(const Key('selected_location_card')), findsOneWidget);
    });

    testWidgets(
        '6. Selecting a location updates latitude/longitude internally',
        (tester) async {
      final fakeService = FakeLocationService(
        searchResultsToReturn: const [
          LocationSearchResult(
            placeName: 'Central Park',
            formattedAddress: 'Central Park, New York, NY, USA',
            latitude: 40.785091,
            longitude: -73.968285,
          ),
        ],
      );

      await pumpScreen(tester, locationService: fakeService);
      await selectType(tester, CreateQrType.location);

      // Search for location
      await tester.enterText(
        find.byKey(const Key('location_search_input')),
        'Central Park',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search_result_item_0')), findsOneWidget);
      expect(find.text('Central Park'), findsWidgets);

      // Tap search result
      await tester.tap(find.byKey(const Key('search_result_item_0')));
      await tester.pumpAndSettle();

      // Verify internal coordinates and label are updated
      expect(find.byKey(const Key('selected_coordinates')), findsOneWidget);
      expect(find.textContaining('40.785091'), findsWidgets);
      expect(find.textContaining('-73.968285'), findsWidgets);
    });

    testWidgets('7. Selected place/address displays correctly', (tester) async {
      final fakeService = FakeLocationService(
        searchResultsToReturn: const [
          LocationSearchResult(
            placeName: 'Eiffel Tower',
            formattedAddress:
                'Champ de Mars, 5 Av. Anatole France, 75007 Paris, France',
            latitude: 48.858370,
            longitude: 2.294481,
          ),
        ],
      );

      await pumpScreen(tester, locationService: fakeService);
      await selectType(tester, CreateQrType.location);

      await tester.enterText(
        find.byKey(const Key('location_search_input')),
        'Eiffel Tower',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search_result_item_0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('selected_place_name')), findsOneWidget);
      expect(find.text('Eiffel Tower'), findsWidgets);
      expect(
        find.byKey(const Key('selected_formatted_address')),
        findsOneWidget,
      );
      expect(
        find.text('Champ de Mars, 5 Av. Anatole France, 75007 Paris, France'),
        findsOneWidget,
      );
    });

    testWidgets('8. Selected location generates valid geo QR payload',
        (tester) async {
      final fakeService = FakeLocationService(
        searchResultsToReturn: const [
          LocationSearchResult(
            placeName: 'Tokyo Tower',
            formattedAddress:
                '4 Chome-2-8 Shibakoen, Minato City, Tokyo, Japan',
            latitude: 35.658581,
            longitude: 139.745438,
          ),
        ],
      );

      await pumpScreen(tester, locationService: fakeService);
      await selectType(tester, CreateQrType.location);

      await tester.enterText(
        find.byKey(const Key('location_search_input')),
        'Tokyo Tower',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search_result_item_0')));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);

      final state =
          tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      expect(state.generatedPayload, startsWith('geo:35.658581,139.745438'));
      expect(state.generatedPayload, contains('Tokyo%20Tower'));
    });

    testWidgets('9. Changing location regenerates QR', (tester) async {
      final fakeService = FakeLocationService(
        searchResultsToReturn: const [
          LocationSearchResult(
            placeName: 'Location A',
            formattedAddress: 'Address A',
            latitude: 10.0,
            longitude: 20.0,
          ),
        ],
      );

      await pumpScreen(tester, locationService: fakeService);
      await selectType(tester, CreateQrType.location);

      await tester.enterText(
        find.byKey(const Key('location_search_input')),
        'Location A',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search_result_item_0')));
      await tester.pumpAndSettle();

      final state =
          tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      expect(state.generatedPayload, startsWith('geo:10.000000,20.000000'));

      // Tap on map to select different coordinates
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('interactive_map_canvas'))) +
            const Offset(20, 20),
      );
      await tester.pumpAndSettle();

      expect(state.generatedPayload, startsWith('geo:'));
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('10. Manual mode still works', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, CreateQrType.location);

      // Switch to Enter Manually
      await tester.tap(find.text('Enter Manually'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('input_location_lat')), findsOneWidget);
      expect(find.byKey(const Key('input_location_lng')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('input_location_lat')),
        '51.5074',
      );
      await tester.enterText(
        find.byKey(const Key('input_location_lng')),
        '-0.1278',
      );
      await tester.enterText(
        find.byKey(const Key('input_location_label')),
        'London Eye',
      );
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);

      final state =
          tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      expect(state.generatedPayload, startsWith('geo:51.507400,-0.127800'));
      expect(state.generatedPayload, contains('London%20Eye'));
    });

    testWidgets('11. Invalid latitude rejected', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, CreateQrType.location);

      await tester.tap(find.text('Enter Manually'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('input_location_lat')),
        '95.0',
      );
      await tester.enterText(
        find.byKey(const Key('input_location_lng')),
        '10.0',
      );
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsNothing);
      expect(
        find.text('Latitude must be between -90 and +90.'),
        findsOneWidget,
      );

      final state =
          tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      expect(state.generatedPayload, isEmpty);
    });

    testWidgets('12. Invalid longitude rejected', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, CreateQrType.location);

      await tester.tap(find.text('Enter Manually'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('input_location_lat')),
        '10.0',
      );
      await tester.enterText(
        find.byKey(const Key('input_location_lng')),
        '200.0',
      );
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsNothing);
      expect(
        find.text('Longitude must be between -180 and +180.'),
        findsOneWidget,
      );

      final state =
          tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      expect(state.generatedPayload, isEmpty);
    });

    testWidgets(
        '13. Current Location permission denied handled safely, if implemented',
        (tester) async {
      final fakeService = FakeLocationService(
        currentLocationResultToReturn: const CurrentLocationResult(
          status: CurrentLocationStatus.permissionDenied,
        ),
      );

      await pumpScreen(tester, locationService: fakeService);
      await selectType(tester, CreateQrType.location);

      // Explicitly tap Use Current Location button
      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Location permission was denied. You can search, pick a location from the map, or enter coordinates manually.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        '14. Current Location services disabled handled safely, if implemented',
        (tester) async {
      final fakeService = FakeLocationService(
        currentLocationResultToReturn: const CurrentLocationResult(
          status: CurrentLocationStatus.servicesDisabled,
        ),
      );

      await pumpScreen(tester, locationService: fakeService);
      await selectType(tester, CreateQrType.location);

      await tester.tap(find.byKey(const Key('use_current_location_button')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Location services are turned off.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        '15. Existing Universal QR parser can parse the generated Location QR',
        (tester) async {
      final fakeService = FakeLocationService(
        searchResultsToReturn: const [
          LocationSearchResult(
            placeName: 'Opera House',
            formattedAddress: 'Bennelong Point, Sydney NSW 2000, Australia',
            latitude: -33.856784,
            longitude: 151.215297,
          ),
        ],
      );

      await pumpScreen(tester, locationService: fakeService);
      await selectType(tester, CreateQrType.location);

      await tester.enterText(
        find.byKey(const Key('location_search_input')),
        'Opera House',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search_result_item_0')));
      await tester.pumpAndSettle();

      final state =
          tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));
      final generatedPayload = state.generatedPayload;

      // Parse with existing Universal QR parser
      final parsed = QrContentParser.parse(generatedPayload);
      expect(parsed.type, equals(QrContentType.geo));

      final geoData = parsed.dataAs<GeoQrData>();
      expect(geoData.latitude, closeTo(-33.856784, 0.0001));
      expect(geoData.longitude, closeTo(151.215297, 0.0001));
      expect(geoData.query, contains('Opera House'));
      expect(geoData.rawUri, equals(generatedPayload));
    });

    testWidgets('16. Other QR generator types remain unchanged',
        (tester) async {
      await pumpScreen(tester);

      final state =
          tester.state<CreateQrScreenState>(find.byType(CreateQrScreen));

      // Website
      await tester.enterText(
        find.byKey(const Key('input_website_url')),
        'https://digitalshare.app',
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(state.generatedPayload, equals('https://digitalshare.app'));

      // Phone
      await selectType(tester, CreateQrType.phone);
      await tester.enterText(
        find.byKey(const Key('input_phone_number')),
        '+15550199',
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(state.generatedPayload, equals('tel:+15550199'));

      // Email
      await selectType(tester, CreateQrType.email);
      await tester.enterText(
        find.byKey(const Key('input_email_recipient')),
        'contact@example.com',
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(state.generatedPayload, equals('mailto:contact@example.com'));

      // SMS
      await selectType(tester, CreateQrType.sms);
      await tester.enterText(
        find.byKey(const Key('input_sms_phone')),
        '+15550199',
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(state.generatedPayload, equals('sms:+15550199'));

      // Plain Text
      await selectType(tester, CreateQrType.text);
      await tester.enterText(
        find.byKey(const Key('input_plain_text')),
        'Hello Digital Share Plain Text',
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(state.generatedPayload, equals('Hello Digital Share Plain Text'));
    });
  });
}
