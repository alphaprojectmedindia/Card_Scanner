import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/imported_contact.dart';
import 'package:digital_share/models/saved_connection.dart';
import 'package:digital_share/models/user_profile.dart';
import 'package:digital_share/screens/connections/connections_screen.dart';
import 'package:digital_share/screens/home/home_screen.dart';
import 'package:digital_share/screens/meetings/meetings_screen.dart';
import 'package:digital_share/screens/profile/digital_card_screen.dart';
import 'package:digital_share/screens/profile/profile_screen.dart';
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
    fullName: 'Jane Doe',
    email: 'jane.doe@example.com',
    phoneNumber: '+1 555-0199',
    jobTitle: 'VP of Partnerships',
    company: 'Global Digital Networks',
    website: 'https://digitalnetworks.example',
    address: 'New York, NY',
    bio: 'Networking and business card sharing.',
    createdAtUtc: DateTime.utc(2026, 1, 1),
    updatedAtUtc: DateTime.utc(2026, 1, 1),
  );

  Widget createTestApp() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: HomeScreen(
        initialProfile: testProfile,
        connectionService: MockConnectionsService(),
        importedContactService: MockImportedService(),
      ),
    );
  }

  void setPhoneViewport(WidgetTester tester, {double width = 1080, double height = 2400}) {
    tester.view.physicalSize = Size(width, height);
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

  group('Home Page Separate Scanner Actions & Navigation Tests', () {
    testWidgets('1. Both Business Card Scanner and Universal QR Scanner appear as distinct Quick Actions', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Verify Business Card Scanner card
      expect(find.byKey(const Key('home_business_card_scanner_card')), findsOneWidget);
      expect(find.text('Business Card Scanner'), findsOneWidget);
      expect(find.text('Scan a physical business card'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('home_business_card_scanner_card')),
          matching: find.byIcon(Icons.badge_rounded),
        ),
        findsOneWidget,
      );

      // Verify Universal QR Scanner card
      expect(find.byKey(const Key('home_universal_qr_scanner_card')), findsOneWidget);
      expect(find.text('Universal QR Scanner'), findsOneWidget);
      expect(find.text('Scan any QR code'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('home_universal_qr_scanner_card')),
          matching: find.byIcon(Icons.qr_code_scanner_rounded),
        ),
        findsOneWidget,
      );

      // Verify vertical positioning: Business Card Scanner is above Universal QR Scanner
      final bCardCenter = tester.getCenter(find.byKey(const Key('home_business_card_scanner_card')));
      final qrScanCenter = tester.getCenter(find.byKey(const Key('home_universal_qr_scanner_card')));
      expect(bCardCenter.dy < qrScanCenter.dy, isTrue,
          reason: 'Business Card Scanner must be displayed above Universal QR Scanner');
    });

    testWidgets('2. Tapping Business Card Scanner navigates to BusinessCardScanScreen (physical card OCR scanner)', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home_business_card_scanner_card')));
      await tester.pumpAndSettle();

      expect(find.byType(BusinessCardScanScreen), findsOneWidget);
      expect(find.text('Choose Scan Mode'), findsOneWidget);
      expect(find.text('Physical Business Card'), findsOneWidget);
    });

    testWidgets('3. Tapping Universal QR Scanner navigates directly to QrScannerScreen with correct header and instructions', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home_universal_qr_scanner_card')));
      await tester.pumpAndSettle();

      // Directly on QrScannerScreen, NOT routed through BusinessCardScanScreen
      expect(find.byType(QrScannerScreen), findsOneWidget);
      expect(find.byType(BusinessCardScanScreen), findsNothing);

      // Verify title is "Universal QR Scanner"
      expect(find.text('Universal QR Scanner'), findsOneWidget);

      // Verify main instruction and helper text
      expect(find.text('Point your camera at any QR code'), findsOneWidget);
      expect(
        find.text('Supports links, Wi-Fi, contacts, WhatsApp and more.'),
        findsOneWidget,
      );
    });

    testWidgets('4. My Digital Card action remains intact and functional', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('My Digital Card'), findsOneWidget);
      expect(find.text('Show your QR code and contact card'), findsOneWidget);

      await tester.tap(find.text('My Digital Card'));
      await tester.pumpAndSettle();

      expect(find.byType(DigitalCardScreen), findsOneWidget);
    });

    testWidgets('5. QR Generator action remains intact and functional', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home_qr_generator_card')), findsOneWidget);
      expect(find.text('QR Generator'), findsOneWidget);
      expect(
        find.text('Create QR codes for links, Wi-Fi, contacts, location and more'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('home_qr_generator_card')));
      await tester.pumpAndSettle();

      expect(find.byType(CreateQrScreen), findsOneWidget);
      expect(find.text('Create QR Code'), findsOneWidget);
    });

    testWidgets('6. Meetings action remains intact and functional', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Meetings'), findsOneWidget);
      expect(find.text('View requests and upcoming meetings'), findsOneWidget);

      await tester.tap(find.text('Meetings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MeetingsScreen), findsOneWidget);
    });

    testWidgets('7. Manage Contacts section (My Connections and My Profile) remains intact', (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Manage Contacts'), findsOneWidget);
      expect(find.text('My Connections'), findsOneWidget);
      expect(find.text('My Profile'), findsOneWidget);

      // Tapping My Connections
      await tester.tap(find.text('My Connections'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ConnectionsScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tapping My Profile
      await tester.tap(find.text('My Profile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('8. Narrow mobile screens render without layout overflow', (tester) async {
      // Test very narrow screen (320px width)
      setPhoneViewport(tester, width: 320, height: 640);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Business Card Scanner'), findsOneWidget);
      expect(find.text('Universal QR Scanner'), findsOneWidget);
      expect(find.text('My Digital Card'), findsOneWidget);
      expect(find.text('QR Generator'), findsOneWidget);
      expect(find.text('Meetings'), findsOneWidget);

      // Verify no overflow exceptions thrown
      expect(tester.takeException(), isNull);
    });

    testWidgets('9. Standard Android phone screen (360x780) renders cleanly with no overflow', (tester) async {
      setPhoneViewport(tester, width: 360, height: 780);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Business Card Scanner'), findsOneWidget);
      expect(find.text('Universal QR Scanner'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });
}
