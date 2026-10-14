import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/business_card_ocr_service.dart';
import '../../services/business_card_parser.dart';
import '../../services/imported_contact_service.dart';
import '../../theme/app_spacing.dart';
import 'business_card_review_screen.dart';
import 'qr_scanner_screen.dart';

class BusinessCardScanScreen extends StatefulWidget {
  final IBusinessCardOcrService? ocrService;
  final ImagePicker? imagePicker;
  final BusinessCardParser? parser;
  final ImportedContactService? importedContactService;

  const BusinessCardScanScreen({
    super.key,
    this.ocrService,
    this.imagePicker,
    this.parser,
    this.importedContactService,
  });

  @override
  State<BusinessCardScanScreen> createState() => _BusinessCardScanScreenState();
}

class _BusinessCardScanScreenState extends State<BusinessCardScanScreen> {
  late final IBusinessCardOcrService _ocrService;
  late final ImagePicker _imagePicker;
  late final BusinessCardParser _parser;
  late final ImportedContactService _contactService;

  bool _isProcessing = false;
  String _processingTitle = 'Scanning business card...';
  String _processingSubtitle = 'Reading contact information';
  bool _showPhysicalOptions = false;

  @override
  void initState() {
    super.initState();
    _ocrService = widget.ocrService ?? const BusinessCardOcrService();
    _imagePicker = widget.imagePicker ?? ImagePicker();
    _parser = widget.parser ?? const BusinessCardParser();
    _contactService = widget.importedContactService ?? ImportedContactService();
  }

  Future<void> _handleScanDigitalQr() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
  }

  Future<void> _processImageSource(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 95,
      );

      // User cancelled camera or gallery picker
      if (pickedFile == null) {
        return;
      }

      setState(() {
        _isProcessing = true;
        _processingTitle = 'Scanning business card...';
        _processingSubtitle = 'Reading contact information';
      });

      // 100% on-device local OCR processing
      final recognizedText =
          await _ocrService.recognizeTextFromPath(pickedFile.path);

      if (!mounted) return;

      if (recognizedText.trim().isEmpty) {
        setState(() {
          _isProcessing = false;
        });

        _showNoTextDialog(source);
        return;
      }

      // Parse OCR output into structured BusinessCardData
      final cardData = _parser.parse(recognizedText);

      setState(() {
        _isProcessing = false;
      });

      if (!mounted) return;

      // Navigate to Review Details Screen
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BusinessCardReviewScreen(
            cardData: cardData,
            contactService: _contactService,
          ),
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      _showErrorDialog(
        'Permission or Device Error',
        e.message ?? 'Unable to access the camera or gallery. Please check permissions.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      _showErrorDialog(
        'OCR Scanning Error',
        'Unable to scan this card. Try taking another photo.',
      );
    }
  }

  void _showNoTextDialog(ImageSource source) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No Text Detected'),
        content: const Text(
          'No readable text could be recognized on the business card. Please ensure good lighting, avoid glare, and hold the camera steady.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _processImageSource(source);
            },
            child: const Text('Try Again'),
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
              const SizedBox(height: 20),
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
                  _processImageSource(ImageSource.camera);
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
                  _processImageSource(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Scan',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: AppSpacing.pagePadding,
            child: Column(
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
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: AppSpacing.radiusMd,
                                      ),
                                    ),
                                    onPressed: () =>
                                        _processImageSource(ImageSource.camera),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    key: const Key('inline_choose_gallery_button'),
                                    icon: const Icon(Icons.photo_library_rounded),
                                    label: const Text('Gallery'),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: AppSpacing.radiusMd,
                                      ),
                                    ),
                                    onPressed: () =>
                                        _processImageSource(ImageSource.gallery),
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
              ],
            ),
          ),

          // Processing Loading Overlay (Section 12: Polished OCR State)
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
}
