import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/qr/qr_content_type.dart';
import 'package:digital_share/models/qr/qr_scan_models.dart';
import 'package:digital_share/screens/scan/qr_result_screen.dart';
import 'package:digital_share/services/contact_communication_service.dart';
import 'package:digital_share/services/qr/qr_content_parser.dart';

class MockCommunicationService implements IContactCommunicationService {
  bool openWhatsAppCalled = false;
  String? lastPhone;
  String? lastMessage;
  String? lastLinkUrl;
  bool returnSuccess = true;

  @override
  Future<bool> openWhatsApp({
    required String phone,
    required String message,
    String? linkUrl,
  }) async {
    openWhatsAppCalled = true;
    lastPhone = phone;
    lastMessage = message;
    lastLinkUrl = linkUrl;
    return returnSuccess;
  }

  @override
  Future<bool> openEmail({
    required String email,
    required String subject,
    required String body,
  }) async {
    return true;
  }
}

void main() {
  group('WhatsApp QR Code Parser Tests (Prompt Section 2 & 12)', () {
    test('1. https://wa.me/919876543210 (phone only)', () {
      final res = QrContentParser.parse('https://wa.me/919876543210');
      expect(res.type, equals(QrContentType.whatsapp));
      final data = res.dataAs<WhatsAppQrData>();
      expect(data.phone, equals('919876543210'));
      expect(data.message, equals(''));
      expect(data.hasPhone, isTrue);
      expect(data.hasMessage, isFalse);
      expect(data.linkUrl, equals('https://wa.me/919876543210'));
    });

    test('2. https://wa.me/919876543210?text=Hello (phone + message)', () {
      final res = QrContentParser.parse('https://wa.me/919876543210?text=Hello');
      expect(res.type, equals(QrContentType.whatsapp));
      final data = res.dataAs<WhatsAppQrData>();
      expect(data.phone, equals('919876543210'));
      expect(data.message, equals('Hello'));
      expect(data.hasPhone, isTrue);
      expect(data.hasMessage, isTrue);
      expect(data.linkUrl, equals('https://wa.me/919876543210?text=Hello'));
    });

    test('3. https://wa.me/?text=Hello (message only, no phone)', () {
      final res = QrContentParser.parse('https://wa.me/?text=Hello');
      expect(res.type, equals(QrContentType.whatsapp));
      final data = res.dataAs<WhatsAppQrData>();
      expect(data.phone, equals(''));
      expect(data.message, equals('Hello'));
      expect(data.hasPhone, isFalse);
      expect(data.hasMessage, isTrue);
      expect(data.linkUrl, equals('https://wa.me/?text=Hello'));
    });

    test('4. https://wa.me?text=Hello (message only, no trailing slash)', () {
      final res = QrContentParser.parse('https://wa.me?text=Hello');
      expect(res.type, equals(QrContentType.whatsapp));
      final data = res.dataAs<WhatsAppQrData>();
      expect(data.phone, equals(''));
      expect(data.message, equals('Hello'));
      expect(data.hasPhone, isFalse);
      expect(data.hasMessage, isTrue);
    });

    test('5. wa.me/919876543210 (scheme-less phone)', () {
      final res = QrContentParser.parse('wa.me/919876543210');
      expect(res.type, equals(QrContentType.whatsapp));
      final data = res.dataAs<WhatsAppQrData>();
      expect(data.phone, equals('919876543210'));
      expect(data.linkUrl, equals('https://wa.me/919876543210'));
    });

    test('6. https://api.whatsapp.com/send?phone=919876543210', () {
      final res = QrContentParser.parse('https://api.whatsapp.com/send?phone=919876543210');
      expect(res.type, equals(QrContentType.whatsapp));
      final data = res.dataAs<WhatsAppQrData>();
      expect(data.phone, equals('919876543210'));
      expect(data.message, equals(''));
      expect(data.hasPhone, isTrue);
      expect(data.hasMessage, isFalse);
    });

    test('7. https://api.whatsapp.com/send?phone=919876543210&text=Hello', () {
      final res = QrContentParser.parse('https://api.whatsapp.com/send?phone=919876543210&text=Hello');
      expect(res.type, equals(QrContentType.whatsapp));
      final data = res.dataAs<WhatsAppQrData>();
      expect(data.phone, equals('919876543210'));
      expect(data.message, equals('Hello'));
      expect(data.hasPhone, isTrue);
      expect(data.hasMessage, isTrue);
    });

    test('8. whatsapp://send?phone=919876543210 (native scheme)', () {
      final res = QrContentParser.parse('whatsapp://send?phone=919876543210');
      expect(res.type, equals(QrContentType.whatsapp));
      final data = res.dataAs<WhatsAppQrData>();
      expect(data.phone, equals('919876543210'));
      expect(data.message, equals(''));
      expect(data.isNativeScheme, isTrue);
    });

    test('9. whatsapp://send?phone=919876543210&text=Hello (native phone + message)', () {
      final res = QrContentParser.parse('whatsapp://send?phone=919876543210&text=Hello');
      expect(res.type, equals(QrContentType.whatsapp));
      final data = res.dataAs<WhatsAppQrData>();
      expect(data.phone, equals('919876543210'));
      expect(data.message, equals('Hello'));
      expect(data.isNativeScheme, isTrue);
    });

    test('10. whatsapp://send?text=Hello (native message only)', () {
      final res = QrContentParser.parse('whatsapp://send?text=Hello');
      expect(res.type, equals(QrContentType.whatsapp));
      final data = res.dataAs<WhatsAppQrData>();
      expect(data.phone, equals(''));
      expect(data.message, equals('Hello'));
      expect(data.hasPhone, isFalse);
      expect(data.hasMessage, isTrue);
      expect(data.isNativeScheme, isTrue);
    });

    test('11. Security: Fake WhatsApp-looking domain is NOT classified as WhatsApp', () {
      final fake1 = QrContentParser.parse('https://evil.example/?redirect=wa.me');
      expect(fake1.type, equals(QrContentType.url));
      expect(fake1.type, isNot(equals(QrContentType.whatsapp)));

      final fake2 = QrContentParser.parse('https://wa.me.attacker.com/919876543210');
      expect(fake2.type, equals(QrContentType.url));
      expect(fake2.type, isNot(equals(QrContentType.whatsapp)));

      final fake3 = QrContentParser.parse('https://notwhatsapp.com/send?phone=919876543210');
      expect(fake3.type, equals(QrContentType.url));
      expect(fake3.type, isNot(equals(QrContentType.whatsapp)));
    });

    test('12. Malformed WhatsApp URL handled safely without crash', () {
      final malformed = QrContentParser.parse('https://wa.me:notaport/invalid');
      expect(malformed.type, isNot(equals(QrContentType.whatsapp)));
    });

    test('13. Message containing spaces, &, +, emoji, and Unicode decodes cleanly', () {
      const complexMsgUrl = 'https://wa.me/919876543210?text=Hello%20World%26Welcome%2BMore%20%F0%9F%91%8B%20%E2%9C%A8';
      final res = QrContentParser.parse(complexMsgUrl);
      expect(res.type, equals(QrContentType.whatsapp));
      final data = res.dataAs<WhatsAppQrData>();
      expect(data.phone, equals('919876543210'));
      expect(data.message, equals('Hello World&Welcome+More 👋 ✨'));
      expect(data.linkUrl, equals(complexMsgUrl));
    });
  });

  group('WhatsApp QrResultScreen Presentation Tests (Prompt Section 5, 6, 7)', () {
    testWidgets('CASE A — phone only: displays WhatsApp Chat, Number, Copy Number, Open WhatsApp', (tester) async {
      final mockComm = MockCommunicationService();
      final scanResult = QrScanResult(
        type: QrContentType.whatsapp,
        rawValue: 'https://wa.me/919876543210',
        parsedData: const WhatsAppQrData(
          phone: '919876543210',
          message: '',
          linkUrl: 'https://wa.me/919876543210',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: QrResultScreen(
            scanResult: scanResult,
            communicationService: mockComm,
          ),
        ),
      );

      // Verify Header
      expect(find.text('WhatsApp Chat'), findsOneWidget);

      // Verify Phone Row is displayed
      expect(find.text('Number'), findsOneWidget);
      expect(find.text('919876543210'), findsOneWidget);
      expect(find.text('WhatsApp Number: Not specified'), findsNothing);
      expect(find.text('Not specified'), findsNothing);

      // Verify Message Row is completely hidden
      expect(find.text('Message'), findsNothing);

      // Verify Buttons
      expect(find.byKey(const Key('open_whatsapp_button')), findsOneWidget);
      expect(find.byKey(const Key('copy_whatsapp_number_button')), findsOneWidget);
      expect(find.byKey(const Key('copy_whatsapp_message_button')), findsNothing);

      // Tap Open WhatsApp
      await tester.tap(find.byKey(const Key('open_whatsapp_button')));
      await tester.pump();

      expect(mockComm.openWhatsAppCalled, isTrue);
      expect(mockComm.lastPhone, equals('919876543210'));
      expect(mockComm.lastMessage, equals(''));
      expect(mockComm.lastLinkUrl, equals('https://wa.me/919876543210'));
    });

    testWidgets('CASE B — message only: displays WhatsApp, Message, Copy Message, Open WhatsApp, NO number row', (tester) async {
      final mockComm = MockCommunicationService();
      final scanResult = QrScanResult(
        type: QrContentType.whatsapp,
        rawValue: 'https://wa.me/?text=Hello',
        parsedData: const WhatsAppQrData(
          phone: '',
          message: 'Hello',
          linkUrl: 'https://wa.me/?text=Hello',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: QrResultScreen(
            scanResult: scanResult,
            communicationService: mockComm,
          ),
        ),
      );

      // Verify Header is "WhatsApp" (not "WhatsApp Chat")
      expect(find.text('WhatsApp'), findsOneWidget);

      // Verify Phone row and "Not specified" are COMPLETELY HIDDEN
      expect(find.text('Number'), findsNothing);
      expect(find.text('WhatsApp Number'), findsNothing);
      expect(find.text('Not specified'), findsNothing);

      // Verify Message row is displayed
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);

      // Verify Buttons
      expect(find.byKey(const Key('open_whatsapp_button')), findsOneWidget);
      expect(find.byKey(const Key('copy_whatsapp_number_button')), findsNothing);
      expect(find.byKey(const Key('copy_whatsapp_message_button')), findsOneWidget);

      // Tap Open WhatsApp
      await tester.tap(find.byKey(const Key('open_whatsapp_button')));
      await tester.pump();

      expect(mockComm.openWhatsAppCalled, isTrue);
      expect(mockComm.lastPhone, equals(''));
      expect(mockComm.lastMessage, equals('Hello'));
      expect(mockComm.lastLinkUrl, equals('https://wa.me/?text=Hello'));
    });

    testWidgets('CASE C — phone + message: displays WhatsApp Chat, Number, Message, both copy buttons', (tester) async {
      final mockComm = MockCommunicationService();
      final scanResult = QrScanResult(
        type: QrContentType.whatsapp,
        rawValue: 'https://wa.me/919876543210?text=Hello%20World',
        parsedData: const WhatsAppQrData(
          phone: '+91 98765 43210',
          message: 'Hello World',
          linkUrl: 'https://wa.me/919876543210?text=Hello%20World',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: QrResultScreen(
            scanResult: scanResult,
            communicationService: mockComm,
          ),
        ),
      );

      // Verify Header
      expect(find.text('WhatsApp Chat'), findsOneWidget);

      // Verify Number and Message rows
      expect(find.text('Number'), findsOneWidget);
      expect(find.text('+91 98765 43210'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Hello World'), findsOneWidget);

      // Verify All Buttons
      expect(find.byKey(const Key('open_whatsapp_button')), findsOneWidget);
      expect(find.byKey(const Key('copy_whatsapp_number_button')), findsOneWidget);
      expect(find.byKey(const Key('copy_whatsapp_message_button')), findsOneWidget);

      // Tap Open WhatsApp
      await tester.tap(find.byKey(const Key('open_whatsapp_button')));
      await tester.pump();

      expect(mockComm.openWhatsAppCalled, isTrue);
      expect(mockComm.lastPhone, equals('+91 98765 43210'));
      expect(mockComm.lastMessage, equals('Hello World'));
      expect(mockComm.lastLinkUrl, equals('https://wa.me/919876543210?text=Hello%20World'));
    });
  });

  group('ContactCommunicationService Helper & Formatting Tests', () {
    test('buildWhatsAppUniversalUriString formats message-only and phone+message links', () {
      final phoneAndMsg = ContactCommunicationService.buildWhatsAppUniversalUriString(
        phone: '919876543210',
        message: 'Hello World',
      );
      expect(phoneAndMsg, equals('https://wa.me/919876543210?text=Hello%20World'));

      final msgOnly = ContactCommunicationService.buildWhatsAppUniversalUriString(
        phone: '',
        message: 'Hello World',
      );
      expect(msgOnly, equals('https://wa.me/?text=Hello%20World'));
    });

    test('buildWhatsAppNativeUriString formats native schemes accurately', () {
      final nativeWithPhone = ContactCommunicationService.buildWhatsAppNativeUriString(
        phone: '919876543210',
        message: 'Hello World',
      );
      expect(nativeWithPhone, equals('whatsapp://send?phone=919876543210&text=Hello%20World'));

      final nativeMsgOnly = ContactCommunicationService.buildWhatsAppNativeUriString(
        phone: '',
        message: 'Hello World',
      );
      expect(nativeMsgOnly, equals('whatsapp://send?text=Hello%20World'));
    });
  });
}
