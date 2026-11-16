import 'package:flutter/material.dart';
import '../models/field_evidence.dart';
import '../models/historical_reprocess_diff.dart';
import '../services/storage/local_contact_record.dart';

/// Modal dialog displaying historical reprocessing diff proposals for explicit user review.
///
/// Preserves the existing UI theme and layout styling while transparently presenting:
/// 1. Previously saved value vs Newly proposed value.
/// 2. Source of correction (Re-OCR, Gemini Vision, Learned Rule).
/// 3. Verification status badge.
/// 4. Indication if the correction was learned from an earlier user approval.
/// 5. Individual field selection ("Accept Change" vs "Keep Existing").
class HistoricalReprocessDiffDialog extends StatefulWidget {
  final LocalContactRecord originalRecord;
  final HistoricalReprocessDiff diff;
  final void Function(Set<String> acceptedFields)? onAccept;
  final VoidCallback? onKeepAll;

  const HistoricalReprocessDiffDialog({
    super.key,
    required this.originalRecord,
    required this.diff,
    this.onAccept,
    this.onKeepAll,
  });

  @override
  State<HistoricalReprocessDiffDialog> createState() =>
      _HistoricalReprocessDiffDialogState();
}

class _HistoricalReprocessDiffDialogState
    extends State<HistoricalReprocessDiffDialog> {
  late final Set<String> _selectedFields;

  @override
  void initState() {
    super.initState();
    // Default: select all fields that have actual proposed changes
    _selectedFields = widget.diff.changedFields.map((f) => f.fieldName).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changedFields = widget.diff.changedFields;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.history_toggle_off, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Historical Card Reprocess',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: changedFields.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  'No new improvements or changes found. The existing contact details are already up to date.',
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Review proposed updates for ${widget.originalRecord.fullName ?? "this contact"}. Changes will only apply after your approval.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...changedFields.map((fieldDiff) => _buildFieldCard(fieldDiff, theme)),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onKeepAll?.call();
            Navigator.of(context).pop('keep');
          },
          child: const Text('Keep Existing'),
        ),
        if (changedFields.isNotEmpty)
          FilledButton(
            onPressed: _selectedFields.isEmpty
                ? null
                : () {
                    widget.onAccept?.call(_selectedFields);
                    Navigator.of(context).pop('accepted');
                  },
            child: Text('Accept Selected (${_selectedFields.length})'),
          ),
      ],
    );
  }

  Widget _buildFieldCard(HistoricalFieldDiff fieldDiff, ThemeData theme) {
    final isSelected = _selectedFields.contains(fieldDiff.fieldName);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: isSelected,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedFields.add(fieldDiff.fieldName);
                      } else {
                        _selectedFields.remove(fieldDiff.fieldName);
                      }
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    _formatFieldLabel(fieldDiff.fieldName),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                _buildStatusChip(fieldDiff.status, theme),
              ],
            ),
            if (fieldDiff.isLearnedFromEarlierApproval)
              Container(
                margin: const EdgeInsets.only(left: 48, bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.school, size: 14, color: theme.colorScheme.onSecondaryContainer),
                    const SizedBox(width: 4),
                    Text(
                      'Learned from earlier approval',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 48.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 70,
                        child: Text(
                          'Previous:',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          fieldDiff.previousValue?.trim().isNotEmpty == true
                              ? fieldDiff.previousValue!
                              : '(Empty)',
                          style: TextStyle(
                            fontSize: 12,
                            decoration: TextDecoration.lineThrough,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 70,
                        child: Text(
                          'Proposed:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          fieldDiff.proposedValue?.trim().isNotEmpty == true
                              ? fieldDiff.proposedValue!
                              : '(Empty)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Source: ${_formatSource(fieldDiff.source)}',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(FieldVerificationStatus status, ThemeData theme) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case FieldVerificationStatus.verified:
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        label = 'Verified';
        break;
      case FieldVerificationStatus.probable:
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade900;
        label = 'Probable';
        break;
      case FieldVerificationStatus.reviewRequired:
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade900;
        label = 'Review';
        break;
      case FieldVerificationStatus.notFound:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        label = 'Not Found';
        break;
      case FieldVerificationStatus.rejected:
        bg = Colors.red.shade100;
        fg = Colors.red.shade900;
        label = 'Rejected';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  String _formatFieldLabel(String key) {
    switch (key) {
      case 'fullName':
        return 'Full Name';
      case 'company':
        return 'Company';
      case 'jobTitle':
        return 'Job Title';
      case 'website':
        return 'Website';
      case 'address':
        return 'Address';
      case 'phone':
        return 'Phone';
      case 'email':
        return 'Email';
      default:
        return key;
    }
  }

  String _formatSource(String source) {
    if (source.contains('learnedExactImage')) return 'Exact Card Reuse';
    if (source.contains('learnedParserRule')) return 'Learned Rule';
    if (source.contains('gemini')) return 'Gemini Vision AI';
    if (source.contains('targetedReOcr')) return 'Targeted Re-OCR';
    if (source.contains('reconciliation')) return 'Multi-Engine Reconciler';
    return source;
  }
}
