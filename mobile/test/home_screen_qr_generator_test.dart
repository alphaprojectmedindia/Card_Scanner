import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/imported_contact.dart';
import 'package:digital_share/models/saved_connection.dart';
import 'package:digital_share/models/user_profile.dart';
import 'package:digital_share/screens/home/home_screen.dart';
import 'package:digital_share/screens/profile/digital_card_screen.dart';
import 'package:digital_share/screens/scan/business_card_scan_screen.dart';
import 'package:digital_share/screens/scan/create_qr_screen.dart';
import 'package:digital_share/screens/scan/qr_scanner_screen.dart';
import 'package:digital_share/services/connection_service.dart';
import 'package:digital_share/services/imported_contact_service.dart';
import 'package:digital_share/services/pending_card_capture_store.dart';
import 'package:digital_share/services/pending_profile_photo_store.dart';
import 'package:digital_share/theme/app_theme.dart';

class MockConnectionsService extends ConnectionService {
  final List<SavedConnection> connections;
  MockConnectionsService({this.connections = const []});

  @override
  Future<List<SavedConnection>> getConnections() async => connections;
}

class MockImportedService extends ImportedContactService {
  final List<ImportedContact> contacts;
  MockImportedService({this.contacts = const []});

  @override
  Future<List<ImportedContact>> getContacts() async => contacts;
}

void main() {
  final testProfile = UserProfile(
    id: 'user-001',
    userId: 'uid-001',
    shareId: 'alpha1234567890123',
    fullName: 'David Miller',
    email: 'david.miller@example.com',
    phoneNumber: '+1 555-0100',
    jobTitle: 'Product Director',
    company: 'Apex Digital',
    website: 'https://apexdigital.io',
    address: 'Austin, TX',
    bio: 'Digital business cards and networking.',
    createdAtUtc: DateTime.utc(2026, 1, 1),
    updatedAtUtc: DateTime.utc(2026, 1, 1),
  );

  Widget createTestApp({Size? surfaceSize}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: HomeScreen(
        initialProfile: testProfile,
        connectionService: MockConnectionsService(),
        importedContactService: MockImportedService(),
      ),
    );
  }

  void setPhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  setUp(() {
    PendingCardCaptureStore.resetForTesting();
    PendingProfilePhotoStore.resetForTesting();
  });

  tearDown(() {
    PendingCardCaptureStore.resetForTesting();
    PendingProfilePhotoStore.resetForTesting();
  });

  group('Home Screen QR Generator Placement & Navigation Tests', () {
    // 1. My Digital QR still appears on Home
    testWidgets('1. My Digital QR card appears on Home page with subtitle', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('My Digital Card'), findsOneWidget);
      expect(find.text('Show your QR code and contact card'), findsOneWidget);
    });

    // 2. QR Generator appears DIRECTLY BELOW My Digital QR
    testWidgets('2. QR Generator card appears DIRECTLY BELOW My Digital QR and above Meetings', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home_qr_generator_card')), findsOneWidget);
      expect(find.text('QR Generator'), findsOneWidget);
      expect(
        find.text('Create QR codes for links, Wi-Fi, contacts, location and more'),
        findsOneWidget,
      );
      expect(find.text('Create QR'), findsOneWidget);

      // Verify layout geometry order:
      // Business Card Scanner -> Universal QR Scanner -> My Digital Card -> QR Generator -> Meetings
      final bCardCenter = tester.getCenter(find.text('Business Card Scanner'));
      final qrScanCenter = tester.getCenter(find.text('Universal QR Scanner'));
      final digitalCardCenter = tester.getCenter(find.text('My Digital Card'));
      final qrGenCenter = tester.getCenter(find.text('QR Generator'));
      final meetingsCenter = tester.getCenter(find.text('Meetings').first);

      // Vertical ordering strictly verified:
      expect(bCardCenter.dy < qrScanCenter.dy, isTrue,
          reason: 'Business Card Scanner must be above Universal QR Scanner');
      expect(qrScanCenter.dy < digitalCardCenter.dy, isTrue,
          reason: 'Universal QR Scanner must be above My Digital Card');
      expect(digitalCardCenter.dy < qrGenCenter.dy, isTrue,
          reason: 'QR Generator must be DIRECTLY BELOW My Digital Card');
      expect(qrGenCenter.dy < meetingsCenter.dy, isTrue,
          reason: 'Meetings must be below QR Generator');
    });

    // 3. Tapping QR Generator opens the EXISTING Universal QR Generator
    testWidgets('3. Tapping QR Generator card opens the EXISTING CreateQrScreen', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home_qr_generator_card')));
      await tester.pumpAndSettle();

      // Confirms existing CreateQrScreen is rendered
      expect(find.byType(CreateQrScreen), findsOneWidget);
      expect(find.text('Create QR Code'), findsOneWidget);
    });

    // 4. Back returns to Home
    testWidgets('4. Back navigation from QR Generator returns to Home', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Navigate to QR Generator
      await tester.tap(find.byKey(const Key('home_qr_generator_card')));
      await tester.pumpAndSettle();
      expect(find.byType(CreateQrScreen), findsOneWidget);

      // Tap back button in AppBar
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Returned back to HomeScreen
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(CreateQrScreen), findsNothing);
      expect(find.text('QR Generator'), findsOneWidget);
    });

    // 5. My Digital QR functionality remains unchanged
    testWidgets('5. Tapping My Digital Card opens DigitalCardScreen and returns smoothly', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('My Digital Card'));
      await tester.pumpAndSettle();

      expect(find.byType(DigitalCardScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
    });

    // 6. Business Card Scanner opens BusinessCardScanScreen
    testWidgets('6. Business Card Scanner action on Home opens BusinessCardScanScreen', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Business Card Scanner'), findsOneWidget);
      expect(find.text('Scan a physical business card'), findsOneWidget);
      await tester.tap(find.text('Business Card Scanner'));
      await tester.pumpAndSettle();

      expect(find.byType(BusinessCardScanScreen), findsOneWidget);
      expect(find.text('Choose Scan Mode'), findsOneWidget);
    });

    // 6b. Universal QR Scanner opens QrScannerScreen directly
    testWidgets('6b. Universal QR Scanner action on Home opens QrScannerScreen directly', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Universal QR Scanner'), findsOneWidget);
      expect(find.text('Scan any QR code'), findsOneWidget);
      await tester.tap(find.text('Universal QR Scanner'));
      await tester.pumpAndSettle();

      expect(find.byType(QrScannerScreen), findsOneWidget);
      expect(find.text('Universal QR Scanner'), findsOneWidget);
      expect(find.text('Point your camera at any QR code'), findsOneWidget);
    });

    // 7. All existing QR Generator types remain available
    testWidgets('7. All existing QR types are available in CreateQrScreen opened from Home', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home_qr_generator_card')));
      await tester.pumpAndSettle();

      // Check all defined types exist
      for (final type in CreateQrType.values) {
        expect(
          find.byKey(Key('create_type_${type.name}')),
          findsOneWidget,
          reason: 'QR type ${type.label} (${type.name}) must be present',
        );
      }
    });

    // 8. Location QR remains available
    testWidgets('8. Location QR type is accessible and can be selected', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home_qr_generator_card')));
      await tester.pumpAndSettle();

      final locChip = find.byKey(const Key('create_type_location'));
      expect(locChip, findsOneWidget);

      await tester.ensureVisible(locChip);
      await tester.tap(locChip);
      await tester.pumpAndSettle();

      expect(find.text('Location'), findsWidgets);
    });

    // 9. WhatsApp QR remains available
    testWidgets('9. WhatsApp QR type is accessible and can be selected', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home_qr_generator_card')));
      await tester.pumpAndSettle();

      final waChip = find.byKey(const Key('create_type_whatsapp'));
      expect(waChip, findsOneWidget);

      await tester.tap(waChip);
      await tester.pumpAndSettle();

      expect(find.text('WhatsApp'), findsWidgets);
    });

    // 10. Home has no overflow on a representative small screen
    testWidgets('10. Home page renders with zero overflow on small Android screen (320x533)', (tester) async {
      tester.view.physicalSize = const Size(320 * 2.0, 533 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home_qr_generator_card')), findsOneWidget);
      expect(find.text('QR Generator'), findsOneWidget);
      expect(find.text('Create QR'), findsOneWidget);

      // Verify no Flutter exceptions / overflows occurred
      expect(tester.takeException(), isNull);
    });
  });
}
