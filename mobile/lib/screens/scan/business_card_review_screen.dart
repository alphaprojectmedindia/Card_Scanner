import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/business_card_data.dart';
import '../../models/business_card_email.dart';
import '../../models/business_card_phone.dart';
import '../../models/field_evidence.dart';
import '../../models/ocr_side_result.dart';
import '../../services/api_client.dart';
import '../../services/contact_communication_service.dart';
import '../../services/contact_service.dart';
import '../../services/imported_contact_service.dart';
import '../../services/secure_storage_service.dart';
import '../../services/ocr/local_correction_learning_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/business_card_email_editor.dart';
import '../../widgets/business_card_phone_editor.dart';
import '../../widgets/contact_message_composer.dart';
import '../../widgets/medindia_branding_footer.dart';
import '../connections/imported_contact_details_screen.dart';

class BusinessCardReviewScreen extends StatefulWidget {
  final BusinessCardData cardData;
  final ImportedContactService? contactService;
  final IContactCommunicationService? communicationService;
  final IContactService? phoneContactService;
  final String? imageFingerprint;
  final String? imageDHash;
  final String? frontImagePath;
  final String? backImagePath;
  final List<Map<String, dynamic>> frontObservations;
  final List<Map<String, dynamic>> backObservations;
  final String? ocrEngineName;
  final double? overallOcrConfidence;
  final LocalCorrectionLearningService? learningService;
  final String? userId;

  const BusinessCardReviewScreen({
    super.key,
    required this.cardData,
    this.contactService,
    this.communicationService,
    this.phoneContactService,
    this.imageFingerprint,
    this.imageDHash,
    this.frontImagePath,
    this.backImagePath,
    this.frontObservations = const [],
    this.backObservations = const [],
    this.ocrEngineName,
    this.overallOcrConfidence,
    this.learningService,
    this.userId,
  });

  @override
  State<BusinessCardReviewScreen> createState() => _BusinessCardReviewScreenState();
}

class _BusinessCardReviewScreenState extends State<BusinessCardReviewScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _jobTitleController;
  late final TextEditingController _companyController;
  late final TextEditingController _websiteController;
  late final TextEditingController _addressController;
  late final TextEditingController _rememberController;

  final FocusNode _jobTitleFocusNode = FocusNode();
  final FocusNode _companyFocusNode = FocusNode();
  late bool _showJobTitleField;
  late bool _showCompanyField;

  late List<BusinessCardPhone> _phones;
  late List<BusinessCardEmail> _emails;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.cardData.fullName ?? '');
    _jobTitleController = TextEditingController(text: widget.cardData.jobTitle ?? '');
    _companyController = TextEditingController(text: widget.cardData.company ?? '');
    _websiteController = TextEditingController(text: widget.cardData.website ?? '');
    _addressController = TextEditingController(text: widget.cardData.address ?? '');
    _rememberController = TextEditingController();

    _showJobTitleField = widget.cardData.jobTitle != null &&
        widget.cardData.jobTitle!.trim().isNotEmpty;
    _showCompanyField = widget.cardData.company != null &&
        widget.cardData.company!.trim().isNotEmpty;

    _phones = List<BusinessCardPhone>.from(widget.cardData.phoneNumbers);
    _emails = List<BusinessCardEmail>.from(widget.cardData.emailAddresses);

    _nameController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _jobTitleController.dispose();
    _companyController.dispose();
    _websiteController.dispose();
    _addressController.dispose();
    _rememberController.dispose();
    _jobTitleFocusNode.dispose();
    _companyFocusNode.dispose();
    super.dispose();
  }

  BusinessCardData _buildUpdatedData() {
    final updatedEvidence = Map<String, FieldEvidence>.from(widget.cardData.fieldEvidence);

    void applyUserEdit(String fieldName, String? updatedVal) {
      if (updatedVal != null && updatedVal.isNotEmpty) {
        final existing = updatedEvidence[fieldName];
        final originalCandidate = existing?.normalizedValue ?? '';
        final isUserEdited = originalCandidate.isNotEmpty && originalCandidate != updatedVal;
        updatedEvidence[fieldName] = FieldEvidence(
          fieldName: fieldName,
          originalOcrText: existing?.originalOcrText ?? updatedVal,
          normalizedValue: existing?.normalizedValue ?? updatedVal,
          sourceEngine: existing?.sourceEngine ?? 'UserConfirmed',
          sourceObservationIds: existing?.sourceObservationIds ?? const [],
          boundingBoxes: existing?.boundingBoxes ?? const [],
          ocrConfidence: existing?.ocrConfidence ?? 1.0,
          parserConfidence: 1.0,
          verificationStatus: FieldVerificationStatus.verified,
          userApprovedValue: updatedVal,
          verificationSource: isUserEdited ? 'userManualEdit' : (existing?.verificationSource ?? 'userConfirmed'),
          verifiedAt: DateTime.now().toUtc(),
          side: existing?.side ?? CardSide.front,
          processingVersion: '4.0.0',
        );
      }
    }

    applyUserEdit('fullName', _nameController.text.trim().isEmpty ? null : _nameController.text.trim());
    applyUserEdit('company', (!_showCompanyField || _companyController.text.trim().isEmpty) ? null : _companyController.text.trim());
    applyUserEdit('jobTitle', (!_showJobTitleField || _jobTitleController.text.trim().isEmpty) ? null : _jobTitleController.text.trim());
    applyUserEdit('website', _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim());
    applyUserEdit('address', _addressController.text.trim().isEmpty ? null : _addressController.text.trim());

    return BusinessCardData(
      fullName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      jobTitle: (!_showJobTitleField || _jobTitleController.text.trim().isEmpty)
          ? null
          : _jobTitleController.text.trim(),
      company: (!_showCompanyField || _companyController.text.trim().isEmpty)
          ? null
          : _companyController.text.trim(),
      phoneNumbers: _phones.where((p) => p.number.trim().isNotEmpty).toList(),
      emailAddresses: _emails.where((e) => e.email.trim().isNotEmpty).toList(),
      website: _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      rawRecognizedText: widget.cardData.rawRecognizedText,
      alternativeCandidates: widget.cardData.alternativeCandidates,
      parsingNotes: widget.cardData.parsingNotes,
      fieldEvidence: updatedEvidence,
      fieldConfidenceStates: widget.cardData.fieldConfidenceStates,
      isDualSided: widget.cardData.isDualSided,
      frontRawText: widget.cardData.frontRawText,
      backRawText: widget.cardData.backRawText,
    );
  }

  Future<void> _handleSave() async {
    final updated = _buildUpdatedData();

    if (widget.contactService == null) {
      // Local confirmation fallback (e.g., Phase 5A tests or offline review)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Business card details confirmed!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(updated);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final phoneNumbers = updated.phoneNumbers.map((p) => p.number.trim()).toList();
      final emailAddresses = updated.emailAddresses.map((e) => e.email.trim()).toList();

      // 1. Duplicate check
      final dupResult = widget.userId != null
          ? await widget.contactService!.checkDuplicateForUser(
              phoneNumbers: phoneNumbers,
              emailAddresses: emailAddresses,
              userId: widget.userId,
            )
          : await widget.contactService!.checkDuplicate(
              phoneNumbers: phoneNumbers,
              emailAddresses: emailAddresses,
            );

      if (!mounted) return;

      if (dupResult.isDuplicate && dupResult.existingContact != null) {
        setState(() {
          _isSaving = false;
        });
        // Show Already Saved dialog with update and details options
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Already Saved'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('This business card/contact is already saved in Digital Share.'),
                SizedBox(height: 8),
                Text('Would you like to update the existing contact or view details?'),
              ],
            ),
            actions: [
              TextButton(
                key: const Key('duplicate_dialog_ok_button'),
                onPressed: () => Navigator.of(ctx).pop('cancel'),
                child: const Text('OK'),
              ),
              TextButton(
                key: const Key('duplicate_dialog_update_button'),
                onPressed: () => Navigator.of(ctx).pop('update'),
                child: const Text('Update Existing'),
              ),
              FilledButton(
                key: const Key('duplicate_dialog_show_details_button'),
                onPressed: () => Navigator.of(ctx).pop('details'),
                child: const Text('Show Details'),
              ),
            ],
          ),
        );

        if (action == 'update' && mounted) {
          setState(() {
            _isSaving = true;
          });
          final memory = _rememberController.text.trim();
          final contactData = {
            'fullName': updated.fullName,
            'company': updated.company,
            'jobTitle': updated.jobTitle,
            'website': updated.website,
            'address': updated.address,
            if (memory.isNotEmpty) 'rememberThisContact': memory,
            if (memory.isNotEmpty) 'personalRemark': memory,
            'phoneNumbers': updated.phoneNumbers
                .map((p) => {
                      'number': p.number,
                      'label': p.label,
                    })
                .toList(),
            'emailAddresses': updated.emailAddresses
                .map((e) => {
                      'email': e.email,
                      'label': e.label,
                    })
                .toList(),
          };
          await widget.contactService!.updateContact(
            dupResult.existingContact!.id,
            contactData,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Contact details updated!'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            Navigator.of(context).pop(updated);
          }
        } else if (action == 'details' && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ImportedContactDetailsScreen(
                contact: dupResult.existingContact!,
                contactService: widget.contactService,
                communicationService: widget.communicationService,
                phoneContactService: widget.phoneContactService,
              ),
            ),
          );
        }
        return;
      }

      // 2. Not a duplicate -> Save API / Local Database
      final memory = _rememberController.text.trim();

      String effectiveUserId = widget.userId ?? 'default_user';
      final bool isTestBinding =
          WidgetsBinding.instance.runtimeType.toString().contains('Test') ||
              Platform.environment.containsKey('FLUTTER_TEST');
      if (widget.userId == null && !isTestBinding) {
        try {
          final storedUid = await SecureStorageService().getUserId();
          if (storedUid != null && storedUid.isNotEmpty) {
            effectiveUserId = storedUid;
          } else {
            effectiveUserId = await SecureStorageService().getAnonymousInstallId();
          }
        } catch (_) {}
      }

      final contactData = {
        'fullName': updated.fullName,
        'company': updated.company,
        'jobTitle': updated.jobTitle,
        'website': updated.website,
        'address': updated.address,
        'userId': effectiveUserId,
        if (memory.isNotEmpty) 'rememberThisContact': memory,
        if (memory.isNotEmpty) 'personalRemark': memory,
        'phoneNumbers': updated.phoneNumbers
            .map((p) => {
                  'number': p.number,
                  'label': p.label,
                })
            .toList(),
        'emailAddresses': updated.emailAddresses
            .map((e) => {
                  'email': e.email,
                  'label': e.label,
                })
            .toList(),
      };

      await widget.contactService!.saveContact(
        contactData,
        imageFingerprint: widget.imageFingerprint,
        imageDHash: widget.imageDHash,
        frontImagePath: widget.frontImagePath,
        backImagePath: widget.backImagePath,
        rawRecognizedText: updated.rawRecognizedText,
        frontRawText: widget.cardData.frontRawText ?? updated.rawRecognizedText,
        backRawText: widget.cardData.backRawText,
        frontObservations: widget.frontObservations,
        backObservations: widget.backObservations,
        ocrEngineName: widget.ocrEngineName,
        overallOcrConfidence: widget.overallOcrConfidence,
        fieldEvidence: updated.fieldEvidence,
        parserVersion: '5.0.0',
        preprocessingVersion: '1.0.0',
      );

      // Stage 5: Record user-approved manual corrections for local on-device learning
      if (widget.learningService != null && widget.imageFingerprint != null) {
        for (final entry in updated.fieldEvidence.entries) {
          if (entry.value.isUserEdited) {
            await widget.learningService!.recordUserCorrection(
              imageFingerprint: widget.imageFingerprint!,
              fieldName: entry.key,
              originalExtractedValue: entry.value.originalOcrText,
              approvedValue: entry.value.effectiveValue,
              userId: effectiveUserId,
              source: 'userManualEdit',
            );
          }
        }
      }

      if (kDebugMode && !Platform.environment.containsKey('FLUTTER_TEST')) {
        try {
          final pending = await widget.contactService!.syncQueue.getPendingOperations();
          debugPrint('[Save Diagnostics] Contact Saved Locally. Pending Sync Operations: ${pending.length}');
        } catch (_) {}
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved in Digital Share!'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Redirect and return saved card data
      Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save contact. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildFieldStatusBadge(String fieldKey, String? value) {
    if (value == null || value.trim().isEmpty) {
      return Text(
        'Not detected',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
              fontStyle: FontStyle.italic,
            ),
      );
    }
    final state = widget.cardData.fieldConfidenceStates[fieldKey];
    if (state == 'highConfidence') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, size: 12, color: Colors.green),
            const SizedBox(width: 4),
            Text(
              'Detected',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.green.shade800,
              ),
            ),
          ],
        ),
      );
    }
    // Any field that is not highConfidence (uncertain, unverified, or missing) shows "Please verify"
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.amber.shade700, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 12, color: Colors.amber.shade800),
          const SizedBox(width: 4),
          Text(
            'Please verify',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.amber.shade900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, top: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.xs + 2),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCroppedCardPreview(ThemeData theme) {
    final frontPath = widget.frontImagePath;
    final backPath = widget.backImagePath;

    final hasFront = frontPath != null && File(frontPath).existsSync();
    final hasBack = backPath != null && File(backPath).existsSync();

    if (!hasFront && !hasBack) return const SizedBox.shrink();

    final bool isTest = Platform.environment.containsKey('FLUTTER_TEST') ||
        WidgetsBinding.instance.runtimeType.toString().contains('Test');

    Widget buildImage(String path, String label) {
      if (isTest) {
        final sideKey = label.toLowerCase().contains('front') ? 'front' : 'back';
        return Container(
          key: Key('cropped_card_$sideKey'),
          height: 140,
          color: theme.colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.crop_rounded, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '$label (Cropped)',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }

      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: Center(
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.crop_rounded, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '$label (Cropped)',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: Row(
              children: [
                Icon(
                  Icons.crop_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  hasBack ? 'Cropped Card Images' : 'Cropped Card Image',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Background Removed',
                    style: TextStyle(
                      color: Color(0xFF047857),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasFront) buildImage(frontPath, 'Front Card Image'),
          if (hasBack) ...[
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                'Back Side',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            buildImage(backPath, 'Back Card Image'),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Card Details'),
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cropped Business Card Preview (Table/room background removed)
            _buildCroppedCardPreview(theme),

            // Header hint banner
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
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
                    widget.cardData.isDualSided
                        ? Icons.flip_to_back_rounded
                        : Icons.info_outline_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      widget.cardData.isDualSided
                          ? 'Dual-sided card recognized (Front + Back). Please verify details.'
                          : 'Please verify and edit the recognized details before confirming.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.cardData.parsingNotes.any((n) => n.contains('Gemini AI') || n.contains('[Review Warning]'))) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                  borderRadius: AppSpacing.radiusMd,
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Interpretation Applied',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ...widget.cardData.parsingNotes
                              .where((n) => n.contains('Gemini AI') || n.contains('[Review Warning]'))
                              .map(
                                (note) => Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    note,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),

            // SECTION 1: PERSON
            _buildSectionHeader(context, 'PERSON', Icons.person_outline_rounded),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: AppSpacing.radiusLg,
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant,
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
                        Expanded(
                          child: Text(
                            'Name',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildFieldStatusBadge('fullName', _nameController.text),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: const Key('review_name_field'),
                      controller: _nameController,
                      decoration: const InputDecoration(
                        hintText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    if (_showJobTitleField) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Job Title',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildFieldStatusBadge('jobTitle', _jobTitleController.text),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: const Key('review_job_title_field'),
                        controller: _jobTitleController,
                        focusNode: _jobTitleFocusNode,
                        decoration: const InputDecoration(
                          hintText: 'Job Title',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('add_job_title_button'),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('+ Add Job Title'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onPressed: () {
                            setState(() {
                              _showJobTitleField = true;
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _jobTitleFocusNode.requestFocus();
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    if (_showCompanyField) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Company',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildFieldStatusBadge('company', _companyController.text),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: const Key('review_company_field'),
                        controller: _companyController,
                        focusNode: _companyFocusNode,
                        decoration: const InputDecoration(
                          hintText: 'Company or Organization',
                          prefixIcon: Icon(Icons.business_outlined),
                        ),
                      ),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('add_company_button'),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('+ Add Company'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onPressed: () {
                            setState(() {
                              _showCompanyField = true;
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _companyFocusNode.requestFocus();
                            });
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // SECTION 2: CONTACT
            _buildSectionHeader(context, 'CONTACT', Icons.contact_phone_outlined),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.xs),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Detected (${_phones.length} phones, ${_emails.length} emails)',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: AppSpacing.radiusLg,
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  children: [
                    BusinessCardPhoneEditor(
                      initialPhones: _phones,
                      onChanged: (updatedPhones) {
                        setState(() {
                          _phones = updatedPhones;
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const Divider(),
                    const SizedBox(height: AppSpacing.md),
                    BusinessCardEmailEditor(
                      initialEmails: _emails,
                      onChanged: (updatedEmails) {
                        setState(() {
                          _emails = updatedEmails;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // SECTION 3: ADDITIONAL INFORMATION
            _buildSectionHeader(context, 'ADDITIONAL INFORMATION', Icons.info_outline_rounded),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: AppSpacing.radiusLg,
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant,
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
                        Expanded(
                          child: Text(
                            'Website',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildFieldStatusBadge('website', _websiteController.text),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: const Key('review_website_field'),
                      controller: _websiteController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        hintText: 'https://...',
                        prefixIcon: Icon(Icons.language_rounded),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Address',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildFieldStatusBadge('address', _addressController.text),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: const Key('review_address_field'),
                      controller: _addressController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Address',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),



            // SECTION 4: FOLLOW UP
            _buildSectionHeader(context, 'FOLLOW UP', Icons.send_rounded),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: AppSpacing.radiusLg,
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: ContactMessageComposer(
                  fullName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
                  company: _companyController.text.trim().isEmpty ? null : _companyController.text.trim(),
                  jobTitle: _jobTitleController.text.trim().isEmpty ? null : _jobTitleController.text.trim(),
                  website: _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim(),
                  address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
                  phones: _phones,
                  emails: _emails,
                  communicationService: widget.communicationService,
                  contactService: widget.phoneContactService,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // SECTION: REMEMBER THIS CONTACT
            _buildSectionHeader(context, 'REMEMBER THIS CONTACT', Icons.lightbulb_outline_rounded),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: AppSpacing.radiusLg,
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Remember This Contact',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Add a small detail so you can find them later, even if you forget their name.',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0, right: 8.0),
                            child: Icon(
                              Icons.edit_note_rounded,
                              size: 24,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              key: const Key('remember_this_contact_input'),
                              controller: _rememberController,
                              minLines: 2,
                              maxLines: 4,
                              maxLength: 2000,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Example: Met at a coffee shop in Austin.',
                                hintStyle: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                counterText: '',
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_rememberController.text.length}/2000',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // SECTION 5: ACTIONS
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                key: const Key('confirm_details_button'),
                icon: _isSaving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline_rounded),
                label: Text(
                  _isSaving
                      ? 'Saving...'
                      : (widget.contactService != null
                          ? 'Save in Digital Share'
                          : 'Confirm Details'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _isSaving ? null : _handleSave,
              ),
            ),
            const SizedBox(height: AppSpacing.xxxl),
            const MedindiaBrandingFooter(showDivider: true),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
