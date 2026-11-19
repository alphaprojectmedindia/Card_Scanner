import 'package:flutter/material.dart';
import '../../models/business_card_email.dart';
import '../../models/business_card_phone.dart';
import '../../models/imported_contact.dart';
import '../../services/api_client.dart';
import '../../services/imported_contact_service.dart';
import '../../widgets/business_card_email_editor.dart';
import '../../widgets/business_card_phone_editor.dart';

class EditImportedContactScreen extends StatefulWidget {
  final ImportedContact contact;
  final ImportedContactService? contactService;

  const EditImportedContactScreen({
    super.key,
    required this.contact,
    this.contactService,
  });

  @override
  State<EditImportedContactScreen> createState() =>
      _EditImportedContactScreenState();
}

class _EditImportedContactScreenState extends State<EditImportedContactScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _jobTitleController;
  late final TextEditingController _companyController;
  late final TextEditingController _websiteController;
  late final TextEditingController _addressController;

  late List<BusinessCardPhone> _phones;
  late List<BusinessCardEmail> _emails;

  late final ImportedContactService _contactService;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _contactService = widget.contactService ?? ImportedContactService();

    _nameController =
        TextEditingController(text: widget.contact.fullName ?? '');
    _jobTitleController =
        TextEditingController(text: widget.contact.jobTitle ?? '');
    _companyController =
        TextEditingController(text: widget.contact.company ?? '');
    _websiteController =
        TextEditingController(text: widget.contact.website ?? '');
    _addressController =
        TextEditingController(text: widget.contact.address ?? '');

    _phones = widget.contact.phoneNumbers
        .map((p) => BusinessCardPhone(
              number: p.number,
              label: p.label,
            ))
        .toList();

    _emails = widget.contact.emailAddresses
        .map((e) => BusinessCardEmail(
              email: e.email,
              label: e.label,
            ))
        .toList();
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

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    final company = _companyController.text.trim();
    final jobTitle = _jobTitleController.text.trim();
    final website = _websiteController.text.trim();
    final address = _addressController.text.trim();

    final validPhones = _phones.where((p) => p.number.trim().isNotEmpty).toList();
    final validEmails = _emails.where((e) => e.email.trim().isNotEmpty).toList();

    if (name.isEmpty && company.isEmpty && validPhones.isEmpty && validEmails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter at least a name, company, phone, or email.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final updatedData = {
        'fullName': name.isEmpty ? null : name,
        'company': company.isEmpty ? null : company,
        'jobTitle': jobTitle.isEmpty ? null : jobTitle,
        'website': website.isEmpty ? null : website,
        'address': address.isEmpty ? null : address,
        if (widget.contact.effectiveMemory != null)
          'rememberThisContact': widget.contact.effectiveMemory,
        if (widget.contact.effectiveMemory != null)
          'personalRemark': widget.contact.effectiveMemory,
        'phoneNumbers': validPhones
            .map((p) => {
                  'number': p.number.trim(),
                  'label': p.label,
                })
            .toList(),
        'emailAddresses': validEmails
            .map((e) => {
                  'email': e.email.trim(),
                  'label': e.label,
                })
            .toList(),
      };

      final updatedContact = await _contactService.updateContact(
        widget.contact.id,
        updatedData,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contact updated successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(context).pop(updatedContact);
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
          content: Text('Failed to update contact. Please try again.'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Business Card'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name Field
            Text(
              'Name',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('edit_name_field'),
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Full Name',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            // Job Title Field
            Text(
              'Job Title',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('edit_job_title_field'),
              controller: _jobTitleController,
              decoration: InputDecoration(
                hintText: 'e.g. Senior Developer',
                prefixIcon: const Icon(Icons.badge_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            // Company Field
            Text(
              'Company',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('edit_company_field'),
              controller: _companyController,
              decoration: InputDecoration(
                hintText: 'e.g. ABC Technologies',
                prefixIcon: const Icon(Icons.business_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),

            // Phone Numbers Editor
            BusinessCardPhoneEditor(
              initialPhones: _phones,
              showTypeSelector: true,
              onChanged: (updatedPhones) {
                setState(() {
                  _phones = updatedPhones;
                });
              },
            ),
            const SizedBox(height: 24),

            // Email Addresses Editor
            BusinessCardEmailEditor(
              initialEmails: _emails,
              showTypeSelector: true,
              onChanged: (updatedEmails) {
                setState(() {
                  _emails = updatedEmails;
                });
              },
            ),
            const SizedBox(height: 24),

            // Website Field
            Text(
              'Website',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('edit_website_field'),
              controller: _websiteController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'e.g. https://example.com',
                prefixIcon: const Icon(Icons.language_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            // Address Field
            Text(
              'Address',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('edit_address_field'),
              controller: _addressController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'e.g. Chennai, Tamil Nadu',
                prefixIcon: const Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 32),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                key: const Key('save_imported_contact_button'),
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  _isSaving ? 'Saving...' : 'Save Changes',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _isSaving ? null : _handleSave,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
