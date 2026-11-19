import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:digital_share/screens/scan/business_card_scan_screen.dart';
import 'package:digital_share/screens/scan/ocr_engine_comparison_screen.dart';
import 'package:digital_share/services/ocr/ocr_engine.dart';
import 'package:digital_share/services/ocr/ml_kit_ocr_engine.dart';
import 'package:digital_share/services/ocr/paddle_ocr_engine.dart';
import 'package:digital_share/services/business_card_ocr_service.dart';
import 'package:digital_share/services/card_geometry_service.dart';
import 'package:digital_share/services/image_enhancement_service.dart';

class MockOcrEngine implements OcrEngine {
  @override
  final String name;
  OcrEngineResult? resultToReturn;
  Duration simulatedDelay;
  bool shouldThrow;
  int invocationCount = 0;
  bool isDisposed = false;
  String? lastRecognizedPath;

  MockOcrEngine({
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

class MockImagePicker extends ImagePicker {
  XFile? pickedFile;
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
    return pickedFile;
  }
}

class FakeGeometryService extends CardGeometryService {
  const FakeGeometryService();

  @override
  Future<CardGeometryResult> correctPerspectiveIfReliable(
    String imagePath, [
    ViewfinderNormalizedRect? viewfinderRoi,
    List<Offset>? detectedNormalizedPolygon,
  ]) async {
    return CardGeometryResult.original(imagePath);
  }
}

class FakeEnhancementService extends ImageEnhancementService {
  const FakeEnhancementService();

  @override
  Future<String> normalizeExifOrientation(String imagePath) async => imagePath;

  @override
  Future<bool> isDarkCard(String imagePath) async => false;
}

void main() {
  group('OCR Engine Isolation & Architecture Tests', () {
    test('ML Kit remains the default engine for production scanner', () {
      const defaultService = BusinessCardOcrService();
      expect(defaultService, isA<BusinessCardOcrService>());
      expect(defaultService, isA<IBusinessCardOcrService>());
      // Verify ML Kit engine wraps text recognition under OcrEngine contract
      const mlKitEngine = MlKitOcrEngine();
      expect(mlKitEngine.name, equals('Google ML Kit'));
      expect(mlKitEngine, isA<OcrEngine>());
    });

    test('PaddleOcrEngine conforms to OcrEngine contract and reports name', () {
      final paddleEngine = PaddleOcrEngine();
      expect(paddleEngine.name, contains('PaddleOCR'));
      expect(paddleEngine, isA<OcrEngine>());
    });

    test('OcrEngineResult calculates character count correctly', () {
      const text = 'Line 1\nLine 2\r\nLine 3';
      final count = OcrEngineResult.countCharacters(text);
      expect(count, equals(18)); // 'Line 1Line 2Line 3' has 18 chars
    });

    test('OcrEngineResult.failure constructs clean failure state', () {
      final failure = OcrEngineResult.failure(
        engineName: 'PaddleOCR',
        error: 'Model loading error',
        processingTime: const Duration(milliseconds: 50),
      );

      expect(failure.isSuccess, isFalse);
      expect(failure.error, equals('Model loading error'));
      expect(failure.rawText, isEmpty);
      expect(failure.lineCount, equals(0));
      expect(failure.characterCount, equals(0));
      expect(failure.processingTime.inMilliseconds, equals(50));
    });
  });

  group('OcrEngineComparisonScreen Unit & Widget Tests', () {
    late MockOcrEngine mockMlKit;
    late MockOcrEngine mockPaddle;
    late MockImagePicker mockPicker;
    late Directory tempDir;
    late File testImageFile;

    setUp(() {
      mockMlKit = MockOcrEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'JOHN DOE\nACME CORP\n+1 555-0199',
          lineCount: 3,
          characterCount: 26,
          processingTime: Duration(milliseconds: 85),
          isSuccess: true,
          detectedLines: ['JOHN DOE', 'ACME CORP', '+1 555-0199'],
        ),
      );

      mockPaddle = MockOcrEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'JOHN DOE\nSenior Director\nACME CORP\n+1 555-0199',
          lineCount: 4,
          characterCount: 41,
          processingTime: Duration(milliseconds: 140),
          isSuccess: true,
          detectedLines: [
            'JOHN DOE',
            'Senior Director',
            'ACME CORP',
            '+1 555-0199',
          ],
        ),
      );

      mockPicker = MockImagePicker();
      tempDir = Directory.systemTemp.createTempSync('ocr_test_');
      testImageFile = File('${tempDir.path}/sample_card.jpg');
      final testImg = img.Image(width: 100, height: 60);
      img.fill(testImg, color: img.ColorRgb8(255, 255, 255));
      testImageFile.writeAsBytesSync(img.encodeJpg(testImg));
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets('Renders comparison screen with Dev/Test banner and picker buttons',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OcrEngineComparisonScreen(
            mlKitEngine: mockMlKit,
            paddleEngine: mockPaddle,
            imagePicker: mockPicker,
            geometryService: const FakeGeometryService(),
            enhancementService: const FakeEnhancementService(),
          ),
        ),
      );

      expect(find.text('OCR Engine Comparison'), findsOneWidget);
      expect(find.textContaining('EXPERIMENTAL BENCHMARK ONLY'), findsOneWidget);
      expect(find.byKey(const Key('compare_take_photo_button')), findsOneWidget);
      expect(find.byKey(const Key('compare_choose_gallery_button')), findsOneWidget);
    });

    testWidgets('User cancellation does not trigger inference or crash',
        (tester) async {
      mockPicker.pickedFile = null; // User cancelled

      await tester.pumpWidget(
        MaterialApp(
          home: OcrEngineComparisonScreen(
            mlKitEngine: mockMlKit,
            paddleEngine: mockPaddle,
            imagePicker: mockPicker,
            geometryService: const FakeGeometryService(),
            enhancementService: const FakeEnhancementService(),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('compare_choose_gallery_button')));
      await tester.pumpAndSettle();

      expect(mockMlKit.invocationCount, equals(0));
      expect(mockPaddle.invocationCount, equals(0));
      expect(find.text('Running Google ML Kit on-device...'), findsNothing);
    });

    Future<void> pumpUntilDone(WidgetTester tester) async {
      await tester.pump(); // Deliver gesture event and trigger onPressed
      await tester.runAsync(() async {
        for (int i = 0; i < 100; i++) {
          await Future.delayed(const Duration(milliseconds: 30));
          if (mockMlKit.invocationCount > 0 && mockPaddle.invocationCount > 0) {
            break;
          }
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets(
        'Executes engines sequentially and displays side-by-side raw results & deltas',
        (tester) async {
      mockPicker.pickedFile = XFile(testImageFile.path);

      await tester.pumpWidget(
        MaterialApp(
          home: OcrEngineComparisonScreen(
            mlKitEngine: mockMlKit,
            paddleEngine: mockPaddle,
            imagePicker: mockPicker,
            geometryService: const FakeGeometryService(),
            enhancementService: const FakeEnhancementService(),
          ),
        ),
      );

      await tester.ensureVisible(
          find.byKey(const Key('compare_choose_gallery_button')));
      await tester.tap(find.byKey(const Key('compare_choose_gallery_button')));
      await pumpUntilDone(tester);

      expect(mockPicker.lastSource, equals(ImageSource.gallery));
      // Both engines invoked exactly once
      expect(mockMlKit.invocationCount, equals(1));
      expect(mockPaddle.invocationCount, equals(1));

      // Raw OCR text displayed
      expect(find.textContaining('JOHN DOE\nACME CORP'), findsOneWidget);
      expect(find.textContaining('Senior Director'), findsOneWidget);

      // Latency, lines, and chars displayed
      expect(find.text('85 ms'), findsOneWidget);
      expect(find.text('140 ms'), findsOneWidget);
      expect(find.text('3'), findsWidgets);
      expect(find.text('4'), findsWidgets);

      // Delta comparison card displayed
      expect(find.textContaining('Engine Comparison Delta'), findsOneWidget);
      expect(find.text('+55 ms'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('+15'), findsOneWidget);
    });

    testWidgets('Gracefully handles PaddleOCR failure without crashing or hiding ML Kit',
        (tester) async {
      mockPicker.pickedFile = XFile(testImageFile.path);

      // PaddleOCR fails
      mockPaddle = MockOcrEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: OcrEngineResult.failure(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          error: 'Unavailable: Model asset could not be initialized on device',
          processingTime: const Duration(milliseconds: 15),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OcrEngineComparisonScreen(
            mlKitEngine: mockMlKit,
            paddleEngine: mockPaddle,
            imagePicker: mockPicker,
            geometryService: const FakeGeometryService(),
            enhancementService: const FakeEnhancementService(),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('compare_choose_gallery_button')));
      await pumpUntilDone(tester);

      // ML Kit result is still intact and shown
      expect(mockMlKit.invocationCount, equals(1));
      expect(find.textContaining('JOHN DOE\nACME CORP'), findsOneWidget);

      // PaddleOCR shows clear error message
      expect(
        find.textContaining('Unavailable: Model asset could not be initialized'),
        findsOneWidget,
      );
    });

    testWidgets('Handles empty OCR results cleanly', (tester) async {
      mockPicker.pickedFile = XFile(testImageFile.path);

      mockMlKit = MockOcrEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: '',
          lineCount: 0,
          characterCount: 0,
          processingTime: Duration(milliseconds: 30),
          isSuccess: true,
          detectedLines: [],
        ),
      );

      mockPaddle = MockOcrEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: '',
          lineCount: 0,
          characterCount: 0,
          processingTime: Duration(milliseconds: 40),
          isSuccess: true,
          detectedLines: [],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OcrEngineComparisonScreen(
            mlKitEngine: mockMlKit,
            paddleEngine: mockPaddle,
            imagePicker: mockPicker,
            geometryService: const FakeGeometryService(),
            enhancementService: const FakeEnhancementService(),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('compare_choose_gallery_button')));
      await pumpUntilDone(tester);

      expect(find.text('No text recognized'), findsNWidgets(2));
    });

    testWidgets('Disposes engines when screen is popped', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OcrEngineComparisonScreen(
            mlKitEngine: mockMlKit,
            paddleEngine: mockPaddle,
            imagePicker: mockPicker,
          ),
        ),
      );

      // Push and pop
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();

      expect(mockPaddle.isDisposed, isTrue);
      expect(mockMlKit.isDisposed, isTrue);
    });

    testWidgets(
        'Navigation from BusinessCardScanScreen to OcrEngineComparisonScreen works via AppBar and Card',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BusinessCardScanScreen(),
        ),
      );

      // 1. Verify AppBar comparison button exists
      final appBarButton = find.byKey(const Key('ocr_engine_comparison_button'));
      expect(appBarButton, findsOneWidget);

      // 2. Verify Mode Selection dev card exists
      final devCard = find.byKey(const Key('ocr_comparison_entry_card'));
      expect(devCard, findsOneWidget);

      // 3. Tap dev card to navigate
      await tester.tap(devCard);
      await tester.pumpAndSettle();

      expect(find.text('OCR Engine Comparison'), findsOneWidget);
      expect(find.textContaining('EXPERIMENTAL BENCHMARK ONLY'), findsOneWidget);
    });
  });
}
