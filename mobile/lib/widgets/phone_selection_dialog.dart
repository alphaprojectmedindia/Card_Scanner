import 'package:flutter/material.dart';
import '../models/business_card_phone.dart';

class PhoneSelectionDialog extends StatefulWidget {
  final List<BusinessCardPhone> phones;

  const PhoneSelectionDialog({
    super.key,
    required this.phones,
  });

  @override
  State<PhoneSelectionDialog> createState() => _PhoneSelectionDialogState();
}

class _PhoneSelectionDialogState extends State<PhoneSelectionDialog> {
  late String _selectedNumber;

  @override
  void initState() {
    super.initState();
    _selectedNumber = widget.phones.first.number;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send WhatsApp Message To'),
      content: SingleChildScrollView(
        child: RadioGroup<String>(
          groupValue: _selectedNumber,
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedNumber = val;
              });
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: widget.phones.map((phone) {
              final labelText = phone.label?.trim().isNotEmpty == true
                  ? phone.label!.trim()
                  : 'Phone';
              return RadioListTile<String>(
                key: Key('phone_radio_${phone.number}'),
                value: phone.number,
                title: Text(
                  labelText,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(phone.number),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancel_phone_selection_button'),
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('continue_phone_selection_button'),
          onPressed: () => Navigator.of(context).pop(_selectedNumber),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
