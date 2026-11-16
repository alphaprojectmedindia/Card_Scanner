import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/screens/scan/business_card_camera_screen.dart';
import 'package:digital_share/screens/scan/widgets/business_card_camera_overlay.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/card_geometry_service.dart';
import 'package:digital_share/services/card_image_normalization_service.dart';
import 'package:digital_share/services/ocr/email_ocr_recovery.dart';
import 'package:digital_share/services/ocr/field_semantic_evaluator.dart';
import 'package:digital_share/services/ocr/hybrid_ocr_pipeline.dart';
import 'package:digital_share/services/ocr/ocr_engine.dart';
import 'package:digital_share/services/ocr/ocr_quality_assessment.dart';
import 'package:digital_share/services/ocr/phone_ocr_recovery.dart';

/// Mock OCR Engine for unit testing hybrid resolution rules.
class MockTestOcrEngine implements OcrEngine {
  @override
  final String name;
  final List<String> linesToReturn;
  final double confidence;
  final Duration latency;
  final bool shouldFail;
  int invocationCount = 0;

  MockTestOcrEngine({
    required this.name,
    this.linesToReturn = const [],
    this.confidence = 0.90,
    this.latency = const Duration(milliseconds: 50),
    this.shouldFail = false,
  });

  @override
  Future<OcrEngineResult> recognize(String imagePath) async {
    invocationCount++;
    if (shouldFail) {
      return OcrEngineResult.failure(
        engineName: name,
        error: 'Engine failure simulated for testing',
      );
    }
    return OcrEngineResult(
      engineName: name,
      rawText: linesToReturn.join('\n'),
      detectedLines: linesToReturn,
      lineCount: linesToReturn.length,
      characterCount: linesToReturn.fold(0, (sum, l) => sum + l.length),
      processingTime: latency,
      isSuccess: true,
    );
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper to generate a dummy card image for geometry tests
  img.Image createSyntheticCardImage({
    int width = 1200,
    int height = 800,
    Color bgColor = Colors.white,
    bool drawCard = true,
    Rect? cardRect,
    int brightnessOffset = 0,
    bool addBlur = false,
  }) {
    final image = img.Image(width: width, height: height);
    // Fill background (table/desk)
    final bgR = (60 + brightnessOffset).clamp(0, 255);
    final bgG = (50 + brightnessOffset).clamp(0, 255);
    final bgB = (45 + brightnessOffset).clamp(0, 255);
    img.fill(image, color: img.ColorRgb8(bgR, bgG, bgB));

    if (drawCard) {
      final cRect = cardRect ??
          Rect.fromLTWH(
            width * 0.15,
            height * 0.20,
            width * 0.70,
            height * 0.60,
          );
      final cardR = (240 + brightnessOffset).clamp(0, 255);
      final cardG = (240 + brightnessOffset).clamp(0, 255);
      final cardB = (240 + brightnessOffset).clamp(0, 255);
      final cardColor = img.ColorRgb8(cardR, cardG, cardB);

      img.fillRect(
        image,
        x1: cRect.left.toInt(),
        y1: cRect.top.toInt(),
        x2: cRect.right.toInt(),
        y2: cRect.bottom.toInt(),
        color: cardColor,
      );

      // Draw high-contrast text lines on the card
      final textR = (10 + brightnessOffset).clamp(0, 255);
      final textColor = img.ColorRgb8(textR, textR, textR);
      final lineCount = min(4, max(1, (cRect.height ~/ 45)));
      for (int i = 0; i < lineCount; i++) {
        final y1 = (cRect.top + 20 + (i * 30)).toInt();
        final y2 = (y1 + 15).toInt();
        if (y2 < cRect.bottom) {
          img.fillRect(
            image,
            x1: (cRect.left + 20).toInt(),
            y1: y1,
            x2: (cRect.right - 20).toInt(),
            y2: y2,
            color: textColor,
          );
        }
      }
    }

    if (addBlur) {
      return img.gaussianBlur(image, radius: 8);
    }
    return image;
  }

  // ===========================================================================
  // GROUP 1: CAPTURE / GEOMETRY TESTS (Scenarios 1-10)
  // ===========================================================================
  group('1. CAPTURE / GEOMETRY Tests (Scenarios 1-10)', () {
    const geometryService = CardGeometryService();

    test('1. Card centered inside frame returns high confidence and ready guidance', () {
      final image = createSyntheticCardImage(width: 1000, height: 600);
      final detection = geometryService.detectCorners(image);
      final quality = geometryService.assessCaptureQuality(
        image,
        corners: detection.corners,
        confidence: detection.confidence,
      );

      expect(detection.confidence, greaterThanOrEqualTo(0.65));
      expect(detection.corners, isNotNull);
      expect(quality.isTooSmall, isFalse);
      expect(quality.isTooClose, isFalse);
      expect(quality.guidanceMessage, equals('Card aligned'));
    });

    test('2. Card too small triggers "Move closer" guidance', () {
      // Very small card occupying only 10% of image
      final image = createSyntheticCardImage(
        width: 1200,
        height: 800,
        cardRect: const Rect.fromLTWH(400, 280, 400, 240),
      );
      final detection = geometryService.detectCorners(image);
      final quality = geometryService.assessCaptureQuality(
        image,
        corners: detection.corners,
        confidence: detection.confidence,
      );

      expect(quality.isTooSmall, isTrue);
      expect(quality.guidanceMessage, equals('Move closer to the card'));
    });

    test('3. Card partially outside region triggers clipping warning', () {
      final image = createSyntheticCardImage(
        width: 1000,
        height: 600,
        cardRect: const Rect.fromLTWH(0, 0, 800, 500), // touches edge
      );
      final detection = geometryService.detectCorners(image);
      final quality = geometryService.assessCaptureQuality(
        image,
        corners: detection.corners,
        confidence: detection.confidence,
      );

      expect(quality.isClipping, isTrue);
      expect(quality.guidanceMessage, equals('Keep the full card inside the frame'));
    });

    test('4. Dark capture detects extreme darkness and triggers lighting guidance', () {
      final image = createSyntheticCardImage(
        width: 1000,
        height: 600,
        brightnessOffset: -200, // Very dark
      );
      final detection = geometryService.detectCorners(image);
      final quality = geometryService.assessCaptureQuality(
        image,
        corners: detection.corners,
        confidence: detection.confidence,
      );

      expect(quality.isExtremelyDark, isTrue);
      expect(quality.guidanceMessage, equals('Move to better lighting'));
    });

    test('5. Overexposed capture detects glare and triggers tilt guidance', () {
      final image = createSyntheticCardImage(
        width: 1000,
        height: 600,
        brightnessOffset: 200, // Very overexposed/white
      );
      final detection = geometryService.detectCorners(image);
      final quality = geometryService.assessCaptureQuality(
        image,
        corners: detection.corners,
        confidence: detection.confidence,
      );

      expect(quality.isExtremelyOverexposed, isTrue);
      expect(quality.guidanceMessage, equals('Reduce glare'));
    });

    test('6. Blurred capture detects low edge variance and triggers hold steady guidance', () {
      final image = createSyntheticCardImage(
        width: 1000,
        height: 600,
        addBlur: true,
      );
      final detection = geometryService.detectCorners(image);
      final quality = geometryService.assessCaptureQuality(
        image,
        corners: detection.corners,
        confidence: detection.confidence,
      );

      expect(quality.isBlurry, isTrue);
      expect(quality.guidanceMessage, equals('Hold the card steady'));
    });

    test('7. Perspective/skewed card detects non-parallelism', () {
      final corners = CardCorners(
        topLeft: const Point(100, 100),
        topRight: const Point(900, 120),
        bottomLeft: const Point(350, 500), // heavy trapezoid skew
        bottomRight: const Point(650, 510),
      );
      final image = createSyntheticCardImage(width: 1000, height: 600);
      final quality = geometryService.assessCaptureQuality(
        image,
        corners: corners,
        confidence: 0.55,
      );

      expect(quality.isSeverePerspective, isTrue);
    });

    test('8. Geometry failure safely uses full image without destructive crop', () async {
      final tempDir = Directory.systemTemp.path;
      final tempFile = File('$tempDir/test_no_card_${DateTime.now().microsecondsSinceEpoch}.jpg');
      final image = img.Image(width: 800, height: 600);
      img.fill(image, color: img.ColorRgb8(128, 128, 128)); // Blank flat gray: no card
      await tempFile.writeAsBytes(img.encodeJpg(image));

      final result = await geometryService.correctPerspectiveIfReliable(tempFile.path);

      expect(result.wasCorrected, isFalse);
      expect(result.imagePath, equals(tempFile.path)); // safely retains original!

      if (tempFile.existsSync()) tempFile.deleteSync();
    });

    test('9. Small card gets controlled upscale in normalization pipeline', () async {
      const normalizer = CardImageNormalizationService(
        minLongEdge: 1000,
        targetUpscaleLongEdge: 1200,
        maxUpscaleFactor: 1.8,
      );
      final tempDir = Directory.systemTemp.path;
      final tempFile = File('$tempDir/test_small_${DateTime.now().microsecondsSinceEpoch}.jpg');
      // Low resolution 600x400 card image
      final small = createSyntheticCardImage(width: 600, height: 400);
      await tempFile.writeAsBytes(img.encodeJpg(small));

      final res = await normalizer.normalizeCardImage(imagePath: tempFile.path);

      expect(res.wasUpscaled, isTrue);
      expect(max(res.normalizedWidth, res.normalizedHeight), greaterThanOrEqualTo(1000));

      if (tempFile.existsSync()) tempFile.deleteSync();
      if (res.temporaryFilePath != null && File(res.temporaryFilePath!).existsSync()) {
        File(res.temporaryFilePath!).deleteSync();
      }
    });

    test('10. Edge text is not destructively cropped due to safe margins', () {
      final image = createSyntheticCardImage(width: 1000, height: 600);
      final detection = geometryService.detectCorners(image);

      if (detection.corners != null) {
        // Safe 2% margin padding ensures corners don't clip text
        expect(detection.corners!.topLeft.x, lessThanOrEqualTo(160));
        expect(detection.corners!.topLeft.y, lessThanOrEqualTo(130));
      }
    });
  });

  // ===========================================================================
  // GROUP 2: NAME RECOVERY TESTS (Scenarios 11-18)
  // ===========================================================================
  group('2. NAME RECOVERY Tests (Scenarios 11-18)', () {
    test('11. Clear full name extracted with high semantic confidence', () {
      final candidate = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'Denil Varghese Samuvel',
        sourceEngine: 'ML Kit',
        lineIndex: 1,
        totalLines: 5,
        jobTitleIndex: 2,
      );

      expect(candidate.isTrustworthy, isTrue);
      expect(candidate.value, equals('Denil Varghese Samuvel'));
      expect(candidate.semanticConfidence, greaterThanOrEqualTo(0.70));
    });

    test('12. Full name beats abbreviated initials where evidence supports it', () {
      final fullCandidate = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'Sonia Mathew',
        sourceEngine: 'Paddle',
        lineIndex: 0,
        detectedEmails: ['sonia.mathew@company.com'],
      );

      final initialCandidate = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'Sonia M.',
        sourceEngine: 'ML Kit',
        lineIndex: 0,
        detectedEmails: ['sonia.mathew@company.com'],
      );

      expect(fullCandidate.semanticConfidence,
          greaterThan(initialCandidate.semanticConfidence));

      // In cross-engine resolution:
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: ['Sonia M.', 'Director', 'sonia.mathew@company.com'],
        primaryEngineName: 'ML Kit',
        primaryOcrQualityScore: 92.0,
        secondaryLines: ['Sonia Mathew', 'Director', 'sonia.mathew@company.com'],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 90.0,
      );

      expect(res.name?.value, equals('Sonia Mathew'));
    });

    test('13. Company is not selected as Name', () {
      final candidate = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'MEDINDIA HEALTHCARE PVT LTD',
        sourceEngine: 'ML Kit',
        lineIndex: 0,
      );

      expect(candidate.isTrustworthy, isFalse);
      expect(candidate.rejectionReasons, anyElement(contains('corporate')));
    });

    test('14. City is not selected as Name', () {
      final candidate = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'Chennai',
        sourceEngine: 'ML Kit',
        lineIndex: 3,
      );

      expect(candidate.isTrustworthy, isFalse);
      expect(candidate.semanticConfidence, lessThan(0.20));
      expect(candidate.rejectionReasons, anyElement(contains('city')));
    });

    test('15. Address is not selected as Name', () {
      final candidate = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: '12 Anna Salai, Mount Road, Chennai - 600002',
        sourceEngine: 'ML Kit',
        lineIndex: 4,
      );

      expect(candidate.isTrustworthy, isFalse);
      expect(candidate.semanticConfidence, lessThan(0.20));
    });

    test('16. Website is not selected as Name', () {
      final candidate = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'www.medindia.net',
        sourceEngine: 'ML Kit',
        lineIndex: 4,
      );

      expect(candidate.isTrustworthy, isFalse);
      expect(candidate.rejectionReasons, anyElement(contains('URL')));
    });

    test('17. Missing ML Kit Name + valid Paddle Name -> Paddle Name used', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: ['MEDINDIA', 'Software Engineer', '+91 98765 43210', 'denil@medindia.net'],
        primaryEngineName: 'ML Kit',
        primaryOcrQualityScore: 88.0,
        secondaryLines: ['Denil Varghese', 'Software Engineer', '+91 98765 43210', 'denil@medindia.net'],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 85.0,
      );

      expect(res.name?.value, equals('Denil Varghese'));
      expect(res.name?.sourceEngine, contains('PaddleOCR'));
    });

    test('18. No trustworthy Name -> blank (zero hallucination)', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: ['MEDINDIA PVT LTD', 'Chennai - 600004', '+91 98765 43210'],
        primaryEngineName: 'ML Kit',
        primaryOcrQualityScore: 80.0,
        secondaryLines: ['MEDINDIA PVT LTD', 'Chennai - 600004', '+91 98765 43210'],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 80.0,
      );

      expect(res.name, isNull);
    });
  });

  // ===========================================================================
  // GROUP 3: PHONE RECOVERY TESTS (Scenarios 19-24)
  // ===========================================================================
  group('3. PHONE RECOVERY Tests (Scenarios 19-24)', () {
    test('19. Existing phone recovery tests remain passing', () {
      final phones = PhoneOcrRecovery.extractPhoneCandidates([
        'Mobile: +91 98765 43210',
        'Tel: 044-24991234',
      ]);

      expect(phones.length, equals(2));
      expect(phones[0].formatted, equals('+91 98765 43210'));
      expect(phones[0].label, equals('Mobile'));
    });

    test('20. High ML Kit score + missing Phone -> phone fallback triggered', () {
      final primaryLines = ['Arun Kumar', 'Managing Director', 'arun@example.com'];
      final primaryAssessment =
          OcrQualityEvaluator.assessText(primaryLines.join('\n'));

      // Overall score is decent, but phone is missing
      expect(primaryAssessment.criticalFields?.phoneFieldFailure, isTrue);
      expect(primaryAssessment.criticalFields?.hasAnyFailure, isTrue);

      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: primaryLines,
        primaryEngineName: 'ML Kit',
        primaryOcrQualityScore: 92.0,
        secondaryLines: ['Arun Kumar', 'Director', 'Phone: +91 98765 43210', 'arun@example.com'],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 88.0,
      );

      expect(res.phones.isNotEmpty, isTrue);
      expect(res.phones.first.value, equals('+91 98765 43210'));
      expect(res.phones.first.sourceEngine, contains('PaddleOCR'));
    });

    test('21. Multiple numbers preserved without dropping', () {
      final phones = PhoneOcrRecovery.extractPhoneCandidates([
        'M: +91 98765 43210',
        'Off: +91 44 2499 1234',
        'WhatsApp: +91 98765 00000',
      ]);

      expect(phones.length, equals(3));
      expect(phones.map((p) => p.label).toSet(), containsAll(['Mobile', 'Office', 'WhatsApp']));
    });

    test('22. International numbers with parenthesis and hyphens preserved', () {
      final phones = PhoneOcrRecovery.extractPhoneCandidates([
        'Phone: +1 (415) 555-0199',
      ]);

      expect(phones.isNotEmpty, isTrue);
      expect(phones.first.formatted, contains('+1 (415) 555-0199'));
    });

    test('23. Split phone across two lines reconstructed', () {
      final phones = PhoneOcrRecovery.extractPhoneCandidates([
        'Mobile: +91 98765',
        '43210',
      ]);

      expect(phones.isNotEmpty, isTrue);
      expect(phones.first.normalized, contains('919876543210'));
      expect(phones.first.wasSplitJoined, isTrue);
    });

    test('24. No trustworthy Phone -> blank (zero hallucination)', () {
      final phones = PhoneOcrRecovery.extractPhoneCandidates([
        'Denil Samuvel',
        'Software Engineer',
        'denil@example.com',
      ]);

      expect(phones, isEmpty);
    });
  });

  // ===========================================================================
  // GROUP 4: EMAIL RECOVERY TESTS (Scenarios 25-31)
  // ===========================================================================
  group('4. EMAIL RECOVERY Tests (Scenarios 25-31)', () {
    test('25. Standard email extracted with high confidence', () {
      final emails = EmailOcrRecovery.extractEmailCandidates([
        'Email: denil@medindia.net',
      ]);

      expect(emails.length, equals(1));
      expect(emails.first.email, equals('denil@medindia.net'));
      expect(emails.first.label, equals('Email'));
    });

    test('26. Spaces around @ reconstructed safely', () {
      final emails = EmailOcrRecovery.extractEmailCandidates([
        'denil @ medindia.net',
        'contact@ medindia.com',
        'info @medindia.org',
      ]);

      expect(emails.length, equals(3));
      expect(emails[0].email, equals('denil@medindia.net'));
      expect(emails[0].wasSpacedReconstructed, isTrue);
      expect(emails[1].email, equals('contact@medindia.com'));
      expect(emails[2].email, equals('info@medindia.org'));
    });

    test('27. Spaces around dot safely handled when evidence is strong', () {
      final emails = EmailOcrRecovery.extractEmailCandidates([
        'denil@medindia . net',
      ]);

      expect(emails.length, equals(1));
      expect(emails.first.email, equals('denil@medindia.net'));
      expect(emails.first.wasSpacedReconstructed, isTrue);
    });

    test('28. Broken adjacent email tokens reconstructed across lines', () {
      final emails = EmailOcrRecovery.extractEmailCandidates([
        'denil',
        '@',
        'medindia.net',
      ]);

      expect(emails.isNotEmpty, isTrue);
      expect(emails.first.email, equals('denil@medindia.net'));
      expect(emails.first.wasSplitJoined, isTrue);
    });

    test('29. Invalid candidate rejected (not an email)', () {
      final emails = EmailOcrRecovery.extractEmailCandidates([
        'www.medindia.net',
        'Date: 21/10/2026',
        '123 Anna Salai',
        '@twitter_handle',
      ]);

      expect(emails, isEmpty);
    });

    test('30. Missing ML Kit Email + valid Paddle Email -> Paddle Email used', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: ['Denil Samuvel', '+91 98765 43210', 'MEDINDIA'],
        primaryEngineName: 'ML Kit',
        primaryOcrQualityScore: 90.0,
        secondaryLines: ['Denil Samuvel', '+91 98765 43210', 'denil@medindia.net'],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 88.0,
      );

      expect(res.emails.isNotEmpty, isTrue);
      expect(res.emails.first.value, equals('denil@medindia.net'));
      expect(res.emails.first.sourceEngine, contains('PaddleOCR'));
    });

    test('31. No trustworthy Email -> blank (zero hallucination)', () {
      final emails = EmailOcrRecovery.extractEmailCandidates([
        'Denil Samuvel',
        '+91 98765 43210',
        'Chennai',
      ]);

      expect(emails, isEmpty);
    });
  });

  // ===========================================================================
  // GROUP 5: HYBRID RESOLUTION TESTS (Scenarios 32-37)
  // ===========================================================================
  group('5. HYBRID RESOLUTION Tests (Scenarios 32-37)', () {
    test('32. ML Kit Name + Paddle Phone + ML Kit Email (individual field selection)', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          'Arun Kumar',
          'Chief Executive Officer',
          'arun@globaltech.com',
        ],
        primaryEngineName: 'ML Kit',
        primaryOcrQualityScore: 94.0,
        secondaryLines: [
          'Arun K.',
          'CEO',
          '+91 98765 43210',
          'arun@globaltech.com',
        ],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 89.0,
      );

      // Name from ML Kit (full name beats initial)
      expect(res.name?.value, equals('Arun Kumar'));
      expect(res.name?.sourceEngine, contains('ML Kit'));

      // Phone from Paddle (ML Kit had none)
      expect(res.phones.first.value, equals('+91 98765 43210'));
      expect(res.phones.first.sourceEngine, contains('PaddleOCR'));

      // Email agreed by both
      expect(res.emails.first.value, equals('arun@globaltech.com'));
      expect(res.emails.first.sourceEngine, contains('Both'));
    });

    test('33. Paddle Name + ML Kit Phone + ML Kit Email', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          'MEDINDIA CORP',
          'Mobile: +91 98765 43210',
          'denil@medindia.net',
        ],
        primaryEngineName: 'ML Kit',
        primaryOcrQualityScore: 85.0,
        secondaryLines: [
          'Denil Varghese Samuvel',
          'Developer',
          '+91 98765 43210',
          'denil@medindia.net',
        ],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 88.0,
      );

      expect(res.name?.value, equals('Denil Varghese Samuvel'));
      expect(res.name?.sourceEngine, contains('PaddleOCR'));
      expect(res.phones.first.value, equals('+91 98765 43210'));
      expect(res.emails.first.value, equals('denil@medindia.net'));
    });

    test('34. ML Kit Name + ML Kit Phone + Paddle Email', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          'Priya Sharma',
          'Senior Architect',
          '+91 98111 22233',
        ],
        primaryEngineName: 'ML Kit',
        primaryOcrQualityScore: 91.0,
        secondaryLines: [
          'Priya Sharma',
          'priya.sharma@design.co.in',
        ],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 86.0,
      );

      expect(res.name?.value, equals('Priya Sharma'));
      expect(res.phones.first.value, equals('+91 98111 22233'));
      expect(res.emails.first.value, equals('priya.sharma@design.co.in'));
      expect(res.emails.first.sourceEngine, contains('PaddleOCR'));
    });

    test('35. Different engines provide all three fields independently', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          'Kavita Nair', // Name
          'kavita@domain.com', // Email
        ],
        primaryEngineName: 'ML Kit',
        primaryOcrQualityScore: 87.0,
        secondaryLines: [
          'K. Nair',
          'Mobile: +91 94440 12345', // Phone
        ],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 84.0,
      );

      expect(res.name?.value, equals('Kavita Nair')); // ML Kit
      expect(res.phones.first.value, equals('+91 94440 12345')); // Paddle
      expect(res.emails.first.value, equals('kavita@domain.com')); // ML Kit
    });

    test('36. Dual engine execution runs both engines and arbitrates at field level', () async {
      final primary = MockTestOcrEngine(
        name: 'Mock ML Kit',
        linesToReturn: [
          'Denil Varghese',
          'Full Stack Developer',
          'Mobile: +91 98765 43210',
          'Email: denil@example.com',
        ],
        confidence: 0.95,
      );

      final secondary = MockTestOcrEngine(
        name: 'Mock Paddle',
        linesToReturn: ['Secondary lines'],
        confidence: 0.90,
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: primary,
        secondaryEngine: secondary,
      );

      final result = await pipeline.processCardSide(
        imagePath: 'dummy.jpg',
        side: CardSide.front,
      );

      expect(primary.invocationCount, 1);
      expect(secondary.invocationCount, 1);
      expect(result.fallbackInvoked, isTrue);
      expect(result.engineName, contains('Hybrid Field-Resolved'));
    });

    test('37. All critical fields weak -> fallback triggered', () async {
      final primary = MockTestOcrEngine(
        name: 'Mock ML Kit',
        linesToReturn: [r'random unreadable noise #$%'],
        confidence: 0.30,
      );

      final secondary = MockTestOcrEngine(
        name: 'Mock Paddle',
        linesToReturn: [
          'Suresh Kumar',
          '+91 99999 88888',
          'suresh@company.com',
        ],
        confidence: 0.92,
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: primary,
        secondaryEngine: secondary,
      );

      final result = await pipeline.processCardSide(
        imagePath: 'dummy.jpg',
        side: CardSide.front,
      );

      expect(result.fallbackInvoked, isTrue);
      expect(result.rawText, contains('Suresh Kumar'));
    });
  });

  // ===========================================================================
  // GROUP 6: FRONT / BACK DUAL-SIDED TESTS (Scenarios 38-40)
  // ===========================================================================
  group('6. FRONT / BACK DUAL-SIDED Tests (Scenarios 38-40)', () {
    const parser = BusinessCardParser();

    test('38. Name on front + Phone/Email on back merged seamlessly', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: 'front.jpg',
        rawText: '''
Denil Varghese Samuvel
Full Stack Developer
Medindia Healthcare
''',
      );

      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: 'back.jpg',
        rawText: '''
Mobile: +91 98765 43210
Email: denil@medindia.net
Website: www.medindia.net
''',
      );

      final cardData = parser.parseDualSided(front: front, back: back);

      expect(cardData.fullName, equals('Denil Varghese Samuvel'));
      expect(cardData.jobTitle, equals('Full Stack Developer'));
      expect(cardData.company, equals('Medindia Healthcare'));
      expect(cardData.phoneNumbers.first.number, contains('98765 43210'));
      expect(cardData.emailAddresses.first.email, equals('denil@medindia.net'));
      expect(cardData.website, equals('www.medindia.net'));
    });

    test('39. Phone on front + company information on back merged', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: 'front.jpg',
        rawText: '''
Rohit Verma
+91 98888 77777
''',
      );

      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: 'back.jpg',
        rawText: '''
Apex Solutions Pvt Ltd
Consulting Division
123 Brigade Road, Bangalore
''',
      );

      final cardData = parser.parseDualSided(front: front, back: back);

      expect(cardData.fullName, equals('Rohit Verma'));
      expect(cardData.phoneNumbers.first.number, contains('98888 77777'));
      expect(cardData.company, equals('Apex Solutions Pvt Ltd'));
      expect(cardData.address, contains('Brigade Road'));
    });

    test('40. Duplicate fields across both sides are deduplicated', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: 'front.jpg',
        rawText: '''
Pooja Hegde
+91 98765 43210
pooja@example.com
''',
      );

      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: 'back.jpg',
        rawText: '''
+91 98765 43210
pooja@example.com
''',
      );

      final cardData = parser.parseDualSided(front: front, back: back);

      expect(cardData.phoneNumbers.length, equals(1));
      expect(cardData.emailAddresses.length, equals(1));
    });
  });

  // ===========================================================================
  // GROUP 7: GALLERY OCR TESTS (Scenarios 41-43)
  // ===========================================================================
  group('7. GALLERY OCR Tests (Scenarios 41-43)', () {
    const normalizer = CardImageNormalizationService();

    test('41. Gallery OCR normalization retains aspect ratio and decodes cleanly', () async {
      final tempDir = Directory.systemTemp.path;
      final tempFile = File('$tempDir/gallery_test_${DateTime.now().microsecondsSinceEpoch}.jpg');
      final image = createSyntheticCardImage(width: 1600, height: 1000);
      await tempFile.writeAsBytes(img.encodeJpg(image));

      final res = await normalizer.normalizeCardImage(imagePath: tempFile.path);

      expect(res.normalizedWidth, lessThanOrEqualTo(2160));
      expect(res.normalizedHeight, lessThanOrEqualTo(2160));
      expect(File(res.normalizedPath).existsSync(), isTrue);

      if (tempFile.existsSync()) tempFile.deleteSync();
      if (res.temporaryFilePath != null && File(res.temporaryFilePath!).existsSync()) {
        File(res.temporaryFilePath!).deleteSync();
      }
    });

    test('42. Gallery card with small phone/email text gets controlled upscale', () async {
      final tempDir = Directory.systemTemp.path;
      final tempFile = File('$tempDir/gallery_small_${DateTime.now().microsecondsSinceEpoch}.jpg');
      final small = createSyntheticCardImage(width: 500, height: 320);
      await tempFile.writeAsBytes(img.encodeJpg(small));

      final res = await normalizer.normalizeCardImage(imagePath: tempFile.path);

      expect(res.wasUpscaled, isTrue);

      if (tempFile.existsSync()) tempFile.deleteSync();
      if (res.temporaryFilePath != null && File(res.temporaryFilePath!).existsSync()) {
        File(res.temporaryFilePath!).deleteSync();
      }
    });

    test('43. Gallery card with EXIF rotation is physically baked upright', () async {
      final tempDir = Directory.systemTemp.path;
      final tempFile = File('$tempDir/gallery_exif_${DateTime.now().microsecondsSinceEpoch}.jpg');
      final image = createSyntheticCardImage(width: 800, height: 1200);
      // Simulate EXIF orientation 6 (90 deg CW)
      image.exif.imageIfd.orientation = 6;
      await tempFile.writeAsBytes(img.encodeJpg(image));

      final res = await normalizer.normalizeCardImage(imagePath: tempFile.path);

      expect(res.wasOrientationBaked, isTrue);

      if (tempFile.existsSync()) tempFile.deleteSync();
      if (res.temporaryFilePath != null && File(res.temporaryFilePath!).existsSync()) {
        File(res.temporaryFilePath!).deleteSync();
      }
    });
  });

  // ===========================================================================
  // GROUP 8: SAFETY & ZERO-HALLUCINATION TESTS (Scenarios 44-48)
  // ===========================================================================
  group('8. SAFETY & ZERO-HALLUCINATION Tests (Scenarios 44-48)', () {
    test('44. Address numbers are not detected as phone numbers', () {
      final phones = PhoneOcrRecovery.extractPhoneCandidates([
        '123 Anna Salai, 4th Floor, Suite 402',
      ]);

      expect(phones, isEmpty);
    });

    test('45. Postal/PIN codes are not detected as phone numbers', () {
      final phones = PhoneOcrRecovery.extractPhoneCandidates([
        'Chennai - 600004',
        'PIN: 560001',
        'ZIP: 94105',
      ]);

      expect(phones, isEmpty);
    });

    test('46. Website is not detected as email', () {
      final emails = EmailOcrRecovery.extractEmailCandidates([
        'Visit us at: www.medindia.net',
        'https://digitalshare.app/profile/user123',
      ]);

      expect(emails, isEmpty);
    });

    test('47. Company is not detected as person name', () {
      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'Tata Consultancy Services Ltd',
        sourceEngine: 'ML Kit',
      );

      expect(cand.isTrustworthy, isFalse);
    });

    test('48. No fabricated critical fields when text is missing', () {
      const parser = BusinessCardParser();
      final emptyResult = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: 'empty.jpg',
        rawText: '',
      );

      final cardData = parser.parseSide(emptyResult);

      expect(cardData.fullName, isNull);
      expect(cardData.phoneNumbers, isEmpty);
      expect(cardData.emailAddresses, isEmpty);
    });
  });

  // ===========================================================================
  // GROUP 9: CAMERA UX & OVERLAY WIDGET TESTS
  // ===========================================================================
  group('9. CAMERA UX & OVERLAY Widget Tests', () {
    testWidgets('BusinessCardCameraOverlay renders landscape frame, guidance, and shutter', (tester) async {
      bool captured = false;
      bool cancelled = false;
      bool torchToggled = false;
      bool galleryPicked = false;
      bool sideSwitched = false;
      ViewfinderNormalizedRect? capturedRoi;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessCardCameraOverlay(
              guidanceMessage: 'Position card inside the frame',
              isReady: false,
              sideName: 'FRONT',
              onCapture: () => captured = true,
              onCancel: () => cancelled = true,
              onToggleTorch: () => torchToggled = true,
              onPickGallery: () => galleryPicked = true,
              onToggleSide: () => sideSwitched = true,
              onViewfinderRectChanged: (roi) => capturedRoi = roi,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Viewfinder and guidance
      expect(find.text('Scan Business Card'), findsOneWidget);
      expect(find.text('FRONT SIDE'), findsOneWidget);
      // Transparent cutout: static 'BUSINESS CARD' watermark was removed for unobstructed live preview
      expect(find.text('BUSINESS CARD'), findsNothing);
      expect(find.text('Position card inside the frame'), findsOneWidget);
      expect(find.text('Capture'), findsOneWidget);

      // Verify buttons
      expect(find.byKey(const Key('camera_cancel_button')), findsOneWidget);
      expect(find.byKey(const Key('camera_torch_button')), findsOneWidget);
      expect(find.byKey(const Key('camera_capture_shutter_button')), findsOneWidget);
      expect(find.byKey(const Key('camera_gallery_button')), findsOneWidget);
      expect(find.byKey(const Key('camera_side_switch_button')), findsOneWidget);

      // Tap Shutter
      await tester.tap(find.byKey(const Key('camera_capture_shutter_button')));
      expect(captured, isTrue);

      // Tap Torch
      await tester.tap(find.byKey(const Key('camera_torch_button')));
      expect(torchToggled, isTrue);

      // Tap Gallery
      await tester.tap(find.byKey(const Key('camera_gallery_button')));
      expect(galleryPicked, isTrue);

      // Tap Side Switch
      await tester.tap(find.byKey(const Key('camera_side_switch_button')));
      expect(sideSwitched, isTrue);

      // Tap Cancel
      await tester.tap(find.byKey(const Key('camera_cancel_button')));
      expect(cancelled, isTrue);

      // Verify normalized ROI export
      expect(capturedRoi, isNotNull);
      expect(capturedRoi!.width, greaterThan(0.5));
    });

    testWidgets('BusinessCardCameraOverlay disables shutter when isCaptureEnabled is false', (tester) async {
      bool captured = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessCardCameraOverlay(
              guidanceMessage: 'Starting camera...',
              isCaptureEnabled: false,
              onCapture: () => captured = true,
              onCancel: () {},
              onToggleTorch: () {},
              onPickGallery: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('camera_capture_shutter_button')));
      expect(captured, isFalse);
    });

    testWidgets('BusinessCardCameraScreen renders cleanly and handles camera preview builder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardCameraScreen(
            side: CardSide.front,
            previewBuilder: (ctx, controller) => Container(
              key: const Key('mock_live_camera_preview'),
              color: Colors.green,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(BusinessCardCameraScreen), findsOneWidget);
      expect(find.byType(BusinessCardCameraOverlay), findsOneWidget);
      expect(find.byKey(const Key('mock_live_camera_preview')), findsOneWidget);
      expect(find.text('FRONT SIDE'), findsOneWidget);
    });

    testWidgets('BusinessCardCameraScreen switches side when toggle tapped', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardCameraScreen(
            side: CardSide.front,
            previewBuilder: (ctx, controller) => const SizedBox(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('FRONT SIDE'), findsOneWidget);

      await tester.tap(find.byKey(const Key('camera_side_switch_button')));
      await tester.pumpAndSettle();

      expect(find.text('BACK SIDE'), findsOneWidget);
    });
  });
}
