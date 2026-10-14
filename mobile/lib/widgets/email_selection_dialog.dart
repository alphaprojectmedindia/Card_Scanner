import 'package:flutter/material.dart';
import '../models/business_card_email.dart';

class EmailSelectionDialog extends StatefulWidget {
  final List<BusinessCardEmail> emails;

  const EmailSelectionDialog({
    super.key,
    required this.emails,
  });

  @override
  State<EmailSelectionDialog> createState() => _EmailSelectionDialogState();
}

class _EmailSelectionDialogState extends State<EmailSelectionDialog> {
  late String _selectedEmail;

  @override
  void initState() {
    super.initState();
    _selectedEmail = widget.emails.first.email;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send Email To'),
      content: SingleChildScrollView(
        child: RadioGroup<String>(
          groupValue: _selectedEmail,
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedEmail = val;
              });
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: widget.emails.map((email) {
              final labelText = email.label?.trim().isNotEmpty == true
                  ? email.label!.trim()
                  : 'Email';
              return RadioListTile<String>(
                key: Key('email_radio_${email.email}'),
                value: email.email,
                title: Text(
                  labelText,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(email.email),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancel_email_selection_button'),
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('continue_email_selection_button'),
          onPressed: () => Navigator.of(context).pop(_selectedEmail),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
