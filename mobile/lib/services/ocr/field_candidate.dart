import 'package:flutter/foundation.dart';

/// Conceptual confidence states for business card fields (Part 20).
enum FieldConfidenceState {
  /// Strong OCR recognition + structural and semantic validation passed.
  highConfidence,

  /// Some evidence exists but disagreement, missing digits, or low confidence remains.
  uncertain,

  /// Insufficient evidence detected on card.
  notDetected,
}

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

  /// IDs of the raw OCR observations contributing to this candidate.
  final List<String> sourceObservationIds;

  /// True if field-specific structural validation passed.
  final bool validationPassed;

  /// True if ML Kit recovery or targeted re-OCR was used to produce or rescue this candidate.
  final bool recoveryUsed;

  /// Multi-signal combined evidence score (0.0 to 1.0).
  final double evidenceScore;

  /// Conservative text-quality score (0.0 to 1.0) assessing OCR character integrity.
  final double textQualityScore;

  const FieldCandidate({
    required this.field,
    required this.value,
    required this.sourceEngine,
    this.ocrConfidence = 0.90,
    required this.semanticConfidence,
    this.textQualityScore = 1.0,
    this.spatialEvidence = const {},
    this.positiveEvidence = const [],
    this.rejectionReasons = const [],
    this.sourceObservationIds = const [],
    this.validationPassed = true,
    this.recoveryUsed = false,
    double? evidenceScore,
  }) : evidenceScore = evidenceScore ?? semanticConfidence;

  /// Field type alias for arbitration.
  String get fieldType => field;

  /// Combined overall confidence.
  double get confidence => (ocrConfidence * 0.35) + (semanticConfidence * 0.65);

  /// Conceptual confidence state (Part 20 & Arbitration Correction).
  /// "Detected" (highConfidence) requires:
  /// - Strong OCR confidence (>= 0.60)
  /// - Strong semantic classification confidence (>= 0.65)
  /// - High text quality score (>= 0.70)
  /// - Structural validation passed
  /// - Zero unresolved rejection reasons
  FieldConfidenceState get confidenceState {
    if (value.trim().isEmpty) return FieldConfidenceState.notDetected;
    if (validationPassed &&
        semanticConfidence >= 0.65 &&
        ocrConfidence >= 0.60 &&
        textQualityScore >= 0.70 &&
        rejectionReasons.isEmpty) {
      return FieldConfidenceState.highConfidence;
    }
    return FieldConfidenceState.uncertain;
  }

  bool get isTrustworthy => semanticConfidence >= 0.40 && textQualityScore >= 0.50;

  /// True if candidate is verified by cross-engine consensus or very high semantic confidence and quality.
  bool get isVerified =>
      validationPassed &&
      (sourceEngine.startsWith('Both') ||
          sourceEngine.startsWith('Agreed') ||
          sourceEngine.startsWith('Recovered') ||
          (semanticConfidence >= 0.85 && textQualityScore >= 0.75)) &&
      rejectionReasons.isEmpty;

  /// PII-safe diagnostic representation omitting raw extracted values.
  Map<String, dynamic> toSafeDiagnosticJson() => {
        'field': field,
        'sourceEngine': sourceEngine,
        'confidenceState': confidenceState.name,
        'ocrConfidence': double.parse(ocrConfidence.toStringAsFixed(2)),
        'semanticConfidence':
            double.parse(semanticConfidence.toStringAsFixed(2)),
        'textQualityScore': double.parse(textQualityScore.toStringAsFixed(2)),
        'validationPassed': validationPassed,
        'recoveryUsed': recoveryUsed,
        if (positiveEvidence.isNotEmpty) 'positiveEvidence': positiveEvidence,
        if (rejectionReasons.isNotEmpty) 'rejectionReasons': rejectionReasons,
      };

  Map<String, dynamic> toJson() => {
        'field': field,
        'value': value,
        'sourceEngine': sourceEngine,
        'confidenceState': confidenceState.name,
        'ocrConfidence': double.parse(ocrConfidence.toStringAsFixed(2)),
        'semanticConfidence':
            double.parse(semanticConfidence.toStringAsFixed(2)),
        'textQualityScore': double.parse(textQualityScore.toStringAsFixed(2)),
        'spatialEvidence': spatialEvidence,
        'sourceObservationIds': sourceObservationIds,
        'validationPassed': validationPassed,
        'recoveryUsed': recoveryUsed,
        'evidenceScore': double.parse(evidenceScore.toStringAsFixed(2)),
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

  /// Unclassified valid OCR text lines preserved for review and diagnostics (Part 15).
  final List<String> unclassifiedLines;

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
    this.unclassifiedLines = const [],
  });

  /// Map of field keys to their conceptual FieldConfidenceState name.
  Map<String, String> get fieldConfidenceStates => {
        'fullName': name?.confidenceState.name ??
            FieldConfidenceState.notDetected.name,
        'jobTitle': jobTitle?.confidenceState.name ??
            FieldConfidenceState.notDetected.name,
        'company': company?.confidenceState.name ??
            FieldConfidenceState.notDetected.name,
        'address': address?.confidenceState.name ??
            FieldConfidenceState.notDetected.name,
        'phone': phones.isNotEmpty
            ? phones.first.confidenceState.name
            : FieldConfidenceState.notDetected.name,
        'email': emails.isNotEmpty
            ? emails.first.confidenceState.name
            : FieldConfidenceState.notDetected.name,
        'website': websites.isNotEmpty
            ? websites.first.confidenceState.name
            : FieldConfidenceState.notDetected.name,
      };

  /// PII-safe diagnostic representation omitting contact and identity values.
  Map<String, dynamic> toSafeDiagnosticJson() => {
        if (name != null) 'name': name!.toSafeDiagnosticJson(),
        if (jobTitle != null) 'jobTitle': jobTitle!.toSafeDiagnosticJson(),
        if (company != null) 'company': company!.toSafeDiagnosticJson(),
        if (address != null) 'address': address!.toSafeDiagnosticJson(),
        'phones': phones.map((p) => p.toSafeDiagnosticJson()).toList(),
        'emails': emails.map((e) => e.toSafeDiagnosticJson()).toList(),
        'websites': websites.map((w) => w.toSafeDiagnosticJson()).toList(),
        if (agreedSignals.isNotEmpty) 'agreedSignals': agreedSignals,
        if (diagnosticNotes.isNotEmpty) 'diagnosticNotes': diagnosticNotes,
        'unclassifiedCount': unclassifiedLines.length,
      };

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
        'unclassifiedLines': unclassifiedLines,
        'fieldConfidenceStates': fieldConfidenceStates,
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

