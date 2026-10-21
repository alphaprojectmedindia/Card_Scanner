import 'package:flutter/foundation.dart';

/// Represents a candidate extraction for a specific business card field.
/// Separates OCR character recognition confidence from semantic assignment confidence.
@immutable
class FieldCandidate {
  /// The field type: 'fullName', 'jobTitle', 'company', 'address', 'phone', 'email', 'website'.
  final String field;

  /// The extracted string value.
  final String value;

  /// The engine that produced this candidate (e.g. 'Google ML Kit', 'PaddleOCR (PP-OCRv5 Mobile)').
  final String sourceEngine;

  /// Character recognition confidence (0.0 to 1.0).
  /// "How confidently were these characters recognized by the OCR model?"
  final double ocrConfidence;

  /// Semantic confidence (0.0 to 1.0).
  /// "How confidently does this text represent this business-card field?"
  final double semanticConfidence;

  /// Spatial layout metadata (e.g. lineIndex, totalLines, relative position).
  final Map<String, dynamic> spatialEvidence;

  /// Diagnostic list of positive evidence supporting this candidate.
  final List<String> positiveEvidence;

  /// Diagnostic list of negative signals / penalties / rejection reasons.
  final List<String> rejectionReasons;

  const FieldCandidate({
    required this.field,
    required this.value,
    required this.sourceEngine,
    this.ocrConfidence = 0.90,
    required this.semanticConfidence,
    this.spatialEvidence = const {},
    this.positiveEvidence = const [],
    this.rejectionReasons = const [],
  });

  bool get isTrustworthy => semanticConfidence >= 0.40;

  Map<String, dynamic> toJson() => {
        'field': field,
        'value': value,
        'sourceEngine': sourceEngine,
        'ocrConfidence': double.parse(ocrConfidence.toStringAsFixed(2)),
        'semanticConfidence':
            double.parse(semanticConfidence.toStringAsFixed(2)),
        'spatialEvidence': spatialEvidence,
        if (positiveEvidence.isNotEmpty) 'positiveEvidence': positiveEvidence,
        if (rejectionReasons.isNotEmpty) 'rejectionReasons': rejectionReasons,
      };

  @override
  String toString() =>
      'FieldCandidate($field: "$value", engine: $sourceEngine, ocrConf: ${(ocrConfidence * 100).toStringAsFixed(0)}%, semConf: ${(semanticConfidence * 100).toStringAsFixed(0)}%)';
}

/// Represents the complete field-level resolution produced by combining or selecting
/// candidates across OCR engines.
@immutable
class FieldResolutionResult {
  final FieldCandidate? name;
  final FieldCandidate? jobTitle;
  final FieldCandidate? company;
  final FieldCandidate? address;
  final List<FieldCandidate> phones;
  final List<FieldCandidate> emails;
  final List<FieldCandidate> websites;

  /// Signals agreed upon by both engines after normalization.
  final List<String> agreedSignals;

  /// Plausible alternative candidates kept for user review.
  final Map<String, List<String>> alternatives;

  /// Explanatory diagnostic notes.
  final List<String> diagnosticNotes;

  const FieldResolutionResult({
    this.name,
    this.jobTitle,
    this.company,
    this.address,
    this.phones = const [],
    this.emails = const [],
    this.websites = const [],
    this.agreedSignals = const [],
    this.alternatives = const {},
    this.diagnosticNotes = const [],
  });

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name!.toJson(),
        if (jobTitle != null) 'jobTitle': jobTitle!.toJson(),
        if (company != null) 'company': company!.toJson(),
        if (address != null) 'address': address!.toJson(),
        'phones': phones.map((p) => p.toJson()).toList(),
        'emails': emails.map((e) => e.toJson()).toList(),
        'websites': websites.map((w) => w.toJson()).toList(),
        if (agreedSignals.isNotEmpty) 'agreedSignals': agreedSignals,
        if (alternatives.isNotEmpty) 'alternatives': alternatives,
        if (diagnosticNotes.isNotEmpty) 'diagnosticNotes': diagnosticNotes,
      };
}

/// Represents independent completeness and failure states for the three critical fields:
/// NAME, PHONE, and EMAIL.
///
/// Prevents a high global OCR score from masking missing contact or identity fields,
/// and prevents presence of email from bypassing phone recovery (and vice versa).
@immutable
class CriticalFieldCompleteness {
  final bool hasName;
  final bool hasPhone;
  final bool hasEmail;
  final bool nameFieldFailure;
  final bool phoneFieldFailure;
  final bool emailFieldFailure;
  final double nameConfidence;
  final double phoneConfidence;
  final double emailConfidence;
  final List<String> failureReasons;

  const CriticalFieldCompleteness({
    required this.hasName,
    required this.hasPhone,
    required this.hasEmail,
    required this.nameFieldFailure,
    required this.phoneFieldFailure,
    required this.emailFieldFailure,
    this.nameConfidence = 0.0,
    this.phoneConfidence = 0.0,
    this.emailConfidence = 0.0,
    this.failureReasons = const [],
  });

  /// All critical fields are complete and trustworthy with no individual field failures.
  bool get isComplete => !nameFieldFailure && !phoneFieldFailure && !emailFieldFailure;

  /// Whether any critical field failed or is missing with evidence.
  bool get hasAnyFailure => nameFieldFailure || phoneFieldFailure || emailFieldFailure;

  Map<String, dynamic> toJson() => {
        'hasName': hasName,
        'hasPhone': hasPhone,
        'hasEmail': hasEmail,
        'nameFieldFailure': nameFieldFailure,
        'phoneFieldFailure': phoneFieldFailure,
        'emailFieldFailure': emailFieldFailure,
        'nameConfidence': double.parse(nameConfidence.toStringAsFixed(2)),
        'phoneConfidence': double.parse(phoneConfidence.toStringAsFixed(2)),
        'emailConfidence': double.parse(emailConfidence.toStringAsFixed(2)),
        'isComplete': isComplete,
        'failureReasons': failureReasons,
      };

  @override
  String toString() =>
      'CriticalFieldCompleteness(complete: $isComplete, '
      'nameFail: $nameFieldFailure, phoneFail: $phoneFieldFailure, emailFail: $emailFieldFailure, '
      'reasons: ${failureReasons.join(", ")})';
}

