import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/screens/scan/business_card_review_screen.dart';
import 'package:digital_share/services/business_card_ocr_service.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/card_geometry_service.dart';

void main() {
  const parser = BusinessCardParser();
  const ocrService = BusinessCardOcrService();
  const geometryService = CardGeometryService();

  group('Phase 2C: Real-World Business Card Hardening — Fixture Tests', () {
    // -------------------------------------------------------------------------
    // 1. Fixture A: KUMAR JAYANT, I.A.S. (Prominent person name with credentials)
    // -------------------------------------------------------------------------
    test('1. IAS credential/suffix does not break name; multi-line designation combined', () {
      const text = '''
KUMAR JAYANT, I.A.S.,
Additional Chief Secretary /
Chairman and Managing Director
THE TAMILNADU INDUSTRIAL INVESTMENT CORPORATION LTD.,
(A Government of Tamilnadu Undertaking)
MHU Complex, 692, Anna Salai,
Nandanam, Chennai - 600 035.
Mob: 94443 43536
''';
      final res = parser.parse(text);

      expect(res.fullName, 'KUMAR JAYANT');
      expect(res.jobTitle, 'Additional Chief Secretary / Chairman and Managing Director');
      expect(res.company, 'THE TAMILNADU INDUSTRIAL INVESTMENT CORPORATION LTD.');
      expect(res.alternativeCandidates['credentials'], isNotNull);
      expect(res.alternativeCandidates['credentials']!.first, contains('I.A.S.'));
      expect(res.phoneNumbers, isNotEmpty);
      expect(res.phoneNumbers.any((p) => p.number.contains('94443 43536')), isTrue);
    });

    test('2. Multiple designation lines can be combined/preserved appropriately', () {
      const text = '''
Dr. Ramesh Chand, MD
Executive Director /
Chief Medical Officer
Apollo Hospitals
Tel: 044 2829 0200
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Dr. Ramesh Chand');
      expect(res.jobTitle, 'Executive Director / Chief Medical Officer');
      expect(res.company, 'Apollo Hospitals');
    });

    test('3. Long government corporation recognized as organization', () {
      const text = '''
THE TAMILNADU INDUSTRIAL INVESTMENT CORPORATION LTD.
(A Government of Tamilnadu Undertaking)
S. Sundaram
General Manager
Phone: 044 2434 5678
''';
      final res = parser.parse(text);
      expect(res.company, 'THE TAMILNADU INDUSTRIAL INVESTMENT CORPORATION LTD.');
      expect(res.fullName, 'S. Sundaram');
      expect(res.jobTitle, 'General Manager');
    });

    // -------------------------------------------------------------------------
    // 4. Fixture B: Slogan & Visually Separated Person / Company (Banyan Tree)
    // -------------------------------------------------------------------------
    test('4. Slogan before company is not classified as person', () {
      const text = '''
We bring performances aLIVE
Banyan Tree
www.BanyanTreeEvents.com
Mahesh Babu
Managing Director
Banyan Tree Events India Pvt. Ltd.
123, Gokul Arcade, Subhash Road, Vile Parle East, Mumbai - 400 057
Mobile +91 9821217572
Email maheshbabu@banyantreeevents.com
''';
      final res = parser.parse(text);

      expect(res.fullName, 'Mahesh Babu');
      expect(res.jobTitle, 'Managing Director');
      expect(res.company, 'Banyan Tree Events India Pvt. Ltd.');
      expect(res.website, 'www.BanyanTreeEvents.com');
      expect(res.emailAddresses.any((e) => e.email == 'maheshbabu@banyantreeevents.com'), isTrue);
      expect(res.phoneNumbers.any((p) => p.number.contains('9821217572')), isTrue);
      expect(res.fullName != 'We bring performances aLIVE', isTrue);
      expect(res.alternativeCandidates['slogan'], isNotNull);
      expect(res.alternativeCandidates['slogan']!.first, contains('performances aLIVE'));
    });

    test('5. Slogan not classified as designation', () {
      const text = '''
Transforming healthcare for all
Dr. Priya Sharma
Cardiologist
City Hospital
Tel: +91 44 2499 1122
''';
      final res = parser.parse(text);
      expect(res.jobTitle, 'Cardiologist');
      expect(res.jobTitle != 'Transforming healthcare for all', isTrue);
    });

    test('6. Person visually separated from company is still detected', () {
      const text = '''
Global Logistics Solutions
www.globallogistics.com
Office: 044 11223344

Sarah Jenkins
Chief Operating Officer

123 Harborside Ave, Chennai - 600001
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Sarah Jenkins');
      expect(res.jobTitle, 'Chief Operating Officer');
      expect(res.company, 'Global Logistics Solutions');
    });

    // -------------------------------------------------------------------------
    // 7. Fixture C: Decorative / Cursive Font Card (Antony Lobo)
    // -------------------------------------------------------------------------
    test('7. Decorative / diplomatic card correctly parses Antony Lobo and Consulate of Spain', () {
      const text = '''
Antony Lobo
Hon. Consul of Spain
Consulate of Spain
6, Nirmal Road, Santhome,
Chennai - 600 004
Tel: +91-44-42107657
spainconsulate.chennai@gmail.com
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Antony Lobo');
      expect(res.jobTitle, 'Hon. Consul of Spain');
      expect(res.company, 'Consulate of Spain');
      expect(res.phoneNumbers.any((p) => p.number.contains('42107657')), isTrue);
      expect(res.emailAddresses.any((e) => e.email.contains('spainconsulate.chennai@gmail.com')), isTrue);
    });

    // -------------------------------------------------------------------------
    // 8. Fixture D: Background / Non-Card Text (Chandra Kanthan. M / 1 Shift)
    // -------------------------------------------------------------------------
    test('8. Random short background text "1 Shift" is rejected and company remains null', () {
      const text = '''
Chandra Kanthan. M
1 Shift
83002 71261
+91 94444 20464
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Chandra Kanthan. M');
      expect(res.company, isNull);
      expect(res.company != '1 Shift', isTrue);
      expect(res.phoneNumbers.length, greaterThanOrEqualTo(2));
    });

    test('9. Weak company evidence results in null without fabricating data', () {
      const text = '''
Rajesh Kumar
Desk 4
98400 12345
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Rajesh Kumar');
      expect(res.company, isNull);
    });

    test('10. Unknown legitimate organization can still be detected contextually', () {
      const text = '''
Meridian Crest Partners
Vikram Singhania
Senior Partner
Tel: 022 2847 9900
vikram@meridiancrest.com
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Vikram Singhania');
      expect(res.jobTitle, 'Senior Partner');
      expect(res.company, 'Meridian Crest Partners');
    });
  });

  group('Phase 2C: BusinessCardReviewScreen Empty Optional Fields Tests', () {
    testWidgets('10. Empty jobTitle renders + Add Job Title button', (tester) async {
      const data = BusinessCardData(
        fullName: 'Chandra Kanthan. M',
        jobTitle: null,
        company: 'Some Org Ltd.',
        phoneNumbers: [BusinessCardPhone(number: '+91 94444 20464')],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: BusinessCardReviewScreen(cardData: data),
        ),
      );

      expect(find.byKey(const Key('add_job_title_button')), findsOneWidget);
      expect(find.text('+ Add Job Title'), findsOneWidget);
      expect(find.byKey(const Key('review_job_title_field')), findsNothing);
    });

    testWidgets('11. Tapping Add Job Title reveals editable field', (tester) async {
      const data = BusinessCardData(
        fullName: 'Chandra Kanthan. M',
        jobTitle: null,
        company: null,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: BusinessCardReviewScreen(cardData: data),
        ),
      );

      expect(find.byKey(const Key('review_job_title_field')), findsNothing);
      await tester.tap(find.byKey(const Key('add_job_title_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('review_job_title_field')), findsOneWidget);
    });

    testWidgets('12. Empty company renders + Add Company button', (tester) async {
      const data = BusinessCardData(
        fullName: 'Chandra Kanthan. M',
        jobTitle: 'Consultant',
        company: null,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: BusinessCardReviewScreen(cardData: data),
        ),
      );

      expect(find.byKey(const Key('add_company_button')), findsOneWidget);
      expect(find.text('+ Add Company'), findsOneWidget);
      expect(find.byKey(const Key('review_company_field')), findsNothing);
    });

    testWidgets('13. Tapping Add Company reveals editable field', (tester) async {
      const data = BusinessCardData(
        fullName: 'Chandra Kanthan. M',
        jobTitle: null,
        company: null,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: BusinessCardReviewScreen(cardData: data),
        ),
      );

      expect(find.byKey(const Key('review_company_field')), findsNothing);
      await tester.tap(find.byKey(const Key('add_company_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('review_company_field')), findsOneWidget);
    });

    testWidgets('14. Detected job title renders editable field', (tester) async {
      const data = BusinessCardData(
        fullName: 'Mahesh Babu',
        jobTitle: 'Managing Director',
        company: 'Banyan Tree Events India Pvt. Ltd.',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: BusinessCardReviewScreen(cardData: data),
        ),
      );

      expect(find.byKey(const Key('review_job_title_field')), findsOneWidget);
      final field = tester.widget<TextFormField>(find.byKey(const Key('review_job_title_field')));
      expect(field.controller?.text, 'Managing Director');
      expect(find.byKey(const Key('add_job_title_button')), findsNothing);
    });

    testWidgets('15. Detected company renders editable field', (tester) async {
      const data = BusinessCardData(
        fullName: 'Mahesh Babu',
        jobTitle: 'Managing Director',
        company: 'Banyan Tree Events India Pvt. Ltd.',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: BusinessCardReviewScreen(cardData: data),
        ),
      );

      expect(find.byKey(const Key('review_company_field')), findsOneWidget);
      final field = tester.widget<TextFormField>(find.byKey(const Key('review_company_field')));
      expect(field.controller?.text, 'Banyan Tree Events India Pvt. Ltd.');
      expect(find.byKey(const Key('add_company_button')), findsNothing);
    });

    testWidgets('16. No "e.g. Senior Developer" placeholder exists', (tester) async {
      const data = BusinessCardData(
        fullName: 'Test User',
        jobTitle: 'Specialist',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: BusinessCardReviewScreen(cardData: data),
        ),
      );

      expect(find.text('e.g. Senior Developer'), findsNothing);
    });

    testWidgets('17. No "e.g. ABC Technologies" placeholder exists', (tester) async {
      const data = BusinessCardData(
        fullName: 'Test User',
        company: 'Apex Labs',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: BusinessCardReviewScreen(cardData: data),
        ),
      );

      expect(find.text('e.g. ABC Technologies'), findsNothing);
    });
  });

  group('Phase 2C: Multi-Pass OCR & Deduplication Tests', () {
    test('18. Enhanced OCR fallback activates only for weak OCR', () {
      final weakResult = OcrSideResult(
        side: CardSide.front,
        imagePath: '/tmp/test.jpg',
        rawText: 'Antony\nConsul',
        lines: [
          OcrLineMetadata(
            text: 'Antony',
            side: CardSide.front,
            lineIndex: 0,
            blockIndex: 0,
            boundingBox: const Rect.fromLTWH(10, 10, 50, 20),
            cornerPoints: const [],
          ),
          OcrLineMetadata(
            text: 'Consul',
            side: CardSide.front,
            lineIndex: 1,
            blockIndex: 0,
            boundingBox: const Rect.fromLTWH(10, 35, 50, 20),
            cornerPoints: const [],
          ),
        ],
        blocks: [],
        processedAt: DateTime.now().toUtc(),
      );

      expect(ocrService.isOcrResultSufficient(weakResult), isFalse);
    });

    test('19. Strong OCR does not trigger unnecessary second pass', () {
      final strongResult = OcrSideResult(
        side: CardSide.front,
        imagePath: '/tmp/test.jpg',
        rawText: '''
Mahesh Babu
Managing Director
Banyan Tree Events India Pvt. Ltd.
Tel: +91 9821217572
email: mahesh@banyantree.com
''',
        lines: [
          OcrLineMetadata(
            text: 'Mahesh Babu',
            side: CardSide.front,
            lineIndex: 0,
            blockIndex: 0,
            boundingBox: const Rect.fromLTWH(10, 10, 100, 20),
            cornerPoints: const [],
          ),
          OcrLineMetadata(
            text: 'Managing Director',
            side: CardSide.front,
            lineIndex: 1,
            blockIndex: 0,
            boundingBox: const Rect.fromLTWH(10, 35, 100, 20),
            cornerPoints: const [],
          ),
          OcrLineMetadata(
            text: 'Banyan Tree Events India Pvt. Ltd.',
            side: CardSide.front,
            lineIndex: 2,
            blockIndex: 0,
            boundingBox: const Rect.fromLTWH(10, 60, 200, 20),
            cornerPoints: const [],
          ),
          OcrLineMetadata(
            text: 'Tel: +91 9821217572',
            side: CardSide.front,
            lineIndex: 3,
            blockIndex: 1,
            boundingBox: const Rect.fromLTWH(10, 85, 120, 20),
            cornerPoints: const [],
          ),
        ],
        blocks: [],
        processedAt: DateTime.now().toUtc(),
      );

      expect(ocrService.isOcrResultSufficient(strongResult), isTrue);
    });

    test('20. Multi-pass phone deduplication avoids duplicate numbers in merged result', () {
      final pass1 = OcrSideResult(
        side: CardSide.front,
        imagePath: '/tmp/card.jpg',
        rawText: 'Chennai - 600004\nTel: +91 9821217572',
        lines: [
          OcrLineMetadata(
            text: 'Chennai - 600004',
            side: CardSide.front,
            lineIndex: 0,
            blockIndex: 0,
            boundingBox: const Rect.fromLTWH(10, 10, 100, 20),
            cornerPoints: const [],
          ),
          OcrLineMetadata(
            text: 'Tel: +91 9821217572',
            side: CardSide.front,
            lineIndex: 1,
            blockIndex: 0,
            boundingBox: const Rect.fromLTWH(10, 35, 100, 20),
            cornerPoints: const [],
          ),
        ],
        blocks: [],
        processedAt: DateTime.now().toUtc(),
      );

      final pass2 = OcrSideResult(
        side: CardSide.front,
        imagePath: '/tmp/card.jpg',
        rawText: 'Antony Lobo\n+919821217572',
        lines: [
          OcrLineMetadata(
            text: 'Antony Lobo',
            side: CardSide.front,
            lineIndex: 0,
            blockIndex: 0,
            boundingBox: const Rect.fromLTWH(10, 5, 80, 20),
            cornerPoints: const [],
          ),
          OcrLineMetadata(
            text: '+919821217572',
            side: CardSide.front,
            lineIndex: 1,
            blockIndex: 0,
            boundingBox: const Rect.fromLTWH(10, 35, 100, 20),
            cornerPoints: const [],
          ),
        ],
        blocks: [],
        processedAt: DateTime.now().toUtc(),
      );

      final merged = ocrService.mergeOcrResults(pass1: pass1, pass2: pass2);
      expect(merged.rawText, contains('Antony Lobo'));

      final parsed = parser.parseSide(merged);
      // Ensure only 1 phone number is extracted, not 2 duplicates
      expect(parsed.phoneNumbers.length, 1);
      expect(parsed.fullName, 'Antony Lobo');
    });

    test('21. Multi-pass email deduplication avoids duplicate emails', () {
      final pass1 = OcrSideResult(
        side: CardSide.front,
        imagePath: '/tmp/card.jpg',
        rawText: 'spainconsulate.chennai@gmail.com',
        lines: [
          OcrLineMetadata(
            text: 'spainconsulate.chennai@gmail.com',
            side: CardSide.front,
            lineIndex: 0,
            blockIndex: 0,
            boundingBox: const Rect.fromLTWH(10, 10, 150, 20),
            cornerPoints: const [],
          ),
        ],
        blocks: [],
        processedAt: DateTime.now().toUtc(),
      );

      final pass2 = OcrSideResult(
        side: CardSide.front,
        imagePath: '/tmp/card.jpg',
        rawText: 'Antony Lobo\nSPAINCONSULATE.CHENNAI@GMAIL.COM',
        lines: [
          OcrLineMetadata(
            text: 'Antony Lobo',
            side: CardSide.front,
            lineIndex: 0,
            blockIndex: 0,
            boundingBox: const Rect.fromLTWH(10, 5, 80, 20),
            cornerPoints: const [],
          ),
          OcrLineMetadata(
            text: 'SPAINCONSULATE.CHENNAI@GMAIL.COM',
            side: CardSide.front,
            lineIndex: 1,
            blockIndex: 0,
            boundingBox: const Rect.fromLTWH(10, 10, 150, 20),
            cornerPoints: const [],
          ),
        ],
        blocks: [],
        processedAt: DateTime.now().toUtc(),
      );

      final merged = ocrService.mergeOcrResults(pass1: pass1, pass2: pass2);
      final parsed = parser.parseSide(merged);

      expect(parsed.emailAddresses.length, 1);
      expect(parsed.emailAddresses.first.email.toLowerCase(), 'spainconsulate.chennai@gmail.com');
      expect(parsed.fullName, 'Antony Lobo');
    });

    test('22. Card-region OCR excludes simulated outside-card text', () {
      final corners = CardCorners(
        topLeft: Point(100, 100),
        topRight: Point(900, 100),
        bottomLeft: Point(100, 600),
        bottomRight: Point(900, 600),
      );

      // Points inside card
      expect(corners.containsPoint(200, 200), isTrue);
      expect(corners.containsPoint(500, 350), isTrue);

      // Points outside card (table surface, keyboard, background stickers)
      expect(corners.containsPoint(50, 50), isFalse);
      expect(corners.containsPoint(950, 750), isFalse);
      expect(corners.containsPoint(50, 300), isFalse);
    });

    test('23. Failed card detection safely uses original image', () async {
      // Create a solid blank image (no card edges)
      final blankImage = img.Image(width: 400, height: 300);
      img.fill(blankImage, color: img.ColorRgb8(128, 128, 128));

      final cornersDetection = geometryService.detectCorners(blankImage);
      // Low confidence or null corners on blank surface
      expect(cornersDetection.confidence < geometryService.minConfidenceThreshold || cornersDetection.corners == null, isTrue);
    });
  });
}
