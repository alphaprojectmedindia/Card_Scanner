import 'package:flutter/material.dart';
import '../../models/business_card_data.dart';
import '../../models/business_card_email.dart';
import '../../models/business_card_phone.dart';
import '../../services/api_client.dart';
import '../../services/contact_communication_service.dart';
import '../../services/contact_service.dart';
import '../../services/imported_contact_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/business_card_email_editor.dart';
import '../../widgets/business_card_phone_editor.dart';
import '../../widgets/contact_message_composer.dart';
import '../connections/imported_contact_details_screen.dart';

class BusinessCardReviewScreen extends StatefulWidget {
  final BusinessCardData cardData;
  final ImportedContactService? contactService;
  final IContactCommunicationService? communicationService;
  final IContactService? phoneContactService;

  const BusinessCardReviewScreen({
    super.key,
    required this.cardData,
    this.contactService,
    this.communicationService,
    this.phoneContactService,
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

    _phones = List<BusinessCardPhone>.from(widget.cardData.phoneNumbers);
    _emails = List<BusinessCardEmail>.from(widget.cardData.emailAddresses);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _jobTitleController.dispose();
    _companyController.dispose();
    _websiteController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  BusinessCardData _buildUpdatedData() {
    return BusinessCardData(
      fullName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      jobTitle: _jobTitleController.text.trim().isEmpty ? null : _jobTitleController.text.trim(),
      company: _companyController.text.trim().isEmpty ? null : _companyController.text.trim(),
      phoneNumbers: _phones.where((p) => p.number.trim().isNotEmpty).toList(),
      emailAddresses: _emails.where((e) => e.email.trim().isNotEmpty).toList(),
      website: _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      rawRecognizedText: widget.cardData.rawRecognizedText,
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
      final dupResult = await widget.contactService!.checkDuplicate(
        phoneNumbers: phoneNumbers,
        emailAddresses: emailAddresses,
      );

      if (!mounted) return;

      if (dupResult.isDuplicate && dupResult.existingContact != null) {
        setState(() {
          _isSaving = false;
        });
        // Show Already Saved dialog
        final showDetails = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Already Saved'),
            content: const Text(
              'This business card/contact is already saved in Digital Share.',
            ),
            actions: [
              TextButton(
                key: const Key('duplicate_dialog_ok_button'),
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('OK'),
              ),
              FilledButton(
                key: const Key('duplicate_dialog_show_details_button'),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Show Details'),
              ),
            ],
          ),
        );

        if (showDetails == true && mounted) {
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

      // 2. Not a duplicate -> Save API
      final contactData = {
        'fullName': updated.fullName,
        'company': updated.company,
        'jobTitle': updated.jobTitle,
        'website': updated.website,
        'address': updated.address,
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

      await widget.contactService!.saveContact(contactData);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved in Digital Share!'),
          behavior: SnackBarBehavior.floating,
        ),
      );

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

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, top: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.xs + 2),
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: theme.colorScheme.primary,
            ),
          ),
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
                    Icons.info_outline_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Please verify and edit the recognized details before confirming.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                    Text(
                      'Name',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
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

                    Text(
                      'Job Title',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: const Key('review_job_title_field'),
                      controller: _jobTitleController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Senior Developer',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    Text(
                      'Company',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: const Key('review_company_field'),
                      controller: _companyController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. ABC Technologies',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // SECTION 2: CONTACT
            _buildSectionHeader(context, 'CONTACT', Icons.contact_phone_outlined),
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
                    Text(
                      'Website',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: const Key('review_website_field'),
                      controller: _websiteController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        hintText: 'e.g. https://example.com',
                        prefixIcon: Icon(Icons.language_rounded),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    Text(
                      'Address',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: const Key('review_address_field'),
                      controller: _addressController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Chennai, Tamil Nadu',
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
          ],
        ),
      ),
    );
  }
}
