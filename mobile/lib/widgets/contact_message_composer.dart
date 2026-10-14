import 'package:flutter/material.dart';
import '../models/business_card_email.dart';
import '../models/business_card_phone.dart';
import '../models/contact_communication_data.dart';
import '../models/shared_profile.dart';
import '../services/contact_communication_service.dart';
import '../services/contact_service.dart';
import 'country_code_dialog.dart';
import 'email_selection_dialog.dart';
import 'phone_selection_dialog.dart';

class ContactMessageComposer extends StatefulWidget {
  final String? fullName;
  final String? company;
  final String? jobTitle;
  final String? website;
  final String? address;
  final List<BusinessCardPhone> phones;
  final List<BusinessCardEmail> emails;
  final String? sectionTitle;
  final bool showAddToContacts;
  final IContactCommunicationService? communicationService;
  final IContactService? contactService;
  final TextEditingController? messageController;

  const ContactMessageComposer({
    super.key,
    this.fullName,
    this.company,
    this.jobTitle,
    this.website,
    this.address,
    required this.phones,
    required this.emails,
    this.sectionTitle = 'Message',
    this.showAddToContacts = true,
    this.communicationService,
    this.contactService,
    this.messageController,
  });

  /// Factory creating composer directly from a registered Digital Share profile.
  factory ContactMessageComposer.fromSharedProfile({
    Key? key,
    required SharedProfile profile,
    String? sectionTitle = 'FOLLOW UP',
    bool showAddToContacts = false,
    IContactCommunicationService? communicationService,
    IContactService? contactService,
    TextEditingController? messageController,
  }) {
    final commData = ContactCommunicationData.fromSharedProfile(profile);
    return ContactMessageComposer(
      key: key,
      fullName: commData.displayName,
      company: commData.company,
      jobTitle: commData.jobTitle,
      website: commData.website,
      address: commData.address,
      phones: commData.phones,
      emails: commData.emails,
      sectionTitle: sectionTitle,
      showAddToContacts: showAddToContacts,
      communicationService: communicationService,
      contactService: contactService,
      messageController: messageController,
    );
  }

  /// Factory creating composer directly from a ContactCommunicationData DTO.
  factory ContactMessageComposer.fromContactData({
    Key? key,
    required ContactCommunicationData contactData,
    String? sectionTitle = 'FOLLOW UP',
    bool showAddToContacts = false,
    IContactCommunicationService? communicationService,
    IContactService? contactService,
    TextEditingController? messageController,
  }) {
    return ContactMessageComposer(
      key: key,
      fullName: contactData.displayName,
      company: contactData.company,
      jobTitle: contactData.jobTitle,
      website: contactData.website,
      address: contactData.address,
      phones: contactData.phones,
      emails: contactData.emails,
      sectionTitle: sectionTitle,
      showAddToContacts: showAddToContacts,
      communicationService: communicationService,
      contactService: contactService,
      messageController: messageController,
    );
  }

  @override
  State<ContactMessageComposer> createState() => _ContactMessageComposerState();
}

class _ContactMessageComposerState extends State<ContactMessageComposer> {
  late final TextEditingController _messageController;
  late final bool _internalController;
  late final IContactCommunicationService _communicationService;
  late final IContactService _contactService;

  bool _isSavingContact = false;

  @override
  void initState() {
    super.initState();
    if (widget.messageController != null) {
      _messageController = widget.messageController!;
      _internalController = false;
    } else {
      final defaultMsg =
          ContactCommunicationService.getDefaultMessage(widget.fullName);
      _messageController = TextEditingController(text: defaultMsg);
      _internalController = true;
    }

    _communicationService =
        widget.communicationService ?? const ContactCommunicationService();
    _contactService = widget.contactService ?? ContactService();
  }

  @override
  void dispose() {
    if (_internalController) {
      _messageController.dispose();
    }
    super.dispose();
  }

  Future<void> _handleWhatsApp() async {
    final validPhones =
        widget.phones.where((p) => p.number.trim().isNotEmpty).toList();

    if (validPhones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No phone number is available for this contact.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    String? selectedNumber;
    if (validPhones.length == 1) {
      selectedNumber = validPhones.first.number;
    } else {
      selectedNumber = await showDialog<String>(
        context: context,
        builder: (ctx) => PhoneSelectionDialog(phones: validPhones),
      );
    }

    if (selectedNumber == null || !mounted) return;

    // Check if selected number includes an international country code
    String targetPhone = selectedNumber;
    if (!ContactCommunicationService.hasCountryCode(selectedNumber)) {
      final confirmedPhone = await showDialog<String>(
        context: context,
        builder: (ctx) => CountryCodeDialog(phoneNumber: selectedNumber!),
      );
      if (confirmedPhone == null || !mounted) return;
      targetPhone = confirmedPhone;
    }

    final success = await _communicationService.openWhatsApp(
      phone: targetPhone,
      message: _messageController.text,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open WhatsApp for this number.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleEmail() async {
    final validEmails =
        widget.emails.where((e) => e.email.trim().isNotEmpty).toList();

    if (validEmails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email address is available for this contact.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    String? selectedEmail;
    if (validEmails.length == 1) {
      selectedEmail = validEmails.first.email;
    } else {
      selectedEmail = await showDialog<String>(
        context: context,
        builder: (ctx) => EmailSelectionDialog(emails: validEmails),
      );
    }

    if (selectedEmail == null || !mounted) return;

    final success = await _communicationService.openEmail(
      email: selectedEmail,
      subject: 'Great meeting you',
      body: _messageController.text,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open an email application on this device.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleAddToContacts() async {
    setState(() {
      _isSavingContact = true;
    });

    try {
      var result = await _contactService.saveBusinessCardToPhone(
        fullName: widget.fullName,
        company: widget.company,
        jobTitle: widget.jobTitle,
        website: widget.website,
        address: widget.address,
        phones: widget.phones,
        emails: widget.emails,
        force: false,
      );

      if (!mounted) return;

      if (result.status == ContactSaveStatus.duplicateFound) {
        final addAnyway = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Contact May Already Exist'),
            content: const Text('This contact may already exist on your phone.'),
            actions: [
              TextButton(
                key: const Key('cancel_phone_duplicate_button'),
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('add_anyway_phone_duplicate_button'),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Add Anyway'),
              ),
            ],
          ),
        );

        if (addAnyway == true && mounted) {
          result = await _contactService.saveBusinessCardToPhone(
            fullName: widget.fullName,
            company: widget.company,
            jobTitle: widget.jobTitle,
            website: widget.website,
            address: widget.address,
            phones: widget.phones,
            emails: widget.emails,
            force: true,
          );
        } else {
          return;
        }
      }

      if (!mounted) return;

      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact added to your phone.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingContact = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.edit_note_rounded,
                size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              widget.sectionTitle ?? 'Message',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Message text input
        TextFormField(
          key: const Key('contact_message_field'),
          controller: _messageController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Enter your message...',
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        const SizedBox(height: 14),

        // Action Buttons Row: WhatsApp & Email
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                key: const Key('whatsapp_action_button'),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('WhatsApp'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _handleWhatsApp,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                key: const Key('email_action_button'),
                icon: const Icon(Icons.mail_outline_rounded),
                label: const Text('Email'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _handleEmail,
              ),
            ),
          ],
        ),

        // Add to Contacts Action (conditionally rendered)
        if (widget.showAddToContacts) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              key: const Key('add_to_contacts_action_button'),
              icon: _isSavingContact
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded),
              label: Text(
                _isSavingContact ? 'Saving...' : 'Add to Contacts',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isSavingContact ? null : _handleAddToContacts,
            ),
          ),
        ],
      ],
    );
  }
}
