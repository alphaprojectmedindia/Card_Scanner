import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:digital_share/config/legal_urls.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/user_profile.dart';
import 'package:digital_share/screens/profile/profile_screen.dart';
import 'package:digital_share/screens/scan/business_card_review_screen.dart';
import 'package:digital_share/screens/scan/widgets/business_card_camera_overlay.dart';
import 'package:digital_share/services/card_geometry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper to create synthetic card images
  img.Image createTestCardImage({
    int width = 1000,
    int height = 600,
    Rect? cardRect,
    bool drawText = true,
  }) {
    final image = img.Image(width: width, height: height);
    // Desk background (dark wood / slate)
    img.fill(image, color: img.ColorRgb8(55, 50, 45));

    final cRect = cardRect ??
        Rect.fromLTWH(
          width * 0.15,
          height * 0.20,
          width * 0.70,
          height * 0.60,
        );

    // Card surface (light ivory / white)
    img.fillRect(
      image,
      x1: cRect.left.toInt(),
      y1: cRect.top.toInt(),
      x2: cRect.right.toInt(),
      y2: cRect.bottom.toInt(),
      color: img.ColorRgb8(245, 245, 240),
    );

    if (drawText) {
      // Printed text lines (dark ink) distributed across the card
      final textColor = img.ColorRgb8(20, 20, 20);
      final lineCount = min(8, max(3, (cRect.height ~/ 55)));
      for (int i = 0; i < lineCount; i++) {
        final y1 = (cRect.top + 30 + (i * 45)).toInt();
        final y2 = y1 + 16;
        if (y2 < cRect.bottom - 20) {
          img.fillRect(
            image,
            x1: (cRect.left + 25).toInt(),
            y1: y1,
            x2: (cRect.right - 30).toInt(),
            y2: y2,
            color: textColor,
          );
        }
      }
    }

    return image;
  }

  group('Part 1 & 2: Business Card Detection & Crop Background Removal', () {
    const geometryService = CardGeometryService();

    test('1. Valid landscape card (1.75:1) with text is detected with high confidence', () {
      final image = createTestCardImage(width: 1000, height: 600);
      final detection = geometryService.detectBusinessCardPresence(image);

      expect(detection.isDetected, isTrue);
      expect(detection.hasCardContent, isTrue);
      expect(detection.aspectRatio, greaterThanOrEqualTo(1.25));
      expect(detection.aspectRatio, lessThanOrEqualTo(2.20));
      expect(detection.isLandscape, isTrue);
      expect(detection.normalizedBoundingBox, isNotNull);
      expect(detection.confidence, greaterThanOrEqualTo(0.65));
      expect(detection.quality.guidanceMessage, equals('Card aligned'));
    });

    test('2. Valid portrait card (0.60:1) with text is detected', () {
      final image = createTestCardImage(
        width: 800,
        height: 1200,
        cardRect: const Rect.fromLTWH(180, 200, 440, 750), // aspect ratio ~ 0.58
      );
      final detection = geometryService.detectBusinessCardPresence(image);

      expect(detection.isDetected, isTrue);
      expect(detection.hasCardContent, isTrue);
      expect(detection.aspectRatio, greaterThanOrEqualTo(0.45));
      expect(detection.aspectRatio, lessThanOrEqualTo(0.80));
      expect(detection.isLandscape, isFalse);
    });

    test('3. Square card (1.0:1) with text is detected when allowSquare is enabled, and rejected when disabled', () {
      final image = createTestCardImage(
        width: 1000,
        height: 1000,
        cardRect: const Rect.fromLTWH(250, 250, 500, 500), // 1:1 square
      );
      final detectionDefault = geometryService.detectBusinessCardPresence(image, allowSquare: false);
      expect(detectionDefault.isDetected, isFalse);

      final detectionSquare = geometryService.detectBusinessCardPresence(image, allowSquare: true);
      expect(detectionSquare.isDetected, isTrue);
      expect(detectionSquare.isSquare, isTrue);
    });

    test('4. Blank paper without text/content is rejected (interior texture check)', () {
      // White rectangle on desk, but NO text or interior variance
      final image = createTestCardImage(
        width: 1000,
        height: 600,
        drawText: false, // Blank monotone sheet
      );
      final detection = geometryService.detectBusinessCardPresence(image);

      expect(detection.isDetected, isFalse);
      expect(detection.hasCardContent, isFalse);
    });

    test('5. Clipping card touching frame edges is rejected with margin warning', () {
      final image = createTestCardImage(
        width: 1000,
        height: 600,
        cardRect: const Rect.fromLTWH(0, 0, 800, 500), // touches edge
      );
      final detection = geometryService.detectBusinessCardPresence(image);

      expect(detection.isDetected, isFalse);
      expect(detection.quality.isClipping, isTrue);
      expect(detection.quality.guidanceMessage, equals('Keep the full card inside the frame'));
    });

    test('6. Perspective rectification removes background and outputs rectangular card image', () async {
      final tempDir = Directory.systemTemp.path;
      final tempFile = File('$tempDir/test_card_crop_${DateTime.now().microsecondsSinceEpoch}.jpg');
      final image = createTestCardImage(width: 1200, height: 800);
      tempFile.writeAsBytesSync(img.encodeJpg(image, quality: 92));

      final result = await geometryService.correctPerspectiveIfReliable(tempFile.path);

      expect(result.wasCorrected, isTrue);
      expect(result.imagePath, isNot(equals(tempFile.path))); // Must be cropped image!
      expect(File(result.imagePath).existsSync(), isTrue);

      // Verify cropped image is smaller/focused on the card
      final croppedImg = img.decodeImage(await File(result.imagePath).readAsBytes());
      expect(croppedImg, isNotNull);
      expect(croppedImg!.width, greaterThan(200));

      // Clean up test files
      if (tempFile.existsSync()) tempFile.deleteSync();
      if (File(result.imagePath).existsSync()) File(result.imagePath).deleteSync();
    });
  });

  group('Part 3: Legal URLs & Privacy Centre Integration', () {
    test('1. LegalUrls constants match official hosted GitHub Pages specifications', () {
      expect(
        LegalUrls.termsAndConditions,
        equals('https://alphaprojectmedindia.github.io/Privacy_Policy_URL_Medindia/terms-and-conditions.html'),
      );
      expect(
        LegalUrls.privacyPolicy,
        equals('https://alphaprojectmedindia.github.io/Privacy_Policy_URL_Medindia/privacy-policy.html'),
      );
      expect(
        LegalUrls.privacyCentre,
        equals('https://alphaprojectmedindia.github.io/Privacy_Policy_URL_Medindia/'),
      );
    });

    testWidgets('2. ProfileScreen displays Privacy Centre tile with Shield icon & subtitle', (tester) async {
      final now = DateTime.now().toUtc();
      final testProfile = UserProfile(
        id: 'test_uid_123',
        userId: 'test_uid_123',
        shareId: 'drjane',
        fullName: 'Dr. Jane Smith',
        email: 'drjane@example.com',
        phoneNumber: '+919876543210',
        company: 'Medindia Health',
        jobTitle: 'Consultant',
        createdAtUtc: now,
        updatedAtUtc: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: ProfileScreen(initialProfile: testProfile),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Privacy Centre Tile exists
      final privacyCentreTile = find.byKey(const Key('profile_privacy_centre_tile'));
      expect(privacyCentreTile, findsOneWidget);
      expect(find.text('Privacy Centre'), findsOneWidget);
      expect(
        find.text('Manage your privacy and learn how your data is used.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

      // Verify Terms & Privacy Policy tile also exists
      expect(find.byKey(const Key('profile_legal_privacy_tile')), findsOneWidget);
      expect(find.text('Terms & Privacy Policy'), findsOneWidget);
    });

    testWidgets('3. BusinessCardReviewScreen displays cropped card image with Background Removed indicator', (tester) async {
      // Create temporary cropped card image
      final tempDir = Directory.systemTemp.path;
      final tempCardFile = File('$tempDir/review_test_card_${DateTime.now().microsecondsSinceEpoch}.jpg');
      final image = createTestCardImage(width: 700, height: 400);
      tempCardFile.writeAsBytesSync(img.encodeJpg(image, quality: 90));

      final testCardData = BusinessCardData(
        fullName: 'Dr. Robert Chen',
        company: 'Global Med Solutions',
        jobTitle: 'Chief Medical Officer',
        phoneNumbers: [],
        emailAddresses: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(
            cardData: testCardData,
            frontImagePath: tempCardFile.path,
          ),
        ),
      );

      expect(find.text('Cropped Card Image'), findsOneWidget);
      expect(find.text('Background Removed'), findsOneWidget);
      expect(find.byIcon(Icons.crop_rounded), findsWidgets);

      if (tempCardFile.existsSync()) tempCardFile.deleteSync();
    });

    testWidgets('4. BusinessCardCameraOverlay renders detectedCardRect outline and flash', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessCardCameraOverlay(
              guidanceMessage: 'Card detected — Hold steady...',
              isReady: true,
              isFlashing: true,
              detectedCardRect: const Rect.fromLTWH(40, 150, 320, 180),
              onCapture: () {},
              onCancel: () {},
              onToggleTorch: () {},
              onPickGallery: () {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Card Detected'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });
  });
}
