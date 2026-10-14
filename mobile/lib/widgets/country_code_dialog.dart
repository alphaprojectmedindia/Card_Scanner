import 'package:flutter/material.dart';
import '../services/contact_communication_service.dart';

/// Dialog requesting country-code confirmation for a local phone number
/// before routing to WhatsApp.
class CountryCodeDialog extends StatefulWidget {
  final String phoneNumber;
  final String initialCountryCode;

  const CountryCodeDialog({
    super.key,
    required this.phoneNumber,
    this.initialCountryCode = '+91',
  });

  @override
  State<CountryCodeDialog> createState() => _CountryCodeDialogState();
}

class _CountryCodeDialogState extends State<CountryCodeDialog> {
  late final TextEditingController _countryCodeController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _countryCodeController =
        TextEditingController(text: widget.initialCountryCode);
  }

  @override
  void dispose() {
    _countryCodeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      final code = _countryCodeController.text.trim();
      final fullNumber = ContactCommunicationService.formatWithCountryCode(
        countryCode: code,
        phoneNumber: widget.phoneNumber,
      );
      Navigator.of(context).pop(fullNumber);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      key: const Key('country_code_dialog'),
      title: const Text('Country code required'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WhatsApp requires an international phone number.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Phone number',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.phoneNumber,
                key: const Key('country_code_phone_display'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Country code',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                key: const Key('country_code_input_field'),
                controller: _countryCodeController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '+91',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                validator: (val) {
                  final text = val?.trim() ?? '';
                  if (text.isEmpty) {
                    return 'Please enter a country code';
                  }
                  final digits = text.replaceAll(RegExp(r'\D'), '');
                  if (digits.isEmpty) {
                    return 'Invalid country code';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancel_country_code_button'),
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('continue_country_code_button'),
          onPressed: _submit,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
