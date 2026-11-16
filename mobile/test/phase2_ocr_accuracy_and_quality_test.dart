import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/screens/scan/business_card_scan_screen.dart';
import 'package:digital_share/services/business_card_ocr_service.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/card_geometry_service.dart';
import 'package:digital_share/services/image_enhancement_service.dart';
import 'package:digital_share/services/image_quality_service.dart';
import 'package:digital_share/services/pending_card_capture_store.dart';

class MockImagePicker extends ImagePicker {
  XFile? nextFile;
  LostDataResponse lostData = LostDataResponse.empty();

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    return nextFile;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    return lostData;
  }
}

class MockOcrService implements IBusinessCardOcrService {
  String frontText;
  String backText;
  bool wasCalled = false;

  MockOcrService({this.frontText = '', this.backText = ''});

  @override
  Future<String> recognizeTextFromPath(String imagePath) async {
    wasCalled = true;
    return frontText;
  }

  @override
  Future<OcrSideResult> processCardSide({
    required String imagePath,
    required CardSide side,
    String? source,
    ViewfinderNormalizedRect? viewfinderRoi,
  }) async {
    wasCalled = true;
    return OcrSideResult.fromText(
      side: side,
      imagePath: imagePath,
      rawText: side == CardSide.front ? frontText : backText,
    );
  }
}

class FakeQualityService extends ImageQualityService {
  final ImageQualityResult stubbedResult;

  const FakeQualityService(this.stubbedResult);

  @override
  Future<ImageQualityResult> evaluateImagePath(String imagePath) async {
    return stubbedResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PendingCardCaptureStore.resetForTesting();
  });

  tearDown(() {
    PendingCardCaptureStore.resetForTesting();
  });

  group('Phase 2: Image Quality Assessment Tests', () {
    const qualityService = ImageQualityService();

    test('1. Good image quality evaluation', () {
      final image = img.Image(width: 1200, height: 800);
      // Fill with moderate midtone pattern
      for (int y = 0; y < 800; y++) {
        for (int x = 0; x < 1200; x++) {
          final c = (x % 20 == 0 || y % 20 == 0) ? 200 : 80;
          image.setPixelRgb(x, y, c, c, c);
        }
      }

      final result = qualityService.evaluateImage(image);
      expect(result.status, ImageQualityStatus.good);
      expect(result.isGood, isTrue);
      expect(result.warnings.isEmpty, isTrue);
    });

    test('2. Severe blur detected with warning', () {
      // Uniform solid image has zero Laplacian variance (maximum blur)
      final flatImage = img.Image(width: 1000, height: 600);
      img.fill(flatImage, color: img.ColorRgb8(128, 128, 128));

      final result = qualityService.evaluateImage(flatImage);
      expect(result.isBlurry, isTrue);
      expect(result.warnings.any((w) => w.contains('blurry')), isTrue);
      expect(result.status, ImageQualityStatus.poorRetakeRecommended);
    });

    test('3. Severe underexposure detected', () {
      final darkImage = img.Image(width: 1000, height: 600);
      img.fill(darkImage, color: img.ColorRgb8(15, 15, 15)); // avg luma 15 < 25

      final result = qualityService.evaluateImage(darkImage);
      expect(result.isUnderexposed, isTrue);
      expect(result.status, ImageQualityStatus.poorRetakeRecommended);
    });

    test('4. Severe overexposure / glare detected', () {
      final blownImage = img.Image(width: 1000, height: 600);
      img.fill(blownImage, color: img.ColorRgb8(252, 252, 252));

      final result = qualityService.evaluateImage(blownImage);
      expect(result.isOverexposed, isTrue);
      expect(result.status, ImageQualityStatus.poorRetakeRecommended);
    });

    test('5. Low resolution image flagged with warning', () {
      final smallImage = img.Image(width: 300, height: 200);
      img.fill(smallImage, color: img.ColorRgb8(120, 120, 120));

      final result = qualityService.evaluateImage(smallImage);
      expect(result.isTooSmall, isTrue);
      expect(result.warnings.any((w) => w.contains('Low resolution')), isTrue);
    });
  });

  group('Phase 2: Card Edge Detection & Perspective Correction Tests', () {
    const geometryService = CardGeometryService();

    test('6. Corner detection failure falls back to original image', () async {
      final result = await geometryService.correctPerspectiveIfReliable(
        'c:/non_existent_card_path_12345.jpg',
      );
      expect(result.wasCorrected, isFalse);
      expect(result.imagePath, 'c:/non_existent_card_path_12345.jpg');
    });

    test('7. High confidence quadrilateral detection and rectification', () async {
      // Create a simulated 800x500 image with a distinct centered business card
      final image = img.Image(width: 800, height: 500);
      img.fill(image, color: img.ColorRgb8(30, 30, 30)); // dark surface

      // Draw light card in the center (100, 80) to (700, 420)
      for (int y = 80; y < 420; y++) {
        for (int x = 100; x < 700; x++) {
          image.setPixelRgb(x, y, 230, 230, 230);
        }
      }

      final detection = geometryService.detectCorners(image);
      expect(detection.corners, isNotNull);
      expect(detection.confidence, greaterThanOrEqualTo(0.65));
      expect(detection.corners!.topLeft.x, lessThan(detection.corners!.topRight.x));
      expect(detection.corners!.topLeft.y, lessThan(detection.corners!.bottomLeft.y));
    });

    test('8. Perspective correction preserves landscape and portrait cards', () {
      // Test portrait card aspect ratio check
      final portraitCard = img.Image(width: 500, height: 800);
      img.fill(portraitCard, color: img.ColorRgb8(40, 40, 40));
      for (int y = 100; y < 700; y++) {
        for (int x = 80; x < 420; x++) {
          portraitCard.setPixelRgb(x, y, 220, 220, 220);
        }
      }

      final detection = geometryService.detectCorners(portraitCard);
      expect(detection.corners, isNotNull);
    });
  });

  group('Phase 2: Image Enhancement & Multi-Pass Evaluation Tests', () {
    const enhancementService = ImageEnhancementService();

    test('9. Dark card detection identifies predominantly dark background', () async {
      final tempDir = Directory.systemTemp.path;
      final darkFile = File('$tempDir/test_dark_card.jpg');
      final darkImg = img.Image(width: 200, height: 120);
      img.fill(darkImg, color: img.ColorRgb8(20, 25, 30));
      await darkFile.writeAsBytes(img.encodeJpg(darkImg));

      final isDark = await enhancementService.isDarkCard(darkFile.path);
      expect(isDark, isTrue);

      if (darkFile.existsSync()) darkFile.deleteSync();
    });

    test('10. Inverted candidate generation inverts colors for dark cards', () async {
      final tempDir = Directory.systemTemp.path;
      final srcFile = File('$tempDir/test_src_card.jpg');
      final srcImg = img.Image(width: 200, height: 120);
      img.fill(srcImg, color: img.ColorRgb8(10, 10, 10));
      await srcFile.writeAsBytes(img.encodeJpg(srcImg));

      final invertedPath = await enhancementService.createInvertedCandidate(srcFile.path);
      expect(invertedPath, isNotNull);
      expect(File(invertedPath!).existsSync(), isTrue);

      final invertedBytes = await File(invertedPath).readAsBytes();
      final invertedImg = img.decodeImage(invertedBytes)!;
      // Inverted of RGB(10,10,10) is roughly RGB(245,245,245)
      expect(invertedImg.getPixel(10, 10).r, greaterThan(230));

      if (srcFile.existsSync()) srcFile.deleteSync();
      if (File(invertedPath).existsSync()) File(invertedPath).deleteSync();
    });
  });

  group('Phase 2: Quality Dialog User Interaction Widget Tests', () {
    testWidgets('11. Poor image shows warning; User chooses "Use Anyway"', (tester) async {
      final picker = MockImagePicker();
      picker.nextFile = XFile('c:/test_poor_card.jpg');

      const poorResult = ImageQualityResult(
        status: ImageQualityStatus.poorRetakeRecommended,
        warnings: ['Photo appears blurry.', 'Low resolution.'],
        metrics: ImageQualityMetrics(
          width: 400,
          height: 250,
          blurScore: 30.0,
          averageLuminance: 120.0,
          blownOutRatio: 0.0,
        ),
      );

      final fakeQuality = FakeQualityService(poorResult);

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(
            imagePicker: picker,
            qualityService: fakeQuality,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Physical Business Card to expand options, then tap Camera
      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inline_take_photo_button')));
      await tester.pumpAndSettle();

      // Verify Quality Warning Dialog appears
      expect(find.text('Photo Quality Notice'), findsOneWidget);
      expect(find.text('This photo may be difficult to read.'), findsOneWidget);
      expect(find.text('Photo appears blurry.'), findsOneWidget);
      expect(find.byKey(const Key('quality_retake_button')), findsOneWidget);
      expect(find.byKey(const Key('quality_use_anyway_button')), findsOneWidget);

      // Tap "Use Anyway"
      await tester.tap(find.byKey(const Key('quality_use_anyway_button')));
      await tester.pumpAndSettle();

      // Dialog dismisses and image is staged
      expect(find.text('Photo Quality Notice'), findsNothing);
      expect(find.text('FRONT SIDE'), findsOneWidget);
    });

    testWidgets('12. Poor image shows warning; User chooses "Retake Photo"', (tester) async {
      final picker = MockImagePicker();
      picker.nextFile = XFile('c:/test_poor_card.jpg');

      const poorResult = ImageQualityResult(
        status: ImageQualityStatus.poorRetakeRecommended,
        warnings: ['Severe glare / overexposure detected.'],
        metrics: ImageQualityMetrics(
          width: 800,
          height: 500,
          blurScore: 100.0,
          averageLuminance: 240.0,
          blownOutRatio: 0.6,
        ),
      );

      final fakeQuality = FakeQualityService(poorResult);

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(
            imagePicker: picker,
            qualityService: fakeQuality,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inline_take_photo_button')));
      await tester.pumpAndSettle();

      expect(find.text('Photo Quality Notice'), findsOneWidget);

      // Tap "Retake Photo"
      await tester.tap(find.byKey(const Key('quality_retake_button')));
      await tester.pumpAndSettle();

      // Dialog dismisses and image is NOT staged (retake options shown in bottom sheet)
      expect(find.text('Photo Quality Notice'), findsNothing);
      expect(find.text('Retake Front Side'), findsOneWidget);
    });
  });

  group('Phase 2: Synthetic Business Card Layouts A through T Parser Tests', () {
    const parser = BusinessCardParser();

    test('Layout A: Company first / name second', () {
      const text = '''
Acme Industrial Solutions
David Miller
Operations Director
Tel: +1 415 555 2671
david@acmesolutions.com
''';
      final res = parser.parse(text);
      expect(res.company, 'Acme Industrial Solutions');
      expect(res.fullName, 'David Miller');
      expect(res.jobTitle, 'Operations Director');
      expect(res.phoneNumbers.first.number, contains('555 2671'));
      expect(res.emailAddresses.first.email, 'david@acmesolutions.com');
    });

    test('Layout B: Name first / company second', () {
      const text = '''
Ananya Roy
Senior UX Designer
DesignCraft Studio
ananya@designcraft.in
+91 98400 12345
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Ananya Roy');
      expect(res.jobTitle, 'Senior UX Designer');
      expect(res.company, 'DesignCraft Studio');
      expect(res.phoneNumbers.first.number, contains('98400'));
    });

    test('Layout C: Vertical card design', () {
      const text = '''
Pooja Patel
Architect
Verve Architecture
Mob: +91 98200 45678
pooja@vervearch.com
Mumbai, Maharashtra
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Pooja Patel');
      expect(res.jobTitle, 'Architect');
      expect(res.company, 'Verve Architecture');
      expect(res.address, contains('Mumbai'));
    });

    test('Layout D: Two columns with contact details alongside designation', () {
      final frontOcr = OcrSideResult(
        side: CardSide.front,
        imagePath: 'card_col.jpg',
        rawText: '''
Dr Rajesh Verma
Cardiologist
Apollo Hospitals
Mobile: +91 94440 98765
rajesh.verma@apollo.com
''',
        lines: [
          const OcrLineMetadata(
            text: 'Dr Rajesh Verma',
            side: CardSide.front,
            lineIndex: 0,
            blockIndex: 0,
            boundingBox: Rect.fromLTWH(20, 30, 180, 25),
          ),
          const OcrLineMetadata(
            text: 'Cardiologist',
            side: CardSide.front,
            lineIndex: 1,
            blockIndex: 0,
            boundingBox: Rect.fromLTWH(20, 60, 150, 20),
          ),
          const OcrLineMetadata(
            text: 'Apollo Hospitals',
            side: CardSide.front,
            lineIndex: 2,
            blockIndex: 0,
            boundingBox: Rect.fromLTWH(20, 90, 170, 20),
          ),
          const OcrLineMetadata(
            text: 'Mobile: +91 94440 98765',
            side: CardSide.front,
            lineIndex: 3,
            blockIndex: 1,
            boundingBox: Rect.fromLTWH(250, 30, 200, 20),
          ),
          const OcrLineMetadata(
            text: 'rajesh.verma@apollo.com',
            side: CardSide.front,
            lineIndex: 4,
            blockIndex: 1,
            boundingBox: Rect.fromLTWH(250, 60, 210, 20),
          ),
        ],
      );

      final res = parser.parseSide(frontOcr);
      expect(res.fullName, 'Dr Rajesh Verma');
      expect(res.jobTitle, 'Cardiologist');
      expect(res.company, 'Apollo Hospitals');
      expect(res.phoneNumbers.first.number, contains('94440'));
      expect(res.emailAddresses.first.email, 'rajesh.verma@apollo.com');
    });

    test('Layout E: Phone/email on opposite column', () {
      const text = '''
Suresh Menon
General Manager
Horizon Logistics
Tel: 044 4524 2424
Email: smenon@horizon.in
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Suresh Menon');
      expect(res.jobTitle, 'General Manager');
      expect(res.phoneNumbers.first.number, '044 4524 2424');
    });

    test('Layout F: Address on back of card', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: 'front.jpg',
        rawText: '''
Vikram Seth
Chartered Accountant
Seth & Associates
vikram@sethca.com
''',
      );
      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: 'back.jpg',
        rawText: '''
Headquarters:
Plot 45, Anna Salai, T. Nagar
Chennai - 600017, Tamil Nadu, India
''',
      );

      final res = parser.parseDualSided(front: front, back: back);
      expect(res.fullName, 'Vikram Seth');
      expect(res.jobTitle, 'Chartered Accountant');
      expect(res.company, 'Seth & Associates');
      expect(res.address, contains('Chennai - 600017'));
    });

    test('Layout G: Multiple phone numbers (Mobile + Office + WhatsApp)', () {
      const text = '''
Neha Gupta
Sales Manager
Alpha Infotech
Mobile: +91 98111 22334
Office: 011 2654 3210
Fax: 011 2654 3219
''';
      final res = parser.parse(text);
      expect(res.phoneNumbers.length, 3);
      expect(res.phoneNumbers[0].label, 'Mobile');
      expect(res.phoneNumbers[1].label, 'Office');
      expect(res.phoneNumbers[2].label, 'Fax');
    });

    test('Layout H: Multiple email addresses (Work + Personal)', () {
      const text = '''
Carlos Gomez
Solutions Architect
CloudCore Systems
Work: carlos@cloudcore.io
Personal: carlos.gomez@gmail.com
''';
      final res = parser.parse(text);
      expect(res.emailAddresses.length, 2);
      expect(res.emailAddresses[0].email, 'carlos@cloudcore.io');
      expect(res.emailAddresses[0].label, 'Work');
      expect(res.emailAddresses[1].email, 'carlos.gomez@gmail.com');
      expect(res.emailAddresses[1].label, 'Personal');
    });

    test('Layout I: Company logo text before person\'s name (MEDINDIA example)', () {
      const text = '''
MEDINDIA
Dr Sunil Shroff
Managing Trustee
Health Information For All
Tel: +91 98400 25680
shroffmed@gmail.com
www.medindia.net
''';
      final res = parser.parse(text);
      expect(res.company, 'MEDINDIA');
      expect(res.fullName, 'Dr Sunil Shroff');
      expect(res.jobTitle, 'Managing Trustee');
      expect(res.phoneNumbers.first.number, contains('98400'));
      expect(res.emailAddresses.first.email, 'shroffmed@gmail.com');
      expect(res.website, contains('medindia.net'));
    });

    test('Layout J: Slogan before name resistance', () {
      const text = '''
Innovate Technologies
Building the Future
Arun Kumar
Lead Developer
arun@innovatetech.com
''';
      final res = parser.parse(text);
      expect(res.company, 'Innovate Technologies');
      expect(res.fullName, 'Arun Kumar');
      expect(res.jobTitle, 'Lead Developer');
    });

    test('Layout K: All-uppercase card', () {
      const text = '''
ABC TECHNOLOGIES
DENIL VARGHESE
SOFTWARE DEVELOPER
PHONE: +91 98765 43210
EMAIL: DENIL@ABCTECH.COM
''';
      final res = parser.parse(text);
      expect(res.company, 'ABC TECHNOLOGIES');
      expect(res.fullName, 'DENIL VARGHESE');
      expect(res.jobTitle, 'SOFTWARE DEVELOPER');
      expect(res.emailAddresses.first.email, 'DENIL@ABCTECH.COM');
      expect(res.emailAddresses.first.normalizedEmail, 'denil@abctech.com');
    });

    test('Layout L: International contact details (UK, US, India)', () {
      const text = '''
Sarah Jenkins
Global Consultant
Alliance Group
Tel UK: +44 20 7946 0958
Tel US: +1 (555) 019-2834
Mob IN: +91 98400 25680
sarah@alliancegroup.co.uk
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Sarah Jenkins');
      expect(res.phoneNumbers.length, 3);
      expect(res.phoneNumbers.any((p) => p.number.contains('+44')), isTrue);
      expect(res.phoneNumbers.any((p) => p.number.contains('+1')), isTrue);
      expect(res.phoneNumbers.any((p) => p.number.contains('+91')), isTrue);
      expect(res.emailAddresses.first.email, 'sarah@alliancegroup.co.uk');
    });

    test('Layout M: Minimalist card (Name, Title, single phone)', () {
      const text = '''
Elena Rostova
Creative Director
+33 1 42 68 55 00
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Elena Rostova');
      expect(res.jobTitle, 'Creative Director');
      expect(res.phoneNumbers.length, 1);
      expect(res.emailAddresses, isEmpty);
    });

    test('Layout N: Front mostly logo / details on back', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: 'front.jpg',
        rawText: 'NEXUS DYNAMICS',
      );
      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: 'back.jpg',
        rawText: '''
Marcus Vance
Chief Technology Officer
+1 (555) 019-2834
marcus@nexusdynamics.com
''',
      );

      final res = parser.parseDualSided(front: front, back: back);
      expect(res.company, 'NEXUS DYNAMICS');
      expect(res.fullName, 'Marcus Vance');
      expect(res.jobTitle, 'Chief Technology Officer');
      expect(res.emailAddresses.first.email, 'marcus@nexusdynamics.com');
    });

    test('Layout O: Healthcare professional card', () {
      const text = '''
Dr. Sunil Shroff
Managing Trustee
Medindia Health Foundation
Tel: 044 45242424
shroff@medindia.net
www.medindia.net
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Dr. Sunil Shroff');
      expect(res.jobTitle, 'Managing Trustee');
      expect(res.company, 'Medindia Health Foundation');
      expect(res.website, contains('medindia.net'));
    });

    test('Layout P: Developer/company card', () {
      const text = '''
DENIL VARGHESE
Software Engineer
ABC Technologies Pvt Ltd
Mob: +91 98400 25680
denil@abctech.in
''';
      final res = parser.parse(text);
      expect(res.fullName, 'DENIL VARGHESE');
      expect(res.jobTitle, 'Software Engineer');
      expect(res.company, 'ABC Technologies Pvt Ltd');
    });

    test('Layout Q: Executive/CEO card', () {
      const text = '''
Robert Sterling
Founder & CEO
Apex Ventures
robert@apexventures.com
www.apexventures.com
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Robert Sterling');
      expect(res.jobTitle, contains('CEO'));
      expect(res.company, 'Apex Ventures');
    });

    test('Layout R: Long multi-line address', () {
      const text = '''
Tower B, 7th Floor, DLF Cyber City
Phase III, Sector 24, Gurugram
Haryana - 122002, India
''';
      final res = parser.parse(text);
      expect(res.address, contains('Tower B'));
      expect(res.address, contains('122002'));
    });

    test('Layout S: UK phone and London address', () {
      const text = '''
Arthur Pendelton
Solicitor
Pendelton Legal
Tel: +44 20 7946 0958
10 Downing Street, London, SW1A 2AA, UK
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Arthur Pendelton');
      expect(res.jobTitle, 'Solicitor');
      expect(res.phoneNumbers.first.number, contains('+44 20'));
      expect(res.address, contains('SW1A 2AA'));
    });

    test('Layout T: US phone and California address', () {
      const text = '''
Lisa Ray
Product Manager
Silicon Valley Innovations
Phone: +1 (555) 019-2834
500 Howard Street, San Francisco, CA 94105, USA
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Lisa Ray');
      expect(res.jobTitle, 'Product Manager');
      expect(res.phoneNumbers.first.number, contains('555'));
      expect(res.address, contains('CA 94105'));
    });
  });

  group('Phase 2: Specific Edge Cases & Safety Invariants Tests', () {
    const parser = BusinessCardParser();

    test('21. Postal code is not treated as phone number', () {
      const text = '''
John Doe
Engineer
Chennai - 600028
PIN: 600028
''';
      final res = parser.parse(text);
      // Postal code 600028 must NOT appear in phone numbers
      expect(res.phoneNumbers, isEmpty);
    });

    test('22. Date strings are not treated as phone number', () {
      const text = '''
Jane Doe
Accountant
Est: 2024-10-15
Date: 15/10/2024
2024
''';
      final res = parser.parse(text);
      expect(res.phoneNumbers, isEmpty);
    });

    test('23. OCR-spaced email correction', () {
      const text1 = 'name @ company.com';
      const text2 = 'name@ company .com';
      const text3 = 'name @company. com';
      const text4 = 'name (at) company . com';

      expect(parser.parse(text1).emailAddresses.first.email, 'name@company.com');
      expect(parser.parse(text2).emailAddresses.first.email, 'name@company.com');
      expect(parser.parse(text3).emailAddresses.first.email, 'name@company.com');
      expect(parser.parse(text4).emailAddresses.first.email, 'name@company.com');
    });

    test('24. Malformed email not fabricated', () {
      const text = 'Contact: not-an-email @';
      final res = parser.parse(text);
      expect(res.emailAddresses, isEmpty);
    });

    test('25. Email domain not automatically treated as website', () {
      const text = '''
Rahul Kumar
Developer
rahul@abctech.com
''';
      final res = parser.parse(text);
      expect(res.emailAddresses.first.email, 'rahul@abctech.com');
      // "abctech.com" must NOT be extracted as website if it never appeared standalone
      expect(res.website, isNull);
    });

    test('26. Empty OCR produces empty BusinessCardData safely', () {
      final emptyResult = parser.parse('');
      expect(emptyResult.fullName, isNull);
      expect(emptyResult.company, isNull);
      expect(emptyResult.phoneNumbers, isEmpty);
      expect(emptyResult.emailAddresses, isEmpty);
    });

    test('27. Partial OCR does not crash or fabricate fields', () {
      final partial = parser.parse('Just one stray word');
      expect(partial.phoneNumbers, isEmpty);
      expect(partial.emailAddresses, isEmpty);
    });
  });
}
