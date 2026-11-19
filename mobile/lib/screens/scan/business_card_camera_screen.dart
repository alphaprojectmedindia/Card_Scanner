import 'dart:async';
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
  final bool enableAutoCapture;
  final int requiredStableFrames;

  const BusinessCardCameraScreen({
    super.key,
    this.side = CardSide.front,
    this.imagePicker,
    this.qualityService,
    this.geometryService,
    this.controller,
    this.camerasProvider,
    this.previewBuilder,
    this.enableAutoCapture = true,
    this.requiredStableFrames = 10,
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
  String _guidanceMessage = 'Position your business card inside the camera view';
  late bool _isAutoCaptureEnabled;
  late int _requiredStableFrames;
  CardDetectionState _detectionState = CardDetectionState.searching;
  int _diagnosticFramesReceived = 0;
  int _diagnosticFramesProcessed = 0;
  int _diagnosticQuadsDetected = 0;
  double _lastCardArea = 0.0;
  bool _isCardDetected = false;
  int _stableFrameCount = 0;
  DateTime? _firstStableTime;
  double _autoCaptureProgress = 0.0;
  Rect? _detectedCardRect;
  List<Offset>? _detectedPolygon;
  List<Offset>? _lastNormalizedPolygon;
  BusinessCardDetectionResult? _lastValidDetection;
  List<CameraDescription> _availableCameras = [];
  int _selectedCameraIndex = 0;
  Timer? _autoDetectionTimer;
  bool _isTorchOn = false;
  bool _isCapturing = false;
  ViewfinderNormalizedRect? _viewfinderRoi;
  Size? _lastScreenSize;
  bool _isFlashing = false;
  bool _isProcessingFrameLock = false;
  bool _isStreamingFrames = false;
  DateTime _lastFrameAnalyzedTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _imagePicker = widget.imagePicker ?? ImagePicker();
    _qualityService = widget.qualityService ?? const ImageQualityService();
    _geometryService = widget.geometryService ?? const CardGeometryService();
    _currentSide = widget.side;
    _isAutoCaptureEnabled = widget.enableAutoCapture;
    _requiredStableFrames = widget.requiredStableFrames;

    if (widget.controller != null && widget.controller!.value.isInitialized) {
      _cameraController = widget.controller;
      _isCameraInitialized = true;
      _startAutoDetectionLoop();
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
    _stopAutoDetectionTimer();
    await _safeStopImageStream();
    final controller = _cameraController;
    _cameraController = null;
    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
        _isTorchOn = false;
        _isCardDetected = false;
        _detectedCardRect = null;
        _detectedPolygon = null;
        _lastNormalizedPolygon = null;
        _lastCardArea = 0.0;
        _stableFrameCount = 0;
        _firstStableTime = null;
        _autoCaptureProgress = 0.0;
        _detectionState = CardDetectionState.searching;
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
    _stopAutoDetectionTimer();
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

        _availableCameras = cameras;
        final backIdx =
            cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        if (_selectedCameraIndex == 0 && backIdx >= 0) {
          _selectedCameraIndex = backIdx;
        } else if (_selectedCameraIndex >= cameras.length) {
          _selectedCameraIndex = 0;
        }

        final selectedCamera = cameras[_selectedCameraIndex];

        controller = CameraController(
          selectedCamera,
          ResolutionPreset.veryHigh,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
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
        _guidanceMessage = 'Position your business card inside the camera view';
      });
      _startAutoDetectionLoop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCameraInitializing = false;
        _cameraErrorMessage = 'Unable to start camera: ${e.toString()}';
      });
    }
  }

  /// Cycles between available camera lenses (e.g. back wide vs back telephoto vs front)
  Future<void> _handleSwitchCamera() async {
    if (_availableCameras.length <= 1 || _isCapturing) return;
    _stopAutoDetectionTimer();
    await _safeStopImageStream();

    final nextIndex = (_selectedCameraIndex + 1) % _availableCameras.length;
    final nextCam = _availableCameras[nextIndex];

    final oldController = _cameraController;
    _cameraController = null;
    if (mounted) {
      setState(() {
        _selectedCameraIndex = nextIndex;
        _isCameraInitialized = false;
        _isCardDetected = false;
        _detectedPolygon = null;
        _detectedCardRect = null;
        _lastNormalizedPolygon = null;
        _lastCardArea = 0.0;
        _stableFrameCount = 0;
        _firstStableTime = null;
        _autoCaptureProgress = 0.0;
        _detectionState = CardDetectionState.searching;
        _isCameraInitializing = true;
      });
    }

    if (oldController != null) {
      try {
        await oldController.dispose();
      } catch (_) {}
    }

    try {
      final newController = CameraController(
        nextCam,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await newController.initialize();
      if (!mounted) {
        await newController.dispose();
        return;
      }
      setState(() {
        _cameraController = newController;
        _isCameraInitialized = true;
        _isCameraInitializing = false;
        _isTorchOn = false;
        _guidanceMessage = 'Position your business card inside the camera view';
      });
      _startAutoDetectionLoop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
          _cameraErrorMessage = 'Unable to switch camera: $e';
        });
      }
    }
  }

  void _startAutoDetectionLoop() {
    _stopAutoDetectionTimer();
    if (!_isAutoCaptureEnabled) return;

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    try {
      if (!_isStreamingFrames) {
        controller.startImageStream(_handleCameraImageFrame).then((_) {
          _isStreamingFrames = true;
        }).catchError((err) {
          debugPrint('[CameraScreen] startImageStream not supported: ');
          _isStreamingFrames = false;
        });
      }
    } catch (e) {
      debugPrint('[CameraScreen] Frame streaming exception: ');
      _isStreamingFrames = false;
    }
  }

  Future<void> _safeStopImageStream() async {
    final controller = _cameraController;
    if (controller != null && _isStreamingFrames) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
      _isStreamingFrames = false;
    }
  }

  void _stopAutoDetectionTimer() {
    _autoDetectionTimer?.cancel();
    _autoDetectionTimer = null;
  }

  void _handleCameraImageFrame(CameraImage image) {
    if (!mounted || !_isAutoCaptureEnabled || _isCapturing || _isProcessingFrameLock) {
      return;
    }

    _diagnosticFramesReceived++;

    final now = DateTime.now();
    if (now.difference(_lastFrameAnalyzedTime).inMilliseconds < 75) {
      return;
    }

    _lastFrameAnalyzedTime = now;
    _isProcessingFrameLock = true;

    Future.microtask(() {
      try {
        if (!mounted || _isCapturing) return;
        _diagnosticFramesProcessed++;

        if (image.planes.isEmpty || image.planes[0].bytes.isEmpty) {
          return;
        }

        final lumaPlane = image.planes[0];
        final orientation = _cameraController?.description.sensorOrientation ?? 0;
        final isFront = _cameraController?.description.lensDirection == CameraLensDirection.front;

        final detection = _geometryService.detectCardInLumaBytes(
          lumaBytes: lumaPlane.bytes,
          width: image.width,
          height: image.height,
          bytesPerRow: lumaPlane.bytesPerRow,
          bytesPerPixel: lumaPlane.bytesPerPixel ?? 1,
          sensorOrientation: orientation,
          isFrontFacing: isFront,
          viewfinderRoi: _viewfinderRoi,
          allowSquare: true,
        );

        if (mounted) {
          _applyDetectionResult(detection);
        }
      } catch (e) {
        debugPrint('[CardDetector Diagnostic] Frame analysis error: $e');
      } finally {
        _isProcessingFrameLock = false;
      }
    });
  }

  /// Evaluates and applies a business card detection result across consecutive frames.
  void _applyDetectionResult(BusinessCardDetectionResult detection) {
    if (!mounted || !_isAutoCaptureEnabled || _isCapturing) return;

    if (!detection.isDetected || _lastScreenSize == null) {
      setState(() {
        _detectionState = CardDetectionState.searching;
        _stableFrameCount = 0;
        _firstStableTime = null;
        _autoCaptureProgress = 0.0;
        _isCardDetected = false;
        _detectedCardRect = null;
        _detectedPolygon = null;
        _lastNormalizedPolygon = null;
        _lastCardArea = 0.0;
        _guidanceMessage = detection.quality.guidanceMessage.isNotEmpty &&
                detection.quality.guidanceMessage != 'Card aligned'
            ? detection.quality.guidanceMessage
            : 'Position your business card inside the camera view';
      });
      return;
    }

    _diagnosticQuadsDetected++;

    final previewSize = _cameraController?.value.previewSize;
    double previewAspect;
    if (previewSize != null) {
      previewAspect = min(previewSize.width, previewSize.height) /
          max(previewSize.width, previewSize.height);
    } else {
      previewAspect = 9.0 / 16.0;
    }

    final mapper = CameraCoordinateMapper(
      screenSize: _lastScreenSize!,
      previewAspect: previewAspect,
    );

    // Convert normalized polygon to screen pixel space using CameraCoordinateMapper
    final screenPolygon = (detection.normalizedPolygon ?? []).map((p) {
      return mapper.cameraToScreen(p);
    }).toList();

    Rect? candidateRect;
    if (screenPolygon.length == 4) {
      final minX = screenPolygon.map((p) => p.dx).reduce(min);
      final maxX = screenPolygon.map((p) => p.dx).reduce(max);
      final minY = screenPolygon.map((p) => p.dy).reduce(min);
      final maxY = screenPolygon.map((p) => p.dy).reduce(max);
      candidateRect = Rect.fromLTRB(minX, minY, maxX, maxY);
    }

    // 4-corner multi-frame stability check (<3.8% screen displacement across consecutive frames)
    double maxDisp = 0.0;
    if (_lastNormalizedPolygon != null &&
        _lastNormalizedPolygon!.length == 4 &&
        detection.normalizedPolygon != null &&
        detection.normalizedPolygon!.length == 4) {
      for (int i = 0; i < 4; i++) {
        final d = (detection.normalizedPolygon![i] - _lastNormalizedPolygon![i]).distance;
        if (d > maxDisp) maxDisp = d;
      }
    }

    // Area consistency check (< 15% variation)
    final currentArea = detection.corners?.area ?? 0.0;
    bool areaConsistent = true;
    if (_lastCardArea > 0 && currentArea > 0) {
      final areaDiff = (currentArea - _lastCardArea).abs() / _lastCardArea;
      if (areaDiff > 0.15) {
        areaConsistent = false;
      }
    }

    final now = DateTime.now();
    final bool isStable = _lastNormalizedPolygon != null &&
        maxDisp < 0.038 &&
        areaConsistent;

    if (isStable) {
      _stableFrameCount++;
      _firstStableTime ??= now;
    } else {
      _stableFrameCount = 1;
      _firstStableTime = now;
    }

    _lastNormalizedPolygon = detection.normalizedPolygon;
    _lastCardArea = currentArea;
    _lastValidDetection = detection;

    // Advance state machine
    if (_stableFrameCount == 1) {
      _detectionState = CardDetectionState.detected;
    } else if (_stableFrameCount < max(2, (_requiredStableFrames * 0.4).round())) {
      _detectionState = CardDetectionState.tracking;
    } else {
      _detectionState = CardDetectionState.stabilizing;
    }

    _autoCaptureProgress = (_stableFrameCount / _requiredStableFrames.toDouble()).clamp(0.0, 1.0);

    // Diagnostic logging
    final corners = detection.corners;
    debugPrint(
      '[CardDetector Diagnostic] State: ${_detectionState.name} | '
      'Frames Rcv: $_diagnosticFramesReceived | Proc: $_diagnosticFramesProcessed | '
      'Quads: $_diagnosticQuadsDetected | Stability: $_stableFrameCount/$_requiredStableFrames | '
      'Area: ${(detection.cardAreaRatio * 100).toStringAsFixed(1)}% | '
      'Corners: [TL(${corners?.topLeft.x},${corners?.topLeft.y}), '
      'TR(${corners?.topRight.x},${corners?.topRight.y}), '
      'BR(${corners?.bottomRight.x},${corners?.bottomRight.y}), '
      'BL(${corners?.bottomLeft.x},${corners?.bottomLeft.y})]',
    );

    String nextGuidance;
    if (_stableFrameCount == 1) {
      nextGuidance = 'Card detected — Hold steady...';
    } else if (_stableFrameCount < _requiredStableFrames) {
      nextGuidance = 'Aligning & focusing ($_stableFrameCount/$_requiredStableFrames)...';
    } else {
      nextGuidance = 'Hold steady — Capturing automatically...';
    }

    setState(() {
      _isCardDetected = true;
      _detectedCardRect = candidateRect;
      _detectedPolygon = screenPolygon;
      _guidanceMessage = nextGuidance;
    });

    // Step 5: Automatic capture triggered ONLY when genuine card is confirmed for >= requiredStableFrames
    // AND card is sharp (not blurry) AND lighting is acceptable
    if (_stableFrameCount >= _requiredStableFrames &&
        _isAutoCaptureEnabled &&
        !detection.quality.isBlurry &&
        !detection.quality.isExtremelyDark &&
        !detection.quality.isExtremelyOverexposed &&
        !_isCapturing) {
      _detectionState = CardDetectionState.capturing;
      debugPrint(
        '[CardDetector Diagnostic] Auto-capture triggered! Reason: '
        '$_requiredStableFrames consecutive stable frames reached '
        '(blurScore: ${detection.quality.blurScore.toStringAsFixed(1)}, '
        'brightness: ${detection.quality.brightness.toStringAsFixed(1)})',
      );
      _triggerAutoCapture();
    }
  }

  Future<void> _triggerAutoCapture() async {
    if (_isCapturing || !mounted) return;
    await _safeStopImageStream();
    await _handleCapture();
  }

  @visibleForTesting
  void testProcessDetection(BusinessCardDetectionResult detection) {
    _applyDetectionResult(detection);
  }

  void _handleToggleAutoCapture() {
    setState(() {
      _isAutoCaptureEnabled = !_isAutoCaptureEnabled;
      if (!_isAutoCaptureEnabled) {
        _stopAutoDetectionTimer();
        _isCardDetected = false;
        _detectedCardRect = null;
        _stableFrameCount = 0;
        _guidanceMessage = 'Position card inside the frame';
      } else {
        _stableFrameCount = 0;
        _startAutoDetectionLoop();
      }
    });
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

    _stopAutoDetectionTimer();
    await _safeStopImageStream();

    setState(() {
      _isCapturing = true;
      _detectionState = CardDetectionState.capturing;
      _isFlashing = true;
      _guidanceMessage = 'Capturing card...';
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() {
          _isFlashing = false;
        });
      }
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

      setState(() {
        _detectionState = CardDetectionState.processing;
        _guidanceMessage = 'Processing card perspective...';
      });

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

      String finalCapturedPath = picture.path;
      CaptureQualityAssessment? captureQuality;
      try {
        final geom = await _geometryService.correctPerspectiveIfReliable(
          picture.path,
          mappedRoi,
          _lastValidDetection?.normalizedPolygon,
        );
        captureQuality = geom.quality;
        if (geom.wasCorrected || geom.wasRoiCropped) {
          finalCapturedPath = geom.imagePath;
        }
        _detectionState = CardDetectionState.completed;
        debugPrint(
          '[CardDetector Diagnostic] Perspective correction: '
          'wasCorrected=${geom.wasCorrected}, wasRoiCropped=${geom.wasRoiCropped}, '
          'path=${geom.imagePath}',
        );
      } catch (_) {}

      if (!mounted) return;

      if (qualityResult.isPoor) {
        final bool? proceed =
            await _showQualityWarningDialog(qualityResult.warnings);
        if (proceed != true) {
          setState(() {
            _isCapturing = false;
            _detectionState = CardDetectionState.searching;
            _isCardDetected = false;
            _detectedCardRect = null;
            _detectedPolygon = null;
            _lastNormalizedPolygon = null;
            _lastCardArea = 0.0;
            _stableFrameCount = 0;
            _guidanceMessage = qualityResult.warnings.isNotEmpty
                ? qualityResult.warnings.first
                : 'Position your business card inside the camera view';
          });
          _startAutoDetectionLoop();
          return;
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(
        BusinessCardCameraResult(
          imagePath: finalCapturedPath,
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
        _detectionState = CardDetectionState.searching;
        _isCardDetected = false;
        _detectedCardRect = null;
        _detectedPolygon = null;
        _lastNormalizedPolygon = null;
        _lastCardArea = 0.0;
        _stableFrameCount = 0;
        _guidanceMessage = 'Camera error';
      });
      _startAutoDetectionLoop();
      _showErrorDialog(
        'Camera Error',
        e.description ?? 'Unable to capture image.',
      );
    } catch (_) {
      await PendingCardCaptureStore.clear();
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _detectionState = CardDetectionState.searching;
        _isCardDetected = false;
        _detectedCardRect = null;
        _detectedPolygon = null;
        _lastNormalizedPolygon = null;
        _lastCardArea = 0.0;
        _stableFrameCount = 0;
        _guidanceMessage = 'Capture failed';
      });
      _startAutoDetectionLoop();
    }
  }

  Future<void> _handlePickGallery() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (pickedFile == null || !mounted) return;

      String finalGalleryPath = pickedFile.path;
      CaptureQualityAssessment? captureQuality;
      try {
        final geom = await _geometryService.correctPerspectiveIfReliable(
          pickedFile.path,
          _viewfinderRoi,
        );
        captureQuality = geom.quality;
        if (geom.wasCorrected || geom.wasRoiCropped) {
          finalGalleryPath = geom.imagePath;
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pop(
        BusinessCardCameraResult(
          imagePath: finalGalleryPath,
          side: _currentSide,
          isFromGallery: true,
          viewfinderRoi: _viewfinderRoi,
          quality: captureQuality,
        ),
      );
    } catch (_) {}
  }

  void _handleToggleSide() {
    setState(() {
      _currentSide =
          _currentSide == CardSide.front ? CardSide.back : CardSide.front;
      _isCardDetected = false;
      _detectedCardRect = null;
      _stableFrameCount = 0;
      _guidanceMessage = 'Position card inside the frame';
    });
    _startAutoDetectionLoop();
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
                isReady: _isCardDetected,
                detectionState: _detectionState,
                sideName: _currentSide == CardSide.front ? 'FRONT' : 'BACK',
                isTorchOn: _isTorchOn,
                isCaptureEnabled:
                    (_isCameraInitialized || widget.previewBuilder != null) &&
                        !_isCapturing,
                isAutoCapture: _isAutoCaptureEnabled,
                onToggleAutoCapture: _handleToggleAutoCapture,
                detectedCardRect: _detectedCardRect,
                detectedPolygon: _detectedPolygon,
                autoCaptureProgress: _autoCaptureProgress,
                onSwitchCamera:
                    _availableCameras.length > 1 ? _handleSwitchCamera : null,
                isFlashing: _isFlashing,
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
