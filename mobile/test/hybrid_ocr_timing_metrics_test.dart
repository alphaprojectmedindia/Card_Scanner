import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/ocr/ocr_engine.dart';
import 'package:digital_share/services/ocr/ml_kit_ocr_engine.dart';
import 'package:digital_share/services/ocr/paddle_ocr_engine.dart';
import 'package:digital_share/services/ocr/hybrid_ocr_pipeline.dart';

/// Test engine simulating execution delays, exceptions, and configurable results.
class FakeEngine implements OcrEngine {
  @override
  final String name;
  final Duration simulatedDelay;
  final bool shouldThrow;
  final OcrEngineResult? resultToReturn;
  int invocationCount = 0;

  FakeEngine({
    required this.name,
    this.simulatedDelay = Duration.zero,
    this.shouldThrow = false,
    this.resultToReturn,
  });

  @override
  Future<OcrEngineResult> recognize(String imagePath) async {
    invocationCount++;
    if (simulatedDelay > Duration.zero) {
      await Future.delayed(simulatedDelay);
    }
    if (shouldThrow) {
      throw Exception('Simulated crash in $name');
    }
    return resultToReturn ??
        OcrEngineResult(
          engineName: name,
          rawText: 'Alex Rivera\nSoftware Engineer\nAcme Corp\n+1 555-0199\nalex@acme.com',
          lineCount: 5,
          characterCount: 65,
          processingTime: simulatedDelay,
          isSuccess: true,
          detectedLines: [
            'Alex Rivera',
            'Software Engineer',
            'Acme Corp',
            '+1 555-0199',
            'alex@acme.com',
          ],
        );
  }

  @override
  Future<void> dispose() async {}
}

class FakePaddleEngine extends FakeEngine implements PaddleOcrEngine {
  FakePaddleEngine({super.simulatedDelay, super.shouldThrow, super.resultToReturn})
      : super(name: 'PaddleOCR (PP-OCRv5 Mobile)');

  @override
  Future<void> initialize() async {}

  @override
  Future<void> prewarm() async {}

  @override
  List<PaddleTextBox> sortBoxesReadingOrderForTesting(List<PaddleTextBox> boxes) => boxes;
}

class FakeMlKitEngine extends FakeEngine implements MlKitOcrEngine {
  @override
  final TextRecognitionScript script;

  FakeMlKitEngine({
    this.script = TextRecognitionScript.latin,
    super.simulatedDelay,
    super.shouldThrow,
    super.resultToReturn,
  }) : super(name: 'Google ML Kit');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Hybrid OCR Timing Metrics — Static Attribution Unit Tests', () {
    test('1. Default order: Paddle primary, ML Kit secondary (Deterministic durations)', () {
      final paddle = FakePaddleEngine();
      final mlKit = FakeMlKitEngine();

      final timing = HybridOcrPipeline.attributeEngineDurations(
        primaryEngine: paddle,
        primaryDuration: const Duration(milliseconds: 320),
        secondaryEngine: mlKit,
        secondaryDuration: const Duration(milliseconds: 45),
      );

      expect(timing.paddleDuration.inMilliseconds, equals(320));
      expect(timing.mlKitDuration.inMilliseconds, equals(45));
    });

    test('2. Reversed order: ML Kit primary, Paddle secondary (Deterministic durations)', () {
      final mlKit = FakeMlKitEngine();
      final paddle = FakePaddleEngine();

      final timing = HybridOcrPipeline.attributeEngineDurations(
        primaryEngine: mlKit,
        primaryDuration: const Duration(milliseconds: 55),
        secondaryEngine: paddle,
        secondaryDuration: const Duration(milliseconds: 410),
      );

      expect(timing.mlKitDuration.inMilliseconds, equals(55));
      expect(timing.paddleDuration.inMilliseconds, equals(410));
    });

    test('3. Name-based recognition when engine types are generic mocks', () {
      final genericPaddle = FakeEngine(name: 'PaddleOCR PP-OCRv5 Mobile');
      final genericMlKit = FakeEngine(name: 'Google ML Kit');

      // Verify helper predicates
      expect(HybridOcrPipeline.isPaddleEngine(genericPaddle), isTrue);
      expect(HybridOcrPipeline.isMlKitEngine(genericPaddle), isFalse);
      expect(HybridOcrPipeline.isMlKitEngine(genericMlKit), isTrue);
      expect(HybridOcrPipeline.isPaddleEngine(genericMlKit), isFalse);

      final timing = HybridOcrPipeline.attributeEngineDurations(
        primaryEngine: genericPaddle,
        primaryDuration: const Duration(milliseconds: 200),
        secondaryEngine: genericMlKit,
        secondaryDuration: const Duration(milliseconds: 80),
      );

      expect(timing.paddleDuration.inMilliseconds, equals(200));
      expect(timing.mlKitDuration.inMilliseconds, equals(80));
    });

    test('4. Unknown/custom engines do not receive false ML Kit or Paddle attribution', () {
      final customA = FakeEngine(name: 'Tesseract OCR Engine');
      final customB = FakeEngine(name: 'Custom Vision Neural Net');

      expect(HybridOcrPipeline.isPaddleEngine(customA), isFalse);
      expect(HybridOcrPipeline.isMlKitEngine(customA), isFalse);
      expect(HybridOcrPipeline.isPaddleEngine(customB), isFalse);
      expect(HybridOcrPipeline.isMlKitEngine(customB), isFalse);

      final timing = HybridOcrPipeline.attributeEngineDurations(
        primaryEngine: customA,
        primaryDuration: const Duration(milliseconds: 150),
        secondaryEngine: customB,
        secondaryDuration: const Duration(milliseconds: 90),
      );

      // Documented behavior: custom engines do NOT falsely attribute to mlKitMs or paddleMs
      expect(timing.mlKitDuration, equals(Duration.zero));
      expect(timing.paddleDuration, equals(Duration.zero));
    });

    test('5. Single custom engine paired with Paddle attributes Paddle and leaves ML Kit zero', () {
      final paddle = FakePaddleEngine();
      final custom = FakeEngine(name: 'Apple Vision Framework');

      final timing = HybridOcrPipeline.attributeEngineDurations(
        primaryEngine: paddle,
        primaryDuration: const Duration(milliseconds: 280),
        secondaryEngine: custom,
        secondaryDuration: const Duration(milliseconds: 110),
      );

      expect(timing.paddleDuration.inMilliseconds, equals(280));
      expect(timing.mlKitDuration, equals(Duration.zero));
    });
  });

  group('Hybrid OCR Timing Metrics — Pipeline Integration & Safety Tests', () {
    test('6. Default order pipeline assigns paddleMs and mlKitMs correctly', () async {
      final paddle = FakePaddleEngine(
        simulatedDelay: const Duration(milliseconds: 30),
      );
      final mlKit = FakeMlKitEngine(
        simulatedDelay: const Duration(milliseconds: 5),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: paddle,
        secondaryEngine: mlKit,
      );

      final result = await pipeline.processCardSide(
        imagePath: '/test/card.jpg',
        side: CardSide.front,
      );

      expect(paddle.invocationCount, equals(1));
      expect(mlKit.invocationCount, equals(1));

      final timings = result.metadata['timings'] as Map<String, dynamic>;
      expect(timings, isNotNull);
      expect(timings['paddleMs'], isA<int>());
      expect(timings['mlKitMs'], isA<int>());
      expect(timings['arbitrationMs'], isA<int>());
      expect(timings['totalMs'], isA<int>());
      expect(timings['primaryMs'], isA<int>());
      expect(timings['secondaryMs'], isA<int>());

      // Paddle was primary (longer delay), ML Kit secondary (shorter delay)
      expect(timings['paddleMs'] as int, greaterThanOrEqualTo(25));
      expect(result.metadata['paddleMs'], equals(timings['paddleMs']));
      expect(result.metadata['mlKitMs'], equals(timings['mlKitMs']));
      expect(result.metadata['totalMs'], equals(timings['totalMs']));
    });

    test('7. Reversed order pipeline assigns paddleMs and mlKitMs without swapping', () async {
      final mlKit = FakeMlKitEngine(
        simulatedDelay: const Duration(milliseconds: 30),
      );
      final paddle = FakePaddleEngine(
        simulatedDelay: const Duration(milliseconds: 5),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mlKit,
        secondaryEngine: paddle,
      );

      final result = await pipeline.processCardSide(
        imagePath: '/test/card.jpg',
        side: CardSide.front,
      );

      final timings = result.metadata['timings'] as Map<String, dynamic>;
      // In reversed order: primary was ML Kit (~30ms), secondary was Paddle (~5ms)
      expect(timings['mlKitMs'] as int, greaterThanOrEqualTo(25));
      expect(result.metadata['mlKitMs'], equals(timings['mlKitMs']));
      expect(result.metadata['paddleMs'], equals(timings['paddleMs']));
    });

    test('8. Primary engine exception records its own duration and does not transfer to secondary', () async {
      final failingPaddle = FakePaddleEngine(
        simulatedDelay: const Duration(milliseconds: 15),
        shouldThrow: true,
      );
      final succeedingMlKit = FakeMlKitEngine(
        simulatedDelay: const Duration(milliseconds: 5),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: failingPaddle,
        secondaryEngine: succeedingMlKit,
      );

      final result = await pipeline.processCardSide(
        imagePath: '/test/card.jpg',
        side: CardSide.front,
      );

      expect(failingPaddle.invocationCount, equals(1));
      expect(succeedingMlKit.invocationCount, equals(1));

      // Result should preserve the working secondary engine
      expect(result.metadata['fallbackInvoked'], isTrue);
      expect(result.metadata['fallbackReason'], contains('Primary failed'));

      final timings = result.metadata['timings'] as Map<String, dynamic>;
      expect(timings['paddleMs'] as int, greaterThanOrEqualTo(10));
      expect(timings['mlKitMs'] as int, isNotNull);
      expect(result.metadata['paddleMs'], equals(timings['paddleMs']));
      expect(result.metadata['mlKitMs'], equals(timings['mlKitMs']));
    });

    test('9. Secondary engine exception records its duration without corrupting primary', () async {
      final succeedingPaddle = FakePaddleEngine(
        simulatedDelay: const Duration(milliseconds: 10),
      );
      final failingMlKit = FakeMlKitEngine(
        simulatedDelay: const Duration(milliseconds: 15),
        shouldThrow: true,
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: succeedingPaddle,
        secondaryEngine: failingMlKit,
      );

      final result = await pipeline.processCardSide(
        imagePath: '/test/card.jpg',
        side: CardSide.front,
      );

      expect(succeedingPaddle.invocationCount, equals(1));
      expect(failingMlKit.invocationCount, equals(1));

      expect(result.metadata['fallbackInvoked'], isTrue);
      expect(result.metadata['fallbackReason'], contains('Secondary failed'));

      final timings = result.metadata['timings'] as Map<String, dynamic>;
      expect(timings['paddleMs'] as int, greaterThanOrEqualTo(5));
      expect(timings['mlKitMs'] as int, greaterThanOrEqualTo(10));
    });

    test('10. Both engines failing preserves measured timings in fail-soft result', () async {
      final failingPaddle = FakePaddleEngine(shouldThrow: true);
      final failingMlKit = FakeMlKitEngine(shouldThrow: true);

      final pipeline = HybridOcrPipeline(
        primaryEngine: failingPaddle,
        secondaryEngine: failingMlKit,
      );

      final result = await pipeline.processCardSide(
        imagePath: '/test/card.jpg',
        side: CardSide.front,
      );

      expect(result.metadata['selectedEngine'], equals('Both engines failed'));
      expect(result.metadata['fallbackInvoked'], isTrue);

      final timings = result.metadata['timings'] as Map<String, dynamic>;
      expect(timings['paddleMs'], isA<int>());
      expect(timings['mlKitMs'], isA<int>());
      expect(timings['arbitrationMs'], isA<int>());
      expect(timings['totalMs'], isA<int>());
    });

    test('11. Unknown custom engine records primaryMs/secondaryMs and leaves mlKitMs/paddleMs at zero', () async {
      final customPrimary = FakeEngine(name: 'Custom OCR Alpha', simulatedDelay: const Duration(milliseconds: 10));
      final customSecondary = FakeEngine(name: 'Custom OCR Beta', simulatedDelay: const Duration(milliseconds: 10));

      final pipeline = HybridOcrPipeline(
        primaryEngine: customPrimary,
        secondaryEngine: customSecondary,
      );

      final result = await pipeline.processCardSide(
        imagePath: '/test/card.jpg',
        side: CardSide.front,
      );

      final timings = result.metadata['timings'] as Map<String, dynamic>;
      // Documented behavior: zero for non-matching engines
      expect(timings['mlKitMs'], equals(0));
      expect(timings['paddleMs'], equals(0));
      // Custom slots are accessible via primaryMs and secondaryMs
      expect(timings['primaryMs'] as int, greaterThanOrEqualTo(5));
      expect(timings['secondaryMs'] as int, greaterThanOrEqualTo(5));
    });

    test('12. Preserves existing metadata contract and field resolution structure', () async {
      final paddle = FakePaddleEngine();
      final mlKit = FakeMlKitEngine();

      final pipeline = HybridOcrPipeline(
        primaryEngine: paddle,
        secondaryEngine: mlKit,
      );

      final result = await pipeline.processCardSide(
        imagePath: '/test/card.jpg',
        side: CardSide.front,
      );

      // Verify all contract keys required by downstream consumers and benchmark reporter
      expect(result.metadata['pipeline'], equals('Hybrid OCR Pipeline'));
      expect(result.metadata['selectedEngine'], contains('Hybrid Field-Resolved'));
      expect(result.metadata['fallbackInvoked'], isNotNull);
      expect(result.metadata['processingTimeMs'], isA<int>());
      expect(result.metadata['timings'], isA<Map<String, dynamic>>());
      expect(result.metadata['mlKitMs'], isA<int>());
      expect(result.metadata['paddleMs'], isA<int>());
      expect(result.metadata['arbitrationMs'], isA<int>());
      expect(result.metadata['totalMs'], isA<int>());
      expect(result.metadata['fieldSources'], isA<Map<String, dynamic>>());
      expect(result.metadata['fieldResolution'], isA<Map<String, dynamic>>());
    });
  });
}
