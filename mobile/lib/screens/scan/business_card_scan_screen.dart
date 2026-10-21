import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/ocr_side_result.dart';
import '../../services/business_card_ocr_service.dart';
import '../../services/business_card_parser.dart';
import '../../services/card_image_normalization_service.dart';
import '../../services/image_quality_service.dart';
import '../../services/imported_contact_service.dart';
import '../../services/pending_card_capture_store.dart';
import '../../theme/app_spacing.dart';
import 'business_card_camera_screen.dart';
import 'business_card_review_screen.dart';
import 'ocr_engine_comparison_screen.dart';
import 'qr_scanner_screen.dart';

class BusinessCardScanScreen extends StatefulWidget {
  final IBusinessCardOcrService? ocrService;
  final ImagePicker? imagePicker;
  final BusinessCardParser? parser;
  final ImportedContactService? importedContactService;
  final ImageQualityService? qualityService;

  const BusinessCardScanScreen({
    super.key,
    this.ocrService,
    this.imagePicker,
    this.parser,
    this.importedContactService,
    this.qualityService,
  });

  @override
  State<BusinessCardScanScreen> createState() => _BusinessCardScanScreenState();
}

class _BusinessCardScanScreenState extends State<BusinessCardScanScreen>
    with WidgetsBindingObserver {
  late final IBusinessCardOcrService _ocrService;
  late final ImagePicker _imagePicker;
  late final BusinessCardParser _parser;
  late final ImportedContactService _contactService;
  late final ImageQualityService _qualityService;

  String? _frontImagePath;
  String? _backImagePath;
  String? _frontImageSource;
  String? _backImageSource;
  int _scanSessionId = 0;
  bool _isProcessing = false;
  String _processingTitle = 'Scanning business card...';
  String _processingSubtitle = 'Reading contact information on-device';
  bool _showPhysicalOptions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ocrService = widget.ocrService ??
        BusinessCardOcrService(
          onProgressUpdate: (msg) {
            if (mounted) {
              setState(() {
                _processingSubtitle = msg;
              });
            }
          },
        );
    _imagePicker = widget.imagePicker ?? ImagePicker();
    _parser = widget.parser ?? const BusinessCardParser();
    _contactService =
        widget.importedContactService ?? ImportedContactService();
    _qualityService = widget.qualityService ?? const ImageQualityService();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLostData();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLostData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deleteLocalFile(_frontImagePath);
    _deleteLocalFile(_backImagePath);
    super.dispose();
  }

  void _deleteLocalFile(String? path) {
    if (path == null || path.isEmpty) return;
    try {
      final tempDir = Directory.systemTemp.path;
      // Only delete if it is located inside system temp directory to protect user gallery files
      if (path.startsWith(tempDir)) {
        final file = File(path);
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    } catch (_) {}
  }

  /// Recovers image data if Android killed the application Activity while the external
  /// camera app was active.
  Future<void> _checkLostData() async {
    try {
      final pendingData = await PendingCardCaptureStore.loadPendingCapture();

      // Restore previously staged paths from before process death if available
      if (pendingData != null) {
        final stagedFront = pendingData['frontPath'] as String?;
        final stagedBack = pendingData['backPath'] as String?;
        if (_frontImagePath == null && stagedFront != null && File(stagedFront).existsSync()) {
          _frontImagePath = stagedFront;
        }
        if (_backImagePath == null && stagedBack != null && File(stagedBack).existsSync()) {
          _backImagePath = stagedBack;
        }
      }

      final LostDataResponse response = await _imagePicker.retrieveLostData();
      if (response.isEmpty) {
        if (pendingData != null) {
          await PendingCardCaptureStore.clear();
          if (mounted) setState(() {});
        }
        return;
      }

      final side = (pendingData != null && pendingData['side'] == CardSide.back.name)
          ? CardSide.back
          : CardSide.front;

      final recoveredFile = response.file ??
          (response.files != null && response.files!.isNotEmpty ? response.files!.first : null);

      if (recoveredFile != null) {
        final path = recoveredFile.path;

        // Prevent duplicating if already staged
        if ((side == CardSide.front && _frontImagePath == path) ||
            (side == CardSide.back && _backImagePath == path)) {
          await PendingCardCaptureStore.clear();
          return;
        }

        if (!mounted) return;
        setState(() {
          if (side == CardSide.front) {
            _frontImagePath = path;
            _showPhysicalOptions = false;
          } else {
            _backImagePath = path;
          }
        });
        await PendingCardCaptureStore.clear();
      } else if (response.exception != null) {
        await PendingCardCaptureStore.clear();
        if (!mounted) return;
        _showErrorDialog(
          'Image Capture Error',
          response.exception!.message ?? 'Unable to recover captured image.',
        );
      }
    } catch (_) {
      // Graceful catch ensures no crash if disposed or channel fails
      await PendingCardCaptureStore.clear();
    }
  }

  Future<void> _handleScanDigitalQr() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
  }

  Future<void> _pickImage(ImageSource source, CardSide side) async {
    if (source == ImageSource.camera && widget.imagePicker == null) {
      final res = await Navigator.of(context).push<BusinessCardCameraResult>(
        MaterialPageRoute(
          builder: (_) => BusinessCardCameraScreen(
            side: side,
            qualityService: _qualityService,
          ),
        ),
      );
      if (res != null && mounted) {
        setState(() {
          _scanSessionId++;
          if (res.side == CardSide.front) {
            _frontImagePath = res.imagePath;
            _frontImageSource = res.isFromGallery ? 'gallery' : 'camera';
            _showPhysicalOptions = false;
          } else {
            _backImagePath = res.imagePath;
            _backImageSource = res.isFromGallery ? 'gallery' : 'camera';
          }
        });
      }
      return;
    }

    await PendingCardCaptureStore.savePendingCapture(
      side: side,
      frontPath: _frontImagePath,
      backPath: _backImagePath,
    );

    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 100,
      );

      // Successfully returned or cancelled within the active session
      await PendingCardCaptureStore.clear();

      if (pickedFile == null) {
        return;
      }

      // Pre-OCR image quality assessment
      final qualityResult = await _qualityService.evaluateImagePath(pickedFile.path);

      if (qualityResult.isPoor) {
        if (!mounted) return;
        final bool? proceed = await _showQualityWarningDialog(qualityResult);
        if (proceed != true) {
          // User chose "Retake Photo"
          if (mounted) {
            _showRetakeModal(side);
          }
          return;
        }
      } else if (qualityResult.status == ImageQualityStatus.usableWithWarning &&
          qualityResult.warnings.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(qualityResult.warnings.first),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      setState(() {
        _scanSessionId++;
        if (side == CardSide.front) {
          _frontImagePath = pickedFile.path;
          _frontImageSource = source == ImageSource.camera ? 'camera' : 'gallery';
          _showPhysicalOptions = false;
        } else {
          _backImagePath = pickedFile.path;
          _backImageSource = source == ImageSource.camera ? 'camera' : 'gallery';
        }
      });
    } on PlatformException catch (e) {
      await PendingCardCaptureStore.clear();
      if (!mounted) return;
      _showErrorDialog(
        'Permission or Device Error',
        e.message ??
            'Unable to access the camera or gallery. Please check permissions.',
      );
    } catch (_) {
      await PendingCardCaptureStore.clear();
      if (!mounted) return;
      _showErrorDialog(
        'Image Selection Error',
        'Unable to select image. Please try again.',
      );
    }
  }

  Future<bool?> _showQualityWarningDialog(ImageQualityResult quality) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Photo Quality Notice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This photo may be difficult to read.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...quality.warnings.map(
              (w) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(child: Text(w, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('quality_retake_button'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Retake Photo'),
          ),
          FilledButton(
            key: const Key('quality_use_anyway_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Use Anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _processStagedCards() async {
    if (_frontImagePath == null || _isProcessing) return;

    final currentSession = ++_scanSessionId;
    final isDualSide = _backImagePath != null;

    setState(() {
      _isProcessing = true;
      _processingTitle = isDualSide
          ? 'Scanning front & back sides...'
          : 'Scanning business card...';
      _processingSubtitle = isDualSide
          ? 'Running on-device OCR on both sides'
          : 'Reading contact information on-device';
    });

    try {
      // 1. Process Front Side
      final frontOcr = await _ocrService.processCardSide(
        imagePath: _frontImagePath!,
        side: CardSide.front,
        source: _frontImageSource,
      );

      if (!mounted || _scanSessionId != currentSession) return;

      OcrSideResult? backOcr;
      if (isDualSide) {
        backOcr = await _ocrService.processCardSide(
          imagePath: _backImagePath!,
          side: CardSide.back,
          source: _backImageSource,
        );
      }

      if (!mounted || _scanSessionId != currentSession) return;

      // Verify readable text exists
      if (frontOcr.isEmpty && (backOcr == null || backOcr.isEmpty)) {
        setState(() {
          _isProcessing = false;
        });
        _showNoTextDialog();
        return;
      }

      if (isDualSide && frontOcr.isNotEmpty && backOcr!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No readable text found on back side. Continuing with front side.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Parse OCR output into structured BusinessCardData
      final cardData = _parser.parseDualSided(
        front: frontOcr,
        back: backOcr,
      );

      setState(() {
        _isProcessing = false;
      });

      if (!mounted || _scanSessionId != currentSession) return;

      // Navigate to Review Details Screen
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BusinessCardReviewScreen(
            cardData: cardData,
            contactService: _contactService,
          ),
        ),
      );
    } on CardNormalizationException catch (_) {
      if (!mounted || _scanSessionId != currentSession) return;
      setState(() {
        _isProcessing = false;
      });
      _showErrorDialog(
        'Image Read Error',
        'Unable to read this image. Please choose another photo.',
      );
    } on PlatformException catch (e) {
      if (!mounted || _scanSessionId != currentSession) return;
      setState(() {
        _isProcessing = false;
      });
      _showErrorDialog(
        'Permission or Device Error',
        e.message ??
            'Unable to process card. Please check permissions.',
      );
    } catch (_) {
      if (!mounted || _scanSessionId != currentSession) return;
      setState(() {
        _isProcessing = false;
      });
      _showErrorDialog(
        'OCR Scanning Error',
        'Unable to scan this card. Try retaking the photo.',
      );
    }
  }

  void _showNoTextDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No Text Detected'),
        content: const Text(
          "We couldn't confidently detect enough business-card details. Try a clearer image or enter the details manually.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            child: const Text('OK'),
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

  void _showRetakeModal(CardSide side) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                side == CardSide.front ? 'Retake Front Side' : 'Retake Back Side',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              ListTile(
                key: side == CardSide.front
                    ? const Key('retake_front_camera_button')
                    : const Key('retake_back_camera_button'),
                leading: const Icon(Icons.camera_alt_rounded),
                title: const Text('Take Photo with Camera'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.camera, side);
                },
              ),
              ListTile(
                key: side == CardSide.front
                    ? const Key('retake_front_gallery_button')
                    : const Key('retake_back_gallery_button'),
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.gallery, side);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddBackSideModal() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Back Side (Optional)',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Capture the back side of the card using the camera or select an existing photo.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              ListTile(
                key: const Key('back_camera_button'),
                leading: const Icon(Icons.camera_alt_rounded),
                title: const Text('Take Photo with Camera'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.camera, CardSide.back);
                },
              ),
              ListTile(
                key: const Key('back_gallery_button'),
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.gallery, CardSide.back);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPhysicalCardBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scan Physical Business Card',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Scan a printed card or choose an image.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: AppSpacing.radiusSm,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      size: 16,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tip: Place whole card in guide, avoid glare, hold steady & move closer for small text.',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                key: const Key('take_photo_button'),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primaryContainer,
                    borderRadius: AppSpacing.radiusSm,
                  ),
                  child: Icon(Icons.camera_alt_rounded,
                      color: Theme.of(ctx).colorScheme.primary),
                ),
                title: const Text(
                  'Take Photo',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Scan using device camera'),
                shape: RoundedRectangleBorder(
                  borderRadius: AppSpacing.radiusMd,
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.camera, CardSide.front);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                key: const Key('choose_gallery_button'),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.secondaryContainer,
                    borderRadius: AppSpacing.radiusSm,
                  ),
                  child: Icon(Icons.photo_library_rounded,
                      color: Theme.of(ctx).colorScheme.secondary),
                ),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Select a saved business card photo'),
                shape: RoundedRectangleBorder(
                  borderRadius: AppSpacing.radiusMd,
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.gallery, CardSide.front);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardImagePreview(String imagePath) {
    final file = File(imagePath);
    return ClipRRect(
      borderRadius: AppSpacing.radiusMd,
      child: Container(
        height: 140,
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.credit_card_rounded,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 4),
                Text(
                  'Card Image Staged',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStaged = _frontImagePath != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isStaged ? 'Stage Card Sides' : 'Scan',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: isStaged
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  setState(() {
                    _scanSessionId++;
                    _isProcessing = false;
                    _frontImagePath = null;
                    _backImagePath = null;
                    _frontImageSource = null;
                    _backImageSource = null;
                  });
                },
              )
            : null,
        actions: [
          if (kDebugMode)
            IconButton(
              key: const Key('ocr_engine_comparison_button'),
              tooltip: 'OCR Engine Comparison (Benchmark)',
              icon: const Icon(Icons.compare_arrows_rounded),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OcrEngineComparisonScreen(),
                  ),
                );
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: AppSpacing.pagePadding,
            child: isStaged
                ? _buildStagingView(theme)
                : _buildModeSelectionView(theme),
          ),

          // Processing Loading Overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.6),
              child: Center(
                child: Container(
                  padding: AppSpacing.dialogPadding,
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: AppSpacing.radiusLg,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        _processingTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _processingSubtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStagingView(ThemeData theme) {
    final hasBack = _backImagePath != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview & Add Card Sides',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Verify your photo or optionally add the back side before scanning.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // FRONT SIDE CARD
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.radiusLg,
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.badge_outlined,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'FRONT SIDE',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: AppSpacing.radiusSm,
                      ),
                      child: Text(
                        'Required',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _buildCardImagePreview(_frontImagePath!),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('retake_front_button'),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retake'),
                        onPressed: () => _showRetakeModal(CardSide.front),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('remove_front_button'),
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 18),
                        label: const Text('Remove'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: () {
                          setState(() {
                            _scanSessionId++;
                            _isProcessing = false;
                            _frontImagePath = null;
                            _backImagePath = null;
                            _frontImageSource = null;
                            _backImageSource = null;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // BACK SIDE CARD (OPTIONAL)
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.radiusLg,
            side: BorderSide(
              color: hasBack
                  ? theme.colorScheme.outlineVariant
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.flip_to_back_rounded,
                            size: 18, color: theme.colorScheme.secondary),
                        const SizedBox(width: 8),
                        Text(
                          'BACK SIDE (OPTIONAL)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: AppSpacing.radiusSm,
                      ),
                      child: Text(
                        'Optional',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (!hasBack) ...[
                  Text(
                    'Scan the reverse side if the business card has office addresses, additional phone numbers, websites, or foreign translation.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('add_back_side_button'),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('+ Add Back Side'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _showAddBackSideModal,
                    ),
                  ),
                ] else ...[
                  _buildCardImagePreview(_backImagePath!),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('retake_back_button'),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retake'),
                          onPressed: () => _showRetakeModal(CardSide.back),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('remove_back_button'),
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          label: const Text('Remove'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                          onPressed: () {
                            setState(() {
                              _scanSessionId++;
                              _backImagePath = null;
                              _backImageSource = null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // PRIMARY ACTION BUTTON (Dynamic text)
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            key: const Key('scan_details_button'),
            icon: const Icon(Icons.document_scanner_rounded),
            label: Text(
              hasBack ? 'Scan Details (Front & Back)' : 'Scan Details (1 Side)',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            onPressed: _processStagedCards,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: TextButton(
            key: const Key('cancel_staging_button'),
            onPressed: () {
              setState(() {
                _scanSessionId++;
                _isProcessing = false;
                _frontImagePath = null;
                _backImagePath = null;
                _frontImageSource = null;
                _backImageSource = null;
              });
            },
            child: const Text('Cancel & Start Over'),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  Widget _buildModeSelectionView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose Scan Mode',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Connect digitally with registered users or scan physical paper business cards with on-device OCR.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // Choice 1: Scan Digital Share QR
        Card(
          key: const Key('scan_digital_share_qr_button'),
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.radiusLg,
            side: BorderSide(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: InkWell(
            borderRadius: AppSpacing.radiusLg,
            onTap: _handleScanDigitalQr,
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: AppSpacing.radiusMd,
                    ),
                    child: Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 28,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Digital Share QR',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Instantly connect with another Digital Share user.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Choice 2: Scan Physical Business Card
        Card(
          key: const Key('scan_physical_card_button'),
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.radiusLg,
            side: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: InkWell(
            borderRadius: AppSpacing.radiusLg,
            onTap: () {
              setState(() {
                _showPhysicalOptions = !_showPhysicalOptions;
              });
              if (!_showPhysicalOptions) {
                _showPhysicalCardBottomSheet();
              }
            },
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: AppSpacing.radiusMd,
                        ),
                        child: Icon(
                          Icons.badge_outlined,
                          size: 28,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Physical Business Card',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Scan a printed card or choose an image.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _showPhysicalOptions
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),

                  // Direct Options when expanded
                  if (_showPhysicalOptions) ...[
                    const SizedBox(height: AppSpacing.md),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('inline_take_photo_button'),
                            icon: const Icon(Icons.camera_alt_rounded),
                            label: const Text('Camera'),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppSpacing.radiusMd,
                              ),
                            ),
                            onPressed: () =>
                                _pickImage(ImageSource.camera, CardSide.front),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            key: const Key('inline_choose_gallery_button'),
                            icon: const Icon(Icons.photo_library_rounded),
                            label: const Text('Gallery'),
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppSpacing.radiusMd,
                              ),
                            ),
                            onPressed: () =>
                                _pickImage(ImageSource.gallery, CardSide.front),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // Privacy assurance note
        Container(
          padding: AppSpacing.cardPadding,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: AppSpacing.radiusMd,
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'On-Device Privacy: Physical card recognition runs completely on your phone. Card images are never uploaded to any server.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: AppSpacing.lg),

          // Dev Benchmark Option
          Card(
            key: const Key('ocr_comparison_entry_card'),
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: AppSpacing.radiusMd,
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: ListTile(
              leading: Icon(
                Icons.science_outlined,
                color: theme.colorScheme.tertiary,
              ),
              title: Text(
                'OCR Engine Comparison (Dev/Test)',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                'Benchmark Google ML Kit vs. PaddleOCR PP-OCRv5 mobile on difficult cards',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OcrEngineComparisonScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
