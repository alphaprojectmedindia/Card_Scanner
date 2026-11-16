import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:digital_share/models/qr/qr_content_type.dart';
import 'package:digital_share/models/qr/qr_scan_models.dart';
import 'package:digital_share/models/shared_profile.dart';
import 'package:digital_share/screens/scan/create_qr_screen.dart';
import 'package:digital_share/screens/scan/qr_result_screen.dart';
import 'package:digital_share/screens/scan/qr_scanner_screen.dart';
import 'package:digital_share/screens/scan/recent_scans_screen.dart';
import 'package:digital_share/screens/scan/scanned_profile_screen.dart';
import 'package:digital_share/services/qr/qr_content_parser.dart';
import 'package:digital_share/services/qr/qr_generator_service.dart';
import 'package:digital_share/services/qr/qr_recent_scans_service.dart';
import 'package:digital_share/services/share_service.dart';

class MockShareService extends ShareService {
  int invocationCount = 0;
  String? lastShareId;
  SharedProfile? profileToReturn;
  bool shouldThrow = false;

  MockShareService({this.profileToReturn});

  @override
  Future<SharedProfile> getSharedProfile(String shareId) async {
    invocationCount++;
    lastShareId = shareId;
    if (shouldThrow) {
      throw Exception('Failed to load profile');
    }
    return profileToReturn ??
        SharedProfile(
          shareId: shareId,
          fullName: 'Alice Walker',
          email: 'alice@example.com',
          company: 'TechCorp',
          jobTitle: 'VP of Engineering',
        );
  }
}

class FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _data[key] = value;
    } else {
      _data.remove(key);
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

void main() {
  group('Universal QR Content Parser Tests', () {
    // -------------------------------------------------------------------------
    // 1. Digital Share Profile QR
    // -------------------------------------------------------------------------
    test('1. Valid Digital Share QR canonical URL extracts shareId accurately', () {
      const canonical = 'https://digitalshare.app/s/x7F9K2mQ8pL4vYkVl6VUbG7T';
      final result = QrContentParser.parse(canonical);

      expect(result.type, equals(QrContentType.digitalShare));
      final data = result.dataAs<DigitalShareQrData>();
      expect(data.shareId, equals('x7F9K2mQ8pL4vYkVl6VUbG7T'));
      expect(data.canonicalUrl, equals(canonical));
    });

    test('2. Digital Share QR with http or domain prefix without https is recognized', () {
      final res1 = QrContentParser.parse('http://digitalshare.app/s/x7F9K2mQ8pL4vYkVl6VUbG7T/');
      expect(res1.type, equals(QrContentType.digitalShare));
      expect(res1.dataAs<DigitalShareQrData>().shareId, equals('x7F9K2mQ8pL4vYkVl6VUbG7T'));

      final res2 = QrContentParser.parse('digitalshare.app/s/x7F9K2mQ8pL4vYkVl6VUbG7T?ref=qr');
      expect(res2.type, equals(QrContentType.digitalShare));
      expect(res2.dataAs<DigitalShareQrData>().shareId, equals('x7F9K2mQ8pL4vYkVl6VUbG7T'));
    });

    test('3. Direct pure shareId format is recognized as Digital Share', () {
      const shareId = 'x7F9K2mQ8pL4vYkVl6VUbG7T';
      final res = QrContentParser.parse(shareId);
      expect(res.type, equals(QrContentType.digitalShare));
      expect(res.dataAs<DigitalShareQrData>().shareId, equals(shareId));
    });

    test('4. Arbitrary similar-length text must NOT become Digital Share QR', () {
      // General URL with similar path length
      final extUrl = QrContentParser.parse('https://example.com/s/x7F9K2mQ8pL4vYkVl6VUbG7T');
      expect(extUrl.type, equals(QrContentType.url));
      expect(extUrl.type, isNot(equals(QrContentType.digitalShare)));

      // Plain sentence with spaces
      final sentence = QrContentParser.parse('arbitrary similar text here');
      expect(sentence.type, equals(QrContentType.text));
      expect(sentence.type, isNot(equals(QrContentType.digitalShare)));

      // Email address with @ and dot
      final email = QrContentParser.parse('user@example.com');
      expect(email.type, equals(QrContentType.text));
      expect(email.type, isNot(equals(QrContentType.digitalShare)));

      // Malformed shareId with invalid characters
      final invalidChars = QrContentParser.parse('https://digitalshare.app/s/invalid!chars@#\$%');
      expect(invalidChars.type, isNot(equals(QrContentType.digitalShare)));

      // Too short (<16 chars)
      final tooShort = QrContentParser.parse('https://digitalshare.app/s/shortid');
      expect(tooShort.type, isNot(equals(QrContentType.digitalShare)));
    });

    // -------------------------------------------------------------------------
    // 2. Website URL
    // -------------------------------------------------------------------------
    test('5. Standard HTTPS and HTTP website URLs are parsed safely', () {
      final resHttps = QrContentParser.parse('https://www.example.com/contact?id=123');
      expect(resHttps.type, equals(QrContentType.url));
      final dataHttps = resHttps.dataAs<UrlQrData>();
      expect(dataHttps.displayHost, equals('www.example.com'));
      expect(dataHttps.isSecure, isTrue);

      final resHttp = QrContentParser.parse('http://insecure.site/test');
      expect(resHttp.type, equals(QrContentType.url));
      final dataHttp = resHttp.dataAs<UrlQrData>();
      expect(dataHttp.displayHost, equals('insecure.site'));
      expect(dataHttp.isSecure, isFalse);
    });

    // -------------------------------------------------------------------------
    // 3. WhatsApp Links
    // -------------------------------------------------------------------------
    test('6. WhatsApp wa.me link parses phone and pre-filled message correctly', () {
      const waUrl = 'https://wa.me/919876543210?text=Hello%20Digital%20Share';
      final res = QrContentParser.parse(waUrl);

      expect(res.type, equals(QrContentType.whatsapp));
      final data = res.dataAs<WhatsAppQrData>();
      expect(data.phone, equals('919876543210'));
      expect(data.message, equals('Hello Digital Share'));
    });

    test('7. Native whatsapp:// scheme parses phone and message', () {
      const waNative = 'whatsapp://send?phone=15550199&text=Meeting%20at%203pm';
      final res = QrContentParser.parse(waNative);

      expect(res.type, equals(QrContentType.whatsapp));
      final data = res.dataAs<WhatsAppQrData>();
      expect(data.phone, equals('15550199'));
      expect(data.message, equals('Meeting at 3pm'));
    });

    // -------------------------------------------------------------------------
    // 4. Wi-Fi Configuration
    // -------------------------------------------------------------------------
    test('8. Wi-Fi QR with WPA, hidden network, and escaped characters', () {
      const wifiStr = r'WIFI:T:WPA;S:Office\;Guest;P:Pass\:word\\123;H:true;;';
      final res = QrContentParser.parse(wifiStr);

      expect(res.type, equals(QrContentType.wifi));
      final data = res.dataAs<WifiQrData>();
      expect(data.ssid, equals('Office;Guest'));
      expect(data.security, equals('WPA'));
      expect(data.password, equals(r'Pass:word\123'));
      expect(data.isHidden, isTrue);
    });

    test('9. Wi-Fi open network (nopass) with no password', () {
      const openWifi = 'WIFI:T:nopass;S:AirportFreeWifi;;';
      final res = QrContentParser.parse(openWifi);

      expect(res.type, equals(QrContentType.wifi));
      final data = res.dataAs<WifiQrData>();
      expect(data.ssid, equals('AirportFreeWifi'));
      expect(data.security, equals('nopass'));
      expect(data.password, isEmpty);
      expect(data.isHidden, isFalse);
    });

    // -------------------------------------------------------------------------
    // 5. Geographic Location
    // -------------------------------------------------------------------------
    test('10. geo: URI with positive and negative coordinates', () {
      const geoStr = 'geo:-33.8688,151.2093?q=-33.8688,151.2093(Sydney%20CBD)';
      final res = QrContentParser.parse(geoStr);

      expect(res.type, equals(QrContentType.geo));
      final data = res.dataAs<GeoQrData>();
      expect(data.latitude, closeTo(-33.8688, 0.0001));
      expect(data.longitude, closeTo(151.2093, 0.0001));
      expect(data.query, equals('-33.8688,151.2093(Sydney CBD)'));
    });

    test('11. Google Maps URLs are classified as geographic content', () {
      const gmaps = 'https://maps.google.com/?q=13.0827,80.2707';
      final res = QrContentParser.parse(gmaps);
      expect(res.type, equals(QrContentType.geo));
    });

    test('12. Out-of-bounds geo coordinates are rejected from coordinate fields', () {
      const invalidGeo = 'geo:195.0,250.0'; // lat > 90, lng > 180
      final res = QrContentParser.parse(invalidGeo);
      expect(res.type, equals(QrContentType.geo));
      final data = res.dataAs<GeoQrData>();
      expect(data.latitude, isNull);
      expect(data.longitude, isNull);
    });

    // -------------------------------------------------------------------------
    // 6. Phone Links
    // -------------------------------------------------------------------------
    test('13. tel: links preserve international number and do not force +91', () {
      const telUs = 'tel:+1-800-555-0199';
      final resUs = QrContentParser.parse(telUs);
      expect(resUs.type, equals(QrContentType.phone));
      expect(resUs.dataAs<PhoneQrData>().phoneNumber, equals('+1-800-555-0199'));

      const telUk = 'tel:+447700900123';
      final resUk = QrContentParser.parse(telUk);
      expect(resUk.type, equals(QrContentType.phone));
      expect(resUk.dataAs<PhoneQrData>().phoneNumber, equals('+447700900123'));
    });

    // -------------------------------------------------------------------------
    // 7. Email Links
    // -------------------------------------------------------------------------
    test('14. mailto: link parses recipient, subject, body, and cc parameters', () {
      const mailto = 'mailto:lead@acme.com?subject=Partnership%20Inquiry&body=Hello%20Team&cc=boss@acme.com';
      final res = QrContentParser.parse(mailto);

      expect(res.type, equals(QrContentType.email));
      final data = res.dataAs<EmailQrData>();
      expect(data.email, equals('lead@acme.com'));
      expect(data.subject, equals('Partnership Inquiry'));
      expect(data.body, equals('Hello Team'));
      expect(data.cc, equals('boss@acme.com'));
    });

    // -------------------------------------------------------------------------
    // 8. SMS Links
    // -------------------------------------------------------------------------
    test('15. sms: and SMSTO: formats parse phone and message', () {
      const smsUri = 'sms:+919876543210?body=On%20my%20way';
      final res1 = QrContentParser.parse(smsUri);
      expect(res1.type, equals(QrContentType.sms));
      expect(res1.dataAs<SmsQrData>().phoneNumber, equals('+919876543210'));
      expect(res1.dataAs<SmsQrData>().message, equals('On my way'));

      const smsto = 'SMSTO:+15550199:Meeting confirmed';
      final res2 = QrContentParser.parse(smsto);
      expect(res2.type, equals(QrContentType.sms));
      expect(res2.dataAs<SmsQrData>().phoneNumber, equals('+15550199'));
      expect(res2.dataAs<SmsQrData>().message, equals('Meeting confirmed'));
    });

    // -------------------------------------------------------------------------
    // 9. vCard 3.0 Contact Card
    // -------------------------------------------------------------------------
    test('16. vCard parses full name, multiple phones, multiple emails, org, and address', () {
      const vcard = '''
BEGIN:VCARD
VERSION:3.0
FN:Jane Doe
N:Doe;Jane;;Dr.;
ORG:Starlight Health Systems
TITLE:Chief Medical Officer
TEL;TYPE=WORK:+15550111
TEL;TYPE=CELL:+15550222
EMAIL;TYPE=WORK:jane.doe@starlight.org
EMAIL;TYPE=HOME:jane@personal.com
URL:https://starlight.org
ADR;TYPE=WORK:;;100 Innovation Way;Boston;MA;02115;USA
NOTE:Met at Digital Health 2026
END:VCARD''';

      final res = QrContentParser.parse(vcard);
      expect(res.type, equals(QrContentType.vcard));
      final data = res.dataAs<ContactQrData>();
      expect(data.fullName, equals('Jane Doe'));
      expect(data.organization, equals('Starlight Health Systems'));
      expect(data.title, equals('Chief Medical Officer'));
      expect(data.phones, equals(['+15550111', '+15550222']));
      expect(data.emails, equals(['jane.doe@starlight.org', 'jane@personal.com']));
      expect(data.website, equals('https://starlight.org'));
      expect(data.address, contains('100 Innovation Way, Boston, MA, 02115, USA'));
      expect(data.notes, equals('Met at Digital Health 2026'));
      expect(data.isVCard, isTrue);
    });

    // -------------------------------------------------------------------------
    // 10. MECARD Contact Card
    // -------------------------------------------------------------------------
    test('17. MECARD format correctly extracts name, phones, and emails', () {
      const mecard = 'MECARD:N:Smith,John;TEL:9876543210;TEL:9876543211;EMAIL:john@smith.com;ORG:Smith Legal;;';
      final res = QrContentParser.parse(mecard);

      expect(res.type, equals(QrContentType.mecard));
      final data = res.dataAs<ContactQrData>();
      expect(data.fullName, equals('John Smith'));
      expect(data.phones, equals(['9876543210', '9876543211']));
      expect(data.emails, equals(['john@smith.com']));
      expect(data.organization, equals('Smith Legal'));
      expect(data.isVCard, isFalse);
    });

    // -------------------------------------------------------------------------
    // 11. Calendar Event (VEVENT)
    // -------------------------------------------------------------------------
    test('18. iCalendar VEVENT parses summary, dates, location, and description', () {
      const vevent = '''
BEGIN:VEVENT
SUMMARY:Global Strategy Summit
DTSTART:20261115T090000Z
DTEND:20261115T170000Z
LOCATION:Convention Center Hall A
DESCRIPTION:Annual business conference and networking
END:VEVENT''';

      final res = QrContentParser.parse(vevent);
      expect(res.type, equals(QrContentType.event));
      final data = res.dataAs<CalendarEventQrData>();
      expect(data.summary, equals('Global Strategy Summit'));
      expect(data.location, equals('Convention Center Hall A'));
      expect(data.description, contains('Annual business conference'));
      expect(data.dtStart?.year, equals(2026));
      expect(data.dtStart?.month, equals(11));
      expect(data.dtStart?.day, equals(15));
    });

    // -------------------------------------------------------------------------
    // 12. Security: Dangerous URI Schemes & App Links
    // -------------------------------------------------------------------------
    test('19. Dangerous schemes (javascript, data, file) are safely blocked', () {
      final js = QrContentParser.parse('javascript:alert(document.cookie)');
      expect(js.type, equals(QrContentType.unknown));

      final dataUri = QrContentParser.parse('data:text/html,<script>alert(1)</script>');
      expect(dataUri.type, equals(QrContentType.unknown));

      final fileUri = QrContentParser.parse('file:///etc/passwd');
      expect(fileUri.type, equals(QrContentType.unknown));
    });

    test('20. Custom app deep link displays as appLink with isSafeToOpen false', () {
      final app = QrContentParser.parse('market://details?id=com.digitalshare.app');
      expect(app.type, equals(QrContentType.appLink));
      final data = app.dataAs<AppLinkQrData>();
      expect(data.scheme, equals('market'));
      expect(data.isSafeToOpen, isFalse);
    });

    // -------------------------------------------------------------------------
    // 13. Plain Text & Unknown
    // -------------------------------------------------------------------------
    test('21. Plain text preserves Unicode and multiline structure', () {
      const text = 'வணக்கம் / नमस्ते / Hello 🚀\nWelcome to Digital Share!';
      final res = QrContentParser.parse(text);
      expect(res.type, equals(QrContentType.text));
      expect(res.dataAs<TextQrData>().text, equals(text));
    });

    test('22. Empty or null rawValue returns clean Unknown result without crashing', () {
      final resNull = QrContentParser.parse(null);
      expect(resNull.type, equals(QrContentType.unknown));

      final resEmpty = QrContentParser.parse('   ');
      expect(resEmpty.type, equals(QrContentType.unknown));
    });
  });

  // ---------------------------------------------------------------------------
  // Generator Service Tests
  // ---------------------------------------------------------------------------
  group('Universal QR Generator Service Tests', () {
    test('23. buildDigitalSharePayload generates canonical URL', () {
      final p = QrGeneratorService.buildDigitalSharePayload('x7F9K2mQ8pL4vYkVl6VUbG7T');
      expect(p, equals('https://digitalshare.app/s/x7F9K2mQ8pL4vYkVl6VUbG7T'));
    });

    test('24. buildWifiPayload escapes special characters and formats WPA/hidden', () {
      final wifi = QrGeneratorService.buildWifiPayload(
        ssid: 'Office;Guest',
        security: 'WPA',
        password: r'Pass:word\123',
        isHidden: true,
      );
      expect(wifi, equals(r'WIFI:T:WPA;S:Office\;Guest;P:Pass\:word\\123;H:true;;'));
    });

    test('25. buildWhatsAppPayload formats wa.me URL with clean digits', () {
      final wa = QrGeneratorService.buildWhatsAppPayload(
        phone: '+91 (987) 654-3210',
        message: 'Hello World',
      );
      expect(wa, equals('https://wa.me/919876543210?text=Hello%20World'));
    });

    test('26. buildLocationPayload validates coordinate ranges', () {
      final valid = QrGeneratorService.buildLocationPayload(
        latitude: 13.0827,
        longitude: 80.2707,
        label: 'Office',
      );
      expect(valid, contains('geo:13.082700,80.270700'));

      expect(
        () => QrGeneratorService.buildLocationPayload(latitude: 95.0, longitude: 0.0),
        throwsArgumentError,
      );
      expect(
        () => QrGeneratorService.buildLocationPayload(latitude: 0.0, longitude: 200.0),
        throwsArgumentError,
      );
    });

    test('27. buildContactVCardPayload generates valid vCard 3.0 format', () {
      final vcard = QrGeneratorService.buildContactVCardPayload(
        name: 'Jane Doe',
        phones: ['+15550199'],
        emails: ['jane@example.com'],
        company: 'Acme Inc',
      );
      expect(vcard, contains('BEGIN:VCARD'));
      expect(vcard, contains('VERSION:3.0'));
      expect(vcard, contains('FN:Jane Doe'));
      expect(vcard, contains('TEL;TYPE=CELL:+15550199'));
      expect(vcard, contains('EMAIL;TYPE=WORK:jane@example.com'));
      expect(vcard, contains('ORG:Acme Inc'));
      expect(vcard, contains('END:VCARD'));
    });
  });

  // ---------------------------------------------------------------------------
  // Privacy & Recent Scans Tests
  // ---------------------------------------------------------------------------
  group('Privacy & Recent Scans Tests', () {
    test('28. Wi-Fi passwords are NEVER stored in recent scan history', () async {
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      const rawWifi = 'WIFI:T:WPA;S:SecretOfficeNet;P:TopSecretPassword123;;';
      final parsedWifi = QrContentParser.parse(rawWifi);

      await recentService.addScan(parsedWifi);

      final scans = await recentService.getRecentScans();
      expect(scans.length, equals(1));
      expect(scans.first.displayTitle, equals('Wi-Fi Network'));
      expect(scans.first.displaySubtitle, contains('SecretOfficeNet'));

      // Check stored raw payload in storage
      final storedJson = await fakeStorage.read(key: 'digital_share_recent_qr_scans_v1');
      expect(storedJson, isNotNull);
      expect(storedJson, isNot(contains('TopSecretPassword123')));
      expect(scans.first.safePayload, isNot(contains('TopSecretPassword123')));
    });

    test('29. Clear history deletes all items locally', () async {
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      final scan = QrContentParser.parse('https://example.com');
      await recentService.addScan(scan);

      var scans = await recentService.getRecentScans();
      expect(scans.isNotEmpty, isTrue);

      await recentService.clearHistory();
      scans = await recentService.getRecentScans();
      expect(scans.isEmpty, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Widget & Duplicate Scan Protection Tests
  // ---------------------------------------------------------------------------
  group('Universal QR Scanner Screen Widget Tests', () {
    testWidgets('30. Renders Universal QR Scanner header, instructions, and action buttons',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: QrScannerScreen(),
        ),
      );

      expect(find.text('Universal QR Scanner'), findsOneWidget);
      expect(find.text('Point your camera at any QR code'), findsOneWidget);
      expect(
        find.text('Supports links, Wi-Fi, contacts, WhatsApp and more.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('qr_recent_scans_button')), findsOneWidget);
      expect(find.byKey(const Key('qr_create_qr_button')), findsOneWidget);
      expect(find.byKey(const Key('qr_toggle_torch_button')), findsOneWidget);
      expect(find.byKey(const Key('qr_switch_camera_button')), findsOneWidget);
    });

    testWidgets(
        '31. Digital Share QR scan invokes ShareService and navigates to ScannedProfileScreen',
        (tester) async {
      final mockShare = MockShareService();
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      late QrScannerScreenState state;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final widget = QrScannerScreen(
                shareService: mockShare,
                recentScansService: recentService,
              );
              return widget;
            },
          ),
        ),
      );

      state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      // Simulate camera detecting Digital Share QR code
      const shareUrl = 'https://digitalshare.app/s/x7F9K2mQ8pL4vYkVl6VUbG7T';
      final capture = BarcodeCapture(
        barcodes: [
          Barcode(rawValue: shareUrl, format: BarcodeFormat.qrCode),
        ],
      );

      unawaited(state.handleBarcode(capture));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Profile service was called with exact shareId
      expect(mockShare.invocationCount, equals(1));
      expect(mockShare.lastShareId, equals('x7F9K2mQ8pL4vYkVl6VUbG7T'));

      // Successfully pushed ScannedProfileScreen
      expect(find.byType(ScannedProfileScreen), findsOneWidget);
      expect(find.text('Alice Walker'), findsOneWidget);
    });

    testWidgets('32. Non-Digital-Share QR code opens QrResultScreen safely',
        (tester) async {
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            recentScansService: recentService,
          ),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      // Simulate scanning a website QR
      const website = 'https://flutter.dev';
      final capture = BarcodeCapture(
        barcodes: [
          Barcode(rawValue: website, format: BarcodeFormat.qrCode),
        ],
      );

      unawaited(state.handleBarcode(capture));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Pushed QrResultScreen
      expect(find.byType(QrResultScreen), findsOneWidget);
      expect(find.text('Website Link'), findsOneWidget);
      expect(find.text('flutter.dev'), findsOneWidget);
      expect(find.byKey(const Key('open_website_button')), findsOneWidget);
      expect(find.byKey(const Key('qr_scan_again_button')), findsOneWidget);
    });

    testWidgets(
        '33. Duplicate camera frames are guarded and scanner unlocks after returning',
        (tester) async {
      final mockShare = MockShareService();
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            shareService: mockShare,
            recentScansService: recentService,
          ),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      const shareUrl = 'https://digitalshare.app/s/x7F9K2mQ8pL4vYkVl6VUbG7T';
      final capture = BarcodeCapture(
        barcodes: [
          Barcode(rawValue: shareUrl, format: BarcodeFormat.qrCode),
        ],
      );

      // Fire 4 rapid barcode frame events in succession
      unawaited(state.handleBarcode(capture));
      unawaited(state.handleBarcode(capture));
      unawaited(state.handleBarcode(capture));
      unawaited(state.handleBarcode(capture));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Guarded! Invocation occurred strictly ONCE
      expect(mockShare.invocationCount, equals(1));
      expect(find.byType(ScannedProfileScreen), findsOneWidget);

      // Pop back from ScannedProfileScreen to QrScannerScreen
      Navigator.of(tester.element(find.byType(ScannedProfileScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Scanner is visible and unlocked for next scan
      expect(find.byType(QrScannerScreen), findsOneWidget);

      // Next distinct scan works
      const secondShareUrl = 'https://digitalshare.app/s/SecondValidShareId1234';
      final secondCapture = BarcodeCapture(
        barcodes: [
          Barcode(rawValue: secondShareUrl, format: BarcodeFormat.qrCode),
        ],
      );

      unawaited(state.handleBarcode(secondCapture));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(mockShare.invocationCount, equals(2));
      expect(mockShare.lastShareId, equals('SecondValidShareId1234'));
    });

    testWidgets('34. CreateQrScreen generates live QR preview for multiple types',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CreateQrScreen(),
        ),
      );

      expect(find.text('Create QR Code'), findsOneWidget);
      expect(find.byKey(const Key('input_website_url')), findsOneWidget);

      // Enter website
      await tester.enterText(find.byKey(const Key('input_website_url')), 'https://digitalshare.app');
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.byKey(const Key('copy_created_qr_button')), findsOneWidget);

      // Switch to Wi-Fi
      await tester.tap(find.byKey(const Key('create_type_wifi')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('input_wifi_ssid')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('input_wifi_ssid')), 'HomeNetwork');
      await tester.enterText(find.byKey(const Key('input_wifi_password')), 'secret123');
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('35. RecentScansScreen displays items and can clear history',
        (tester) async {
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      // Add a scan item
      final scan = QrContentParser.parse('https://example.com');
      await recentService.addScan(scan);

      await tester.pumpWidget(
        MaterialApp(
          home: RecentScansScreen(storageService: recentService),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recent Scans'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);

      // Tap clear history button
      await tester.tap(find.byKey(const Key('clear_history_button')));
      await tester.pumpAndSettle();

      expect(find.text('Clear Scan History?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm_clear_history_button')));
      await tester.pumpAndSettle();

      expect(find.text('No Recent Scans'), findsOneWidget);
    });
  });
}
