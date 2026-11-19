import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../models/qr/qr_content_type.dart';
import '../../models/qr/qr_scan_models.dart';
import '../../services/api_client.dart';
import '../../services/qr/qr_content_parser.dart';
import '../../services/qr/qr_recent_scans_service.dart';
import '../../services/share_service.dart';
import 'create_qr_screen.dart';
import 'qr_result_screen.dart';
import 'recent_scans_screen.dart';
import 'scanned_profile_screen.dart';

/// Universal QR Code Scanner screen.
///
/// Features high-resolution 1080p camera acquisition, QR-only ML Kit optimization,
/// real linear camera zoom (pinch-to-zoom + 1x/2x presets), continuous autofocus
/// with interactive tap-to-focus, contextual user guidance for small/dense QR codes,
/// clean session-scoped duplicate suppression, robust pause/resume lifecycle recovery,
/// and local gallery image decoding with multiple-code disambiguation.
class QrScannerScreen extends StatefulWidget {
  final ShareService? shareService;
  final QrRecentScansService? recentScansService;
  final MobileScannerController? controller;
  final ImagePicker? imagePicker;

  const QrScannerScreen({
    super.key,
    this.shareService,
    this.recentScansService,
    this.controller,
    this.imagePicker,
  });

  @override
  State<QrScannerScreen> createState() => QrScannerScreenState();
}

class QrScannerScreenState extends State<QrScannerScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _scannerController;
  late final ShareService _shareService;
  late final QrRecentScansService _recentScansService;
  late final ImagePicker _imagePicker;

  late final String _sessionId;
  bool _isScannerRunning = true;
  bool _isStartingScanner = false;
  bool _isStoppingScanner = false;
  bool _isDisposed = false;

  bool _isProcessing = false;
  String _processingMessage = 'Reading QR Code...';
  bool _isTorchOn = false;

  // Session-scoped duplicate detection protection
  String? _lastScannedPayload;
  DateTime? _lastScannedTimestamp;

  // Real Camera Zoom state (0.0 = 1x base, 1.0 = max zoom)
  double _currentZoom = 0.0;
  double _basePinchZoom = 0.0;

  // Tap-to-focus visual feedback
  Offset? _focusOffset;
  Timer? _focusIndicatorTimer;

  // Guidance hint for small / dense QR codes
  bool _showSmallQrHint = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _sessionId = 'qr_${DateTime.now().microsecondsSinceEpoch}';
    if (kDebugMode) {
      debugPrint('[QR] session created: $_sessionId');
    }

    WidgetsBinding.instance.addObserver(this);

    _shareService = widget.shareService ?? ShareService();
    _recentScansService = widget.recentScansService ?? QrRecentScansService();
    _imagePicker = widget.imagePicker ?? ImagePicker();

    // Production controller configuration:
    // 1. cameraResolution: 1080p (1920x1080) instead of the 640x480 default, providing ~7x pixels.
    // 2. formats: restricted strictly to BarcodeFormat.qrCode for maximum decoder speed & sensitivity.
    // 3. autoZoom: enabled to engage ML Kit's native zoom suggestion on supported Android devices.
    // 4. detectionSpeed: noDuplicates with immediate navigation lock.
    _scannerController = widget.controller ??
        MobileScannerController(
          detectionSpeed: DetectionSpeed.noDuplicates,
          facing: CameraFacing.back,
          torchEnabled: false,
          cameraResolution: const Size(1920, 1080),
          formats: const [BarcodeFormat.qrCode],
          autoZoom: true,
        );

    if (kDebugMode) {
      debugPrint('[QR] controller initialized');
    }

    _scannerController.addListener(_onControllerStateChanged);
    _startHintTimer();
  }

  Future<void> _startScanner() async {
    if (_isDisposed || !mounted || _isScannerRunning || _isStartingScanner) return;
    _isStartingScanner = true;
    try {
      await _scannerController.start();
      _isScannerRunning = true;
      if (kDebugMode) {
        debugPrint('[QR] scanner started');
      }
    } catch (_) {
      // Safe fallback if mocked in tests or platform uninitialized
    } finally {
      _isStartingScanner = false;
    }
  }

  Future<void> _stopScanner() async {
    if (_isDisposed || !_isScannerRunning || _isStoppingScanner) return;
    _isStoppingScanner = true;
    try {
      await _scannerController.stop();
      _isScannerRunning = false;
      if (kDebugMode) {
        debugPrint('[QR] scanner stopped');
      }
    } catch (_) {
      // Safe fallback
    } finally {
      _isStoppingScanner = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _hintTimer?.cancel();
      _focusIndicatorTimer?.cancel();
      _stopScanner();
    } else if (state == AppLifecycleState.resumed) {
      // CRITICAL B8: Only resume the scanner if this route is currently active on top
      if (mounted && !_isDisposed && ModalRoute.of(context)?.isCurrent == true) {
        _resetHintTimer();
        _startScanner();
      }
    } else if (state == AppLifecycleState.detached) {
      _stopScanner();
    }
  }

  void _onControllerStateChanged() {
    if (!mounted) return;
    final stateZoom = _scannerController.value.zoomScale;
    if ((stateZoom - _currentZoom).abs() > 0.02) {
      setState(() {
        _currentZoom = stateZoom.clamp(0.0, 1.0);
      });
    }
  }

  void _startHintTimer() {
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isProcessing) {
        setState(() {
          _showSmallQrHint = true;
        });
      }
    });
  }

  void _resetHintTimer() {
    _hintTimer?.cancel();
    if (_showSmallQrHint) {
      setState(() {
        _showSmallQrHint = false;
      });
    }
    _startHintTimer();
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _hintTimer?.cancel();
    _focusIndicatorTimer?.cancel();
    _scannerController.removeListener(_onControllerStateChanged);

    if (kDebugMode) {
      debugPrint('[QR] session closed');
    }

    // Only dispose controller if created internally
    if (widget.controller == null) {
      try {
        _scannerController.dispose();
        if (kDebugMode) {
          debugPrint('[QR] controller disposed');
        }
      } catch (_) {}
    }
    super.dispose();
  }

  /// Sets actual hardware/camera linear zoom level (clamped 0.0 to 1.0).
  Future<void> setZoom(double zoom) async {
    final clamped = zoom.clamp(0.0, 1.0);
    setState(() {
      _currentZoom = clamped;
    });
    _resetHintTimer();
    try {
      await _scannerController.setZoomScale(clamped);
    } catch (_) {
      // Safely ignore if controller is unstarted or platform does not support zoom
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _basePinchZoom = _currentZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Only zoom when user pinches with two or more fingers
    if (details.pointerCount >= 2) {
      final double delta = (details.scale - 1.0) * 0.45;
      final double newZoom = (_basePinchZoom + delta).clamp(0.0, 1.0);
      setZoom(newZoom);
    }
  }

  Future<void> _onTapUp(TapUpDetails details) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    if (size.width <= 0 || size.height <= 0) return;

    final local = details.localPosition;
    setState(() {
      _focusOffset = local;
    });

    _focusIndicatorTimer?.cancel();
    _focusIndicatorTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) {
        setState(() {
          _focusOffset = null;
        });
      }
    });

    _resetHintTimer();

    final double relativeX = (local.dx / size.width).clamp(0.0, 1.0);
    final double relativeY = (local.dy / size.height).clamp(0.0, 1.0);

    try {
      await _scannerController.setFocusPoint(Offset(relativeX, relativeY));
    } catch (_) {
      // Platform may not support focus point or camera may not be running
    }
  }

  /// Handles incoming barcode detections with session-scoped duplicate protection.
  Future<void> handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing || _isDisposed) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.trim().isEmpty) return;

    // Session-scoped duplicate suppression: ignore repeated frames of the same QR if scanned within 1.5 seconds
    if (_lastScannedPayload == rawValue &&
        _lastScannedTimestamp != null &&
        DateTime.now().difference(_lastScannedTimestamp!) < const Duration(milliseconds: 1500)) {
      return;
    }

    await _processRawValue(rawValue);
  }

  Future<void> _processRawValue(String rawValue) async {
    if (_isProcessing || _isDisposed) return;

    // Record last scanned code and timestamp for session-scoped duplicate suppression
    _lastScannedPayload = rawValue;
    _lastScannedTimestamp = DateTime.now();

    // Cancel hint timer and hide guidance
    _hintTimer?.cancel();
    _showSmallQrHint = false;

    // Lock scanner immediately to prevent duplicate frames from queuing navigation
    setState(() {
      _isProcessing = true;
      _processingMessage = 'Reading QR Code...';
    });
    if (kDebugMode) {
      debugPrint('[QR] processing=true');
    }

    try {
      final scanResult = QrContentParser.parse(rawValue);

      if (scanResult.type == QrContentType.digitalShare) {
        final shareData = scanResult.dataAs<DigitalShareQrData>();
        final sharedProfile =
            await _shareService.getSharedProfile(shareData.shareId);
        if (!mounted || _isDisposed) return;

        // Save to recent scans history
        await _recentScansService.addScan(scanResult);

        if (!mounted || _isDisposed) return;
        // Pause camera hardware before presenting destination screen
        await _stopScanner();

        if (!mounted || _isDisposed) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ScannedProfileScreen(profile: sharedProfile),
          ),
        );
      } else {
        // Standard or general QR code (Website, Wi-Fi, WhatsApp, Contact, Location, etc.)
        await _recentScansService.addScan(scanResult);

        if (!mounted || _isDisposed) return;
        // Pause camera hardware before presenting destination screen
        await _stopScanner();

        if (!mounted || _isDisposed) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => QrResultScreen(scanResult: scanResult),
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to process QR code. Please try again.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted && !_isDisposed) {
        // Debounce reset before unlocking camera frames
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted && !_isDisposed) {
          // Clear payload lock so the same QR code can be re-scanned if the user returned
          _lastScannedPayload = null;
          setState(() {
            _isProcessing = false;
          });
          if (kDebugMode) {
            debugPrint('[QR] processing=false');
          }
          // Restart camera hardware for clean re-scanning
          await _startScanner();
          _startHintTimer();
        }
      }
    }
  }

  /// Picks a high-resolution image from the gallery and decodes QR codes locally on-device.
  Future<void> scanFromGallery() async {
    if (_isProcessing || _isDisposed) return;

    final XFile? imageFile;
    try {
      imageFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not access photo library.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (imageFile == null) {
      // User cancelled gallery: ensure camera scanning remains active
      if (kDebugMode) {
        debugPrint('[QR] gallery cancelled');
      }
      if (mounted && !_isDisposed && ModalRoute.of(context)?.isCurrent == true) {
        _startScanner();
      }
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingMessage = 'Analyzing photo for QR code...';
    });
    if (kDebugMode) {
      debugPrint('[QR] processing=true');
    }

    try {
      final BarcodeCapture? capture = await _scannerController.analyzeImage(
        imageFile.path,
        formats: const [BarcodeFormat.qrCode],
      );

      final validBarcodes = capture?.barcodes
              .where((b) => b.rawValue != null && b.rawValue!.trim().isNotEmpty)
              .toList() ??
          [];

      if (validBarcodes.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isProcessing = false;
        });
        if (kDebugMode) {
          debugPrint('[QR] processing=false');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            key: Key('qr_no_code_found_snackbar'),
            content: Text('No QR code found in selected image.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
        _startHintTimer();
        await _startScanner();
        return;
      }

      if (validBarcodes.length == 1) {
        // Single QR code found: route directly through standard pipeline
        setState(() {
          _isProcessing = false;
        });
        await _processRawValue(validBarcodes.first.rawValue!);
      } else {
        // Multiple QR codes found: show safe disambiguation bottom sheet
        if (!mounted) return;
        setState(() {
          _isProcessing = false;
        });
        if (kDebugMode) {
          debugPrint('[QR] processing=false');
        }
        await _showMultipleBarcodesSheet(validBarcodes);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      if (kDebugMode) {
        debugPrint('[QR] processing=false');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('qr_analysis_error_snackbar'),
          content: Text('Unable to read QR code from this image.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      _startHintTimer();
      await _startScanner();
    }
  }

  Future<void> _showMultipleBarcodesSheet(List<Barcode> barcodes) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.qr_code_2_rounded,
                        color: Colors.white, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'Multiple QR Codes Found (${barcodes.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Select the QR code you want to open:',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: barcodes.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: Colors.white12, height: 1),
                    itemBuilder: (context, index) {
                      final barcode = barcodes[index];
                      final parsed = QrContentParser.parse(barcode.rawValue!);
                      return ListTile(
                        key: Key('multiple_qr_item_$index'),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        leading: CircleAvatar(
                          backgroundColor: Colors.white12,
                          child: Icon(
                            _getIconForType(parsed.type),
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          _getTitleForType(parsed.type),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          barcode.rawValue!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: Colors.white54),
                        onTap: () {
                          Navigator.of(bottomSheetContext).pop();
                          _processRawValue(barcode.rawValue!);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (mounted && !_isDisposed && !_isProcessing) {
      await _startScanner();
    }
  }

  IconData _getIconForType(QrContentType type) {
    switch (type) {
      case QrContentType.digitalShare:
        return Icons.badge_rounded;
      case QrContentType.url:
        return Icons.language_rounded;
      case QrContentType.whatsapp:
        return Icons.chat_rounded;
      case QrContentType.wifi:
        return Icons.wifi_rounded;
      case QrContentType.geo:
        return Icons.location_on_rounded;
      case QrContentType.phone:
        return Icons.phone_rounded;
      case QrContentType.email:
        return Icons.email_rounded;
      case QrContentType.sms:
        return Icons.sms_rounded;
      case QrContentType.vcard:
      case QrContentType.mecard:
        return Icons.contact_page_rounded;
      case QrContentType.event:
        return Icons.event_rounded;
      case QrContentType.appLink:
        return Icons.link_rounded;
      case QrContentType.text:
        return Icons.text_fields_rounded;
      case QrContentType.unknown:
        return Icons.qr_code_rounded;
    }
  }

  String _getTitleForType(QrContentType type) {
    switch (type) {
      case QrContentType.digitalShare:
        return 'Digital Share Profile';
      case QrContentType.url:
        return 'Website Link';
      case QrContentType.whatsapp:
        return 'WhatsApp Chat';
      case QrContentType.wifi:
        return 'Wi-Fi Network';
      case QrContentType.geo:
        return 'Location';
      case QrContentType.phone:
        return 'Phone Number';
      case QrContentType.email:
        return 'Email Message';
      case QrContentType.sms:
        return 'SMS Message';
      case QrContentType.vcard:
      case QrContentType.mecard:
        return 'Contact Card';
      case QrContentType.event:
        return 'Calendar Event';
      case QrContentType.appLink:
        return 'App Link';
      case QrContentType.text:
        return 'Plain Text';
      case QrContentType.unknown:
        return 'QR Code';
    }
  }

  void _openCreateQrScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CreateQrScreen(),
      ),
    );
  }

  void _openRecentScansScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecentScansScreen(storageService: _recentScansService),
      ),
    );
  }

  Widget _buildZoomButton({
    required String label,
    required bool isSelected,
    required Key key,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Universal QR Scanner'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            key: const Key('qr_recent_scans_button'),
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Recent Scans',
            onPressed: _openRecentScansScreen,
          ),
          IconButton(
            key: const Key('qr_gallery_button'),
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Scan from Gallery',
            onPressed: scanFromGallery,
          ),
          IconButton(
            key: const Key('qr_create_qr_button'),
            icon: const Icon(Icons.qr_code_2_rounded),
            tooltip: 'Create QR',
            onPressed: _openCreateQrScreen,
          ),
          IconButton(
            key: const Key('qr_toggle_torch_button'),
            icon: Icon(
              _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _isTorchOn ? Colors.amber : Colors.white,
            ),
            tooltip: 'Toggle Flash',
            onPressed: () async {
              await _scannerController.toggleTorch();
              setState(() {
                _isTorchOn = !_isTorchOn;
              });
            },
          ),
          IconButton(
            key: const Key('qr_switch_camera_button'),
            icon: const Icon(Icons.cameraswitch_rounded),
            tooltip: 'Switch Camera',
            onPressed: () => _scannerController.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Camera preview with full-frame native QR decoding
          MobileScanner(
            controller: _scannerController,
            onDetect: handleBarcode,
          ),

          // Interactive Gesture Layer: Pinch to Zoom & Tap to Focus
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onTapUp: _onTapUp,
            ),
          ),

          // Tap-to-focus animated visual ring
          if (_focusOffset != null)
            Positioned(
              left: _focusOffset!.dx - 32,
              top: _focusOffset!.dy - 32,
              child: IgnorePointer(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.amber, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Scan Frame Viewfinder Overlay (Decorative; does not crop camera sensor pixels)
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white,
                    width: 2.5,
                  ),
                ),
              ),
            ),
          ),

          // Top Subtitle instruction
          Positioned(
            top: 24,
            left: 24,
            right: 24,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Point your camera at any QR code',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Supports links, Wi-Fi, contacts, WhatsApp and more.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Subtle Contextual Guidance Hint for Small or Dense QR Codes
          if (_showSmallQrHint && !_isProcessing)
            Positioned(
              top: MediaQuery.sizeOf(context).height * 0.5 + 145,
              child: IgnorePointer(
                child: Container(
                  key: const Key('qr_small_code_hint'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_in_rounded,
                          color: Colors.amber, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Small QR? Move closer or pinch to zoom',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom Floating Controls: 1x / 2x Zoom Controls + Scan from Gallery
          Positioned(
            bottom: 36,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildZoomButton(
                    label: '1x',
                    isSelected: _currentZoom < 0.15,
                    key: const Key('qr_zoom_1x_button'),
                    onTap: () => setZoom(0.0),
                  ),
                  const SizedBox(width: 6),
                  _buildZoomButton(
                    label: '2x',
                    isSelected: _currentZoom >= 0.15,
                    key: const Key('qr_zoom_2x_button'),
                    onTap: () => setZoom(0.25),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 1,
                    height: 20,
                    color: Colors.white24,
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    key: const Key('qr_gallery_bottom_button'),
                    icon: const Icon(Icons.photo_library_rounded,
                        color: Colors.white, size: 20),
                    tooltip: 'Scan from Gallery',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: scanFromGallery,
                  ),
                ],
              ),
            ),
          ),

          // Medindia4u.com branding footer
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Powered by Medindia4u.com',
                key: const Key('medindia_branding_footer_text'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.6),
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),

          // Loading indicator when processing scan or gallery image
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.65),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      _processingMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
