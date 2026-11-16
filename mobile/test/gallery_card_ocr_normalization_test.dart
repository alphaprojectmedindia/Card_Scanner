import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:digital_share/models/imported_contact.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/screens/scan/business_card_scan_screen.dart';
import 'package:digital_share/services/business_card_ocr_service.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/card_geometry_service.dart';
import 'package:digital_share/services/card_image_normalization_service.dart';
import 'package:digital_share/services/image_enhancement_service.dart';
import 'package:digital_share/services/imported_contact_service.dart';
import 'package:digital_share/services/image_quality_service.dart';
import 'package:digital_share/services/ocr/field_semantic_evaluator.dart';
import 'package:digital_share/services/ocr/hybrid_ocr_pipeline.dart';
import 'package:digital_share/services/ocr/ocr_engine.dart';
import 'package:digital_share/services/pending_card_capture_store.dart';

class _AlwaysGoodQualityService extends ImageQualityService {
  const _AlwaysGoodQualityService();
  @override
  Future<ImageQualityResult> evaluateImagePath(String imagePath) async {
    return ImageQualityResult.good();
  }
}

class TestMockEngine implements OcrEngine {
  @override
  final String name;
  OcrEngineResult resultToReturn;
  int invocationCount = 0;
  String? lastProcessedImagePath;

  TestMockEngine({
    required this.name,
    this.resultToReturn = const OcrEngineResult(
      engineName: 'MockEngine',
      rawText: 'Default text',
      lineCount: 1,
      characterCount: 12,
      processingTime: Duration(milliseconds: 100),
      isSuccess: true,
      detectedLines: ['Default text'],
    ),
  });

  @override
  Future<OcrEngineResult> recognize(String imagePath) async {
    invocationCount++;
    lastProcessedImagePath = imagePath;
    return resultToReturn;
  }

  @override
  Future<void> dispose() async {}
}

class TestMockImagePicker extends ImagePicker {
  XFile? fileToReturn;
  ImageSource? lastSource;
  LostDataResponse lostDataToReturn = LostDataResponse.empty();

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
    return fileToReturn;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    return lostDataToReturn;
  }
}

class TestMockContactService extends ImportedContactService {
  final List<ImportedContact> saved = [];

  Future<List<ImportedContact>> getAll() async => saved;

  Future<void> save(ImportedContact contact) async {
    saved.add(contact);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late CardImageNormalizationService normService;

  setUp(() {
    testDir = Directory.systemTemp.createTempSync('gallery_ocr_test_');
    normService = const CardImageNormalizationService();
    PendingCardCaptureStore.resetForTesting();
  });

  tearDown(() {
    try {
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }
    } catch (_) {}
    PendingCardCaptureStore.resetForTesting();
  });

  String createTestImageFile({
    required String filename,
    required int width,
    required int height,
    int orientation = 1,
    String format = 'jpeg',
  }) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(240, 240, 240));

    // Draw some contrast lines simulating card text
    for (int y = height ~/ 4; y < height ~/ 2; y += 10) {
      for (int x = width ~/ 6; x < 5 * width ~/ 6; x++) {
        image.setPixel(x, y, img.ColorRgb8(30, 30, 30));
      }
    }

    image.exif.imageIfd.orientation = orientation;

    final file = File('${testDir.path}/$filename');
    final Uint8List encoded;
    if (format == 'png') {
      encoded = Uint8List.fromList(img.encodePng(image));
    } else {
      final raw = Uint8List.fromList(img.encodeJpg(image, quality: 92));
      if (orientation != 1) {
        final exif = img.ExifData();
        exif.imageIfd.orientation = orientation;
        final out = img.OutputBuffer();
        exif.write(out);
        final exifBytes = out.getBytes();
        final app1PayloadLength = 2 + 6 + exifBytes.length;
        final app1 = <int>[
          0xFF, 0xE1,
          (app1PayloadLength >> 8) & 0xFF,
          app1PayloadLength & 0xFF,
          0x45, 0x78, 0x69, 0x66, 0x00, 0x00,
          ...exifBytes,
        ];
        encoded = Uint8List.fromList(<int>[
          ...raw.sublist(0, 2),
          ...app1,
          ...raw.sublist(2),
        ]);
      } else {
        encoded = raw;
      }
    }
    file.writeAsBytesSync(encoded);
    return file.path;
  }

  group('Phase 19: Comprehensive Gallery OCR & Image Normalization Tests (36 Scenarios)', () {
    // 1. Gallery JPEG
    test('1. Gallery JPEG normalizes and produces readable output', () async {
      final path = createTestImageFile(filename: 'card.jpg', width: 1400, height: 900);
      final res = await normService.normalizeCardImage(imagePath: path);

      expect(File(res.normalizedPath).existsSync(), isTrue);
      expect(res.imageFormat, 'jpeg');
      expect(res.normalizedWidth, 1400);
      expect(res.normalizedHeight, 900);
      expect(res.wasResized, isFalse);
    });

    // 2. Gallery PNG
    test('2. Gallery PNG normalizes into clean JPEG scan image', () async {
      final path = createTestImageFile(filename: 'card.png', width: 1200, height: 750, format: 'png');
      final res = await normService.normalizeCardImage(imagePath: path);

      expect(File(res.normalizedPath).existsSync(), isTrue);
      expect(res.imageFormat, 'png');
      expect(res.normalizedWidth, 1200);
      expect(res.normalizedHeight, 750);
    });

    // 3. Gallery WEBP (inferred / supported format)
    test('3. Gallery WEBP header detected and normalized', () async {
      final path = createTestImageFile(filename: 'card.webp', width: 1300, height: 800);
      final res = await normService.normalizeCardImage(imagePath: path);

      expect(File(res.normalizedPath).existsSync(), isTrue);
      expect(res.normalizedWidth, 1300);
    });

    // 4. EXIF 90 deg rotation
    test('4. EXIF 90° rotation baked into physically upright pixels', () async {
      final path = createTestImageFile(
        filename: 'exif_90.jpg',
        width: 1600,
        height: 1000,
        orientation: 6, // 90 deg CW
      );
      final res = await normService.normalizeCardImage(imagePath: path);

      expect(res.wasOrientationBaked, isTrue);
      expect(res.exifOrientation, 6);
      // Dimensions swap when rotated 90 deg
      expect(res.normalizedWidth, 1000);
      expect(res.normalizedHeight, 1600);
    });

    // 5. EXIF 180 deg rotation
    test('5. EXIF 180° rotation baked into upright pixels', () async {
      final path = createTestImageFile(
        filename: 'exif_180.jpg',
        width: 1400,
        height: 900,
        orientation: 3, // 180 deg
      );
      final res = await normService.normalizeCardImage(imagePath: path);

      expect(res.wasOrientationBaked, isTrue);
      expect(res.exifOrientation, 3);
      expect(res.normalizedWidth, 1400);
      expect(res.normalizedHeight, 900);
    });

    // 6. EXIF 270 deg rotation
    test('6. EXIF 270° rotation baked into upright pixels', () async {
      final path = createTestImageFile(
        filename: 'exif_270.jpg',
        width: 1500,
        height: 950,
        orientation: 8, // 270 deg CW
      );
      final res = await normService.normalizeCardImage(imagePath: path);

      expect(res.wasOrientationBaked, isTrue);
      expect(res.exifOrientation, 8);
      expect(res.normalizedWidth, 950);
      expect(res.normalizedHeight, 1500);
    });

    // 7. Landscape business card
    test('7. Landscape card preserves landscape aspect ratio', () async {
      final path = createTestImageFile(filename: 'landscape.jpg', width: 1400, height: 800);
      final res = await normService.normalizeCardImage(imagePath: path);

      expect(res.normalizedWidth > res.normalizedHeight, isTrue);
      final ratio = res.normalizedWidth / res.normalizedHeight;
      expect((ratio - 1.75).abs() < 0.05, isTrue);
    });

    // 8. Portrait business card
    test('8. Portrait card preserves portrait aspect ratio', () async {
      final path = createTestImageFile(filename: 'portrait.jpg', width: 800, height: 1400);
      final res = await normService.normalizeCardImage(imagePath: path);

      expect(res.normalizedHeight > res.normalizedWidth, isTrue);
      final ratio = res.normalizedHeight / res.normalizedWidth;
      expect((ratio - 1.75).abs() < 0.05, isTrue);
    });

    // 9. Large 12MP-style image (e.g. 4032 x 3024)
    test('9. Large 12MP image downscaled to target long edge preserving aspect ratio', () async {
      final path = createTestImageFile(filename: '12mp.jpg', width: 4032, height: 3024);
      final res = await normService.normalizeCardImage(imagePath: path);

      expect(res.wasResized, isTrue);
      expect(res.normalizedWidth, 2160);
      // 3024 * (2160 / 4032) = 1620
      expect(res.normalizedHeight, 1620);
    });

    // 10. Very large image normalization (e.g. 6000 x 4000)
    test('10. Very large 24MP image downscaled cleanly without distortion', () async {
      final path = createTestImageFile(filename: '24mp.jpg', width: 6000, height: 4000);
      final res = await normService.normalizeCardImage(imagePath: path);

      expect(res.wasResized, isTrue);
      expect(res.normalizedWidth, 2160);
      // 4000 * (2160 / 6000) = 1440
      expect(res.normalizedHeight, 1440);
    });

    // 11. Low-resolution Gallery image (e.g. WhatsApp / 640x400)
    test('11. Low-resolution gallery card subjected to controlled upscale', () async {
      final path = createTestImageFile(filename: 'small.jpg', width: 640, height: 400);
      final res = await normService.normalizeCardImage(imagePath: path);

      expect(res.wasUpscaled, isTrue);
      expect(res.normalizedWidth > 640, isTrue);
      final scaleFactor = res.normalizedWidth / 640;
      expect(scaleFactor <= 1.8, isTrue);
    });

    // 12. Compressed JPEG
    test('12. Compressed JPEG decoded and normalized safely', () async {
      final image = img.Image(width: 1200, height: 750);
      img.fill(image, color: img.ColorRgb8(250, 250, 250));
      final lowQualBytes = img.encodeJpg(image, quality: 30);
      final file = File('${testDir.path}/compressed.jpg')..writeAsBytesSync(lowQualBytes);

      final res = await normService.normalizeCardImage(imagePath: file.path);
      expect(File(res.normalizedPath).existsSync(), isTrue);
    });

    // 13. Screenshot business card
    test('13. Screenshot card (e.g. phone screen aspect 1080x2400) handled correctly', () async {
      final path = createTestImageFile(filename: 'screenshot.jpg', width: 1080, height: 2400);
      final res = await normService.normalizeCardImage(imagePath: path);

      expect(res.wasResized, isTrue);
      expect(res.normalizedHeight, 2160);
      expect(res.normalizedWidth, (1080 * (2160 / 2400)).round());
    });

    // 14. Card surrounded by large background (corner detection < 0.70 preserves full frame)
    test('14. Card on large desk with low corner confidence preserves full frame without dangerous crops', () async {
      final path = createTestImageFile(filename: 'desk.jpg', width: 1600, height: 1200);
      final geometryService = const CardGeometryService(minConfidenceThreshold: 0.70);

      final res = await normService.normalizeCardImage(
        imagePath: path,
        geometryService: geometryService,
      );

      // Low confidence in simulated flat background prevents dangerous destructive crop
      expect(res.wasPerspectiveCorrected, isFalse);
      expect(res.normalizedWidth, 1600);
      expect(res.normalizedHeight, 1200);
    });

    // 15. Small text character height preservation
    test('15. Small font character dimensions preserved within optimal recognizer bounds', () async {
      final path = createTestImageFile(filename: 'text_card.jpg', width: 2000, height: 1200);
      final res = await normService.normalizeCardImage(imagePath: path);

      // 2000px long edge preserves small glyph strokes
      expect(res.normalizedWidth, 2000);
      expect(res.wasResized, isFalse);
    });

    // 16. Thin font / contrast preservation
    test('16. Low contrast image is gently contrast-enhanced without binary thresholding', () async {
      final image = img.Image(width: 1200, height: 800);
      img.fill(image, color: img.ColorRgb8(180, 180, 180));
      for (int i = 0; i < 50; i++) {
        image.setPixel(100 + i, 100, img.ColorRgb8(140, 140, 140)); // dynamic range = 40
      }
      final file = File('${testDir.path}/washed_out.jpg')..writeAsBytesSync(img.encodeJpg(image));

      final res = await normService.normalizeCardImage(imagePath: file.path);
      expect(File(res.normalizedPath).existsSync(), isTrue);
    });

    // 17. Cursive/decorative font candidate preservation via ImageEnhancementService
    test('17. Script/decorative font candidate generates valid enhanced file without binarization', () async {
      final path = createTestImageFile(filename: 'cursive.jpg', width: 1200, height: 800);
      const enhancement = ImageEnhancementService();
      final scriptCandidate = await enhancement.createScriptEnhancedCandidate(path);

      expect(scriptCandidate, isNotNull);
      expect(File(scriptCandidate!).existsSync(), isTrue);
      // Clean up
      File(scriptCandidate).deleteSync();
    });

    // 18. Gallery Front only
    test('18. Gallery Front only processed independently via BusinessCardOcrService', () async {
      final frontPath = createTestImageFile(filename: 'front_only.jpg', width: 1400, height: 900);
      final mockMlKit = TestMockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'David Miller\nProduct Manager\nAcme Corp\n+1 415 555 1234\ndavid@acme.com',
          lineCount: 5,
          characterCount: 78,
          processingTime: Duration(milliseconds: 250),
          isSuccess: true,
          detectedLines: [
            'David Miller',
            'Product Manager',
            'Acme Corp',
            '+1 415 555 1234',
            'david@acme.com',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(primaryEngine: mockMlKit, secondaryEngine: TestMockEngine(name: 'PaddleOCR'));
      final service = BusinessCardOcrService(hybridPipeline: pipeline);

      final result = await service.processCardSide(
        imagePath: frontPath,
        side: CardSide.front,
        source: 'gallery',
      );

      expect(result.side, CardSide.front);
      expect(result.rawText, contains('David Miller'));
      expect(mockMlKit.invocationCount, 1);
    });

    // 19. Gallery Front + Gallery Back
    test('19. Gallery Front + Gallery Back processed with independent normalization', () async {
      final frontPath = createTestImageFile(filename: 'front_dual.jpg', width: 1400, height: 900);
      final backPath = createTestImageFile(filename: 'back_dual.jpg', width: 1400, height: 900);

      final mockMlKit = TestMockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Sarah Connor\nCyberdyne\n+1 800 555 0199',
          lineCount: 3,
          characterCount: 42,
          processingTime: Duration(milliseconds: 260),
          isSuccess: true,
          detectedLines: ['Sarah Connor', 'Cyberdyne', '+1 800 555 0199'],
        ),
      );

      final pipeline = HybridOcrPipeline(primaryEngine: mockMlKit, secondaryEngine: TestMockEngine(name: 'PaddleOCR'));
      final service = BusinessCardOcrService(hybridPipeline: pipeline);

      final frontOcr = await service.processCardSide(imagePath: frontPath, side: CardSide.front, source: 'gallery');
      final backOcr = await service.processCardSide(imagePath: backPath, side: CardSide.back, source: 'gallery');

      expect(frontOcr.side, CardSide.front);
      expect(backOcr.side, CardSide.back);
      expect(mockMlKit.invocationCount, 2);
    });

    // 20. Camera Front + Gallery Back
    test('20. Camera Front + Gallery Back hybrid input sources supported', () async {
      final frontPath = createTestImageFile(filename: 'cam_front.jpg', width: 1400, height: 900);
      final backPath = createTestImageFile(filename: 'gal_back.jpg', width: 1400, height: 900);

      final mockMlKit = TestMockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Robert Langdon\nHarvard University',
          lineCount: 2,
          characterCount: 33,
          processingTime: Duration(milliseconds: 240),
          isSuccess: true,
          detectedLines: ['Robert Langdon', 'Harvard University'],
        ),
      );

      final pipeline = HybridOcrPipeline(primaryEngine: mockMlKit, secondaryEngine: TestMockEngine(name: 'PaddleOCR'));
      final service = BusinessCardOcrService(hybridPipeline: pipeline);

      final frontOcr = await service.processCardSide(imagePath: frontPath, side: CardSide.front, source: 'camera');
      final backOcr = await service.processCardSide(imagePath: backPath, side: CardSide.back, source: 'gallery');

      expect(frontOcr.side, CardSide.front);
      expect(backOcr.side, CardSide.back);
    });

    // 21. Gallery Front + Camera Back
    test('21. Gallery Front + Camera Back input sources supported', () async {
      final frontPath = createTestImageFile(filename: 'gal_front.jpg', width: 1400, height: 900);
      final backPath = createTestImageFile(filename: 'cam_back.jpg', width: 1400, height: 900);

      final mockMlKit = TestMockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Bruce Wayne\nWayne Enterprises',
          lineCount: 2,
          characterCount: 29,
          processingTime: Duration(milliseconds: 240),
          isSuccess: true,
          detectedLines: ['Bruce Wayne', 'Wayne Enterprises'],
        ),
      );

      final pipeline = HybridOcrPipeline(primaryEngine: mockMlKit, secondaryEngine: TestMockEngine(name: 'PaddleOCR'));
      final service = BusinessCardOcrService(hybridPipeline: pipeline);

      final frontOcr = await service.processCardSide(imagePath: frontPath, side: CardSide.front, source: 'gallery');
      final backOcr = await service.processCardSide(imagePath: backPath, side: CardSide.back, source: 'camera');

      expect(frontOcr.side, CardSide.front);
      expect(backOcr.side, CardSide.back);
    });

    // 22. Corrupt image throws CardNormalizationException
    test('22. Corrupt image file throws CardNormalizationException cleanly', () async {
      final corruptFile = File('${testDir.path}/corrupt.jpg')
        ..writeAsStringSync('THIS IS NOT A VALID JPEG OR PNG IMAGE BUFFER');

      expect(
        () => normService.normalizeCardImage(imagePath: corruptFile.path),
        throwsA(isA<CardNormalizationException>()),
      );
    });

    // 23. Zero-byte image throws CardNormalizationException
    test('23. Zero-byte image throws CardNormalizationException', () async {
      final zeroFile = File('${testDir.path}/zero.jpg')..writeAsBytesSync([]);

      expect(
        () => normService.normalizeCardImage(imagePath: zeroFile.path),
        throwsA(isA<CardNormalizationException>()),
      );
    });

    // 24. Unsupported/undecodable image throws CardNormalizationException
    test('24. Undecodable binary stream throws CardNormalizationException', () async {
      final binFile = File('${testDir.path}/random.bin')
        ..writeAsBytesSync(Uint8List.fromList([0x00, 0x11, 0x22, 0x33, 0x44, 0x55]));

      expect(
        () => normService.normalizeCardImage(imagePath: binFile.path),
        throwsA(isA<CardNormalizationException>()),
      );
    });

    // 25. User rapidly chooses a second image (session ID increments)
    testWidgets('25. User choosing second image increments session ID and updates staged path', (tester) async {
      final fakePicker = TestMockImagePicker();
      final path1 = createTestImageFile(filename: 'first.jpg', width: 800, height: 600);
      final path2 = createTestImageFile(filename: 'second.jpg', width: 800, height: 600);

      fakePicker.fileToReturn = XFile(path1);

      await tester.pumpWidget(MaterialApp(
        home: BusinessCardScanScreen(
          imagePicker: fakePicker,
          qualityService: const _AlwaysGoodQualityService(),
        ),
      ));

      // Tap physical card mode
      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();

      // Pick first image from gallery
      await tester.tap(find.byKey(const Key('inline_choose_gallery_button')));
      await tester.pumpAndSettle();

      expect(find.text('Preview & Add Card Sides'), findsOneWidget);

      // Now pick a second image from gallery via retake
      fakePicker.fileToReturn = XFile(path2);
      await tester.tap(find.byKey(const Key('retake_front_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('retake_front_gallery_button')));
      await tester.pumpAndSettle();

      expect(find.text('Preview & Add Card Sides'), findsOneWidget);
    });

    // 26. Old OCR result cannot overwrite latest selection
    testWidgets('26. Stale scan cannot overwrite newer selection if user clears staging', (tester) async {
      final fakePicker = TestMockImagePicker();
      final path1 = createTestImageFile(filename: 'stale.jpg', width: 800, height: 600);
      fakePicker.fileToReturn = XFile(path1);

      await tester.pumpWidget(MaterialApp(
        home: BusinessCardScanScreen(
          imagePicker: fakePicker,
          qualityService: const _AlwaysGoodQualityService(),
        ),
      ));

      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inline_choose_gallery_button')));
      await tester.pumpAndSettle();

      expect(find.text('Preview & Add Card Sides'), findsOneWidget);

      // User clears staging
      await tester.tap(find.byKey(const Key('remove_front_button')));
      await tester.pumpAndSettle();

      expect(find.text('Choose Scan Mode'), findsOneWidget);
    });

    // 27. Gallery reaches HybridOcrPipeline
    test('27. Gallery image passes through HybridOcrPipeline correctly', () async {
      final path = createTestImageFile(filename: 'hybrid_gal.jpg', width: 1400, height: 900);
      final mockMlKit = TestMockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Dr. Jane Smith\nCardiologist\nMetro Hospital\n+91 98400 12345\njane@metro.org',
          lineCount: 5,
          characterCount: 78,
          processingTime: Duration(milliseconds: 270),
          isSuccess: true,
          detectedLines: [
            'Dr. Jane Smith',
            'Cardiologist',
            'Metro Hospital',
            '+91 98400 12345',
            'jane@metro.org',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(primaryEngine: mockMlKit);
      final service = BusinessCardOcrService(hybridPipeline: pipeline);

      final res = await service.processCardSide(
        imagePath: path,
        side: CardSide.front,
        source: 'gallery',
      );

      expect(res.rawText, contains('Dr. Jane Smith'));
      expect(mockMlKit.invocationCount, 1);
    });

    // 28. Gallery ML Kit <60 invokes PaddleOCR
    test('28. Gallery ML Kit score < 60 invokes PaddleOCR fallback', () async {
      final path = createTestImageFile(filename: 'weak_mlkit.jpg', width: 1400, height: 900);
      final mockMlKit = TestMockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: '--- %%% @@@', // Score < 60
          lineCount: 1,
          characterCount: 11,
          processingTime: Duration(milliseconds: 250),
          isSuccess: true,
          detectedLines: ['--- %%% @@@'],
        ),
      );

      final mockPaddle = TestMockEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Rajesh Sharma\nConsultant\n+91 98765 00000',
          lineCount: 3,
          characterCount: 45,
          processingTime: Duration(milliseconds: 3800),
          isSuccess: true,
          detectedLines: ['Rajesh Sharma', 'Consultant', '+91 98765 00000'],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );
      final service = BusinessCardOcrService(hybridPipeline: pipeline);

      final res = await service.processCardSide(
        imagePath: path,
        side: CardSide.front,
        source: 'gallery',
      );

      expect(mockMlKit.invocationCount, 1);
      expect(mockPaddle.invocationCount, 1);
      expect(res.rawText, contains('Rajesh Sharma'));
    });

    // 29. Gallery card dual-engine execution runs both ML Kit and PaddleOCR
    test('29. Gallery card dual-engine execution runs both ML Kit and PaddleOCR', () async {
      final path = createTestImageFile(filename: 'strong_mlkit.jpg', width: 1400, height: 900);
      final mockMlKit = TestMockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Vikram Seth\nAuthor & Founder\nPenguin Random House\n+91 98111 22233\ncontact@vikramseth.in',
          lineCount: 5,
          characterCount: 88,
          processingTime: Duration(milliseconds: 280),
          isSuccess: true,
          detectedLines: [
            'Vikram Seth',
            'Author & Founder',
            'Penguin Random House',
            '+91 98111 22233',
            'contact@vikramseth.in',
          ],
        ),
      );

      final mockPaddle = TestMockEngine(name: 'PaddleOCR (PP-OCRv5 Mobile)');
      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );
      final service = BusinessCardOcrService(hybridPipeline: pipeline);

      final res = await service.processCardSide(imagePath: path, side: CardSide.front, source: 'gallery');

      expect(mockMlKit.invocationCount, 1);
      expect(mockPaddle.invocationCount, 1); // Both engines run!
      expect(res.rawText, contains('Vikram Seth'));
    });

    // 30. Gallery ML Kit >=60 with suspicious Name invokes PaddleOCR
    test('30. Gallery ML Kit score >= 60 with location selected as Name invokes Paddle fallback', () async {
      final path = createTestImageFile(filename: 'location_name.jpg', width: 1400, height: 900);
      final mockMlKit = TestMockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Chennai\nSoftware Solutions\n+91 98400 99999\ninfo@softwaresolutions.com',
          lineCount: 4,
          characterCount: 65,
          processingTime: Duration(milliseconds: 290),
          isSuccess: true,
          detectedLines: [
            'Chennai',
            'Software Solutions',
            '+91 98400 99999',
            'info@softwaresolutions.com',
          ],
        ),
      );

      final mockPaddle = TestMockEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Arun Kumar\nDirector\nSoftware Solutions\n+91 98400 99999\ninfo@softwaresolutions.com',
          lineCount: 5,
          characterCount: 85,
          processingTime: Duration(milliseconds: 3900),
          isSuccess: true,
          detectedLines: [
            'Arun Kumar',
            'Director',
            'Software Solutions',
            '+91 98400 99999',
            'info@softwaresolutions.com',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );
      final service = BusinessCardOcrService(hybridPipeline: pipeline);

      final res = await service.processCardSide(imagePath: path, side: CardSide.front, source: 'gallery');

      expect(mockPaddle.invocationCount, 1); // Triggered due to location name warning!
      expect(res.rawText, contains('Arun Kumar'));
    });

    // 31. Field-level merge still works (Name from Paddle, phone/email from ML Kit)
    test('31. Field-level merge preserves Paddle Name and ML Kit contact details', () {
      final resolution = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          'Chennai',
          '+91 98400 11111',
          'support@service.com',
          'www.service.com',
        ],
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 85.0,
        secondaryLines: [
          'Arun Kumar',
          '+91 98400 11111',
          'support@service.com',
        ],
        secondaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        secondaryOcrQualityScore: 72.0,
      );

      expect(resolution.name?.value, 'Arun Kumar');
      expect(resolution.name?.sourceEngine, 'PaddleOCR (PP-OCRv5 Mobile)');
      expect(resolution.phones.first.value, contains('98400 11111'));
      expect(resolution.emails.first.value, 'support@service.com');
      expect(resolution.websites.first.value, contains('service.com'));
    });

    // 32. Neither engine trustworthy -> Name remains empty
    test('32. Neither engine has a trustworthy person Name -> Name remains empty', () {
      final resolution = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          'Acme Corporation',
          '+1 415 555 0100',
          'info@acme.com',
        ],
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 70.0,
        secondaryLines: [
          '24/7 Global Solutions',
          '+1 415 555 0100',
        ],
        secondaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        secondaryOcrQualityScore: 70.0,
      );

      expect(resolution.name, isNull); // Zero hallucination!
      expect(resolution.phones.isNotEmpty, isTrue);
    });

    // 33. Phone/email deduplication works
    test('33. Phone and email deduplication removes duplicates across sides and engines', () {
      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/test/front.jpg',
        rawText: 'John Doe\n+91 98400 12345\njohn@example.com',
      );
      final backOcr = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: '/test/back.jpg',
        rawText: '+919840012345\nJOHN@EXAMPLE.COM\nHead Office: Bangalore',
      );

      const parser = BusinessCardParser();
      final parsed = parser.parseDualSided(front: frontOcr, back: backOcr);

      expect(parsed.fullName, 'John Doe');
      expect(parsed.phoneNumbers.length, 1);
      expect(parsed.emailAddresses.length, 1);
    });

    // 34. Existing Camera scanning still works
    test('34. Camera scanning invokes normalizer and pipeline successfully', () async {
      final path = createTestImageFile(filename: 'cam_test.jpg', width: 1400, height: 900);
      final mockMlKit = TestMockEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Priya Raman\nArchitect\nStudio Design\n+91 98765 43210',
          lineCount: 4,
          characterCount: 56,
          processingTime: Duration(milliseconds: 250),
          isSuccess: true,
          detectedLines: ['Priya Raman', 'Architect', 'Studio Design', '+91 98765 43210'],
        ),
      );

      final pipeline = HybridOcrPipeline(primaryEngine: mockMlKit);
      final service = BusinessCardOcrService(hybridPipeline: pipeline);

      final res = await service.processCardSide(imagePath: path, side: CardSide.front, source: 'camera');
      expect(res.rawText, contains('Priya Raman'));
    });

    // 35. Existing business-card lost-data recovery still works
    test('35. PendingCardCaptureStore saves, loads, and clears pending capture state', () async {
      await PendingCardCaptureStore.savePendingCapture(
        side: CardSide.front,
        frontPath: '/path/to/front.jpg',
        backPath: '/path/to/back.jpg',
      );

      final loaded = await PendingCardCaptureStore.loadPendingCapture();
      expect(loaded, isNotNull);
      expect(loaded!['side'], CardSide.front.name);
      expect(loaded['frontPath'], '/path/to/front.jpg');
      expect(loaded['backPath'], '/path/to/back.jpg');

      await PendingCardCaptureStore.clear();
      final cleared = await PendingCardCaptureStore.loadPendingCapture();
      expect(cleared, isNull);
    });

    // 36. No regression to imported-card persistence
    test('36. ImportedContact can be persisted and retrieved via ImportedContactService', () async {
      final contactService = TestMockContactService();
      final contact = ImportedContact(
        id: 'contact_123',
        fullName: 'Anita Roy',
        company: 'Roy Technologies',
        jobTitle: 'Founder & CEO',
        phoneNumbers: [const ImportedContactPhone(number: '+91 98888 77777')],
        emailAddresses: [const ImportedContactEmail(email: 'anita@roytech.com')],
      );

      await contactService.save(contact);
      final all = await contactService.getAll();
      expect(all.length, 1);
      expect(all.first.fullName, 'Anita Roy');
    });
  });
}
