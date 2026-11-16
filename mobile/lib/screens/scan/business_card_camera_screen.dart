import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/ocr_side_result.dart';
import '../../services/card_geometry_service.dart';
import '../../services/image_quality_service.dart';
import '../../services/pending_card_capture_store.dart';
import 'widgets/business_card_camera_overlay.dart';

/// Result returned by [BusinessCardCameraScreen] upon successful capture or selection.
class BusinessCardCameraResult {
  final String imagePath;
  final CardSide side;
  final bool isFromGallery;
  final ViewfinderNormalizedRect? viewfinderRoi;
  final CaptureQualityAssessment? quality;

  const BusinessCardCameraResult({
    required this.imagePath,
    required this.side,
    this.isFromGallery = false,
    this.viewfinderRoi,
    this.quality,
  });
}

/// Full live camera viewfinder screen for capturing physical business cards.
///
/// Features:
/// - Automatic live camera preview running immediately upon screen open
/// - Zero-distortion responsive viewfinder guide frame (1.75:1 landscape)
/// - Direct capture via camera controller (`takePicture()`)
/// - Dynamic coordinate mapping from screen viewfinder to captured photo ROI
/// - Torch control (on/off)
/// - Card side switcher (Front / Back)
/// - Direct gallery fallback shortcut
/// - Clean hardware release on app backgrounding and reinitialization on resume
/// - Process-death pending capture store synchronization
class BusinessCardCameraScreen extends StatefulWidget {
  final CardSide side;
  final ImagePicker? imagePicker;
  final ImageQualityService? qualityService;
  final CardGeometryService? geometryService;
  final CameraController? controller;
  final Future<List<CameraDescription>> Function()? camerasProvider;
  final Widget Function(BuildContext context, CameraController? controller)?
      previewBuilder;

  const BusinessCardCameraScreen({
    super.key,
    this.side = CardSide.front,
    this.imagePicker,
    this.qualityService,
    this.geometryService,
    this.controller,
    this.camerasProvider,
    this.previewBuilder,
  });

  @override
  State<BusinessCardCameraScreen> createState() =>
      _BusinessCardCameraScreenState();
}

class _BusinessCardCameraScreenState extends State<BusinessCardCameraScreen>
    with WidgetsBindingObserver {
  late final ImagePicker _imagePicker;
  late final ImageQualityService _qualityService;
  late final CardGeometryService _geometryService;

  CameraController? _cameraController;
  bool _isCameraInitializing = false;
  bool _isCameraInitialized = false;
  String? _cameraErrorMessage;

  late CardSide _currentSide;
  String _guidanceMessage = 'Position card inside the frame';
  final bool _isReady = false;
  bool _isTorchOn = false;
  bool _isCapturing = false;
  ViewfinderNormalizedRect? _viewfinderRoi;
  Size? _lastScreenSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _imagePicker = widget.imagePicker ?? ImagePicker();
    _qualityService = widget.qualityService ?? const ImageQualityService();
    _geometryService = widget.geometryService ?? const CardGeometryService();
    _currentSide = widget.side;

    if (widget.controller != null && widget.controller!.value.isInitialized) {
      _cameraController = widget.controller;
      _isCameraInitialized = true;
    } else if (widget.previewBuilder != null &&
        widget.controller == null &&
        widget.camerasProvider == null) {
      _isCameraInitialized = true;
    } else {
      _initCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _disposeCurrentCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) {
        _initCamera();
      }
    }
  }

  Future<void> _disposeCurrentCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
        _isTorchOn = false;
      });
    }
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _cameraController = null;
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (_isCameraInitializing) return;

    setState(() {
      _isCameraInitializing = true;
      _cameraErrorMessage = null;
    });

    try {
      CameraController controller;
      if (widget.controller != null) {
        controller = widget.controller!;
        if (!controller.value.isInitialized) {
          await controller.initialize();
        }
      } else {
        final cameras = widget.camerasProvider != null
            ? await widget.camerasProvider!()
            : await availableCameras();

        if (cameras.isEmpty) {
          if (mounted) {
            setState(() {
              _isCameraInitializing = false;
              _cameraErrorMessage = 'No camera found on this device.';
            });
          }
          return;
        }

        final backCamera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );

        controller = CameraController(
          backCamera,
          ResolutionPreset.veryHigh,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );

        await controller.initialize();
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isCameraInitialized = true;
        _isCameraInitializing = false;
        _cameraErrorMessage = null;
        _isTorchOn = false;
        _guidanceMessage = 'Position card inside the frame';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCameraInitializing = false;
        _cameraErrorMessage = 'Unable to start camera: ${e.toString()}';
      });
    }
  }

  Future<void> _handleToggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final nextTorch = !_isTorchOn;
      await controller.setFlashMode(
        nextTorch ? FlashMode.torch : FlashMode.off,
      );
      if (mounted) {
        setState(() {
          _isTorchOn = nextTorch;
        });
      }
    } catch (_) {
      // Graceful fallback if device has no torch
    }
  }

  /// Maps viewfinder rectangle from screen coordinates to normalized camera image coordinates [0.0, 1.0].
  ViewfinderNormalizedRect _mapViewfinderRoiToImage({
    required ViewfinderNormalizedRect screenRoi,
    required Size screenSize,
    required double previewAspectRatio,
  }) {
    if (screenSize.width <= 0 ||
        screenSize.height <= 0 ||
        previewAspectRatio <= 0) {
      return screenRoi;
    }

    final sw = screenSize.width;
    final sh = screenSize.height;
    final screenAspect = sw / sh;

    double scaledW;
    double scaledH;
    double offsetX = 0.0;
    double offsetY = 0.0;

    if (screenAspect > previewAspectRatio) {
      // Screen is wider than preview portrait ratio -> match width, preview is taller
      scaledW = sw;
      scaledH = sw / previewAspectRatio;
      offsetY = (scaledH - sh) / 2.0;
    } else {
      // Screen is taller than preview portrait ratio -> match height, preview is wider
      scaledH = sh;
      scaledW = sh * previewAspectRatio;
      offsetX = (scaledW - sw) / 2.0;
    }

    // Screen frame coordinates in pixels
    final fLeft = screenRoi.left * sw;
    final fTop = screenRoi.top * sh;
    final fWidth = screenRoi.width * sw;
    final fHeight = screenRoi.height * sh;

    // Shift by offset in scaled preview space
    final imgLeft = (fLeft + offsetX) / scaledW;
    final imgTop = (fTop + offsetY) / scaledH;
    final imgWidth = fWidth / scaledW;
    final imgHeight = fHeight / scaledH;

    return ViewfinderNormalizedRect(
      left: imgLeft.clamp(0.0, 1.0),
      top: imgTop.clamp(0.0, 1.0),
      width: imgWidth.clamp(0.0, 1.0),
      height: imgHeight.clamp(0.0, 1.0),
    );
  }

  Future<void> _handleCapture() async {
    if (_isCapturing) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() {
      _isCapturing = true;
      _guidanceMessage = 'Hold steady';
    });

    try {
      // Phase 3: Camera focus & exposure stabilization where supported
      try {
        if (controller.value.focusMode != FocusMode.locked) {
          await controller.setFocusMode(FocusMode.auto);
        }
        // Brief pause for macro autofocus stabilization on business card text
        await Future.delayed(const Duration(milliseconds: 180));
      } catch (_) {
        // Fallback when driver does not support programmatic focus mode
      }

      await PendingCardCaptureStore.savePendingCapture(
        side: _currentSide,
      );

      final XFile picture = await controller.takePicture();

      await PendingCardCaptureStore.clear();

      // Compute mapped ROI for perspective correction
      ViewfinderNormalizedRect? mappedRoi = _viewfinderRoi;
      if (_viewfinderRoi != null && _lastScreenSize != null) {
        final previewSize = controller.value.previewSize;
        double previewAspect;
        if (previewSize != null) {
          previewAspect = min(previewSize.width, previewSize.height) /
              max(previewSize.width, previewSize.height);
        } else {
          final aspect = controller.value.aspectRatio;
          previewAspect = aspect > 1.0 ? 1.0 / aspect : aspect;
        }
        mappedRoi = _mapViewfinderRoiToImage(
          screenRoi: _viewfinderRoi!,
          screenSize: _lastScreenSize!,
          previewAspectRatio: previewAspect,
        );
      }

      // Pre-OCR lightweight quality assessment
      final qualityResult =
          await _qualityService.evaluateImagePath(picture.path);

      CaptureQualityAssessment? captureQuality;
      try {
        final geom = await _geometryService.correctPerspectiveIfReliable(
          picture.path,
          mappedRoi,
        );
        captureQuality = geom.quality;
      } catch (_) {}

      if (!mounted) return;

      if (qualityResult.isPoor) {
        final bool? proceed =
            await _showQualityWarningDialog(qualityResult.warnings);
        if (proceed != true) {
          setState(() {
            _isCapturing = false;
            _guidanceMessage = qualityResult.warnings.isNotEmpty
                ? qualityResult.warnings.first
                : 'Position card inside the frame';
          });
          return;
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(
        BusinessCardCameraResult(
          imagePath: picture.path,
          side: _currentSide,
          isFromGallery: false,
          viewfinderRoi: mappedRoi,
          quality: captureQuality,
        ),
      );
    } on CameraException catch (e) {
      await PendingCardCaptureStore.clear();
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _guidanceMessage = 'Camera error';
      });
      _showErrorDialog(
        'Camera Error',
        e.description ?? 'Unable to capture image.',
      );
    } catch (_) {
      await PendingCardCaptureStore.clear();
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _guidanceMessage = 'Capture failed';
      });
    }
  }

  Future<void> _handlePickGallery() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (pickedFile == null || !mounted) return;

      Navigator.of(context).pop(
        BusinessCardCameraResult(
          imagePath: pickedFile.path,
          side: _currentSide,
          isFromGallery: true,
          viewfinderRoi: _viewfinderRoi,
        ),
      );
    } catch (_) {}
  }

  void _handleToggleSide() {
    setState(() {
      _currentSide =
          _currentSide == CardSide.front ? CardSide.back : CardSide.front;
      _guidanceMessage = 'Position card inside the frame';
    });
  }

  Future<bool?> _showQualityWarningDialog(List<String> warnings) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Capture Quality Notice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This photo may be difficult to read clearly.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...warnings.map(
              (w) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 16, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(w, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Retake Photo'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Use Anyway'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveCameraPreview(
      BuildContext context, BoxConstraints constraints) {
    final controller = _cameraController!;
    if (widget.previewBuilder != null) {
      return widget.previewBuilder!(context, controller);
    }

    final previewSize = controller.value.previewSize;
    double previewAspect;
    if (previewSize != null) {
      previewAspect = min(previewSize.width, previewSize.height) /
          max(previewSize.width, previewSize.height);
    } else {
      final aspect = controller.value.aspectRatio;
      previewAspect = aspect > 1.0 ? 1.0 / aspect : aspect;
    }

    return ClipRect(
      child: SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: 100,
            height: 100 / previewAspect,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraLoadingView() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E293B),
            Color(0xFF0F172A),
            Color(0xFF020617),
          ],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
            ),
            SizedBox(height: 16),
            Text(
              'Starting camera...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraErrorView() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_rounded,
              size: 54,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            Text(
              _cameraErrorMessage ?? 'Camera unavailable',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _initCamera,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Retry Camera'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          _lastScreenSize = Size(constraints.maxWidth, constraints.maxHeight);

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Live Camera Preview (or Loading / Error state)
              if (widget.previewBuilder != null)
                widget.previewBuilder!(context, _cameraController)
              else if (_isCameraInitialized && _cameraController != null)
                _buildLiveCameraPreview(context, constraints)
              else if (_cameraErrorMessage != null)
                _buildCameraErrorView()
              else
                _buildCameraLoadingView(),

              // 2. Viewfinder Overlay
              BusinessCardCameraOverlay(
                guidanceMessage: _guidanceMessage,
                isReady: _isReady,
                sideName: _currentSide == CardSide.front ? 'FRONT' : 'BACK',
                isTorchOn: _isTorchOn,
                isCaptureEnabled:
                    (_isCameraInitialized || widget.previewBuilder != null) &&
                        !_isCapturing,
                onCapture: _handleCapture,
                onCancel: () => Navigator.of(context).pop(),
                onToggleTorch: _handleToggleTorch,
                onPickGallery: _handlePickGallery,
                onToggleSide: _handleToggleSide,
                onViewfinderRectChanged: (roi) {
                  _viewfinderRoi = roi;
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
