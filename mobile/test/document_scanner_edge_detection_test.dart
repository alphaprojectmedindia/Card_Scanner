import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/screens/scan/business_card_camera_screen.dart';
import 'package:digital_share/screens/scan/business_card_review_screen.dart';
import 'package:digital_share/screens/scan/widgets/business_card_camera_overlay.dart';
import 'package:digital_share/services/card_geometry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper to generate test card images with customizable background, aspect ratio, and content
  img.Image generateCardOnTable({
    int width = 1000,
    int height = 650,
    required Rect cardRect,
    img.Color? tableColor,
    img.Color? cardColor,
    bool drawPrintedText = true,
  }) {
    final image = img.Image(width: width, height: height);

    // Table background (default: dark wood / slate)
    img.fill(image, color: tableColor ?? img.ColorRgb8(45, 40, 35));

    // Card surface (default: clean off-white / ivory)
    img.fillRect(
      image,
      x1: cardRect.left.toInt(),
      y1: cardRect.top.toInt(),
      x2: cardRect.right.toInt(),
      y2: cardRect.bottom.toInt(),
      color: cardColor ?? img.ColorRgb8(248, 248, 245),
    );

    if (drawPrintedText) {
      // Printed text lines in dark ink
      final inkColor = img.ColorRgb8(20, 25, 30);
      final lineCount = min(8, max(3, (cardRect.height ~/ 50)));
      for (int i = 0; i < lineCount; i++) {
        final y1 = (cardRect.top + 30 + (i * 42)).toInt();
        final y2 = y1 + 15;
        if (y2 < cardRect.bottom - 20) {
          img.fillRect(
            image,
            x1: (cardRect.left + 30).toInt(),
            y1: y1,
            x2: (cardRect.right - 35).toInt(),
            y2: y2,
            color: inkColor,
          );
        }
      }
    }

    return image;
  }

  group('Requirement 1 & 2: Document-Scanner Edge Detection & Quadrilateral Extraction', () {
    const geometryService = CardGeometryService();

    test('1. Standard rectangular business card (1.75:1) on dark table detects all 4 corners', () {
      final image = generateCardOnTable(
        width: 1000,
        height: 650,
        cardRect: const Rect.fromLTWH(150, 140, 700, 400), // aspect ratio = 1.75
      );

      final result = geometryService.detectBusinessCardPresence(image, allowSquare: true);

      expect(result.isDetected, isTrue);
      expect(result.corners, isNotNull);
      expect(result.corners!.isConvex, isTrue);
      expect(result.normalizedPolygon, isNotNull);
      expect(result.normalizedPolygon!.length, equals(4));
      expect(result.isLandscape, isTrue);
      expect(result.isSquare, isFalse);
      expect(result.aspectRatio, greaterThanOrEqualTo(1.50));
      expect(result.aspectRatio, lessThanOrEqualTo(2.00));
      expect(result.edgeContrast, greaterThanOrEqualTo(12.0));
      expect(result.hasCardContent, isTrue);
    });

    test('2. Rectangular card on light/white table with visible boundary is detected', () {
      final image = generateCardOnTable(
        width: 1000,
        height: 650,
        cardRect: const Rect.fromLTWH(180, 130, 640, 380),
        tableColor: img.ColorRgb8(215, 215, 210), // Light tabletop
        cardColor: img.ColorRgb8(255, 255, 255),  // White card with text
        drawPrintedText: true,
      );

      final result = geometryService.detectBusinessCardPresence(image, allowSquare: true);

      expect(result.isDetected, isTrue);
      expect(result.corners, isNotNull);
      expect(result.hasCardContent, isTrue);
    });

    test('3. Square-shaped business card (1:1) is detected when allowSquare is enabled', () {
      final image = generateCardOnTable(
        width: 900,
        height: 900,
        cardRect: const Rect.fromLTWH(200, 200, 500, 500), // 1:1 square
        drawPrintedText: true,
      );

      final result = geometryService.detectBusinessCardPresence(image, allowSquare: true);

      expect(result.isDetected, isTrue);
      expect(result.isSquare, isTrue);
      expect(result.corners, isNotNull);
      expect(result.corners!.isConvex, isTrue);
      expect(result.aspectRatio, greaterThanOrEqualTo(0.85));
      expect(result.aspectRatio, lessThanOrEqualTo(1.15));
    });

    test('4. Vertical / Portrait business card (0.58:1) is detected accurately', () {
      final image = generateCardOnTable(
        width: 750,
        height: 1100,
        cardRect: const Rect.fromLTWH(150, 160, 450, 780), // aspect ratio ~ 0.58
        drawPrintedText: true,
      );

      final result = geometryService.detectBusinessCardPresence(image, allowSquare: true);

      expect(result.isDetected, isTrue);
      expect(result.isPortrait, isTrue);
      expect(result.isLandscape, isFalse);
      expect(result.aspectRatio, greaterThanOrEqualTo(0.45));
      expect(result.aspectRatio, lessThanOrEqualTo(0.75));
    });

    test('5. Non-card blank sheet of paper is rejected (no interior content)', () {
      final image = generateCardOnTable(
        width: 1000,
        height: 650,
        cardRect: const Rect.fromLTWH(150, 140, 700, 400),
        drawPrintedText: false, // Monotone blank sheet
      );

      final result = geometryService.detectBusinessCardPresence(image, allowSquare: true);

      expect(result.isDetected, isFalse);
      expect(result.hasCardContent, isFalse);
    });

    test('6. Clipping card touching image borders is rejected with margin guidance', () {
      final image = generateCardOnTable(
        width: 1000,
        height: 650,
        cardRect: const Rect.fromLTWH(0, 50, 800, 450), // touches left boundary (x=0)
        drawPrintedText: true,
      );

      final result = geometryService.detectBusinessCardPresence(image, allowSquare: true);

      expect(result.isDetected, isFalse);
      expect(result.quality.isClipping, isTrue);
      expect(result.quality.guidanceMessage, equals('Keep the full card inside the frame'));
    });
  });

  group('Requirement 4: Perspective Correction and Exact Background Removal', () {
    const geometryService = CardGeometryService();

    test('1. Perspective rectification produces cropped image containing only the card', () async {
      final tempDir = Directory.systemTemp.path;
      final tempFile = File('$tempDir/doc_scanner_test_input_${DateTime.now().microsecondsSinceEpoch}.jpg');

      final image = generateCardOnTable(
        width: 1200,
        height: 800,
        cardRect: const Rect.fromLTWH(200, 180, 800, 460),
        drawPrintedText: true,
      );
      tempFile.writeAsBytesSync(img.encodeJpg(image, quality: 92));

      // Pass normalized polygon mapping from preview detection
      final normPolygon = [
        const Offset(200 / 1200, 180 / 800),
        const Offset(1000 / 1200, 180 / 800),
        const Offset(1000 / 1200, 640 / 800),
        const Offset(200 / 1200, 640 / 800),
      ];

      final result = await geometryService.correctPerspectiveIfReliable(
        tempFile.path,
        null,
        normPolygon,
      );

      expect(result.wasCorrected, isTrue);
      expect(result.imagePath, isNot(equals(tempFile.path)));
      expect(File(result.imagePath).existsSync(), isTrue);

      final croppedImage = img.decodeImage(await File(result.imagePath).readAsBytes());
      expect(croppedImage, isNotNull);

      // Verify the final image matches card dimensions without surrounding table
      final cropAspect = croppedImage!.width / croppedImage.height;
      expect(cropAspect, greaterThanOrEqualTo(1.45));
      expect(cropAspect, lessThanOrEqualTo(2.00));

      // Clean up
      if (tempFile.existsSync()) tempFile.deleteSync();
      if (File(result.imagePath).existsSync()) File(result.imagePath).deleteSync();
    });
  });

  group('Requirement 3 & 5: Camera UX, Real-Time Stability & Document Scanner Overlay', () {
    testWidgets('1. BusinessCardCameraOverlay renders Document Scanner boundary painter and corner pins', (tester) async {
      final polygon = [
        const Offset(50, 120),
        const Offset(320, 110),
        const Offset(310, 280),
        const Offset(45, 290),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessCardCameraOverlay(
              guidanceMessage: 'Card detected — Hold steady...',
              isReady: true,
              detectedPolygon: polygon,
              onCapture: () {},
              onCancel: () {},
              onToggleTorch: () {},
              onPickGallery: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check guidance pill text
      expect(find.text('Card detected — Hold steady...'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byKey(const Key('camera_capture_shutter_button')), findsOneWidget);
    });

    testWidgets('2. Multi-frame stability tracking advances guidance to manual capture ready', (tester) async {
      late BusinessCardDetectionResult testDetection;

      final testCorners = CardCorners(
        topLeft: const Point(100, 100),
        topRight: const Point(400, 100),
        bottomLeft: const Point(100, 280),
        bottomRight: const Point(400, 280),
      );

      testDetection = BusinessCardDetectionResult(
        isDetected: true,
        corners: testCorners,
        normalizedPolygon: [
          const Offset(0.2, 0.25),
          const Offset(0.8, 0.25),
          const Offset(0.8, 0.65),
          const Offset(0.2, 0.65),
        ],
        normalizedBoundingBox: const Rect.fromLTWH(0.2, 0.25, 0.6, 0.4),
        confidence: 0.90,
        aspectRatio: 1.66,
        isLandscape: true,
        hasCardContent: true,
        quality: const CaptureQualityAssessment(
          brightness: 128.0,
          isExtremelyDark: false,
          isExtremelyOverexposed: false,
          blurScore: 120.0,
          isBlurry: false,
          cardAreaRatio: 0.45,
          isTooSmall: false,
          isTooClose: false,
          isClipping: false,
          isSeverePerspective: false,
          isUsableResolution: true,
          guidanceMessage: 'Card aligned',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardCameraScreen(
            side: CardSide.front,
            requiredStableFrames: 3,
            previewBuilder: (ctx, controller) => Container(color: Colors.black),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final state = tester.state(find.byType(BusinessCardCameraScreen)) as dynamic;

      // Frame 1: Card detected -> Hold steady
      state.testProcessDetection(testDetection);
      await tester.pumpAndSettle();
      expect(find.text('Card detected — Hold steady...'), findsOneWidget);

      // Frame 2: Still stable -> Aligning & focusing (2/3)
      state.testProcessDetection(testDetection);
      await tester.pumpAndSettle();
      expect(find.text('Aligning & focusing (2/3)...'), findsOneWidget);

      // Frame 3: Stable for 3 frames -> Ready for manual capture
      state.testProcessDetection(testDetection);
      await tester.pumpAndSettle();
      expect(find.text('Card aligned & steady — Tap Capture to scan'), findsOneWidget);
    });

    testWidgets('2b. Default 10-frame consecutive stabilization pipeline requires 10 stable detections', (tester) async {
      final testCorners = CardCorners(
        topLeft: const Point(100, 100),
        topRight: const Point(400, 100),
        bottomLeft: const Point(100, 280),
        bottomRight: const Point(400, 280),
      );

      final testDetection = BusinessCardDetectionResult(
        isDetected: true,
        corners: testCorners,
        normalizedPolygon: [
          const Offset(0.2, 0.25),
          const Offset(0.8, 0.25),
          const Offset(0.8, 0.65),
          const Offset(0.2, 0.65),
        ],
        normalizedBoundingBox: const Rect.fromLTWH(0.2, 0.25, 0.6, 0.4),
        confidence: 0.90,
        aspectRatio: 1.66,
        isLandscape: true,
        hasCardContent: true,
        quality: const CaptureQualityAssessment(
          brightness: 128.0,
          isExtremelyDark: false,
          isExtremelyOverexposed: false,
          blurScore: 120.0,
          isBlurry: false,
          cardAreaRatio: 0.45,
          isTooSmall: false,
          isTooClose: false,
          isClipping: false,
          isSeverePerspective: false,
          isUsableResolution: true,
          guidanceMessage: 'Card aligned',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardCameraScreen(
            side: CardSide.front,
            // Uses default requiredStableFrames = 10
            previewBuilder: (ctx, controller) => Container(color: Colors.black),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final state = tester.state(find.byType(BusinessCardCameraScreen)) as dynamic;

      // Frame 1: DETECTED
      state.testProcessDetection(testDetection);
      await tester.pumpAndSettle();
      expect(find.text('Card detected — Hold steady...'), findsOneWidget);

      // Frames 2-9: TRACKING / STABILIZING
      for (int i = 2; i <= 9; i++) {
        state.testProcessDetection(testDetection);
        await tester.pumpAndSettle();
        expect(find.text('Aligning & focusing ($i/10)...'), findsOneWidget);
      }

      // Frame 10: 10 consecutive stable frames reached -> Ready for manual capture
      state.testProcessDetection(testDetection);
      await tester.pumpAndSettle();
      expect(find.text('Card aligned & steady — Tap Capture to scan'), findsOneWidget);
    });

    testWidgets('3. Corner movement/jitter resets stability counter', (tester) async {
      final testCorners = CardCorners(
        topLeft: const Point(100, 100),
        topRight: const Point(400, 100),
        bottomLeft: const Point(100, 280),
        bottomRight: const Point(400, 280),
      );

      final stableFrame1 = BusinessCardDetectionResult(
        isDetected: true,
        corners: testCorners,
        normalizedPolygon: [
          const Offset(0.2, 0.25),
          const Offset(0.8, 0.25),
          const Offset(0.8, 0.65),
          const Offset(0.2, 0.65),
        ],
        normalizedBoundingBox: const Rect.fromLTWH(0.2, 0.25, 0.6, 0.4),
        confidence: 0.90,
        aspectRatio: 1.66,
        isLandscape: true,
        hasCardContent: true,
        quality: const CaptureQualityAssessment(
          brightness: 128.0,
          isExtremelyDark: false,
          isExtremelyOverexposed: false,
          blurScore: 120.0,
          isBlurry: false,
          cardAreaRatio: 0.45,
          isTooSmall: false,
          isTooClose: false,
          isClipping: false,
          isSeverePerspective: false,
          isUsableResolution: true,
          guidanceMessage: 'Card aligned',
        ),
      );

      // Moved significantly (> 10% screen delta)
      final jitteredFrame2 = BusinessCardDetectionResult(
        isDetected: true,
        corners: testCorners,
        normalizedPolygon: [
          const Offset(0.35, 0.38),
          const Offset(0.92, 0.38),
          const Offset(0.92, 0.78),
          const Offset(0.35, 0.78),
        ],
        normalizedBoundingBox: const Rect.fromLTWH(0.35, 0.38, 0.6, 0.4),
        confidence: 0.90,
        aspectRatio: 1.66,
        isLandscape: true,
        hasCardContent: true,
        quality: stableFrame1.quality,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardCameraScreen(
            side: CardSide.front,
            previewBuilder: (ctx, controller) => Container(color: Colors.black),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final state = tester.state(find.byType(BusinessCardCameraScreen)) as dynamic;

      // Frame 1: Stable
      state.testProcessDetection(stableFrame1);
      await tester.pumpAndSettle();
      expect(find.text('Card detected — Hold steady...'), findsOneWidget);

      // Frame 2: Jittered/Moved -> Counter resets back to 1
      state.testProcessDetection(jitteredFrame2);
      await tester.pumpAndSettle();
      expect(find.text('Card detected — Hold steady...'), findsOneWidget);
    });

    testWidgets('4. Camera lens switcher button renders when onSwitchCamera is provided', (tester) async {
      bool switched = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessCardCameraOverlay(
              guidanceMessage: 'Position your business card inside the camera view',
              onSwitchCamera: () {
                switched = true;
              },
              onCapture: () {},
              onCancel: () {},
              onToggleTorch: () {},
              onPickGallery: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final switchBtn = find.byKey(const Key('camera_switch_lens_button'));
      expect(switchBtn, findsOneWidget);

      await tester.tap(switchBtn);
      await tester.pumpAndSettle();

      expect(switched, isTrue);
    });
  });

  group('Camera Coordinate Mapper, YUV Sensor Rotation & Corner Angle Invariants', () {
    test('1. CameraCoordinateMapper performs bidirectional conversion with BoxFit.cover aspect compensation', () {
      const screenSize = Size(390, 844);
      // 9:16 portrait camera stream
      const previewAspect = 720 / 1280; // 0.5625

      final mapper = CameraCoordinateMapper(
        screenSize: screenSize,
        previewAspect: previewAspect,
      );

      // Camera center (0.5, 0.5) must map exactly to physical screen center
      final screenCenter = mapper.cameraToScreen(const Offset(0.5, 0.5));
      expect(screenCenter.dx, closeTo(195.0, 0.5));
      expect(screenCenter.dy, closeTo(422.0, 0.5));

      // Screen center mapped back to camera space must equal (0.5, 0.5)
      final camCenter = mapper.screenToCamera(screenCenter);
      expect(camCenter.dx, closeTo(0.5, 0.01));
      expect(camCenter.dy, closeTo(0.5, 0.01));
    });

    test('2. convertYuvToUprightLuma rotates landscape 90° Android sensor bytes into upright portrait image', () {
      const rawW = 1280;
      const rawH = 720;
      final yPlane = List<int>.filled(rawW * rawH, 128);

      // Set distinctive bright mark at raw sensor top-left (x=0, y=0)
      yPlane[0] = 250;

      final upright = CardGeometryService.convertYuvToUprightLuma(
        lumaBytes: yPlane,
        rawWidth: rawW,
        rawHeight: rawH,
        bytesPerRow: rawW,
        bytesPerPixel: 1,
        sensorOrientation: 90,
        isFrontFacing: false,
        targetWidth: 200,
      );

      // 90 deg rotation produces portrait image (height > width)
      expect(upright.width, equals(200));
      expect(upright.height, greaterThan(upright.width));
      expect(upright.height, equals(355));
    });

    test('3. CardCorners cornerAngle, angularScore, and edgeConsistency validate document perspective', () {
      // 1. Perfect orthogonal rectangle
      final ortho = CardCorners(
        topLeft: const Point(100, 100),
        topRight: const Point(500, 100),
        bottomLeft: const Point(100, 320),
        bottomRight: const Point(500, 320),
      );

      for (int i = 0; i < 4; i++) {
        expect(ortho.cornerAngle(i), closeTo(90.0, 0.5));
      }
      expect(ortho.hasValidCornerAngles(), isTrue);
      expect(ortho.angularScore, closeTo(1.0, 0.02));
      expect(ortho.edgeConsistency, closeTo(1.0, 0.02));
      expect(ortho.rectangularityScore, closeTo(1.0, 0.02));

      // 2. Tilted perspective quadrilateral (75° to 105° corners)
      final tilted = CardCorners(
        topLeft: const Point(120, 100),
        topRight: const Point(480, 120),
        bottomLeft: const Point(90, 310),
        bottomRight: const Point(510, 300),
      );

      expect(tilted.hasValidCornerAngles(minAngleDeg: 55.0, maxAngleDeg: 125.0), isTrue);
      expect(tilted.angularScore, greaterThan(0.70));
      expect(tilted.edgeConsistency, greaterThan(0.80));

      // 3. Degenerate acute collapsed shape (< 40° corner) is rejected
      final collapsed = CardCorners(
        topLeft: const Point(100, 100),
        topRight: const Point(120, 105), // collapsed edge
        bottomLeft: const Point(100, 300),
        bottomRight: const Point(400, 300),
      );

      expect(collapsed.hasValidCornerAngles(minAngleDeg: 55.0, maxAngleDeg: 125.0), isFalse);
    });
  });

  group('Requirement 7: Comprehensive Acceptance Criteria across Surfaces, Lighting & Angles', () {
    test('1. Cards placed on wooden table with grain patterns are detected with high confidence', () {
      const geometryService = CardGeometryService();
      final image = img.Image(width: 1000, height: 650);

      // Wooden table background (brown base with natural wood grain texture)
      img.fill(image, color: img.ColorRgb8(118, 76, 42));
      for (int y = 0; y < 650; y += 18) {
        img.drawLine(
          image,
          x1: 20,
          y1: y,
          x2: 980,
          y2: y,
          color: img.ColorRgb8(106, 68, 38),
        );
      }

      // Card placed on table
      img.fillRect(
        image,
        x1: 160,
        y1: 140,
        x2: 840,
        y2: 520,
        color: img.ColorRgb8(248, 246, 240),
      );

      // Printed text lines in dark ink
      for (int i = 0; i < 6; i++) {
        img.fillRect(
          image,
          x1: 200,
          y1: 180 + (i * 45),
          x2: 780,
          y2: 198 + (i * 45),
          color: img.ColorRgb8(25, 25, 30),
        );
      }

      final result = geometryService.detectBusinessCardPresence(image, allowSquare: true);

      expect(result.isDetected, isTrue);
      expect(result.corners, isNotNull);
      expect(result.corners!.isConvex, isTrue);
      expect(result.confidence, greaterThanOrEqualTo(0.70));
      expect(result.edgeContrast, greaterThanOrEqualTo(10.0));
      expect(result.hasCardContent, isTrue);
    });

    test('2. Cards with rounded corners have full boundaries preserved without clipping', () async {
      const geometryService = CardGeometryService();
      final tempDir = Directory.systemTemp.path;
      final tempFile = File('$tempDir/rounded_card_${DateTime.now().microsecondsSinceEpoch}.jpg');

      final image = img.Image(width: 1000, height: 650);
      img.fill(image, color: img.ColorRgb8(40, 40, 45));

      // Draw card with rounded corners
      img.fillRect(
        image,
        x1: 150,
        y1: 140,
        x2: 850,
        y2: 520,
        color: img.ColorRgb8(250, 250, 248),
      );
      // Shave 4 corners with background color to simulate rounded radius
      for (int i = 0; i < 15; i++) {
        img.drawLine(image, x1: 150, y1: 140 + i, x2: 150 + (15 - i), y2: 140, color: img.ColorRgb8(40, 40, 45));
        img.drawLine(image, x1: 850 - (15 - i), y1: 140, x2: 850, y2: 140 + i, color: img.ColorRgb8(40, 40, 45));
        img.drawLine(image, x1: 150, y1: 520 - i, x2: 150 + (15 - i), y2: 520, color: img.ColorRgb8(40, 40, 45));
        img.drawLine(image, x1: 850 - (15 - i), y1: 520, x2: 850, y2: 520 - i, color: img.ColorRgb8(40, 40, 45));
      }

      // Printed card text
      for (int i = 0; i < 5; i++) {
        img.fillRect(
          image,
          x1: 200,
          y1: 190 + (i * 45),
          x2: 760,
          y2: 206 + (i * 45),
          color: img.ColorRgb8(20, 25, 30),
        );
      }

      tempFile.writeAsBytesSync(img.encodeJpg(image, quality: 92));

      final detection = geometryService.detectCorners(image, allowSquare: true);
      expect(detection.corners, isNotNull);
      expect(detection.corners!.isConvex, isTrue);

      final rectResult = await geometryService.correctPerspectiveIfReliable(
        tempFile.path,
        null,
        detection.corners!.toNormalizedPolygon(image.width, image.height),
      );

      expect(rectResult.wasCorrected, isTrue);
      final cropped = img.decodeImage(await File(rectResult.imagePath).readAsBytes());
      expect(cropped, isNotNull);
      expect(cropped!.width, greaterThanOrEqualTo(350));
      expect(cropped.height, greaterThanOrEqualTo(250));

      if (tempFile.existsSync()) tempFile.deleteSync();
      if (File(rectResult.imagePath).existsSync()) File(rectResult.imagePath).deleteSync();
    });

    test('3. Cards in low-light and uneven illumination receive gentle tone enhancement', () async {
      const geometryService = CardGeometryService();
      final tempDir = Directory.systemTemp.path;
      final tempFile = File('$tempDir/low_light_card_${DateTime.now().microsecondsSinceEpoch}.jpg');

      final image = img.Image(width: 800, height: 500);
      img.fill(image, color: img.ColorRgb8(20, 18, 16));

      // Dim, low-light card (luma ~70-95) with uneven lighting gradient
      for (int y = 100; y < 400; y++) {
        for (int x = 120; x < 680; x++) {
          final gradientLuma = (60 + (x - 120) * (35 / 560)).round();
          image.setPixelRgb(x, y, gradientLuma, gradientLuma, gradientLuma);
        }
      }

      // Text lines
      for (int i = 0; i < 4; i++) {
        img.fillRect(
          image,
          x1: 160,
          y1: 140 + (i * 45),
          x2: 600,
          y2: 155 + (i * 45),
          color: img.ColorRgb8(10, 10, 12),
        );
      }

      tempFile.writeAsBytesSync(img.encodeJpg(image, quality: 90));

      final normPolygon = [
        const Offset(120 / 800, 100 / 500),
        const Offset(680 / 800, 100 / 500),
        const Offset(680 / 800, 400 / 500),
        const Offset(120 / 800, 400 / 500),
      ];

      final rectResult = await geometryService.correctPerspectiveIfReliable(
        tempFile.path,
        null,
        normPolygon,
      );

      expect(rectResult.wasCorrected, isTrue);
      expect(File(rectResult.imagePath).existsSync(), isTrue);

      final enhanced = img.decodeImage(await File(rectResult.imagePath).readAsBytes());
      expect(enhanced, isNotNull);

      // Verify that the enhanced card image has balanced visibility
      double enhancedLum = 0.0;
      int count = 0;
      for (int y = 0; y < enhanced!.height; y += 4) {
        for (int x = 0; x < enhanced.width; x += 4) {
          final p = enhanced.getPixel(x, y);
          enhancedLum += (0.299 * p.r + 0.587 * p.g + 0.114 * p.b);
          count++;
        }
      }
      final avgEnhancedLum = enhancedLum / count;
      expect(avgEnhancedLum, greaterThan(60.0));

      if (tempFile.existsSync()) tempFile.deleteSync();
      if (File(rectResult.imagePath).existsSync()) File(rectResult.imagePath).deleteSync();
    });

    test('4. Cards tilted/rotated at angle are perspective-rectified to horizontal rectangle', () async {
      const geometryService = CardGeometryService();
      final tempDir = Directory.systemTemp.path;
      final tempFile = File('$tempDir/tilted_card_${DateTime.now().microsecondsSinceEpoch}.jpg');

      final image = img.Image(width: 1000, height: 700);
      img.fill(image, color: img.ColorRgb8(35, 30, 28));

      // Tilted card quadrilateral vertices
      final p0 = const Offset(180 / 1000, 140 / 700); // TL
      final p1 = const Offset(820 / 1000, 100 / 700); // TR (tilted up)
      final p2 = const Offset(860 / 1000, 520 / 700); // BR
      final p3 = const Offset(140 / 1000, 560 / 700); // BL (tilted down)

      final normPolygon = [p0, p1, p2, p3];

      img.fillRect(image, x1: 200, y1: 180, x2: 800, y2: 480, color: img.ColorRgb8(245, 245, 240));

      tempFile.writeAsBytesSync(img.encodeJpg(image, quality: 92));

      final rectResult = await geometryService.correctPerspectiveIfReliable(
        tempFile.path,
        null,
        normPolygon,
      );

      expect(rectResult.wasCorrected, isTrue);
      final corrected = img.decodeImage(await File(rectResult.imagePath).readAsBytes());
      expect(corrected, isNotNull);
      expect(corrected!.width, greaterThan(corrected.height));
      final aspect = corrected.width / corrected.height;
      expect(aspect, greaterThanOrEqualTo(1.30));
      expect(aspect, lessThanOrEqualTo(2.20));

      if (tempFile.existsSync()) tempFile.deleteSync();
      if (File(rectResult.imagePath).existsSync()) File(rectResult.imagePath).deleteSync();
    });

    testWidgets('5. Auto-capture countdown visual indicator renders progress ring and percentage badge', (tester) async {
      final polygon = [
        const Offset(60, 130),
        const Offset(330, 120),
        const Offset(320, 290),
        const Offset(55, 300),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessCardCameraOverlay(
              guidanceMessage: 'Hold steady — Capturing automatically...',
              isReady: true,
              autoCaptureProgress: 0.75,
              detectedPolygon: polygon,
              onCapture: () {},
              onCancel: () {},
              onToggleTorch: () {},
              onPickGallery: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Hold steady — Capturing automatically...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('camera_capture_shutter_button')), findsOneWidget);
    });

    testWidgets('6. Business Card Details Screen displays perspective-corrected image with background removed', (tester) async {
      final tempDir = Directory.systemTemp.path;
      final tempFile = File('$tempDir/review_card_${DateTime.now().microsecondsSinceEpoch}.jpg');
      final dummyImage = img.Image(width: 700, height: 400);
      img.fill(dummyImage, color: img.ColorRgb8(250, 250, 248));
      tempFile.writeAsBytesSync(img.encodeJpg(dummyImage, quality: 90));

      const cardData = BusinessCardData(
        fullName: 'Dr. Jane Smith',
        jobTitle: 'Chief Medical Officer',
        company: 'Medindia Healthcare',
        phoneNumbers: [],
        emailAddresses: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(
            cardData: cardData,
            frontImagePath: tempFile.path,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Business Card Details'), findsOneWidget);
      expect(find.text('Cropped Card Image'), findsOneWidget);
      expect(find.text('Background Removed'), findsOneWidget);
      expect(find.byKey(const Key('cropped_card_front')), findsOneWidget);

      if (tempFile.existsSync()) tempFile.deleteSync();
    });
  });
}
