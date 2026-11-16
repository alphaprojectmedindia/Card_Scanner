import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/ocr/ocr_engine.dart';
import 'package:digital_share/services/ocr/hybrid_ocr_pipeline.dart';
import 'package:digital_share/services/business_card_ocr_service.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/screens/scan/ocr_engine_comparison_screen.dart';

/// Test mock implementation of [OcrEngine] with configurable outputs, delays, and crash simulation.
class MockEngine implements OcrEngine {
  @override
  final String name;
  OcrEngineResult? resultToReturn;
  Duration simulatedDelay;
  bool shouldThrow;
  int invocationCount = 0;
  bool isDisposed = false;
  String? lastRecognizedPath;

  MockEngine({
    required this.name,
    this.resultToReturn,
    this.simulatedDelay = Duration.zero,
    this.shouldThrow = false,
  });

  @override
  Future<OcrEngineResult> recognize(String imagePath) async {
    invocationCount++;
    lastRecognizedPath = imagePath;
    if (simulatedDelay > Duration.zero) {
      await Future.delayed(simulatedDelay);
    }
    if (shouldThrow) {
      throw Exception('Simulated engine crash in $name');
    }
    return resultToReturn ??
        OcrEngineResult(
          engineName: name,
          rawText: 'Mock recognized text from $name',
          lineCount: 1,
          characterCount: 25,
          processingTime: const Duration(milliseconds: 120),
          isSuccess: true,
          detectedLines: ['Mock recognized text from $name'],
        );
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }
}

void main() {
  group('Hybrid OCR Pipeline Selection & Fallback Tests (Prompt Section 25)', () {
    // -------------------------------------------------------------------------
    // 1. Dual Engine Execution: Both ML Kit and PaddleOCR execute for physical cards
    // -------------------------------------------------------------------------
    test('1. Physical card capture -> Both ML Kit and PaddleOCR run for field-level resolution', () async {
      final mockMlKit = MockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Rahul Kumar\nSenior Developer\nABC Technologies\n+91 98765 43210\nrahul@abctech.com',
          lineCount: 5,
          characterCount: 85,
          processingTime: Duration(milliseconds: 320),
          isSuccess: true,
          detectedLines: [
            'Rahul Kumar',
            'Senior Developer',
            'ABC Technologies',
            '+91 98765 43210',
            'rahul@abctech.com',
          ],
        ),
      );

      final mockPaddle = MockEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Rahul Kumar\nSenior Developer\nABC Technologies\n+91 98765 43210\nrahul@abctech.com',
          lineCount: 5,
          characterCount: 85,
          processingTime: Duration(milliseconds: 3800),
          isSuccess: true,
          detectedLines: [
            'Rahul Kumar',
            'Senior Developer',
            'ABC Technologies',
            '+91 98765 43210',
            'rahul@abctech.com',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final result = await pipeline.processCardSide(
        imagePath: '/test/easy_card.jpg',
        side: CardSide.front,
      );

      expect(mockMlKit.invocationCount, 1);
      // Both engines run for every physical card capture
      expect(mockPaddle.invocationCount, 1);
      expect(result.metadata['fallbackInvoked'], isTrue);
      expect(result.rawText, contains('Rahul Kumar'));
      expect(result.lines.length, 5);
      expect(result.metadata['timings'], isNotNull);
      expect(result.metadata['mlKitMs'], isNotNull);
      expect(result.metadata['paddleMs'], isNotNull);
    });

    // -------------------------------------------------------------------------
    // 2. Fallback Path: ML Kit Weak -> PaddleOCR called exactly once
    // -------------------------------------------------------------------------
    test('2. ML Kit weak -> PaddleOCR called exactly once and contributes to final result', () async {
      // Antony Lobo corrupted ML Kit output
      final mockMlKit = MockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Sntony Doto\nKon ConsulfGpain\nspainconsulate.chennai@gmail.com',
          lineCount: 3,
          characterCount: 65,
          processingTime: Duration(milliseconds: 340),
          isSuccess: true,
          detectedLines: [
            'Sntony Doto',
            'Kon ConsulfGpain',
            'spainconsulate.chennai@gmail.com',
          ],
        ),
      );

      // Clean PaddleOCR output
      final mockPaddle = MockEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Antony Lobo\nHon. Consul of Spain.\nConsulate of Spain\n6, Nimmo Road, Santhome\nTel:+91-44-42107657\nChennai-600 004\nspainconsulate.chennai@gmail.com',
          lineCount: 7,
          characterCount: 154,
          processingTime: Duration(milliseconds: 4100),
          isSuccess: true,
          detectedLines: [
            'Antony Lobo',
            'Hon. Consul of Spain.',
            'Consulate of Spain',
            '6, Nimmo Road, Santhome',
            'Tel:+91-44-42107657',
            'Chennai-600 004',
            'spainconsulate.chennai@gmail.com',
          ],
        ),
      );

      String? progressMessage;
      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final result = await pipeline.processCardSide(
        imagePath: '/test/antony_lobo.jpg',
        side: CardSide.front,
        onProgressUpdate: (msg) => progressMessage = msg,
      );

      expect(mockMlKit.invocationCount, 1);
      expect(mockPaddle.invocationCount, 1);
      expect(progressMessage, 'Improving scan accuracy...');
      expect(result.metadata['fallbackInvoked'], isTrue);

      // Verify final merged result contains clean Antony Lobo data
      expect(result.rawText, contains('Antony Lobo'));
      expect(result.rawText, contains('Consulate of Spain'));
      expect(result.rawText, contains('+91-44-42107657'));
      expect(result.rawText, contains('spainconsulate.chennai@gmail.com'));

      // Crucial: Must NEVER concatenate conflicting names!
      expect(result.rawText, isNot(contains('Antony Lobo Sntony Doto')));
      expect(result.rawText, isNot(contains('Sntony Doto Antony Lobo')));

      // Corrupted candidate stored in alternatives
      final alternatives = result.metadata['alternatives'] as Map<String, dynamic>?;
      expect(alternatives, isNotNull);
      expect(alternatives!['fullName'], contains('Sntony Doto'));
    });

    // -------------------------------------------------------------------------
    // 3. Complementary Field Merge: ML Kit has email, Paddle has phone/name
    // -------------------------------------------------------------------------
    test('3. ML Kit valid email + Paddle valid phone/name preserves complementary strong fields', () async {
      final mockMlKit = MockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'David Miller\nEmail: david.miller@novatech.io',
          lineCount: 2,
          characterCount: 44,
          processingTime: Duration(milliseconds: 300),
          isSuccess: true,
          detectedLines: [
            'David Miller',
            'Email: david.miller@novatech.io',
          ],
        ),
      );

      final mockPaddle = MockEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'David Miller\nChief Technology Officer\nNovaTech Solutions\nTel: +1 415 555 0199',
          lineCount: 4,
          characterCount: 78,
          processingTime: Duration(milliseconds: 3900),
          isSuccess: true,
          detectedLines: [
            'David Miller',
            'Chief Technology Officer',
            'NovaTech Solutions',
            'Tel: +1 415 555 0199',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final result = await pipeline.processCardSide(
        imagePath: '/test/card.jpg',
        side: CardSide.front,
      );

      expect(mockMlKit.invocationCount, 1);
      expect(mockPaddle.invocationCount, 1);

      // Verify complementary fields: email from ML Kit, phone and title from PaddleOCR
      expect(result.rawText, contains('david.miller@novatech.io'));
      expect(result.rawText, contains('+1 415 555 0199'));
      expect(result.rawText, contains('Chief Technology Officer'));
      expect(result.rawText, contains('David Miller'));

      // Check parser output on the merged side result
      const parser = BusinessCardParser();
      final parsed = parser.parseSide(result);
      expect(parsed.fullName, 'David Miller');
      expect(parsed.jobTitle, contains('Chief Technology Officer'));
      expect(parsed.company, contains('NovaTech Solutions'));
      expect(parsed.phoneNumbers.any((p) => p.number.contains('0199')), isTrue);
      expect(parsed.emailAddresses.any((e) => e.email.contains('david.miller@novatech.io')), isTrue);
    });

    // -------------------------------------------------------------------------
    // 4. Agreement Detection Increases Confidence & Records Metadata
    // -------------------------------------------------------------------------
    test('4. Matching fields across engines recorded as agreed signals in metadata', () async {
      final mockMlKit = MockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Acme Corp\n+1-800-555-0199\ninfo@acmecorp.com',
          lineCount: 3,
          characterCount: 45,
          processingTime: Duration(milliseconds: 310),
          isSuccess: true,
          detectedLines: [
            'Acme Corp',
            '+1-800-555-0199',
            'info@acmecorp.com',
          ],
        ),
      );

      final mockPaddle = MockEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'John Doe\nAcme Corp\nTel: +1 800 555 0199\ninfo@acmecorp.com',
          lineCount: 4,
          characterCount: 56,
          processingTime: Duration(milliseconds: 3950),
          isSuccess: true,
          detectedLines: [
            'John Doe',
            'Acme Corp',
            'Tel: +1 800 555 0199',
            'info@acmecorp.com',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final result = await pipeline.processCardSide(
        imagePath: '/test/card.jpg',
        side: CardSide.front,
      );

      final agreedSignals = (result.metadata['agreedSignals'] as List<dynamic>?)?.cast<String>();
      expect(agreedSignals, isNotNull);
      expect(agreedSignals!.any((s) => s.contains('email')), isTrue);
      expect(agreedSignals.any((s) => s.contains('phone')), isTrue);
    });

    // -------------------------------------------------------------------------
    // 5. PaddleOCR Failure / Timeout Handling (Never Crash)
    // -------------------------------------------------------------------------
    test('5. PaddleOCR failure preserves ML Kit partial result without crashing', () async {
      final mockMlKit = MockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Antony Lobo\nEmail: antony@example.com',
          lineCount: 2,
          characterCount: 37,
          processingTime: Duration(milliseconds: 320),
          isSuccess: true,
          detectedLines: ['Antony Lobo', 'Email: antony@example.com'],
        ),
      );

      final mockPaddle = MockEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        shouldThrow: true, // Throws exception
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      // Must complete without unhandled exception
      final result = await pipeline.processCardSide(
        imagePath: '/test/card.jpg',
        side: CardSide.front,
      );

      expect(result.rawText, contains('Antony Lobo'));
      expect(result.rawText, contains('antony@example.com'));
      expect(result.metadata['fallbackReason'], contains('Secondary failed'));
    });

    test('6. Both engines failing returns empty result safely without crashing', () async {
      final mockMlKit = MockEngine(
        name: 'Google ML Kit',
        shouldThrow: true,
      );

      final mockPaddle = MockEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        shouldThrow: true,
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final result = await pipeline.processCardSide(
        imagePath: '/test/invalid_image.jpg',
        side: CardSide.front,
      );

      expect(result.isEmpty, isTrue);
    });
  });

  group('Front + Back Independent Evaluation Tests (Prompt Section 26)', () {
    test('7. Front + Back -> Both ML Kit and PaddleOCR run for each side', () async {
      final mockMlKit = MockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Rahul Kumar\nCEO\nTech Corp\n+91 98765 43210\nrahul@techcorp.com',
          lineCount: 5,
          characterCount: 65,
          processingTime: Duration(milliseconds: 300),
          isSuccess: true,
          detectedLines: [
            'Rahul Kumar',
            'CEO',
            'Tech Corp',
            '+91 98765 43210',
            'rahul@techcorp.com',
          ],
        ),
      );

      final mockPaddle = MockEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Rahul Kumar\nCEO\nTech Corp\n+91 98765 43210\nrahul@techcorp.com',
          lineCount: 5,
          characterCount: 65,
          processingTime: Duration(milliseconds: 3800),
          isSuccess: true,
          detectedLines: [
            'Rahul Kumar',
            'CEO',
            'Tech Corp',
            '+91 98765 43210',
            'rahul@techcorp.com',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final ocrService = BusinessCardOcrService(
        hybridPipeline: pipeline,
      );

      // Process front
      final front = await ocrService.processCardSide(
        imagePath: '/test/front.jpg',
        side: CardSide.front,
      );

      // Process back
      final back = await ocrService.processCardSide(
        imagePath: '/test/back.jpg',
        side: CardSide.back,
      );

      expect(mockMlKit.invocationCount, 2);
      expect(mockPaddle.invocationCount, 2); // Both run for front and back
      expect(front.rawText, contains('Rahul Kumar'));
      expect(back.rawText, contains('Rahul Kumar'));
    });

    test('8. Front + Back with complementary data merges correctly', () async {
      final mockMlKit = MockEngine(
        name: 'Google ML Kit',
      );

      final strongFront = const OcrEngineResult(
        engineName: 'Google ML Kit',
        rawText: 'Alice Walker\nVP Engineering\nCloudScale Inc.\n+1 415 555 0100\nalice@cloudscale.io',
        lineCount: 5,
        characterCount: 82,
        processingTime: Duration(milliseconds: 310),
        isSuccess: true,
        detectedLines: [
          'Alice Walker',
          'VP Engineering',
          'CloudScale Inc.',
          '+1 415 555 0100',
          'alice@cloudscale.io',
        ],
      );

      final weakBack = const OcrEngineResult(
        engineName: 'Google ML Kit',
        rawText: '||| ^^^ %%%',
        lineCount: 1,
        characterCount: 11,
        processingTime: Duration(milliseconds: 300),
        isSuccess: true,
        detectedLines: ['||| ^^^ %%%'],
      );

      mockMlKit.resultToReturn = strongFront;

      final mockPaddle = MockEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Headquarters: 100 Broadway, NY\nOffice: +1 212 555 0199\ninfo@cloudscale.io',
          lineCount: 3,
          characterCount: 68,
          processingTime: Duration(milliseconds: 4050),
          isSuccess: true,
          detectedLines: [
            'Headquarters: 100 Broadway, NY',
            'Office: +1 212 555 0199',
            'info@cloudscale.io',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final ocrService = BusinessCardOcrService(
        hybridPipeline: pipeline,
      );

      // 1. Process Front (Strong)
      final front = await ocrService.processCardSide(
        imagePath: '/test/front.jpg',
        side: CardSide.front,
      );
      expect(mockPaddle.invocationCount, 1); // Paddle runs for front

      // Switch ML Kit mock to return weak for back
      mockMlKit.resultToReturn = weakBack;

      // 2. Process Back (Weak)
      final back = await ocrService.processCardSide(
        imagePath: '/test/back.jpg',
        side: CardSide.back,
      );
      expect(mockPaddle.invocationCount, 2); // Paddle runs for back

      // 3. Merging dual-sided card via BusinessCardParser
      const parser = BusinessCardParser();
      final dualData = parser.parseDualSided(front: front, back: back);

      expect(dualData.fullName, 'Alice Walker');
      expect(dualData.jobTitle, 'VP Engineering');
      expect(dualData.company, 'CloudScale Inc.');
      expect(dualData.address, contains('100 Broadway'));
      // Both phone numbers preserved!
      expect(dualData.phoneNumbers.length, 2);
      expect(dualData.phoneNumbers.any((p) => p.number.contains('0100')), isTrue);
      expect(dualData.phoneNumbers.any((p) => p.number.contains('0199')), isTrue);
    });

    test('9. Repeated scans maintain stable sequential execution without state pollution', () async {
      final mockMlKit = MockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'A B C', // Weak
          lineCount: 1,
          characterCount: 5,
          processingTime: Duration(milliseconds: 100),
          isSuccess: true,
          detectedLines: ['A B C'],
        ),
      );

      final mockPaddle = MockEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Elena Vance\nResearcher\nBlack Mesa\n+1 555 0142\nelena@blackmesa.gov',
          lineCount: 5,
          characterCount: 68,
          processingTime: Duration(milliseconds: 200),
          isSuccess: true,
          detectedLines: [
            'Elena Vance',
            'Researcher',
            'Black Mesa',
            '+1 555 0142',
            'elena@blackmesa.gov',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      // Perform 3 sequential scans
      for (int i = 0; i < 3; i++) {
        final result = await pipeline.processCardSide(
          imagePath: '/test/card_$i.jpg',
          side: CardSide.front,
        );
        expect(result.rawText, contains('Elena Vance'));
      }

      expect(mockMlKit.invocationCount, 3);
      expect(mockPaddle.invocationCount, 3);
    });

    testWidgets('10. Benchmark screen renders with dev banner in debug mode', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OcrEngineComparisonScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('OCR Engine Comparison'), findsOneWidget);
      expect(find.byKey(const Key('compare_choose_gallery_button')), findsOneWidget);
    });
  });
}
