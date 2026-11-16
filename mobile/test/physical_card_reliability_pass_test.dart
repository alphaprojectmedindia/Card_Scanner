import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/card_geometry_service.dart';
import 'package:digital_share/services/card_image_normalization_service.dart';
import 'package:digital_share/services/ocr/field_semantic_evaluator.dart';
import 'package:digital_share/services/ocr/hybrid_ocr_pipeline.dart';
import 'package:digital_share/services/ocr/ocr_benchmark_reporter.dart';
import 'package:digital_share/services/ocr/ocr_engine.dart';

class _MockEngine implements OcrEngine {
  @override
  final String name;
  final OcrEngineResult resultToReturn;
  int invocationCount = 0;

  _MockEngine({
    required this.name,
    required this.resultToReturn,
  });

  @override
  Future<OcrEngineResult> recognize(String imagePath) async {
    invocationCount++;
    return resultToReturn;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('reliability_test_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  String createTestImage({int width = 800, int height = 600}) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(240, 240, 240));
    final path = '${tempDir.path}/test_card_${DateTime.now().microsecondsSinceEpoch}.jpg';
    File(path).writeAsBytesSync(img.encodeJpg(image));
    return path;
  }

  group('Physical Card Reliability Pass Tests (Parts 2 - 21)', () {
    // -------------------------------------------------------------------------
    // 1. Viewfinder Safe ROI Fallback When Geometry Confidence is Low
    // -------------------------------------------------------------------------
    test('1. Geometry fallback: Low corner confidence (< 0.70) deterministically uses viewfinder ROI crop', () async {
      final imgPath = createTestImage(width: 1000, height: 1000);
      const geomService = CardGeometryService();
      const normService = CardImageNormalizationService();

      const viewfinderRoi = ViewfinderNormalizedRect(
        left: 0.10,
        top: 0.20,
        width: 0.80,
        height: 0.50,
      );

      // On a plain flat test image, corner detection confidence is 0.0 (< 0.70)
      final geomResult = await geomService.correctPerspectiveIfReliable(
        imgPath,
        viewfinderRoi,
      );

      expect(geomResult.wasRoiCropped, isTrue);
      expect(geomResult.wasCorrected, isFalse);
      expect(geomResult.confidence, lessThan(0.70));
      expect(File(geomResult.imagePath).existsSync(), isTrue);

      final normResult = await normService.normalizeCardImage(
        imagePath: imgPath,
        viewfinderRoi: viewfinderRoi,
      );

      expect(normResult.wasRoiCropped, isTrue);
      expect(normResult.wasPerspectiveCorrected, isFalse);
      expect(File(normResult.normalizedPath).existsSync(), isTrue);
    });

    // -------------------------------------------------------------------------
    // 2. Dual Engine Execution: Both ML Kit and PaddleOCR Run Sequentially
    // -------------------------------------------------------------------------
    test('2. Dual-OCR execution: Both ML Kit and PaddleOCR run for every acceptable capture', () async {
      final mockMlKit = _MockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Rohan Sharma\nSenior Architect\nTech Systems Ltd\n+91 98765 12340\nrohan@techsystems.com',
          lineCount: 5,
          characterCount: 95,
          processingTime: Duration(milliseconds: 250),
          isSuccess: true,
          detectedLines: [
            'Rohan Sharma',
            'Senior Architect',
            'Tech Systems Ltd',
            '+91 98765 12340',
            'rohan@techsystems.com',
          ],
        ),
      );

      final mockPaddle = _MockEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Rohan Sharma\nSenior Architect\nTech Systems Ltd\n+91 98765 12340\nrohan@techsystems.com',
          lineCount: 5,
          characterCount: 95,
          processingTime: Duration(milliseconds: 3800),
          isSuccess: true,
          detectedLines: [
            'Rohan Sharma',
            'Senior Architect',
            'Tech Systems Ltd',
            '+91 98765 12340',
            'rohan@techsystems.com',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final sideResult = await pipeline.processCardSide(
        imagePath: '/test/card.jpg',
        side: CardSide.front,
      );

      // MANDATORY RULE: Fast path removed for physical cards -> BOTH engines run!
      expect(mockMlKit.invocationCount, 1);
      expect(mockPaddle.invocationCount, 1);
      expect(sideResult.metadata['fallbackInvoked'], isTrue);

      // Timings measured
      final timings = sideResult.metadata['timings'] as Map<String, dynamic>?;
      expect(timings, isNotNull);
      expect(timings!['mlKitMs'], isA<int>());
      expect(timings['paddleMs'], isA<int>());
      expect(timings['arbitrationMs'], isA<int>());
      expect(timings['totalMs'], isA<int>());
    });

    // -------------------------------------------------------------------------
    // 3. Field-Level Independent Arbitration (Paddle Wins Name, ML Kit Wins Phone)
    // -------------------------------------------------------------------------
    test('3. Independent field-level arbitration: Paddle wins Name, ML Kit wins Phone and Email', () async {
      final mockMlKit = _MockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Chennai 600002\nFounder & CEO\nAlpha Innovations Pvt Ltd\n+91 98400 54321\nfounder@alphainno.com',
          lineCount: 5,
          characterCount: 110,
          processingTime: Duration(milliseconds: 270),
          isSuccess: true,
          detectedLines: [
            'Chennai 600002', // Corrupted name (location)
            'Founder & CEO',
            'Alpha Innovations Pvt Ltd',
            '+91 98400 54321',
            'founder@alphainno.com',
          ],
        ),
      );

      final mockPaddle = _MockEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Karthik Subramanian\nFounder & CEO\nAlpha Innovations Pvt Ltd',
          lineCount: 3,
          characterCount: 65,
          processingTime: Duration(milliseconds: 3900),
          isSuccess: true,
          detectedLines: [
            'Karthik Subramanian', // Clean name
            'Founder & CEO',
            'Alpha Innovations Pvt Ltd',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final sideResult = await pipeline.processCardSide(
        imagePath: '/test/card.jpg',
        side: CardSide.front,
      );

      const parser = BusinessCardParser();
      final parsed = parser.parseSide(sideResult);

      // Name resolved from PaddleOCR (not the location from ML Kit)
      expect(parsed.fullName, 'Karthik Subramanian');
      expect(parsed.fullName, isNot(contains('Chennai')));

      // Phone and email resolved from ML Kit
      expect(parsed.phoneNumbers.any((p) => p.number.contains('98400')), isTrue);
      expect(parsed.emailAddresses.any((e) => e.email.contains('founder@alphainno.com')), isTrue);

      // PII-Safe field sources in metadata
      final fieldSources = sideResult.metadata['fieldSources'] as Map<String, dynamic>?;
      expect(fieldSources, isNotNull);
      expect(fieldSources!['name'], contains('PaddleOCR'));
      expect((fieldSources['phones'] as List<dynamic>).first, contains('Google ML Kit'));
    });

    // -------------------------------------------------------------------------
    // 4. Zero Hallucination: Untrustworthy Fields Left Blank
    // -------------------------------------------------------------------------
    test('4. Zero hallucination: Untrustworthy company and name remain null', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          'We bring performances alive', // Slogan
          'Call: +1-800-555-0100',
          'support@service.com',
        ],
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 80.0,
        secondaryLines: [
          'We bring performances alive',
          'support@service.com',
        ],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 80.0,
      );

      const parser = BusinessCardParser();
      final parsed = parser.parseSide(OcrSideResult(
        side: CardSide.front,
        imagePath: '/test/card.jpg',
        rawText: 'We bring performances alive\nCall: +1-800-555-0100\nsupport@service.com',
        processedAt: DateTime.now().toUtc(),
        metadata: {
          'fieldResolution': res.toJson(),
        },
      ));

      // Slogan is never hallucinated as Name or Company
      expect(parsed.fullName, isNull);
      expect(parsed.company, isNull);
      expect(parsed.phoneNumbers.isNotEmpty, isTrue);
      expect(parsed.emailAddresses.isNotEmpty, isTrue);
    });

    // -------------------------------------------------------------------------
    // 5. Front/Back Merge: Weaker Back Value Never Replaces Stronger Front Value
    // -------------------------------------------------------------------------
    test('5. Front/Back merge: Weaker back candidate never replaces stronger front field', () {
      const parser = BusinessCardParser();

      final frontData = BusinessCardData(
        fullName: 'Dr. Suresh Venkatesh',
        jobTitle: 'Senior Consultant Cardiologist',
        company: 'Apollo Health City',
        phoneNumbers: const [
          BusinessCardPhone(number: '+91 44 2829 0200', normalizedNumber: '+914428290200'),
        ],
        emailAddresses: const [
          BusinessCardEmail(email: 'suresh@apollohealth.com', normalizedEmail: 'suresh@apollohealth.com'),
        ],
      );

      final backData = BusinessCardData(
        fullName: 'Appointment Desk', // Weaker title/role on back
        jobTitle: null,
        company: null,
        address: 'Greams Road, Thousand Lights, Chennai - 600006', // Valuable address on back
        phoneNumbers: const [
          BusinessCardPhone(number: '+91 44 2829 3333', normalizedNumber: '+914428293333'),
        ],
      );

      final merged = parser.mergeDualSidedData(
        frontData: frontData,
        backData: backData,
        frontRawText: 'Dr. Suresh Venkatesh\nSenior Consultant Cardiologist\nApollo Health City',
        backRawText: 'Appointment Desk\nGreams Road, Thousand Lights, Chennai - 600006\n+91 44 2829 3333',
      );

      // Stronger front name is preserved
      expect(merged.fullName, 'Dr. Suresh Venkatesh');
      expect(merged.jobTitle, 'Senior Consultant Cardiologist');
      expect(merged.company, 'Apollo Health City');

      // Valid complementary address and phone from back are merged
      expect(merged.address, contains('Greams Road'));
      expect(merged.phoneNumbers.length, 2);
    });

    // -------------------------------------------------------------------------
    // 6. Benchmark Reporting & PII Safety
    // -------------------------------------------------------------------------
    test('6. Benchmark reporting: Outputs markdown metrics table without storing PII strings', () {
      final reporter = CardScanBenchmarkReporter();

      reporter.recordEntry(const CardScanBenchmarkEntry(
        cardId: 'CARD_001_MATTE',
        cardDetectionSuccess: true,
        captureQualityResult: 'good',
        perspectiveCorrectionUsed: 'perspective_rectified',
        nameCorrect: true,
        companyCorrect: true,
        jobTitleCorrect: true,
        phoneCorrect: true,
        emailCorrect: true,
        websiteCorrect: true,
        addressCorrect: true,
        mlKitProcessingTimeMs: 280,
        paddleProcessingTimeMs: 3850,
        totalProcessingTimeMs: 4142,
      ));

      reporter.recordEntry(const CardScanBenchmarkEntry(
        cardId: 'CARD_002_GLOSS',
        cardDetectionSuccess: true,
        captureQualityResult: 'good',
        perspectiveCorrectionUsed: 'viewfinder_roi_crop',
        nameCorrect: true,
        companyCorrect: true,
        jobTitleCorrect: false,
        phoneCorrect: true,
        emailCorrect: true,
        websiteCorrect: false,
        addressCorrect: false,
        mlKitProcessingTimeMs: 310,
        paddleProcessingTimeMs: 3950,
        totalProcessingTimeMs: 4275,
      ));

      final markdown = reporter.generateMarkdownReport();

      expect(markdown, contains('| Card ID | Detected | Quality | Geometry Used | Name | Company | Title | Phone | Email | Web | Addr | ML Kit | Paddle | Total |'));
      expect(markdown, contains('CARD_001_MATTE'));
      expect(markdown, contains('CARD_002_GLOSS'));
      expect(markdown, contains('Summary Statistics'));

      // Strict Zero-PII check: Must NEVER contain personal contact data
      expect(markdown, isNot(contains('@')));
      expect(markdown, isNot(contains('+91')));
      expect(markdown, isNot(contains('Dr.')));
      expect(markdown, isNot(contains('Street')));
    });
  });
}
