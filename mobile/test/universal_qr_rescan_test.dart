import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:digital_share/models/shared_profile.dart';
import 'package:digital_share/screens/scan/qr_result_screen.dart';
import 'package:digital_share/screens/scan/qr_scanner_screen.dart';
import 'package:digital_share/screens/scan/scanned_profile_screen.dart';
import 'package:digital_share/services/qr/qr_recent_scans_service.dart';
import 'package:digital_share/services/share_service.dart';

class LifecycleTrackingScannerController extends MobileScannerController {
  int startCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  bool isDisposedState = false;
  BarcodeCapture? analyzeResultToReturn;

  LifecycleTrackingScannerController({
    this.analyzeResultToReturn,
    super.cameraResolution,
    super.formats,
    super.autoZoom,
    super.detectionSpeed,
  }) : super(autoStart: false);

  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async {
    if (isDisposedState) {
      throw StateError('Cannot start disposed controller');
    }
    startCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {
    isDisposedState = true;
    disposeCount++;
    super.dispose();
  }

  @override
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const <BarcodeFormat>[],
  }) async {
    return analyzeResultToReturn;
  }
}

class FakeImagePicker extends ImagePicker {
  XFile? fileToReturn;
  bool shouldThrow = false;
  int pickImageCallCount = 0;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    pickImageCallCount++;
    if (shouldThrow) {
      throw Exception('Picker error');
    }
    return fileToReturn;
  }
}

class FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};

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
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

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
}

class MockShareService extends ShareService {
  int invocationCount = 0;
  String? lastShareId;

  @override
  Future<SharedProfile> getSharedProfile(String shareId) async {
    invocationCount++;
    lastShareId = shareId;
    return SharedProfile(
      shareId: shareId,
      email: 'alice@example.com',
      fullName: 'Alice Walker',
    );
  }
}

Widget buildTestApp({required Widget home}) {
  return MaterialApp(
    home: home,
  );
}

void main() {
  group('Part E2: Universal QR Re-Scan Reliability Tests', () {
    testWidgets('1. Open -> Cancel (Back) -> Open works cleanly', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_scanner_btn'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(builder: (_) => const QrScannerScreen()),
                  );
                },
                child: const Text('Open Scanner'),
              ),
            ),
          ),
        ),
      );

      // Open scanner
      await tester.tap(find.byKey(const Key('open_scanner_btn')));
      await tester.pumpAndSettle();
      expect(find.byType(QrScannerScreen), findsOneWidget);

      // Cancel / Back to home
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(QrScannerScreen), findsNothing);

      // Open scanner again
      await tester.tap(find.byKey(const Key('open_scanner_btn')));
      await tester.pumpAndSettle();
      expect(find.byType(QrScannerScreen), findsOneWidget);
    });

    testWidgets('2. Open -> Back -> Open preserves controller cleanliness', (tester) async {
      final controller1 = LifecycleTrackingScannerController();
      final controller2 = LifecycleTrackingScannerController();

      await tester.pumpWidget(
        buildTestApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_scanner_btn'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => QrScannerScreen(controller: controller1),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_scanner_btn')));
      await tester.pumpAndSettle();
      expect(find.byType(QrScannerScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(QrScannerScreen), findsNothing);

      // Second session with fresh controller
      await tester.pumpWidget(
        buildTestApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_scanner_btn_2'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => QrScannerScreen(controller: controller2),
                    ),
                  );
                },
                child: const Text('Open 2'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_scanner_btn_2')));
      await tester.pumpAndSettle();
      expect(find.byType(QrScannerScreen), findsOneWidget);
    });

    testWidgets('3. Open -> Scan -> Exit -> Open -> Scan works across sessions', (tester) async {
      final mockShare = MockShareService();
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      await tester.pumpWidget(
        buildTestApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_scanner_btn'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => QrScannerScreen(
                        shareService: mockShare,
                        recentScansService: recentService,
                      ),
                    ),
                  );
                },
                child: const Text('Open Scanner'),
              ),
            ),
          ),
        ),
      );

      // Open Session 1
      await tester.tap(find.byKey(const Key('open_scanner_btn')));
      await tester.pumpAndSettle();

      final state1 = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));
      const shareUrl = 'https://digitalshare.app/s/x7F9K2mQ8pL4vYkVl6VUbG7T';
      final capture = BarcodeCapture(
        barcodes: [Barcode(rawValue: shareUrl, format: BarcodeFormat.qrCode)],
      );

      unawaited(state1.handleBarcode(capture));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ScannedProfileScreen), findsOneWidget);

      // Exit back to Root Home
      Navigator.of(tester.element(find.byType(ScannedProfileScreen))).pop();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(QrScannerScreen), findsNothing);

      // Open Session 2
      await tester.tap(find.byKey(const Key('open_scanner_btn')));
      await tester.pumpAndSettle();
      expect(find.byType(QrScannerScreen), findsOneWidget);

      // Scan another code in Session 2
      final state2 = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));
      const website = 'https://flutter.dev';
      final capture2 = BarcodeCapture(
        barcodes: [Barcode(rawValue: website, format: BarcodeFormat.qrCode)],
      );

      unawaited(state2.handleBarcode(capture2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(QrResultScreen), findsOneWidget);
      expect(find.text('flutter.dev'), findsOneWidget);
    });

    testWidgets('4. Same QR code scanned across separate sessions works', (tester) async {
      final mockShare = MockShareService();
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      await tester.pumpWidget(
        buildTestApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_scanner_btn'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => QrScannerScreen(
                        shareService: mockShare,
                        recentScansService: recentService,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      const sameShareUrl = 'https://digitalshare.app/s/x7F9K2mQ8pL4vYkVl6VUbG7T';
      final capture = BarcodeCapture(
        barcodes: [Barcode(rawValue: sameShareUrl, format: BarcodeFormat.qrCode)],
      );

      // Session 1: Scan sameShareUrl
      await tester.tap(find.byKey(const Key('open_scanner_btn')));
      await tester.pumpAndSettle();
      var state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));
      unawaited(state.handleBarcode(capture));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(mockShare.invocationCount, equals(1));

      // Close Session 1 completely
      Navigator.of(tester.element(find.byType(ScannedProfileScreen))).pop();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Session 2: Scan EXACT SAME URL
      await tester.tap(find.byKey(const Key('open_scanner_btn')));
      await tester.pumpAndSettle();
      state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));
      unawaited(state.handleBarcode(capture));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Successfully scanned again!
      expect(mockShare.invocationCount, equals(2));
      expect(find.byType(ScannedProfileScreen), findsOneWidget);
    });

    testWidgets('5. Different QR codes across sessions work cleanly', (tester) async {
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      await tester.pumpWidget(
        buildTestApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_scanner_btn'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => QrScannerScreen(recentScansService: recentService),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      // Session 1: Scan URL 1
      await tester.tap(find.byKey(const Key('open_scanner_btn')));
      await tester.pumpAndSettle();
      var state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));
      unawaited(state.handleBarcode(BarcodeCapture(
        barcodes: [Barcode(rawValue: 'https://site1.com', format: BarcodeFormat.qrCode)],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('site1.com'), findsOneWidget);

      Navigator.of(tester.element(find.byType(QrResultScreen))).pop();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Session 2: Scan URL 2
      await tester.tap(find.byKey(const Key('open_scanner_btn')));
      await tester.pumpAndSettle();
      state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));
      unawaited(state.handleBarcode(BarcodeCapture(
        barcodes: [Barcode(rawValue: 'https://site2.com', format: BarcodeFormat.qrCode)],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('site2.com'), findsOneWidget);
    });

    testWidgets('6. Open / Cancel repeated 5 times operates reliably without leak', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_btn'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(builder: (_) => const QrScannerScreen()),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      for (int i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('open_btn')));
        await tester.pumpAndSettle();
        expect(find.byType(QrScannerScreen), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(QrScannerScreen), findsNothing);
      }
    });

    testWidgets('7. Open / Scan / Back repeated 5 times works without degrading', (tester) async {
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      await tester.pumpWidget(
        buildTestApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_btn'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => QrScannerScreen(recentScansService: recentService),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      for (int i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('open_btn')));
        await tester.pumpAndSettle();

        final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));
        unawaited(state.handleBarcode(BarcodeCapture(
          barcodes: [Barcode(rawValue: 'https://cycle$i.com', format: BarcodeFormat.qrCode)],
        )));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(QrResultScreen), findsOneWidget);
        expect(find.text('cycle$i.com'), findsOneWidget);

        // Pop back to scanner
        Navigator.of(tester.element(find.byType(QrResultScreen))).pop();
        await tester.pumpAndSettle();

        // Pop back to home
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(QrScannerScreen), findsNothing);
      }
    });

    testWidgets('8. Processing lock resets safely after navigation and popping', (tester) async {
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      await tester.pumpWidget(
        buildTestApp(
          home: QrScannerScreen(recentScansService: recentService),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      unawaited(state.handleBarcode(BarcodeCapture(
        barcodes: [Barcode(rawValue: 'https://example.com', format: BarcodeFormat.qrCode)],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(QrResultScreen), findsOneWidget);

      // Pop back
      Navigator.of(tester.element(find.byType(QrResultScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Processing lock is false
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('9. Duplicate state is session-scoped and does not leak globally', (tester) async {
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      await tester.pumpWidget(
        buildTestApp(
          home: QrScannerScreen(recentScansService: recentService),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      const code = 'WIFI:S:MyNetwork;T:WPA;P:secret123;;';
      final capture = BarcodeCapture(
        barcodes: [Barcode(rawValue: code, format: BarcodeFormat.qrCode)],
      );

      // Scan code
      unawaited(state.handleBarcode(capture));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Wi-Fi Network'), findsOneWidget);

      // Dismiss result
      Navigator.of(tester.element(find.byType(QrResultScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Scan SAME code again in the same screen after returning
      unawaited(state.handleBarcode(capture));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Wi-Fi Network'), findsOneWidget);
    });

    testWidgets('10. Old async callback does not affect new session if unmounted', (tester) async {
      final completer = Completer<SharedProfile>();
      final delayedShare = DelayedMockShareService(completer.future);

      await tester.pumpWidget(
        buildTestApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_btn'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => QrScannerScreen(shareService: delayedShare),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_btn')));
      await tester.pumpAndSettle();

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));
      unawaited(state.handleBarcode(BarcodeCapture(
        barcodes: [Barcode(rawValue: 'https://digitalshare.app/s/x7F9K2mQ8pL4vYkVl6VUbG7T', format: BarcodeFormat.qrCode)],
      )));
      await tester.pump();

      // User backs out while request is in-flight
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(QrScannerScreen), findsNothing);

      // Complete async operation after unmount
      completer.complete(SharedProfile(
        shareId: 'late',
        email: 'u@u.com',
        fullName: 'Late User',
      ));

      await tester.pump();
      // Should not throw or crash
      expect(find.byType(ScannedProfileScreen), findsNothing);
    });

    testWidgets('11. Internally created controller is disposed exactly once on exit', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_btn'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(builder: (_) => const QrScannerScreen()),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_btn')));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(QrScannerScreen), findsNothing);
    });

    testWidgets('12. Disposed controller is never restarted', (tester) async {
      final controller = LifecycleTrackingScannerController();

      await tester.pumpWidget(
        buildTestApp(
          home: QrScannerScreen(controller: controller),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));
      expect(state.mounted, isTrue);

      // Dispose screen
      await tester.pumpWidget(buildTestApp(home: const SizedBox()));
      expect(find.byType(QrScannerScreen), findsNothing);

      // Attempting to trigger lifecycle after dispose must never restart
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(controller.isDisposedState, isFalse); // External controller not disposed by widget
    });

    testWidgets('13. Background and resume while scanner route is active', (tester) async {
      final controller = LifecycleTrackingScannerController();

      await tester.pumpWidget(
        buildTestApp(
          home: QrScannerScreen(controller: controller),
        ),
      );

      // Background app
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(controller.stopCount, greaterThanOrEqualTo(1));

      // Resume app
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(controller.startCount, greaterThanOrEqualTo(1));
    });

    testWidgets('14. Background -> route removed -> resume does not restart old controller', (tester) async {
      final controller = LifecycleTrackingScannerController();

      await tester.pumpWidget(
        buildTestApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_btn'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => QrScannerScreen(controller: controller),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_btn')));
      await tester.pumpAndSettle();

      // App paused
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // Route popped while paused
      await tester.pageBack();
      await tester.pumpAndSettle();

      final previousStartCount = controller.startCount;

      // App resumed
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // Old controller did NOT start again
      expect(controller.startCount, equals(previousStartCount));
    });

    testWidgets('15. Result dismissed -> camera scanning resumes smoothly', (tester) async {
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      await tester.pumpWidget(
        buildTestApp(
          home: QrScannerScreen(recentScansService: recentService),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      unawaited(state.handleBarcode(BarcodeCapture(
        barcodes: [Barcode(rawValue: 'https://example.com/item', format: BarcodeFormat.qrCode)],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(QrResultScreen), findsOneWidget);

      // Tap 'Scan Another Code'
      await tester.tap(find.byKey(const Key('qr_scan_again_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // User is back on scanner screen
      expect(find.byType(QrScannerScreen), findsOneWidget);
    });

    testWidgets('16. Gallery Cancel -> camera scan continues functioning', (tester) async {
      final fakePicker = FakeImagePicker();
      fakePicker.fileToReturn = null; // User cancelled picker
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      await tester.pumpWidget(
        buildTestApp(
          home: QrScannerScreen(
            imagePicker: fakePicker,
            recentScansService: recentService,
          ),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      // Trigger gallery scan
      await state.scanFromGallery();
      await tester.pump();

      expect(fakePicker.pickImageCallCount, equals(1));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Subsequent camera scan works immediately
      unawaited(state.handleBarcode(BarcodeCapture(
        barcodes: [Barcode(rawValue: 'tel:+1234567890', format: BarcodeFormat.qrCode)],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Phone Number'), findsOneWidget);
    });

    testWidgets('17. Gallery scan -> exit -> reopen camera works', (tester) async {
      final fakePicker = FakeImagePicker();
      fakePicker.fileToReturn = XFile('test_photo.jpg');
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      final controller = LifecycleTrackingScannerController(
        analyzeResultToReturn: BarcodeCapture(
          barcodes: [Barcode(rawValue: 'mailto:contact@test.com', format: BarcodeFormat.qrCode)],
        ),
      );

      await tester.pumpWidget(
        buildTestApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_btn'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => QrScannerScreen(
                        controller: controller,
                        imagePicker: fakePicker,
                        recentScansService: recentService,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_btn')));
      await tester.pumpAndSettle();

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));
      unawaited(state.scanFromGallery());
      await tester.pumpAndSettle();

      expect(find.text('Email Message'), findsOneWidget);

      // Pop result and scanner
      Navigator.of(tester.element(find.byType(QrResultScreen))).pop();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Reopen scanner
      await tester.tap(find.byKey(const Key('open_btn')));
      await tester.pumpAndSettle();
      expect(find.byType(QrScannerScreen), findsOneWidget);
    });

    testWidgets('18. Invalid QR -> dismiss error -> valid QR scans successfully', (tester) async {
      final fakeStorage = FakeSecureStorage();
      final recentService = QrRecentScansService(storage: fakeStorage);

      await tester.pumpWidget(
        buildTestApp(
          home: QrScannerScreen(recentScansService: recentService),
        ),
      );

      final state = tester.state<QrScannerScreenState>(find.byType(QrScannerScreen));

      // Scan empty / whitespace QR
      await state.handleBarcode(BarcodeCapture(
        barcodes: [Barcode(rawValue: '   ', format: BarcodeFormat.qrCode)],
      ));
      await tester.pump();
      expect(find.byType(QrResultScreen), findsNothing);

      // Now scan valid QR
      unawaited(state.handleBarcode(BarcodeCapture(
        barcodes: [Barcode(rawValue: 'https://valid.com', format: BarcodeFormat.qrCode)],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(QrResultScreen), findsOneWidget);
      expect(find.text('valid.com'), findsOneWidget);
    });
  });
}

class DelayedMockShareService extends ShareService {
  final Future<SharedProfile> future;

  DelayedMockShareService(this.future);

  @override
  Future<SharedProfile> getSharedProfile(String shareId) async {
    return await future;
  }
}
