import 'package:flutter/material.dart';
import '../../models/business_card_email.dart';
import '../../models/business_card_phone.dart';
import '../../models/imported_contact.dart';
import '../../services/api_client.dart';
import '../../services/contact_communication_service.dart';
import '../../services/contact_service.dart';
import '../../services/imported_contact_service.dart';
import '../../widgets/contact_message_composer.dart';
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

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    _contactService = widget.contactService ?? ImportedContactService();
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
            key: const Key('edit_imported_contact_button'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit details',
            onPressed: _handleEdit,
          ),
          IconButton(
            key: const Key('delete_imported_contact_button'),
            icon: Icon(Icons.delete_outline_rounded,
                color: theme.colorScheme.error),
            tooltip: 'Delete contact',
            onPressed: _handleDelete,
          ),
        ],
      ),
      body: _isDeleting
          ? const Center(child: CircularProgressIndicator())
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
}
