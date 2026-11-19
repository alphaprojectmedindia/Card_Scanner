import 'package:flutter/material.dart';
import '../../models/business_card_email.dart';
import '../../models/business_card_phone.dart';
import '../../models/imported_contact.dart';
import '../../services/api_client.dart';
import '../../services/contact_communication_service.dart';
import '../../services/contact_service.dart';
import '../../services/imported_contact_service.dart';
import '../../services/ocr/contact_reprocessing_service.dart';
import '../../services/ocr/ml_kit_ocr_engine.dart';
import '../../services/ocr/paddle_ocr_engine.dart';
import '../../widgets/contact_message_composer.dart';
import '../../widgets/historical_reprocess_diff_dialog.dart';
import '../../widgets/medindia_branding_footer.dart';
import 'edit_imported_contact_screen.dart';

class ImportedContactDetailsScreen extends StatefulWidget {
  final ImportedContact contact;
  final ImportedContactService? contactService;
  final IContactCommunicationService? communicationService;
  final IContactService? phoneContactService;

  const ImportedContactDetailsScreen({
    super.key,
    required this.contact,
    this.contactService,
    this.communicationService,
    this.phoneContactService,
  });

  @override
  State<ImportedContactDetailsScreen> createState() =>
      _ImportedContactDetailsScreenState();
}

class _ImportedContactDetailsScreenState
    extends State<ImportedContactDetailsScreen> {
  late ImportedContact _contact;
  late final ImportedContactService _contactService;
  bool _isDeleting = false;
  bool _isReprocessing = false;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    _contactService = widget.contactService ?? ImportedContactService();
  }

  Future<void> _handleReprocessCard() async {
    final record = await _contactService.localRepository.getRecordById(_contact.id);
    if (record == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contact not found in local storage.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final imageStorage = _contactService.localRepository.imageStorageService;
    final hasFront = await imageStorage.verifyImageFile(record.frontImagePath);
    final hasBack = await imageStorage.verifyImageFile(record.backImagePath);

    if (!hasFront && !hasBack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Original card images are missing or not stored locally.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isReprocessing = true;
    });

    try {
      final reprocessor = ContactReprocessingService(
        imageStorageService: imageStorage,
      );

      final diff = await reprocessor.reprocessHistoricalContact(
        record: record,
        primaryEngine: PaddleOcrEngine(),
        secondaryEngine: MlKitOcrEngine(),
        learningService: _contactService.localRepository.learningService,
        userId: record.userId,
      );

      if (!mounted) return;

      if (!diff.wasReprocessed || !diff.hasChanges) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Card details are already verified and up to date.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      await showDialog<String>(
        context: context,
        builder: (ctx) => HistoricalReprocessDiffDialog(
          originalRecord: record,
          diff: diff,
          onAccept: (acceptedFields) async {
            final updated = await reprocessor.applyApprovedHistoricalDiff(
              record: record,
              diff: diff,
              acceptedFieldNames: acceptedFields,
              learningService: _contactService.localRepository.learningService,
              userId: record.userId,
            );
            await _contactService.localRepository.updateLocalRecord(updated);
            if (mounted) {
              setState(() {
                _contact = updated.toImportedContact();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Card details updated from re-OCR!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reprocessing failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isReprocessing = false;
        });
      }
    }
  }

  Future<void> _handleDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Business Card'),
        content: Text(
          'Are you sure you want to delete ${_contact.displayName} from your saved business cards?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      await _contactService.deleteContact(_contact.id);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted ${_contact.displayName}.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(context).pop(true); // Return deleted flag
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
          content: Text('Failed to delete contact. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  Future<void> _handleEdit() async {
    final updated = await Navigator.of(context).push<ImportedContact>(
      MaterialPageRoute(
        builder: (_) => EditImportedContactScreen(
          contact: _contact,
          contactService: _contactService,
        ),
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        _contact = updated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Details'),
        actions: [
          IconButton(
            key: const Key('reprocess_card_button'),
            icon: const Icon(Icons.auto_fix_high_rounded),
            tooltip: 'Reprocess Card with OCR',
            onPressed: _isReprocessing || _isDeleting ? null : _handleReprocessCard,
          ),
          IconButton(
            key: const Key('edit_imported_contact_button'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit details',
            onPressed: _isReprocessing || _isDeleting ? null : _handleEdit,
          ),
          IconButton(
            key: const Key('delete_imported_contact_button'),
            icon: Icon(Icons.delete_outline_rounded,
                color: theme.colorScheme.error),
            tooltip: 'Delete contact',
            onPressed: _isReprocessing || _isDeleting ? null : _handleDelete,
          ),
        ],
      ),
      body: _isDeleting || _isReprocessing
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_isDeleting
                      ? 'Deleting card...'
                      : 'Reprocessing card with on-device OCR...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Contact Profile Card Header
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor:
                              theme.colorScheme.primaryContainer,
                          child: Text(
                            _contact.initials,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _contact.displayName,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (_contact.jobTitle != null &&
                            _contact.jobTitle!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _contact.company != null &&
                                    _contact.company!.isNotEmpty
                                ? '${_contact.jobTitle} • ${_contact.company}'
                                : _contact.jobTitle!,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ] else if (_contact.company != null &&
                            _contact.company!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _contact.company!,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Phone Numbers Section
                  if (_contact.phoneNumbers.isNotEmpty) ...[
                    _buildSectionHeader(context, 'PHONE NUMBERS'),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: _contact.phoneNumbers.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final phone = entry.value;
                          final isLast = idx == _contact.phoneNumbers.length - 1;

                          return Column(
                            children: [
                              ListTile(
                                leading: Icon(Icons.phone_outlined,
                                    color: theme.colorScheme.primary),
                                title: Text(phone.number),
                                subtitle: phone.label != null &&
                                        phone.label!.isNotEmpty
                                    ? Text(phone.label!)
                                    : null,
                              ),
                              if (!isLast) const Divider(height: 1, indent: 56),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Email Addresses Section
                  if (_contact.emailAddresses.isNotEmpty) ...[
                    _buildSectionHeader(context, 'EMAIL ADDRESSES'),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: _contact.emailAddresses.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final email = entry.value;
                          final isLast = idx == _contact.emailAddresses.length - 1;

                          return Column(
                            children: [
                              ListTile(
                                leading: Icon(Icons.email_outlined,
                                    color: theme.colorScheme.primary),
                                title: Text(email.email),
                                subtitle: email.label != null &&
                                        email.label!.isNotEmpty
                                    ? Text(email.label!)
                                    : null,
                              ),
                              if (!isLast) const Divider(height: 1, indent: 56),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Website Section
                  if (_contact.website != null &&
                      _contact.website!.isNotEmpty) ...[
                    _buildSectionHeader(context, 'WEBSITE'),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.language_rounded,
                            color: theme.colorScheme.primary),
                        title: Text(_contact.website!),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Address Section
                  if (_contact.address != null &&
                      _contact.address!.isNotEmpty) ...[
                    _buildSectionHeader(context, 'ADDRESS'),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.location_on_outlined,
                            color: theme.colorScheme.primary),
                        title: Text(_contact.address!),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Personal Remark Section
                  _buildSectionHeader(context, 'MY PERSONAL REMARK'),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Private Note',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                key: const Key('edit_remark_button'),
                                icon: Icon(
                                  _contact.effectiveMemory != null &&
                                          _contact.effectiveMemory!.isNotEmpty
                                      ? Icons.edit_outlined
                                      : Icons.add_comment_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                  _contact.effectiveMemory != null &&
                                          _contact.effectiveMemory!.isNotEmpty
                                      ? 'Edit'
                                      : 'Add Remark',
                                ),
                                onPressed: () => _showEditRemarkDialog(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _contact.effectiveMemory != null &&
                                    _contact.effectiveMemory!.isNotEmpty
                                ? _contact.effectiveMemory!
                                : 'No personal remark added yet.',
                            key: const Key('contact_details_personal_remark_text'),
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              fontStyle: _contact.effectiveMemory != null &&
                                      _contact.effectiveMemory!.isNotEmpty
                                  ? FontStyle.normal
                                  : FontStyle.italic,
                              color: _contact.effectiveMemory != null &&
                                      _contact.effectiveMemory!.isNotEmpty
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  const SizedBox(height: 10),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Message Composer & Communication Section (Phase 5C)
                  ContactMessageComposer(
                    fullName: _contact.fullName,
                    company: _contact.company,
                    jobTitle: _contact.jobTitle,
                    website: _contact.website,
                    address: _contact.address,
                    phones: _contact.phoneNumbers
                        .map((p) => BusinessCardPhone(
                              number: p.number,
                              label: p.label,
                            ))
                        .toList(),
                    emails: _contact.emailAddresses
                        .map((e) => BusinessCardEmail(
                              email: e.email,
                              label: e.label,
                            ))
                        .toList(),
                    communicationService: widget.communicationService,
                    contactService: widget.phoneContactService,
                  ),
                  const SizedBox(height: 24),
                  const MedindiaBrandingFooter(showDivider: true),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }

  Future<void> _showEditRemarkDialog(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final textController =
        TextEditingController(text: _contact.effectiveMemory ?? '');
    final bool hasExisting =
        _contact.effectiveMemory != null && _contact.effectiveMemory!.isNotEmpty;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final charCount = textController.text.length;
            return AlertDialog(
              title: const Text('My Personal Remark'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add a nickname or a note to help you remember this person. Strictly private to you.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('edit_remark_input'),
                    controller: textController,
                    maxLength: 2000,
                    maxLines: 4,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText:
                          'e.g., Met at Chennai conference, referred by Rajesh...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      counterText: '$charCount / 2000',
                    ),
                  ),
                ],
              ),
              actions: [
                if (hasExisting)
                  TextButton(
                    key: const Key('clear_remark_button'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      try {
                        final updated =
                            await _contactService.clearRemark(_contact.id);
                        if (mounted) {
                          setState(() {
                            _contact = updated;
                          });
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Remark removed.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Failed to clear remark: $e'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Clear'),
                  ),
                TextButton(
                  key: const Key('cancel_remark_button'),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const Key('save_remark_button'),
                  onPressed: () async {
                    final text = textController.text.trim();
                    Navigator.of(ctx).pop();
                    try {
                      final updated = text.isNotEmpty
                          ? await _contactService.updateRemark(_contact.id, text)
                          : await _contactService.clearRemark(_contact.id);
                      if (mounted) {
                        setState(() {
                          _contact = updated;
                        });
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Remark updated.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Failed to update remark: $e'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
