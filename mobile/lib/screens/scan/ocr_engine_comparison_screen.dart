import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../../models/business_card_data.dart';
import '../../services/ocr/ocr_engine.dart';
import '../../services/ocr/ml_kit_ocr_engine.dart';
import '../../services/ocr/paddle_ocr_engine.dart';
import '../../services/card_geometry_service.dart';
import '../../services/image_enhancement_service.dart';
import '../../services/business_card_parser.dart';
import '../../theme/app_spacing.dart';

/// Development and testing screen for comparing Google ML Kit OCR and
/// PaddleOCR PP-OCRv5 mobile on the exact same business card image.
class OcrEngineComparisonScreen extends StatefulWidget {
  final OcrEngine? mlKitEngine;
  final OcrEngine? paddleEngine;
  final CardGeometryService? geometryService;
  final ImageEnhancementService? enhancementService;
  final BusinessCardParser? parser;
  final ImagePicker? imagePicker;

  const OcrEngineComparisonScreen({
    super.key,
    this.mlKitEngine,
    this.paddleEngine,
    this.geometryService,
    this.enhancementService,
    this.parser,
    this.imagePicker,
  });

  @override
  State<OcrEngineComparisonScreen> createState() =>
      _OcrEngineComparisonScreenState();
}

class _OcrEngineComparisonScreenState extends State<OcrEngineComparisonScreen> {
  late final OcrEngine _mlKitEngine;
  late final OcrEngine _paddleEngine;
  late final CardGeometryService _geometryService;
  late final ImageEnhancementService _enhancementService;
  late final BusinessCardParser _parser;
  late final ImagePicker _imagePicker;

  String? _selectedImagePath;
  int? _imageWidth;
  int? _imageHeight;
  bool _wasPerspectiveCorrected = false;
  bool _wasEnhanced = false;

  bool _isComparing = false;
  String _currentStep = '';

  OcrEngineResult? _mlKitResult;
  OcrEngineResult? _paddleResult;

  bool _showParsedResults = false;
  BusinessCardData? _mlKitParsed;
  BusinessCardData? _paddleParsed;

  final List<String> _temporaryFilesToClean = [];

  @override
  void initState() {
    super.initState();
    _mlKitEngine = widget.mlKitEngine ?? const MlKitOcrEngine();
    _paddleEngine = widget.paddleEngine ?? PaddleOcrEngine();
    _geometryService = widget.geometryService ?? const CardGeometryService();
    _enhancementService =
        widget.enhancementService ?? const ImageEnhancementService();
    _parser = widget.parser ?? const BusinessCardParser();
    _imagePicker = widget.imagePicker ?? ImagePicker();
  }

  @override
  void dispose() {
    _cleanupTempFiles();
    _paddleEngine.dispose();
    _mlKitEngine.dispose();
    super.dispose();
  }

  void _cleanupTempFiles() {
    for (final path in _temporaryFilesToClean) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (_) {}
    }
    _temporaryFilesToClean.clear();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isComparing) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 100,
      );

      if (picked == null) return;

      await _processImageForComparison(picked.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  Future<void> _processImageForComparison(String rawPath) async {
    setState(() {
      _isComparing = true;
      _currentStep = 'Preparing image...';
      _mlKitResult = null;
      _paddleResult = null;
      _mlKitParsed = null;
      _paddleParsed = null;
      _wasPerspectiveCorrected = false;
      _wasEnhanced = false;
    });

    try {
      // 1. Normalize EXIF orientation
      final normalizedPath =
          await _enhancementService.normalizeExifOrientation(rawPath);
      if (normalizedPath != rawPath) {
        _temporaryFilesToClean.add(normalizedPath);
      }

      // 2. Read image dimensions safely
      int origW = 0;
      int origH = 0;
      try {
        final file = File(normalizedPath);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          final decoded = img.decodeImage(bytes);
          origW = decoded?.width ?? 0;
          origH = decoded?.height ?? 0;
        }
      } catch (_) {}

      // 3. Perspective correction
      final geomResult =
          await _geometryService.correctPerspectiveIfReliable(normalizedPath);
      String workingPath = geomResult.imagePath;
      final bool wasCorrected = geomResult.wasCorrected;
      if (geomResult.temporaryFilePath != null) {
        _temporaryFilesToClean.add(geomResult.temporaryFilePath!);
      }

      // 4. Low-contrast / dark card check
      bool wasEnhanced = false;
      final isDark = await _enhancementService.isDarkCard(workingPath);
      if (isDark) {
        final inverted =
            await _enhancementService.createInvertedCandidate(workingPath);
        if (inverted != null) {
          workingPath = inverted;
          wasEnhanced = true;
          _temporaryFilesToClean.add(inverted);
        }
      }

      setState(() {
        _selectedImagePath = workingPath;
        _imageWidth = origW;
        _imageHeight = origH;
        _wasPerspectiveCorrected = wasCorrected;
        _wasEnhanced = wasEnhanced;
        _currentStep = 'Running Google ML Kit on-device...';
      });

      // 5. Run Engine 1: Google ML Kit (Sequential)
      final mlKitResult = await _mlKitEngine.recognize(workingPath);

      if (!mounted) return;
      setState(() {
        _mlKitResult = mlKitResult;
        _currentStep = 'Running PaddleOCR PP-OCRv5 mobile on-device...';
      });

      // 6. Run Engine 2: PaddleOCR PP-OCRv5 Mobile (Sequential)
      final paddleResult = await _paddleEngine.recognize(workingPath);

      if (!mounted) return;

      // 7. Optional parsing for secondary inspection
      final mlParsed = mlKitResult.isSuccess
          ? _parser.parse(mlKitResult.rawText)
          : null;
      final padParsed = paddleResult.isSuccess
          ? _parser.parse(paddleResult.rawText)
          : null;

      setState(() {
        _paddleResult = paddleResult;
        _mlKitParsed = mlParsed;
        _paddleParsed = padParsed;
        _isComparing = false;
        _currentStep = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isComparing = false;
        _currentStep = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Comparison failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Dev Only'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'The OCR Engine Comparison benchmark is only available in debug and development builds.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'OCR Engine Comparison',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectedImagePath != null && !_isComparing)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Re-run Comparison',
              onPressed: () => _processImageForComparison(_selectedImagePath!),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dev Banner
            _buildDevBanner(theme),
            const SizedBox(height: AppSpacing.md),

            // Image Picker Section
            _buildImagePickerCard(theme),
            const SizedBox(height: AppSpacing.lg),

            // Loading Indicator
            if (_isComparing) ...[
              _buildProgressCard(theme),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Comparison Results
            if (_mlKitResult != null || _paddleResult != null) ...[
              _buildImageDiagnosticsCard(theme),
              const SizedBox(height: AppSpacing.lg),
              _buildEnginesSideBySide(theme),
              const SizedBox(height: AppSpacing.lg),
              _buildDeltaSummaryCard(theme),
              const SizedBox(height: AppSpacing.lg),
              _buildParsedToggleSection(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDevBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: AppSpacing.radiusMd,
        border: Border.all(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.science_rounded,
            size: 20,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EXPERIMENTAL BENCHMARK ONLY (DEV/TEST)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onTertiaryContainer,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Compares raw on-device OCR between Google ML Kit and PaddleOCR PP-OCRv5 Mobile on the exact same business card image. Existing production scanner remains 100% untouched.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePickerCard(ThemeData theme) {
    return Card(
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
              children: [
                Icon(
                  Icons.camera_alt_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Select Test Card Image',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Capture a physical card or select a difficult card image from your gallery.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('compare_take_photo_button'),
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Take Photo'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isComparing
                        ? null
                        : () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const Key('compare_choose_gallery_button'),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('From Gallery'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isComparing
                        ? null
                        : () => _pickImage(ImageSource.gallery),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.radiusMd,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _currentStep,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageDiagnosticsCard(ThemeData theme) {
    return Card(
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
            Text(
              'Input Image Diagnostics',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildInfoChip(
                  theme,
                  label: 'Resolution',
                  value: _imageWidth != null
                      ? '${_imageWidth}x$_imageHeight px'
                      : 'Unknown',
                  icon: Icons.aspect_ratio_rounded,
                ),
                _buildInfoChip(
                  theme,
                  label: 'Perspective Corrected',
                  value: _wasPerspectiveCorrected ? 'Yes' : 'No',
                  icon: Icons.crop_free_rounded,
                  isPositive: _wasPerspectiveCorrected,
                ),
                _buildInfoChip(
                  theme,
                  label: 'Contrast Enhanced',
                  value: _wasEnhanced ? 'Yes' : 'No',
                  icon: Icons.contrast_rounded,
                  isPositive: _wasEnhanced,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(
    ThemeData theme, {
    required String label,
    required String value,
    required IconData icon,
    bool? isPositive,
  }) {
    Color? chipColor;
    if (isPositive != null) {
      chipColor = isPositive
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppSpacing.radiusSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnginesSideBySide(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;

        final mlKitCard = _buildEngineCard(
          theme: theme,
          engineTitle: 'Google ML Kit',
          engineSubtitle: 'Production Baseline (Latin script)',
          result: _mlKitResult,
          accentColor: theme.colorScheme.primary,
        );

        final paddleCard = _buildEngineCard(
          theme: theme,
          engineTitle: 'PaddleOCR',
          engineSubtitle: 'PP-OCRv5 Mobile ONNX (Experimental)',
          result: _paddleResult,
          accentColor: theme.colorScheme.tertiary,
        );

        if (isNarrow) {
          return Column(
            children: [
              mlKitCard,
              const SizedBox(height: AppSpacing.lg),
              paddleCard,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: mlKitCard),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: paddleCard),
          ],
        );
      },
    );
  }

  Widget _buildEngineCard({
    required ThemeData theme,
    required String engineTitle,
    required String engineSubtitle,
    required OcrEngineResult? result,
    required Color accentColor,
  }) {
    return Card(
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
            // Engine Header
            Row(
              children: [
                Container(
                  width: 8,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        engineTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        engineSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (result != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: result.isSuccess
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.errorContainer,
                      borderRadius: AppSpacing.radiusSm,
                    ),
                    child: Text(
                      result.isSuccess ? 'Success' : 'Error',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: result.isSuccess
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Performance Metrics
            if (result != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: AppSpacing.radiusSm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetricCol(
                      theme,
                      title: 'Time',
                      value: '${result.processingTime.inMilliseconds} ms',
                    ),
                    _buildMetricCol(
                      theme,
                      title: 'Lines',
                      value: '${result.lineCount}',
                    ),
                    _buildMetricCol(
                      theme,
                      title: 'Chars',
                      value: '${result.characterCount}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Content or Error
            if (result == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Pending execution...'),
                ),
              )
            else if (!result.isSuccess)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: AppSpacing.radiusSm,
                  border: Border.all(color: theme.colorScheme.error),
                ),
                child: Text(
                  result.error ?? 'Unknown engine error',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontFamily: 'monospace',
                  ),
                ),
              )
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'RAW RECOGNIZED TEXT',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    tooltip: 'Copy Raw Text',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: result.rawText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$engineTitle raw text copied'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                height: 240,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: AppSpacing.radiusSm,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: result.rawText.isEmpty
                    ? Center(
                        child: Text(
                          'No text recognized',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: SelectableText(
                          result.rawText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            height: 1.4,
                          ),
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCol(
    ThemeData theme, {
    required String title,
    required String value,
  }) {
    return Column(
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDeltaSummaryCard(ThemeData theme) {
    if (_mlKitResult == null || _paddleResult == null) {
      return const SizedBox.shrink();
    }

    final mlKit = _mlKitResult!;
    final paddle = _paddleResult!;

    final timeDelta =
        paddle.processingTime.inMilliseconds - mlKit.processingTime.inMilliseconds;
    final lineDelta = paddle.lineCount - mlKit.lineCount;
    final charDelta = paddle.characterCount - mlKit.characterCount;

    return Card(
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
            Text(
              'Engine Comparison Delta (PaddleOCR vs. ML Kit)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDeltaItem(
                  theme,
                  label: 'Latency Difference',
                  value: timeDelta >= 0 ? '+$timeDelta ms' : '$timeDelta ms',
                  subtitle: timeDelta <= 0
                      ? 'PaddleOCR faster'
                      : 'ML Kit faster (${(timeDelta / (mlKit.processingTime.inMilliseconds == 0 ? 1 : mlKit.processingTime.inMilliseconds)).toStringAsFixed(1)}x)',
                ),
                _buildDeltaItem(
                  theme,
                  label: 'Line Difference',
                  value: lineDelta >= 0 ? '+$lineDelta' : '$lineDelta',
                  subtitle: lineDelta == 0
                      ? 'Identical lines'
                      : (lineDelta > 0 ? 'More lines' : 'Fewer lines'),
                ),
                _buildDeltaItem(
                  theme,
                  label: 'Character Difference',
                  value: charDelta >= 0 ? '+$charDelta' : '$charDelta',
                  subtitle: charDelta == 0
                      ? 'Identical chars'
                      : (charDelta > 0 ? 'More chars' : 'Fewer chars'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeltaItem(
    ThemeData theme, {
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildParsedToggleSection(ThemeData theme) {
    return Card(
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Downstream Contact Parsing (Optional)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Inspect how BusinessCardParser maps each raw OCR output',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _showParsedResults,
                  onChanged: (val) {
                    setState(() {
                      _showParsedResults = val;
                    });
                  },
                ),
              ],
            ),
            if (_showParsedResults) ...[
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildParsedDetails(
                      theme,
                      engineName: 'ML Kit Parsed',
                      parsed: _mlKitParsed,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _buildParsedDetails(
                      theme,
                      engineName: 'PaddleOCR Parsed',
                      parsed: _paddleParsed,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParsedDetails(
    ThemeData theme, {
    required String engineName,
    required BusinessCardData? parsed,
  }) {
    if (parsed == null) {
      return Text(
        'No parsed data',
        style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          engineName,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        _buildFieldRow(theme, 'Name', parsed.fullName),
        _buildFieldRow(theme, 'Job Title', parsed.jobTitle),
        _buildFieldRow(theme, 'Company', parsed.company),
        _buildFieldRow(
          theme,
          'Phones',
          parsed.phoneNumbers.map((p) => p.number).join(', '),
        ),
        _buildFieldRow(
          theme,
          'Emails',
          parsed.emailAddresses.map((e) => e.email).join(', '),
        ),
        _buildFieldRow(theme, 'Website', parsed.website),
        _buildFieldRow(theme, 'Address', parsed.address),
      ],
    );
  }

  Widget _buildFieldRow(ThemeData theme, String field, String? value) {
    if (value == null || value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
          Text(
            value.trim(),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
