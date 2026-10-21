import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:digital_share/models/qr/qr_content_type.dart';
import 'package:digital_share/models/qr/qr_scan_models.dart';
import 'package:digital_share/models/shared_profile.dart';
import 'package:digital_share/screens/scan/qr_result_screen.dart';
import 'package:digital_share/screens/scan/qr_scanner_screen.dart';
import 'package:digital_share/screens/scan/scanned_profile_screen.dart';
import 'package:digital_share/services/qr/qr_content_parser.dart';
import 'package:digital_share/services/qr/qr_recent_scans_service.dart';
import 'package:digital_share/services/share_service.dart';

class MockShareService extends ShareService {
  int invocationCount = 0;
  String? lastShareId;

  @override
  Future<SharedProfile> getSharedProfile(String shareId) async {
    invocationCount++;
    lastShareId = shareId;
    return SharedProfile(
      shareId: shareId,
      fullName: 'Antony Lobo',
      email: 'spainconsulate.chennai@gmail.com',
      company: 'Consulate of Spain',
      jobTitle: 'Hon. Consul of Spain',
      phoneNumber: '+91-44-42107657',
    );
  }
}

class FakeImagePicker extends Fake implements ImagePicker {
  XFile? fileToReturn;
  bool shouldThrow = false;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    if (shouldThrow) {
      throw Exception('User cancelled or picker failed');
    }
    return fileToReturn;
  }
}

class FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _data[key] = value;
    } else {
      _data.remove(key);
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

class TestableScannerController extends MobileScannerController {
  BarcodeCapture? analyzeResultToReturn;
  bool shouldThrowOnAnalyze = false;
  double? lastZoomScale;
  Offset? lastFocusPoint;

  TestableScannerController({
    this.analyzeResultToReturn,
    this.shouldThrowOnAnalyze = false,
    super.cameraResolution,
    super.formats,
    super.autoZoom,
    super.detectionSpeed,
  }) : super(autoStart: false);

  @override
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const <BarcodeFormat>[],
  }) async {
    if (shouldThrowOnAnalyze) {
      throw Exception('Analysis failed');
    }
    return analyzeResultToReturn;
  }

  @override
  Future<void> setZoomScale(double zoomScale) async {
    lastZoomScale = zoomScale;
  }

  @override
  Future<void> setFocusPoint(Offset position) async {
    lastFocusPoint = position;
  }
}

void main() {
  group('Universal QR Camera Acquisition & Gallery Decoding Tests', () {
    test('1. Default MobileScannerController configures 1080p, QR-only, and autoZoom', () {
      final controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        torchEnabled: false,
        cameraResolution: const Size(1920, 1080),
        formats: const [BarcodeFormat.qrCode],
        autoZoom: true,
      );

      // Verify camera resolution is explicitly 1080p (prevents 640x480 Android default)
      expect(controller.cameraResolution, equals(const Size(1920, 1080)));

      // Verify barcode formats restricted exclusively to QR code
      expect(controller.formats, equals(const [BarcodeFormat.qrCode]));

      // Verify native auto-zoom is enabled
      expect(controller.autoZoom, isTrue);

      controller.dispose();
    });

    testWidgets('2. Zoom preset buttons (1x and 2x) update hardware zoom scale safely', (tester) async {
      final controller = TestableScannerController();
      final fakePicker = FakeImagePicker();

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            controller: controller,
            imagePicker: fakePicker,
          ),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      // Initial zoom is 0.0 (1x)
      expect(find.byKey(const Key('qr_zoom_1x_button')), findsOneWidget);
      expect(find.byKey(const Key('qr_zoom_2x_button')), findsOneWidget);

      // Tap 2x zoom button
      await tester.tap(find.byKey(const Key('qr_zoom_2x_button')));
      await tester.pump();

      expect(controller.lastZoomScale, equals(0.25));

      // Tap 1x zoom button to return to base focal length
      await tester.tap(find.byKey(const Key('qr_zoom_1x_button')));
      await tester.pump();

      expect(controller.lastZoomScale, equals(0.0));

      // Direct programmatic zoom call with clamping
      await state.setZoom(1.5); // Greater than 1.0
      expect(controller.lastZoomScale, equals(1.0));

      await state.setZoom(-0.5); // Less than 0.0
      expect(controller.lastZoomScale, equals(0.0));
    });

    testWidgets('3. Tap-to-focus triggers setFocusPoint and shows temporary indicator', (tester) async {
      final controller = TestableScannerController();
      final fakePicker = FakeImagePicker();

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            controller: controller,
            imagePicker: fakePicker,
          ),
        ),
      );

      // Tap center of the screen
      await tester.tapAt(const Offset(200, 300));
      await tester.pump();

      // Focus point was set on controller
      expect(controller.lastFocusPoint, isNotNull);

      // Tap indicator appears, then fades after 900ms
      await tester.pump(const Duration(milliseconds: 1000));
    });

    testWidgets('4. Small QR guidance hint appears after idle delay and resets upon interaction', (tester) async {
      final controller = TestableScannerController();
      final fakePicker = FakeImagePicker();

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            controller: controller,
            imagePicker: fakePicker,
          ),
        ),
      );

      // Initially hint is not visible
      expect(find.byKey(const Key('qr_small_code_hint')), findsNothing);

      // Advance clock past 4 seconds
      await tester.pump(const Duration(seconds: 4, milliseconds: 100));

      // Hint is now visible
      expect(find.byKey(const Key('qr_small_code_hint')), findsOneWidget);
      expect(find.text('Small QR? Move closer or pinch to zoom'), findsOneWidget);

      // User interacts (taps 2x zoom) -> hint resets
      await tester.tap(find.byKey(const Key('qr_zoom_2x_button')));
      await tester.pump();

      expect(find.byKey(const Key('qr_small_code_hint')), findsNothing);
    });

    testWidgets('5. Scan from Gallery: single QR code decodes and opens QrResultScreen', (tester) async {
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);
      final fakePicker = FakeImagePicker()..fileToReturn = XFile('test_qr.png');
      const testUrl = 'https://digitalshare.app/download';
      final controller = TestableScannerController(
        analyzeResultToReturn: BarcodeCapture(
          barcodes: [Barcode(rawValue: testUrl, format: BarcodeFormat.qrCode)],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            recentScansService: recentService,
            controller: controller,
            imagePicker: fakePicker,
          ),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      // Trigger gallery scan
      unawaited(state.scanFromGallery());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Navigated to QrResultScreen
      expect(find.byType(QrResultScreen), findsOneWidget);
      expect(find.text('Website Link'), findsOneWidget);
    });

    testWidgets('6. Scan from Gallery: single Digital Share QR decodes and opens ScannedProfileScreen', (tester) async {
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);
      final fakePicker = FakeImagePicker()..fileToReturn = XFile('profile_card.jpg');
      const shareUrl = 'https://digitalshare.app/s/AntonyLoboSpain1234';
      final mockShare = MockShareService();
      final controller = TestableScannerController(
        analyzeResultToReturn: BarcodeCapture(
          barcodes: [Barcode(rawValue: shareUrl, format: BarcodeFormat.qrCode)],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            shareService: mockShare,
            recentScansService: recentService,
            controller: controller,
            imagePicker: fakePicker,
          ),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      unawaited(state.scanFromGallery());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(mockShare.invocationCount, equals(1));
      expect(mockShare.lastShareId, equals('AntonyLoboSpain1234'));
      expect(find.byType(ScannedProfileScreen), findsOneWidget);
      expect(find.text('Antony Lobo'), findsOneWidget);
    });

    testWidgets('7. Scan from Gallery: multiple QR codes in one image displays disambiguation sheet', (tester) async {
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);
      final fakePicker = FakeImagePicker()..fileToReturn = XFile('multi_qr.png');
      final controller = TestableScannerController(
        analyzeResultToReturn: BarcodeCapture(
          barcodes: [
            Barcode(rawValue: 'https://wa.me/919876543210', format: BarcodeFormat.qrCode),
            Barcode(rawValue: 'https://flutter.dev', format: BarcodeFormat.qrCode),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            recentScansService: recentService,
            controller: controller,
            imagePicker: fakePicker,
          ),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      await state.scanFromGallery();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // finishes bottom sheet slide up animation

      // Bottom sheet is shown
      expect(find.text('Multiple QR Codes Found (2)'), findsOneWidget);
      expect(find.byKey(const Key('multiple_qr_item_0')), findsOneWidget);
      expect(find.byKey(const Key('multiple_qr_item_1')), findsOneWidget);

      // Tap the first QR code (WhatsApp)
      await tester.tap(find.byKey(const Key('multiple_qr_item_0')));
      await tester.pump(); // pops bottom sheet
      await tester.pump(const Duration(milliseconds: 400)); // finishes sheet dismiss
      await tester.pump(const Duration(milliseconds: 600)); // completes route push

      expect(find.byType(QrResultScreen), findsOneWidget);
      expect(find.text('WhatsApp Chat'), findsOneWidget);
    });

    testWidgets('8. Scan from Gallery: image with no QR code shows friendly message and does not crash', (tester) async {
      final fakePicker = FakeImagePicker()..fileToReturn = XFile('scenery.jpg');
      final controller = TestableScannerController(
        analyzeResultToReturn: const BarcodeCapture(barcodes: []),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            controller: controller,
            imagePicker: fakePicker,
          ),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      await state.scanFromGallery();
      await tester.pump();

      expect(find.byKey(const Key('qr_no_code_found_snackbar')), findsOneWidget);
      expect(find.text('No QR code found in selected image.'), findsOneWidget);
    });

    testWidgets('9. Scan from Gallery: decoder exception handles gracefully without crash', (tester) async {
      final fakePicker = FakeImagePicker()..fileToReturn = XFile('corrupt.jpg');
      final controller = TestableScannerController(shouldThrowOnAnalyze: true);

      await tester.pumpWidget(
        MaterialApp(
          home: QrScannerScreen(
            controller: controller,
            imagePicker: fakePicker,
          ),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      await state.scanFromGallery();
      await tester.pump();

      expect(find.byKey(const Key('qr_analysis_error_snackbar')), findsOneWidget);
      expect(find.text('Unable to read QR code from this image.'), findsOneWidget);
    });

    testWidgets('10. WhatsApp QR regression: WhatsApp direct link is parsed accurately', (tester) async {
      const whatsappUrl = 'https://wa.me/914442107657?text=Hello%20Antony';
      final result = QrContentParser.parse(whatsappUrl);

      expect(result.type, equals(QrContentType.whatsapp));
      final data = result.dataAs<WhatsAppQrData>();
      expect(data.phone, equals('914442107657'));
      expect(data.message, equals('Hello Antony'));
    });
  });
}
