import 'package:flutter/material.dart';
import '../models/business_card_phone.dart';

class BusinessCardPhoneEditor extends StatefulWidget {
  final List<BusinessCardPhone> initialPhones;
  final ValueChanged<List<BusinessCardPhone>> onChanged;

  const BusinessCardPhoneEditor({
    super.key,
    required this.initialPhones,
    required this.onChanged,
  });

  @override
  State<BusinessCardPhoneEditor> createState() => _BusinessCardPhoneEditorState();
}

class _BusinessCardPhoneEditorState extends State<BusinessCardPhoneEditor> {
  late List<_PhoneEntry> _entries;

  static const List<String> availableLabels = [
    'Mobile',
    'Phone',
    'Office',
    'Work',
    'Personal',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _entries = widget.initialPhones
        .map((p) => _PhoneEntry(
              numberController: TextEditingController(text: p.number),
              label: p.label,
            ))
        .toList();
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.numberController.dispose();
    }
    super.dispose();
  }

  void _notifyParent() {
    final list = _entries.map((e) {
      final num = e.numberController.text.trim();
      return BusinessCardPhone(
        number: num,
        normalizedNumber: num.isNotEmpty ? BusinessCardPhone.normalize(num) : null,
        label: e.label,
      );
    }).toList();
    widget.onChanged(list);
  }

  void _addPhone() {
    setState(() {
      _entries.add(_PhoneEntry(
        numberController: TextEditingController(),
        label: 'Mobile',
      ));
    });
    _notifyParent();
  }

  void _removePhone(int index) {
    setState(() {
      _entries[index].numberController.dispose();
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
              'PHONE NUMBERS',
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
              'No phone numbers detected on this card.',
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

                // Phone Number Text Field
                Expanded(
                  child: TextFormField(
                    key: Key('phone_field_$index'),
                    controller: item.numberController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: '+91 98765 43210',
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
                  key: Key('delete_phone_$index'),
                  icon: Icon(
                    Icons.remove_circle_outline_rounded,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: 'Remove Phone',
                  onPressed: () => _removePhone(index),
                ),
              ],
            ),
          );
        }),

        // Add Phone Button
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('add_phone_button'),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Phone Number'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _addPhone,
          ),
        ),
      ],
    );
  }
}

class _PhoneEntry {
  final Key key = UniqueKey();
  final TextEditingController numberController;
  String? label;

  _PhoneEntry({
    required this.numberController,
    this.label,
  });
}
