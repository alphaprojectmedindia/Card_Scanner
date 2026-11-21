import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/screens/scan/business_card_camera_screen.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/card_geometry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Helper to generate test card images with customizable background, aspect ratio, and content
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

  group('OpenCV Card Scanner Reference Pipeline — Unit Tests', () {
    const geometryService = CardGeometryService();

    // -------------------------------------------------------------------------
    // 1. get_distance()
    // -------------------------------------------------------------------------
    test('1. getDistance accurately computes Euclidean distance', () {
      final p1 = const Point<int>(0, 0);
      final p2 = const Point<int>(3, 4);
      expect(CardGeometryService.getDistance(p1, p2), equals(5.0));

      final p3 = const Point<int>(100, 200);
      final p4 = const Point<int>(400, 600);
      expect(CardGeometryService.getDistance(p3, p4), equals(500.0));
    });

    // -------------------------------------------------------------------------
    // 2. order_points()
    // -------------------------------------------------------------------------
    test('2. orderPoints sorts vertices into consistent [TL, TR, BR, BL] order', () {
      // Unordered points of a rectangle
      final unordered = [
        const Point<int>(400, 280), // BR
        const Point<int>(100, 100), // TL
        const Point<int>(100, 280), // BL
        const Point<int>(400, 100), // TR
      ];

      final ordered = CardGeometryService.orderPoints(unordered);

      expect(ordered.length, equals(4));
      expect(ordered[0], equals(const Point<int>(100, 100))); // Top-Left
      expect(ordered[1], equals(const Point<int>(400, 100))); // Top-Right
      expect(ordered[2], equals(const Point<int>(400, 280))); // Bottom-Right
      expect(ordered[3], equals(const Point<int>(100, 280))); // Bottom-Left
    });

    test('2b. orderPoints correctly handles rotated quadrilateral points', () {
      // Quadrilateral rotated 30 degrees
      final rotated = [
        const Point<int>(450, 150),
        const Point<int>(200, 100),
        const Point<int>(150, 300),
        const Point<int>(400, 350),
      ];

      final ordered = CardGeometryService.orderPoints(rotated);

      expect(ordered.length, equals(4));
      // Top-Left should be closest to (minX, minY)
      expect(ordered[0], equals(const Point<int>(200, 100)));
      expect(ordered[1], equals(const Point<int>(450, 150)));
      expect(ordered[2], equals(const Point<int>(400, 350)));
      expect(ordered[3], equals(const Point<int>(150, 300)));
    });

    // -------------------------------------------------------------------------
    // 3. find_dest()
    // -------------------------------------------------------------------------
    test('3. findDest calculates destination width, height, and destination coordinates', () {
      final ordered = [
        const Point<int>(100, 100), // TL
        const Point<int>(800, 100), // TR (width = 700)
        const Point<int>(800, 500), // BR (height = 400)
        const Point<int>(100, 500), // BL
      ];

      final dest = CardGeometryService.findDest(ordered);

      expect(dest.width, equals(700));
      expect(dest.height, equals(400));
      expect(dest.destPoints.length, equals(4));
      expect(dest.destPoints[0], equals(const Point<int>(0, 0)));
      expect(dest.destPoints[1], equals(const Point<int>(699, 0)));
      expect(dest.destPoints[2], equals(const Point<int>(699, 399)));
      expect(dest.destPoints[3], equals(const Point<int>(0, 399)));
    });

    // -------------------------------------------------------------------------
    // 4. applyGaussianBlur()
    // -------------------------------------------------------------------------
    test('4. applyGaussianBlur smooths salt-and-pepper noise', () {
      final imgOriginal = img.Image(width: 50, height: 50);
      img.fill(imgOriginal, color: img.ColorRgb8(128, 128, 128));

      // Inject impulse noise spike
      imgOriginal.setPixelRgb(25, 25, 255, 255, 255);

      final blurred = CardGeometryService.applyGaussianBlur(imgOriginal, kernelSize: 5);

      // Noise peak should be attenuated
      final centerLum = blurred.getPixel(25, 25).r.toInt();
      expect(centerLum, lessThan(200));
      expect(centerLum, greaterThan(135));
    });

    // -------------------------------------------------------------------------
    // 5. applyCannyEdgeDetection()
    // -------------------------------------------------------------------------
    test('5. applyCannyEdgeDetection produces clean thinned edges with NMS', () {
      final testImg = img.Image(width: 100, height: 100);
      img.fill(testImg, color: img.ColorRgb8(30, 30, 30));

      // White rectangle in center
      img.fillRect(testImg, x1: 20, y1: 20, x2: 80, y2: 80, color: img.ColorRgb8(240, 240, 240));

      final blur = CardGeometryService.applyGaussianBlur(testImg);
      final canny = CardGeometryService.applyCannyEdgeDetection(blur, adaptive: true);

      // Verify that interior is 0 and boundary is 255
      expect(canny.getPixel(50, 50).r.toInt(), equals(0)); // Center interior has 0 edge
      expect(canny.getPixel(20, 50).r.toInt(), equals(255)); // Left edge
      expect(canny.getPixel(80, 50).r.toInt(), equals(255)); // Right edge
    });

    // -------------------------------------------------------------------------
    // 6. applyMorphologicalDilation()
    // -------------------------------------------------------------------------
    test('6. applyMorphologicalDilation bridges 1-pixel gap in boundary', () {
      final edgeImg = img.Image(width: 50, height: 50);
      img.fill(edgeImg, color: img.ColorRgb8(0, 0, 0));

      // Draw horizontal line with a 1-pixel gap at x=25
      for (int x = 10; x <= 40; x++) {
        if (x == 25) continue; // Gap
        edgeImg.setPixelRgb(x, 25, 255, 255, 255);
      }

      expect(edgeImg.getPixel(25, 25).r.toInt(), equals(0)); // Gap before dilation

      final dilated = CardGeometryService.applyMorphologicalDilation(edgeImg, iterations: 1);

      expect(dilated.getPixel(25, 25).r.toInt(), equals(255)); // Gap bridged after dilation
    });

    // -------------------------------------------------------------------------
    // 7. findContours() & approximatePolygonRdp()
    // -------------------------------------------------------------------------
    test('7. findContours & approximatePolygonRdp extract 4-point quadrilateral', () {
      final edgeImg = img.Image(width: 120, height: 120);
      img.fill(edgeImg, color: img.ColorRgb8(0, 0, 0));

      // Draw closed rectangle boundary
      img.drawRect(edgeImg, x1: 20, y1: 20, x2: 100, y2: 80, color: img.ColorRgb8(255, 255, 255));

      final contours = CardGeometryService.findContours(edgeImg, minPoints: 10);
      expect(contours, isNotEmpty);

      final contour = contours.first;
      final perim = CardGeometryService.calculatePerimeter(contour);
      final approx = CardGeometryService.approximatePolygonRdp(contour, 0.025 * perim);

      expect(approx.length, equals(4));
    });

    // -------------------------------------------------------------------------
    // 8. warpPerspective()
    // -------------------------------------------------------------------------
    test('8. warpPerspective rectifies quadrilateral into rectangular image', () {
      final srcImage = img.Image(width: 500, height: 400);
      img.fill(srcImage, color: img.ColorRgb8(50, 50, 50));

      // Draw colored card in center
      img.fillRect(srcImage, x1: 50, y1: 50, x2: 450, y2: 350, color: img.ColorRgb8(200, 180, 160));

      final corners = CardCorners(
        topLeft: const Point<int>(50, 50),
        topRight: const Point<int>(450, 50),
        bottomRight: const Point<int>(450, 350),
        bottomLeft: const Point<int>(50, 350),
      );

      final warped = CardGeometryService.warpPerspective(srcImage, corners, 400, 300);

      expect(warped.width, equals(400));
      expect(warped.height, equals(300));
      // Center pixel should match card color
      final p = warped.getPixel(200, 150);
      expect(p.r.toInt(), equals(200));
      expect(p.g.toInt(), equals(180));
      expect(p.b.toInt(), equals(160));
    });

    // -------------------------------------------------------------------------
    // 9. scanCard() — End-to-end multi-orientation detection
    // -------------------------------------------------------------------------
    test('9a. scanCard detects standard landscape business card', () {
      final image = generateCardOnTable(
        width: 1000,
        height: 650,
        cardRect: const Rect.fromLTWH(150, 140, 700, 400),
      );

      final corners = geometryService.scanCard(image, allowSquare: true);

      expect(corners, isNotNull);
      expect(corners!.isLandscape, isTrue);
      expect(corners.isSquare, isFalse);
      expect(corners.isPortrait, isFalse);
    });

    test('9b. scanCard detects vertical portrait business card', () {
      final image = generateCardOnTable(
        width: 650,
        height: 1000,
        cardRect: const Rect.fromLTWH(130, 150, 390, 700), // aspect ratio = 0.557
      );

      final corners = geometryService.scanCard(image, allowSquare: true);

      expect(corners, isNotNull);
      expect(corners!.isPortrait, isTrue);
      expect(corners.isLandscape, isFalse);
    });

    test('9c. scanCard detects 1:1 square-shaped business card', () {
      final image = generateCardOnTable(
        width: 800,
        height: 800,
        cardRect: const Rect.fromLTWH(150, 150, 500, 500), // 1:1 square
      );

      final corners = geometryService.scanCard(image, allowSquare: true);

      expect(corners, isNotNull);
      expect(corners!.isSquare, isTrue);
    });
  });

  group('Requirement 4: Manual Capture Enforcement & Gemini Integration Workflow', () {
    testWidgets('10. Automatic capture is strictly disabled; manual shutter button initiates capture', (tester) async {
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
        confidence: 0.95,
        aspectRatio: 1.66,
        isLandscape: true,
        hasCardContent: true,
        quality: const CaptureQualityAssessment(
          brightness: 130.0,
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

      // Pump multiple stable frames well exceeding the stable threshold
      for (int i = 0; i < 15; i++) {
        state.testProcessDetection(testDetection);
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Crucial test: Guidance instructs user to tap capture; screen does NOT auto-pop or auto-capture
      expect(find.text('Card aligned & steady — Tap Capture to scan'), findsOneWidget);
      expect(find.byKey(const Key('camera_capture_shutter_button')), findsOneWidget);
    });

    test('11. Gemini OCR contract extraction extracts structured fields without fabrication', () {
      const parser = BusinessCardParser();
      const ocrRaw = '''
Dr. Angela Bennett
Lead Systems Architect
Cyberdyne Security Systems Ltd
Phone: +1 (415) 555-0199
Mobile: +1 415 555 9821
Email: angela.bennett@cyberdyne.io
Web: www.cyberdyne.io
LinkedIn: linkedin.com/in/abennett
100 Marine Parkway, Redwood City, CA 94065
''';

      final ocr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: ocrRaw,
      );

      final cardData = parser.parseDualSided(front: ocr);

      // Strict extraction checks
      expect(cardData.fullName, equals('Dr. Angela Bennett'));
      expect(cardData.jobTitle, contains('Systems Architect'));
      expect(cardData.company, contains('Cyberdyne Security Systems'));
      expect(cardData.emailAddresses.any((e) => e.email == 'angela.bennett@cyberdyne.io'), isTrue);
      expect(cardData.website, contains('cyberdyne.io'));
      expect(cardData.phoneNumbers.any((p) => p.number.contains('0199')), isTrue);
      expect(cardData.address, contains('Redwood City'));
    });
  });
}
