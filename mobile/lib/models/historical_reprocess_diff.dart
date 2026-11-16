import '../../models/field_evidence.dart';
import '../services/storage/local_contact_record.dart';

/// Represents a change proposal for a single field in a historical contact.
class HistoricalFieldDiff {
  final String fieldName;
  final String? previousValue;
  final String? proposedValue;
  final String source; // e.g. 'targetedReOcr', 'multiEngineReconciliation', 'geminiVisualVerification', 'learnedExactImage', 'learnedParserRule'
  final bool isLearnedFromEarlierApproval;
  final double confidence;
  final String? reason;
  final FieldVerificationStatus status;

  const HistoricalFieldDiff({
    required this.fieldName,
    this.previousValue,
    this.proposedValue,
    required this.source,
    this.isLearnedFromEarlierApproval = false,
    this.confidence = 1.0,
    this.reason,
    this.status = FieldVerificationStatus.probable,
  });

  bool get isChanged => (previousValue?.trim() ?? '') != (proposedValue?.trim() ?? '');

  Map<String, dynamic> toJson() {
    return {
      'fieldName': fieldName,
      'previousValue': previousValue,
      'proposedValue': proposedValue,
      'source': source,
      'isLearnedFromEarlierApproval': isLearnedFromEarlierApproval,
      'confidence': confidence,
      if (reason != null) 'reason': reason,
      'status': status.name,
      'isChanged': isChanged,
    };
  }

  factory HistoricalFieldDiff.fromJson(Map<String, dynamic> json) {
    FieldVerificationStatus parsedStatus = FieldVerificationStatus.probable;
    if (json['status'] != null) {
      final s = json['status'].toString();
      for (final val in FieldVerificationStatus.values) {
        if (val.name == s) {
          parsedStatus = val;
          break;
        }
      }
    }

    return HistoricalFieldDiff(
      fieldName: json['fieldName'] as String? ?? '',
      previousValue: json['previousValue'] as String?,
      proposedValue: json['proposedValue'] as String?,
      source: json['source'] as String? ?? 'reprocessing',
      isLearnedFromEarlierApproval: json['isLearnedFromEarlierApproval'] as bool? ?? false,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      reason: json['reason'] as String?,
      status: parsedStatus,
    );
  }
}

/// Comprehensive diff report between existing saved contact and newly proposed data.
///
/// Under Stage 5 negative constraints, this diff is staged and displayed for explicit
/// user approval before modifying any existing database records.
class HistoricalReprocessDiff {
  final String contactId;
  final String? imageFingerprint;
  final Map<String, HistoricalFieldDiff> fieldDiffs;
  final bool wasReprocessed;
  final bool missingImages;
  final String? diagnosticMessage;
  final LocalContactRecord? proposedRecord;

  const HistoricalReprocessDiff({
    required this.contactId,
    this.imageFingerprint,
    this.fieldDiffs = const {},
    required this.wasReprocessed,
    this.missingImages = false,
    this.diagnosticMessage,
    this.proposedRecord,
  });

  bool get hasChanges => fieldDiffs.values.any((d) => d.isChanged);

  List<HistoricalFieldDiff> get changedFields =>
      fieldDiffs.values.where((d) => d.isChanged).toList();

  Map<String, dynamic> toJson() {
    return {
      'contactId': contactId,
      if (imageFingerprint != null) 'imageFingerprint': imageFingerprint,
      'fieldDiffs': fieldDiffs.map((k, v) => MapEntry(k, v.toJson())),
      'wasReprocessed': wasReprocessed,
      'missingImages': missingImages,
      if (diagnosticMessage != null) 'diagnosticMessage': diagnosticMessage,
      'hasChanges': hasChanges,
    };
  }
}

