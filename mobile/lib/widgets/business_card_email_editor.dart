import 'package:flutter/material.dart';
import '../models/business_card_email.dart';

class BusinessCardEmailEditor extends StatefulWidget {
  final List<BusinessCardEmail> initialEmails;
  final ValueChanged<List<BusinessCardEmail>> onChanged;

  const BusinessCardEmailEditor({
    super.key,
    required this.initialEmails,
    required this.onChanged,
  });

  @override
  State<BusinessCardEmailEditor> createState() => _BusinessCardEmailEditorState();
}

class _BusinessCardEmailEditorState extends State<BusinessCardEmailEditor> {
  late List<_EmailEntry> _entries;

  static const List<String> availableLabels = [
    'Work',
    'Personal',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _entries = widget.initialEmails
        .map((e) => _EmailEntry(
              emailController: TextEditingController(text: e.email),
              label: e.label,
            ))
        .toList();
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.emailController.dispose();
    }
    super.dispose();
  }

  void _notifyParent() {
    final list = _entries.map((e) {
      final email = e.emailController.text.trim();
      return BusinessCardEmail(
        email: email,
        normalizedEmail: email.isNotEmpty ? BusinessCardEmail.normalize(email) : null,
        label: e.label,
      );
    }).toList();
    widget.onChanged(list);
  }

  void _addEmail() {
    setState(() {
      _entries.add(_EmailEntry(
        emailController: TextEditingController(),
        label: 'Work',
      ));
    });
    _notifyParent();
  }

  void _removeEmail(int index) {
    setState(() {
      _entries[index].emailController.dispose();
      _entries.removeAt(index);
    });
    _notifyParent();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'EMAIL ADDRESSES',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: theme.colorScheme.primary,
              ),
            ),
            Text(
              '${_entries.length} detected',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No email addresses detected on this card.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

        ..._entries.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;

          return Padding(
            key: item.key,
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label Dropdown
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    isDense: true,
                    initialValue: availableLabels.contains(item.label) ? item.label : null,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      labelText: 'Type',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Unset', style: TextStyle(fontSize: 12)),
                      ),
                      ...availableLabels.map(
                        (l) => DropdownMenuItem<String?>(
                          value: l,
                          child: Text(l, style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                    onChanged: (newLabel) {
                      setState(() {
                        item.label = newLabel;
                      });
                      _notifyParent();
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // Email Text Field
                Expanded(
                  child: TextFormField(
                    key: Key('email_field_$index'),
                    controller: item.emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'name@example.com',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (_) => _notifyParent(),
                  ),
                ),
                const SizedBox(width: 4),

                // Delete Button
                IconButton(
                  key: Key('delete_email_$index'),
                  icon: Icon(
                    Icons.remove_circle_outline_rounded,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: 'Remove Email',
                  onPressed: () => _removeEmail(index),
                ),
              ],
            ),
          );
        }),

        // Add Email Button
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('add_email_button'),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Email Address'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _addEmail,
          ),
        ),
      ],
    );
  }
}

class _EmailEntry {
  final Key key = UniqueKey();
  final TextEditingController emailController;
  String? label;

  _EmailEntry({
    required this.emailController,
    this.label,
  });
}
