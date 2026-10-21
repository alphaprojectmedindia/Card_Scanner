import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/check_duplicate_result.dart';
import 'package:digital_share/models/imported_contact.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/screens/scan/business_card_review_screen.dart';
import 'package:digital_share/screens/scan/business_card_scan_screen.dart';
import 'package:digital_share/services/business_card_ocr_service.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/contact_service.dart';
import 'package:digital_share/services/imported_contact_service.dart';

class FakeImagePicker extends ImagePicker {
  XFile? nextFile;
  ImageSource? lastSource;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    lastSource = source;
    return nextFile;
  }
}

class FakeOcrService implements IBusinessCardOcrService {
  String frontText;
  String backText;
  bool shouldThrow;

  FakeOcrService({
    this.frontText = '',
    this.backText = '',
    this.shouldThrow = false,
  });

  @override
  Future<String> recognizeTextFromPath(String imagePath) async {
    if (shouldThrow) throw Exception('ML Kit OCR Failed');
    return frontText;
  }

  @override
  Future<OcrSideResult> processCardSide({
    required String imagePath,
    required CardSide side,
    String? source,
  }) async {
    if (shouldThrow) throw Exception('ML Kit OCR Failed');
    final text = side == CardSide.front ? frontText : backText;
    return OcrSideResult.fromText(
      side: side,
      imagePath: imagePath,
      rawText: text,
    );
  }
}

class FakeContactService implements IContactService {
  bool saveBusinessCardCalled = false;

  @override
  Future<ContactSaveResult> saveBusinessCardToPhone({
    required String? fullName,
    required String? company,
    required String? jobTitle,
    required String? website,
    required String? address,
    required List<BusinessCardPhone> phones,
    required List<BusinessCardEmail> emails,
    bool force = false,
  }) async {
    saveBusinessCardCalled = true;
    return const ContactSaveResult(
      status: ContactSaveStatus.success,
      message: 'Contact saved successfully to phone.',
    );
  }

  @override
  Contact buildContactFromBusinessCard({
    required String? fullName,
    required String? company,
    required String? jobTitle,
    required String? website,
    required String? address,
    required List<BusinessCardPhone> phones,
    required List<BusinessCardEmail> emails,
  }) {
    return Contact();
  }

  @override
  Future<ContactSaveResult> saveSharedProfileToPhone(dynamic profile) async {
    return const ContactSaveResult(
      status: ContactSaveStatus.success,
      message: 'Saved profile',
    );
  }

  @override
  Contact buildContactFromProfile(dynamic profile) => Contact();
}

class FakeImportedContactService extends ImportedContactService {
  bool checkDuplicateCalled = false;
  bool saveContactCalled = false;
  CheckDuplicateResult duplicateResult;

  FakeImportedContactService({
    this.duplicateResult = const CheckDuplicateResult(isDuplicate: false),
  });

  @override
  Future<CheckDuplicateResult> checkDuplicate({
    required List<String> phoneNumbers,
    required List<String> emailAddresses,
  }) async {
    checkDuplicateCalled = true;
    return duplicateResult;
  }

  @override
  Future<ImportedContact> saveContact(Map<String, dynamic> contactData) async {
    saveContactCalled = true;
    return ImportedContact(
      id: '1',
      fullName: contactData['fullName'] as String?,
      company: contactData['company'] as String?,
      jobTitle: contactData['jobTitle'] as String?,
      phoneNumbers: const [],
      emailAddresses: const [],
      createdAtUtc: DateTime.now(),
    );
  }
}

void main() {
  const parser = BusinessCardParser();

  group('Dual-Sided Business Card OCR & Parser Comprehensive Tests', () {
    // -------------------------------------------------------------
    // 1. Front-only card
    // -------------------------------------------------------------
    test('1. Front-only card parses correctly with isDualSided=false', () {
      final frontResult = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/front.jpg',
        rawText: '''
Alice Walker
Principal Architect
CloudScale Inc.
+1 415 555 2671
alice@cloudscale.io
https://cloudscale.io
''',
      );

      final data = parser.parseSide(frontResult);
      expect(data.fullName, 'Alice Walker');
      expect(data.jobTitle, 'Principal Architect');
      expect(data.company, 'CloudScale Inc.');
      expect(data.phoneNumbers.length, 1);
      expect(data.phoneNumbers.first.number, '+1 415 555 2671');
      expect(data.emailAddresses.length, 1);
      expect(data.emailAddresses.first.email, 'alice@cloudscale.io');
      expect(data.website, 'https://cloudscale.io');
      expect(data.isDualSided, false);
    });

    // -------------------------------------------------------------
    // 2. Front + back
    // -------------------------------------------------------------
    test('2. Front + back intelligently merges both sides', () {
      final frontResult = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/front.jpg',
        rawText: '''
David Miller
Chief Technology Officer
NovaTech Solutions
+1 212 555 0140
david@novatech.com
''',
      );

      final backResult = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: '/tmp/back.jpg',
        rawText: '''
NovaTech Solutions
Headquarters: 100 Broadway, New York, NY 10005
Office: +1 212 555 0199
info@novatech.com
https://novatech.com
''',
      );

      final data = parser.parseDualSided(
        front: frontResult,
        back: backResult,
      );

      expect(data.isDualSided, true);
      expect(data.fullName, 'David Miller');
      expect(data.jobTitle, 'Chief Technology Officer');
      expect(data.company, 'NovaTech Solutions');
      expect(data.address, contains('100 Broadway'));
      expect(data.website, 'https://novatech.com');
      // Phones merged from both sides
      expect(data.phoneNumbers.length, 2);
      expect(data.phoneNumbers.any((p) => p.number.contains('0140')), isTrue);
      expect(data.phoneNumbers.any((p) => p.number.contains('0199')), isTrue);
      // Emails merged from both sides
      expect(data.emailAddresses.length, 2);
      expect(data.emailAddresses.any((e) => e.email == 'david@novatech.com'), isTrue);
      expect(data.emailAddresses.any((e) => e.email == 'info@novatech.com'), isTrue);
    });

    // -------------------------------------------------------------
    // 3. Back removal
    // -------------------------------------------------------------
    testWidgets('3. Back removal clears back side and updates button text', (tester) async {
      final picker = FakeImagePicker()..nextFile = XFile('front.jpg');
      final ocr = FakeOcrService(frontText: 'Front Card Text');

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(imagePicker: picker, ocrService: ocr),
        ),
      );

      // Expand physical card section and stage front
      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inline_take_photo_button')));
      await tester.pumpAndSettle();

      expect(find.text('FRONT SIDE'), findsOneWidget);
      expect(find.text('Scan Details (1 Side)'), findsOneWidget);

      // Add back side
      picker.nextFile = XFile('back.jpg');
      await tester.ensureVisible(find.byKey(const Key('add_back_side_button')));
      await tester.tap(find.byKey(const Key('add_back_side_button')));
      await tester.pumpAndSettle();

      // Modal options: pick camera for back
      await tester.tap(find.text('Take Photo with Camera'));
      await tester.pumpAndSettle();

      expect(find.text('BACK SIDE (OPTIONAL)'), findsOneWidget);
      expect(find.text('Scan Details (Front & Back)'), findsOneWidget);

      // Remove back side
      await tester.ensureVisible(find.byKey(const Key('remove_back_button')));
      await tester.tap(find.byKey(const Key('remove_back_button')));
      await tester.pumpAndSettle();

      // Back is removed, front remains, button updates back to 1 Side
      expect(find.byKey(const Key('remove_back_button')), findsNothing);
      expect(find.text('FRONT SIDE'), findsOneWidget);
      expect(find.text('Scan Details (1 Side)'), findsOneWidget);
    });

    // -------------------------------------------------------------
    // 4. Front retake
    // -------------------------------------------------------------
    testWidgets('4. Front retake replaces front image without affecting back', (tester) async {
      final picker = FakeImagePicker()..nextFile = XFile('front_initial.jpg');
      final ocr = FakeOcrService(frontText: 'Initial Front');

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(imagePicker: picker, ocrService: ocr),
        ),
      );

      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inline_take_photo_button')));
      await tester.pumpAndSettle();

      // Add back
      picker.nextFile = XFile('back.jpg');
      await tester.ensureVisible(find.byKey(const Key('add_back_side_button')));
      await tester.tap(find.byKey(const Key('add_back_side_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take Photo with Camera'));
      await tester.pumpAndSettle();

      expect(find.text('BACK SIDE (OPTIONAL)'), findsOneWidget);

      // Retake front
      picker.nextFile = XFile('front_retaken.jpg');
      await tester.ensureVisible(find.byKey(const Key('retake_front_button')));
      await tester.tap(find.byKey(const Key('retake_front_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take Photo with Camera'));
      await tester.pumpAndSettle();

      // Front and back both remain staged
      expect(find.text('FRONT SIDE'), findsOneWidget);
      expect(find.text('BACK SIDE (OPTIONAL)'), findsOneWidget);
      expect(find.text('Scan Details (Front & Back)'), findsOneWidget);
    });

    // -------------------------------------------------------------
    // 5. Back retake
    // -------------------------------------------------------------
    testWidgets('5. Back retake replaces back image while preserving front', (tester) async {
      final picker = FakeImagePicker()..nextFile = XFile('front.jpg');
      final ocr = FakeOcrService(frontText: 'Front Text');

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(imagePicker: picker, ocrService: ocr),
        ),
      );

      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inline_take_photo_button')));
      await tester.pumpAndSettle();

      // Add back
      picker.nextFile = XFile('back_first.jpg');
      await tester.ensureVisible(find.byKey(const Key('add_back_side_button')));
      await tester.tap(find.byKey(const Key('add_back_side_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose from Gallery'));
      await tester.pumpAndSettle();

      // Retake back
      picker.nextFile = XFile('back_retaken.jpg');
      await tester.ensureVisible(find.byKey(const Key('retake_back_button')));
      await tester.tap(find.byKey(const Key('retake_back_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose from Gallery'));
      await tester.pumpAndSettle();

      expect(find.text('FRONT SIDE'), findsOneWidget);
      expect(find.text('BACK SIDE (OPTIONAL)'), findsOneWidget);
      expect(find.text('Scan Details (Front & Back)'), findsOneWidget);
    });

    // -------------------------------------------------------------
    // 6. Camera staging
    // -------------------------------------------------------------
    testWidgets('6. Camera staging stages image without auto-running OCR', (tester) async {
      final picker = FakeImagePicker()..nextFile = XFile('cam_staged.jpg');
      final ocr = FakeOcrService(frontText: 'Text');

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(imagePicker: picker, ocrService: ocr),
        ),
      );

      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inline_take_photo_button')));
      await tester.pumpAndSettle();

      expect(picker.lastSource, ImageSource.camera);
      // Front side staged, review screen NOT opened yet
      expect(find.text('FRONT SIDE'), findsOneWidget);
      expect(find.byType(BusinessCardReviewScreen), findsNothing);
    });

    // -------------------------------------------------------------
    // 7. Gallery staging
    // -------------------------------------------------------------
    testWidgets('7. Gallery staging stages image without auto-running OCR', (tester) async {
      final picker = FakeImagePicker()..nextFile = XFile('gallery_staged.jpg');
      final ocr = FakeOcrService(frontText: 'Text');

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(imagePicker: picker, ocrService: ocr),
        ),
      );

      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inline_choose_gallery_button')));
      await tester.pumpAndSettle();

      expect(picker.lastSource, ImageSource.gallery);
      expect(find.text('FRONT SIDE'), findsOneWidget);
      expect(find.byType(BusinessCardReviewScreen), findsNothing);
    });

    // -------------------------------------------------------------
    // 8. Same phone on both sides
    // -------------------------------------------------------------
    test('8. Same phone on both sides is deduplicated correctly', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: 'John Doe\n+91 98765 43210\njohn@example.com',
      );
      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: '/tmp/b.jpg',
        rawText: 'Call us: 9876543210\nwww.example.com',
      );

      final data = parser.parseDualSided(front: front, back: back);
      expect(data.phoneNumbers.length, 1);
      expect(data.phoneNumbers.first.number, '+91 98765 43210');
    });

    // -------------------------------------------------------------
    // 9. Same email on both sides
    // -------------------------------------------------------------
    test('9. Same email with different casing on both sides is deduplicated', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: 'Jane Doe\njane.doe@company.org\nEngineer',
      );
      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: '/tmp/b.jpg',
        rawText: 'Inquiries: JANE.DOE@COMPANY.ORG\nWebsite: company.org',
      );

      final data = parser.parseDualSided(front: front, back: back);
      expect(data.emailAddresses.length, 1);
      expect(data.emailAddresses.first.email.toLowerCase(), 'jane.doe@company.org');
    });

    // -------------------------------------------------------------
    // 10. Different legitimate phones
    // -------------------------------------------------------------
    test('10. Different legitimate phones from front and back are preserved', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: 'Mark Taylor\nMobile: +1 415 555 0199',
      );
      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: '/tmp/b.jpg',
        rawText: 'Direct Line: +1 415 555 0122\nFax: +1 415 555 0123',
      );

      final data = parser.parseDualSided(front: front, back: back);
      expect(data.phoneNumbers.length, 3);
      expect(data.phoneNumbers.map((p) => p.number), containsAll([
        '+1 415 555 0199',
        '+1 415 555 0122',
        '+1 415 555 0123',
      ]));
    });

    // -------------------------------------------------------------
    // 11. Different legitimate emails
    // -------------------------------------------------------------
    test('11. Different legitimate emails from front and back are preserved', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: 'Elena Rostova\nDirect: elena@technocraft.de',
      );
      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: '/tmp/b.jpg',
        rawText: 'General: info@technocraft.de\nSupport: support@technocraft.de',
      );

      final data = parser.parseDualSided(front: front, back: back);
      expect(data.emailAddresses.length, 3);
      expect(data.emailAddresses.map((e) => e.email), containsAll([
        'elena@technocraft.de',
        'info@technocraft.de',
        'support@technocraft.de',
      ]));
    });

    // -------------------------------------------------------------
    // 12. International phone numbers
    // -------------------------------------------------------------
    test('12. International phone formats are preserved without auto-prepending country codes', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: '''
Pierre Dubois
Paris Office: +33 1 42 68 55 00
Tokyo Office: +81 3 1234 5678
London Office: +44 20 7946 0958
''',
      );

      final data = parser.parseSide(front);
      expect(data.phoneNumbers.length, 3);
      expect(data.phoneNumbers.any((p) => p.number.startsWith('+33')), isTrue);
      expect(data.phoneNumbers.any((p) => p.number.startsWith('+81')), isTrue);
      expect(data.phoneNumbers.any((p) => p.number.startsWith('+44')), isTrue);
      expect(data.phoneNumbers.any((p) => p.number.startsWith('+91')), isFalse);
    });

    // -------------------------------------------------------------
    // 13. Front name + unrelated name on back
    // -------------------------------------------------------------
    test('13. Front name preferred, back name stored as alternative without silent overwrite', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: '''
Dr. Sarah Jenkins
Director of Clinical Research
BioHealth Labs
sarah@biohealth.org
''',
      );

      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: '/tmp/b.jpg',
        rawText: '''
Affiliated Partner:
Mark Spencer
Senior Consultant
''',
      );

      final data = parser.parseDualSided(front: front, back: back);
      expect(data.fullName, 'Dr. Sarah Jenkins');
      expect(data.alternativeCandidates['fullName'], contains('Mark Spencer'));
    });

    // -------------------------------------------------------------
    // 14. Name only on back
    // -------------------------------------------------------------
    test('14. Name only on back is promoted when front has no name candidate', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: '''
Nexora Innovations
Empowering Global Fintech
www.nexora.com
+1 800 555 0199
''',
      );

      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: '/tmp/b.jpg',
        rawText: '''
Alexander Hamilton
Managing Director
alex@nexora.com
''',
      );

      final data = parser.parseDualSided(front: front, back: back);
      expect(data.fullName, 'Alexander Hamilton');
      expect(data.jobTitle, 'Managing Director');
      expect(data.company, 'Nexora Innovations');
    });

    // -------------------------------------------------------------
    // 15. Address only on back
    // -------------------------------------------------------------
    test('15. Full address on back is populated when front lacks address', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: '''
Priya Sundaram
Lead Architect
Aura Spaces
priya@auraspaces.com
''',
      );

      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: '/tmp/b.jpg',
        rawText: '''
Aura Spaces Architectural Studio
Suite 400, 750 Market Street
San Francisco, CA 94102, USA
''',
      );

      final data = parser.parseDualSided(front: front, back: back);
      expect(data.address, isNotNull);
      expect(data.address, contains('750 Market Street'));
    });

    // -------------------------------------------------------------
    // 16. Website only on back
    // -------------------------------------------------------------
    test('16. Website only on back is populated accurately', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: '''
Lucas Garcia
Creative Director
lucas@studioalpha.es
''',
      );

      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: '/tmp/b.jpg',
        rawText: '''
Visit our online portfolio at:
https://www.studioalpha.es
''',
      );

      final data = parser.parseDualSided(front: front, back: back);
      expect(data.website, 'https://www.studioalpha.es');
    });

    // -------------------------------------------------------------
    // 17. Missing email
    // -------------------------------------------------------------
    test('17. Missing email leaves email list empty without fabricating placeholders', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: '''
Carlos Mendes
Carpenter & Builder
+1 555 839 2011
''',
      );

      final data = parser.parseSide(front);
      expect(data.fullName, 'Carlos Mendes');
      expect(data.emailAddresses, isEmpty);
      expect(data.emailAddresses.any((e) => e.email.contains('placeholder')), isFalse);
    });

    // -------------------------------------------------------------
    // 18. Missing phone
    // -------------------------------------------------------------
    test('18. Missing phone leaves phone list empty without fabricating dummy numbers', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: '''
Sophia Loren
Visual Designer
sophia@minimal.design
https://minimal.design
''',
      );

      final data = parser.parseSide(front);
      expect(data.fullName, 'Sophia Loren');
      expect(data.phoneNumbers, isEmpty);
    });

    // -------------------------------------------------------------
    // 19. Two-column OCR ordering
    // -------------------------------------------------------------
    test('19. Two-column OCR layout preserves block grouping instead of horizontal interleave', () {
      final blockLeft = OcrBlockMetadata(
        side: CardSide.front,
        text: 'Marcus Vance\nProduct Strategist',
        blockIndex: 0,
        boundingBox: const Rect.fromLTWH(20, 40, 200, 60),
        lines: [
          const OcrLineMetadata(
            side: CardSide.front,
            text: 'Marcus Vance',
            lineIndex: 0,
            blockIndex: 0,
            boundingBox: Rect.fromLTWH(20, 40, 200, 25),
          ),
          const OcrLineMetadata(
            side: CardSide.front,
            text: 'Product Strategist',
            lineIndex: 1,
            blockIndex: 0,
            boundingBox: Rect.fromLTWH(20, 70, 200, 25),
          ),
        ],
      );

      final blockRight = OcrBlockMetadata(
        side: CardSide.front,
        text: 'Vance Advisory Group\nmarcus@vance.io',
        blockIndex: 1,
        boundingBox: const Rect.fromLTWH(250, 40, 200, 60),
        lines: [
          const OcrLineMetadata(
            side: CardSide.front,
            text: 'Vance Advisory Group',
            lineIndex: 0,
            blockIndex: 1,
            boundingBox: Rect.fromLTWH(250, 40, 200, 25),
          ),
          const OcrLineMetadata(
            side: CardSide.front,
            text: 'marcus@vance.io',
            lineIndex: 1,
            blockIndex: 1,
            boundingBox: Rect.fromLTWH(250, 70, 200, 25),
          ),
        ],
      );

      final sideResult = OcrSideResult(
        side: CardSide.front,
        imagePath: '/tmp/twocol.jpg',
        rawText: 'Marcus Vance\nVance Advisory Group\nProduct Strategist\nmarcus@vance.io',
        blocks: [blockLeft, blockRight],
      );

      final data = parser.parseSide(sideResult);
      expect(data.fullName, 'Marcus Vance');
      expect(data.jobTitle, 'Product Strategist');
      expect(data.company, 'Vance Advisory Group');
      expect(data.emailAddresses.first.email, 'marcus@vance.io');
    });

    // -------------------------------------------------------------
    // 20. Uppercase names
    // -------------------------------------------------------------
    test('20. Uppercase personal name is recognized correctly', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: '''
DR. ANANYA SHARMA
CONSULTANT CARDIOLOGIST
APOLLO HEART INSTITUTE
+91 99887 76655
ananya.sharma@apollo.org
''',
      );

      final data = parser.parseSide(front);
      expect(data.fullName, 'DR. ANANYA SHARMA');
      expect(data.jobTitle, 'CONSULTANT CARDIOLOGIST');
      expect(data.company, 'APOLLO HEART INSTITUTE');
    });

    // -------------------------------------------------------------
    // 21. Decorative/unusual text ordering
    // -------------------------------------------------------------
    test('21. Decorative slogan and certification headers do not hijack personal name', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: '''
INNOVATING THE FUTURE TOGETHER
ISO 9001:2015 CERTIFIED FACILITY
Emily Watson
VP of Operations
Acme Robotics Corp.
emily@acmerobotics.com
''',
      );

      final data = parser.parseSide(front);
      expect(data.fullName, 'Emily Watson');
      expect(data.jobTitle, 'VP of Operations');
      expect(data.company, 'Acme Robotics Corp.');
    });

    // -------------------------------------------------------------
    // 22. Conflicting company candidates
    // -------------------------------------------------------------
    test('22. Conflicting company candidate on back is saved as alternative', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: '''
Michael Scott
Regional Manager
Dunder Mifflin Paper Co.
mscott@dundermifflin.com
''',
      );

      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: '/tmp/b.jpg',
        rawText: '''
A Subsidiary of Sabre Industries Inc.
1725 Slough Avenue
Scranton, PA
''',
      );

      final data = parser.parseDualSided(front: front, back: back);
      expect(
        data.alternativeCandidates['company']!.any((c) => c.contains('Sabre Industries Inc.')),
        isTrue,
      );
    });

    // -------------------------------------------------------------
    // 23. Empty OCR result
    // -------------------------------------------------------------
    test('23. Empty OCR text produces empty card data safely without error', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: '',
      );

      final data = parser.parseSide(front);
      expect(data.isEmpty, isTrue);
      expect(data.fullName, isNull);
      expect(data.phoneNumbers, isEmpty);
      expect(data.emailAddresses, isEmpty);
    });

    // -------------------------------------------------------------
    // 24. ML Kit failure
    // -------------------------------------------------------------
    testWidgets('24. ML Kit failure is handled gracefully with error dialog', (tester) async {
      final picker = FakeImagePicker()..nextFile = XFile('bad_image.jpg');
      final ocr = FakeOcrService(shouldThrow: true);

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(imagePicker: picker, ocrService: ocr),
        ),
      );

      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inline_take_photo_button')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('scan_details_button')));
      await tester.tap(find.byKey(const Key('scan_details_button')));
      await tester.pumpAndSettle();

      expect(find.text('OCR Scanning Error'), findsOneWidget);
    });

    // -------------------------------------------------------------
    // 25. Single-side regression
    // -------------------------------------------------------------
    test('25. Single-side legacy parse compatibility is strictly preserved', () {
      const rawText = '''
Vikram Roy
Software Architect
FinTech Systems Pvt Ltd
+91 91234 56789
vikram@fintechsys.in
www.fintechsys.in
Bengaluru, Karnataka
''';

      final legacyData = parser.parse(rawText);
      final sideResult = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: rawText,
      );
      final newSideData = parser.parseSide(sideResult);

      expect(newSideData.fullName, legacyData.fullName);
      expect(newSideData.jobTitle, legacyData.jobTitle);
      expect(newSideData.company, legacyData.company);
      expect(newSideData.phoneNumbers.length, legacyData.phoneNumbers.length);
      expect(newSideData.emailAddresses.length, legacyData.emailAddresses.length);
      expect(newSideData.website, legacyData.website);
      expect(newSideData.address, legacyData.address);
    });

    // -------------------------------------------------------------
    // 26. Existing duplicate detection behavior
    // -------------------------------------------------------------
    testWidgets('26. Duplicate detection checks phone & email against saved contacts', (tester) async {
      final duplicateService = FakeImportedContactService(
        duplicateResult: CheckDuplicateResult(
          isDuplicate: true,
          matchedBy: 'phone',
          existingContact: ImportedContact(
            id: '1',
            fullName: 'Existing Contact',
            phoneNumbers: const [],
            emailAddresses: const [],
            createdAtUtc: DateTime.now(),
          ),
        ),
      );

      final cardData = BusinessCardData(
        fullName: 'New Contact',
        phoneNumbers: const [BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile')],
        emailAddresses: const [BusinessCardEmail(email: 'contact@example.com', label: 'Work')],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(
            cardData: cardData,
            contactService: duplicateService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger Save to Digital Share
      await tester.ensureVisible(find.byKey(const Key('confirm_details_button')));
      await tester.tap(find.byKey(const Key('confirm_details_button')));
      await tester.pumpAndSettle();

      expect(duplicateService.checkDuplicateCalled, isTrue);
      // Duplicate dialog is presented
      expect(find.text('Already Saved'), findsOneWidget);
    });

    // -------------------------------------------------------------
    // 27. Existing save behavior
    // -------------------------------------------------------------
    testWidgets('27. Save to Phone and Save in Digital Share succeed with card details', (tester) async {
      final fakePhoneContactService = FakeContactService();
      final fakeImportedService = FakeImportedContactService();

      final cardData = BusinessCardData(
        fullName: 'Savannah Brooks',
        company: 'Brooks & Associates',
        jobTitle: 'Partner',
        phoneNumbers: const [BusinessCardPhone(number: '+1 650 555 0100', label: 'Mobile')],
        emailAddresses: const [BusinessCardEmail(email: 'savannah@brooks.law', label: 'Work')],
        website: 'https://brooks.law',
        address: 'Palo Alto, CA',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(
            cardData: cardData,
            phoneContactService: fakePhoneContactService,
            contactService: fakeImportedService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Save to phone via ContactMessageComposer action
      await tester.ensureVisible(find.byKey(const Key('add_to_contacts_action_button')));
      await tester.tap(find.byKey(const Key('add_to_contacts_action_button')));
      await tester.pumpAndSettle();
      expect(fakePhoneContactService.saveBusinessCardCalled, isTrue);

      // Save in Digital Share
      await tester.ensureVisible(find.byKey(const Key('confirm_details_button')));
      await tester.tap(find.byKey(const Key('confirm_details_button')));
      await tester.pumpAndSettle();
      expect(fakeImportedService.saveContactCalled, isTrue);
    });
  });
}
