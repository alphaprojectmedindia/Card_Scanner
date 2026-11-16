import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'ocr_side_result.dart';

/// Explicit verification status of an extracted business-card field.
///
/// NOTE: High OCR confidence alone MUST NOT mark a field as [verified].
/// Only explicit user confirmation or verified visual ground truth achieves [verified].
enum FieldVerificationStatus {
  verified,
  probable,
  reviewRequired,
  rejected,
  notFound;

  String get displayName {
    switch (this) {
      case FieldVerificationStatus.verified:
        return 'Verified';
      case FieldVerificationStatus.probable:
        return 'Probable';
      case FieldVerificationStatus.reviewRequired:
        return 'ReviewRequired';
      case FieldVerificationStatus.rejected:
        return 'Rejected';
      case FieldVerificationStatus.notFound:
        return 'NotFound';
    }
  }

  static FieldVerificationStatus fromString(String? value) {
    if (value == null || value.trim().isEmpty) {
      return FieldVerificationStatus.notFound;
    }
    final normalized = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    switch (normalized) {
      case 'verified':
        return FieldVerificationStatus.verified;
      case 'probable':
        return FieldVerificationStatus.probable;
      case 'reviewrequired':
      case 'review':
      case 'uncertain':
        return FieldVerificationStatus.reviewRequired;
      case 'rejected':
        return FieldVerificationStatus.rejected;
      case 'notfound':
      case 'notdetected':
      default:
        return FieldVerificationStatus.notFound;
    }
  }
}

/// Reusable structured model recording granular OCR evidence, spatial geometry,
/// engine attribution, confidence breakdown, and verification state for an extracted field.
@immutable
class FieldEvidence {
  /// Name of the business card field (e.g. 'fullName', 'company', 'jobTitle', 'phone', 'email', 'website', 'address').
  final String fieldName;

  /// Unmodified raw text as recognized by the OCR engine.
  final String originalOcrText;

  /// Cleaned, normalized, or post-processed candidate value.
  final String normalizedValue;

  /// Identifier of the engine that produced the underlying observations
  /// (e.g. 'PaddleOCR (PP-OCRv5 Mobile)', 'Google ML Kit', 'Hybrid Pipeline').
  final String sourceEngine;

  /// Identifiers of all granular [OcrObservation] instances supporting this field.
  final List<String> sourceObservationIds;

  /// Pixel bounding boxes of all supporting observations in source image space.
  final List<Rect> boundingBoxes;

  /// Character recognition confidence (0.0 to 1.0) reported by the OCR model.
  final double ocrConfidence;

  /// Semantic classification confidence (0.0 to 1.0) computed by the layout parser.
  final double parserConfidence;

  /// Evidence-based verification status.
  final FieldVerificationStatus verificationStatus;

  /// User-corrected or explicitly approved value, preserved separately from the original OCR candidate.
  final String? userApprovedValue;

  /// Source attribution for the verification decision (e.g. 'ocrBaseline', 'userManualEdit', 'geminiAiVerification', 'groundTruth').
  final String verificationSource;

  /// UTC timestamp when this field was verified or manually approved.
  final DateTime? verifiedAt;

  /// Explicit diagnostic explanation if the candidate was rejected.
  final String? rejectionReason;

  /// Explicit diagnostic explanation if the field is flagged for user review.
  final String? uncertaintyReason;

  /// Card side where the contributing evidence was discovered (front or back).
  final CardSide side;

  /// Semantic processing and parser version tag (e.g. '3.2.0').
  final String processingVersion;

  /// Timestamp when this evidence was generated or evaluated.
  final DateTime evaluatedAt;

  FieldEvidence({
    required this.fieldName,
    required this.originalOcrText,
    required this.normalizedValue,
    required this.sourceEngine,
    this.sourceObservationIds = const [],
    this.boundingBoxes = const [],
    this.ocrConfidence = 1.0,
    this.parserConfidence = 1.0,
    this.verificationStatus = FieldVerificationStatus.probable,
    this.userApprovedValue,
    this.verificationSource = 'ocrBaseline',
    this.verifiedAt,
    this.rejectionReason,
    this.uncertaintyReason,
    this.side = CardSide.front,
    this.processingVersion = '3.2.0',
    DateTime? evaluatedAt,
  }) : evaluatedAt = evaluatedAt ?? DateTime.now().toUtc();

  /// Creates a fallback evidence entry for a field that was not detected on the card.
  factory FieldEvidence.notFound(
    String fieldName, {
    CardSide side = CardSide.front,
    String processingVersion = '3.2.0',
  }) {
    return FieldEvidence(
      fieldName: fieldName,
      originalOcrText: '',
      normalizedValue: '',
      sourceEngine: 'None',
      sourceObservationIds: const [],
      boundingBoxes: const [],
      ocrConfidence: 0.0,
      parserConfidence: 0.0,
      verificationStatus: FieldVerificationStatus.notFound,
      verificationSource: 'ocrBaseline',
      uncertaintyReason: 'Field was not detected on business card',
      side: side,
      processingVersion: processingVersion,
    );
  }

  /// True if the field value is non-empty and has at least one supporting observation.
  bool get hasSupportingEvidence =>
      normalizedValue.trim().isNotEmpty && sourceObservationIds.isNotEmpty;

  /// Returns true if this field was confidently verified either manually or against ground truth.
  bool get isVerified => verificationStatus == FieldVerificationStatus.verified;

  /// Returns true if this field requires manual user inspection.
  bool get needsReview => verificationStatus == FieldVerificationStatus.reviewRequired;

  /// True if a user has explicitly approved or edited this field.
  bool get isUserEdited => userApprovedValue != null && userApprovedValue != normalizedValue;

  /// Effective active value: returns the user approved/corrected value if present, otherwise normalized OCR value.
  String get effectiveValue => userApprovedValue ?? normalizedValue;

  /// Records a manual user correction or explicit user approval for this field
  /// without mutating or overwriting the original OCR text, observations, or bounding boxes.
  FieldEvidence withUserCorrection(
    String approvedValue, {
    String verificationSource = 'userManualEdit',
    DateTime? verifiedAt,
  }) {
    final now = verifiedAt ?? DateTime.now().toUtc();
    return copyWith(
      userApprovedValue: approvedValue,
      verificationStatus: FieldVerificationStatus.verified,
      verificationSource: verificationSource,
      verifiedAt: now,
    );
  }

  FieldEvidence copyWith({
    String? fieldName,
    String? originalOcrText,
    String? normalizedValue,
    String? sourceEngine,
    List<String>? sourceObservationIds,
    List<Rect>? boundingBoxes,
    double? ocrConfidence,
    double? parserConfidence,
    FieldVerificationStatus? verificationStatus,
    String? userApprovedValue,
    String? verificationSource,
    DateTime? verifiedAt,
    String? rejectionReason,
    String? uncertaintyReason,
    CardSide? side,
    String? processingVersion,
    DateTime? evaluatedAt,
  }) {
    return FieldEvidence(
      fieldName: fieldName ?? this.fieldName,
      originalOcrText: originalOcrText ?? this.originalOcrText,
      normalizedValue: normalizedValue ?? this.normalizedValue,
      sourceEngine: sourceEngine ?? this.sourceEngine,
      sourceObservationIds: sourceObservationIds ?? this.sourceObservationIds,
      boundingBoxes: boundingBoxes ?? this.boundingBoxes,
      ocrConfidence: ocrConfidence ?? this.ocrConfidence,
      parserConfidence: parserConfidence ?? this.parserConfidence,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      userApprovedValue: userApprovedValue ?? this.userApprovedValue,
      verificationSource: verificationSource ?? this.verificationSource,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      uncertaintyReason: uncertaintyReason ?? this.uncertaintyReason,
      side: side ?? this.side,
      processingVersion: processingVersion ?? this.processingVersion,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fieldName': fieldName,
      'originalOcrText': originalOcrText,
      'normalizedValue': normalizedValue,
      if (userApprovedValue != null) 'userApprovedValue': userApprovedValue,
      'sourceEngine': sourceEngine,
      'sourceObservationIds': sourceObservationIds,
      'boundingBoxes': boundingBoxes
          .map((r) => {
                'left': double.parse(r.left.toStringAsFixed(2)),
                'top': double.parse(r.top.toStringAsFixed(2)),
                'width': double.parse(r.width.toStringAsFixed(2)),
                'height': double.parse(r.height.toStringAsFixed(2)),
              })
          .toList(),
      'ocrConfidence': double.parse(ocrConfidence.toStringAsFixed(3)),
      'parserConfidence': double.parse(parserConfidence.toStringAsFixed(3)),
      'verificationStatus': verificationStatus.displayName,
      'verificationSource': verificationSource,
      if (verifiedAt != null) 'verifiedAt': verifiedAt!.toIso8601String(),
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (uncertaintyReason != null) 'uncertaintyReason': uncertaintyReason,
      'side': side.name,
      'processingVersion': processingVersion,
      'evaluatedAt': evaluatedAt.toIso8601String(),
    };
  }

  static double _parseNum(dynamic v, [double defaultValue = 0.0]) {
    if (v == null) return defaultValue;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? defaultValue;
    return defaultValue;
  }

  factory FieldEvidence.fromJson(Map<String, dynamic> json) {
    final rawBoxes = json['boundingBoxes'] is List ? json['boundingBoxes'] as List : null;
    final boxes = <Rect>[];
    if (rawBoxes != null) {
      for (final b in rawBoxes) {
        if (b is Map) {
          boxes.add(Rect.fromLTWH(
            _parseNum(b['left']),
            _parseNum(b['top']),
            _parseNum(b['width']),
            _parseNum(b['height']),
          ));
        }
      }
    } else if (json.containsKey('boundingBox') && json['boundingBox'] is Map) {
      final b = json['boundingBox'] as Map;
      boxes.add(Rect.fromLTWH(
        _parseNum(b['left']),
        _parseNum(b['top']),
        _parseNum(b['width']),
        _parseNum(b['height']),
      ));
    }

    final obsIds = json['sourceObservationIds'] is List
        ? (json['sourceObservationIds'] as List)
            .map((e) => e.toString())
            .toList()
        : const <String>[];

    final sideStr = json['side'] as String?;
    final side = sideStr == 'back'
        ? CardSide.back
        : (sideStr == 'both' ? CardSide.both : CardSide.front);

    return FieldEvidence(
      fieldName: json['fieldName'] as String? ?? '',
      originalOcrText: json['originalOcrText'] as String? ?? '',
      normalizedValue: json['normalizedValue'] as String? ?? '',
      sourceEngine: json['sourceEngine'] as String? ?? 'Unknown',
      sourceObservationIds: obsIds,
      boundingBoxes: boxes,
      ocrConfidence: _parseNum(json['ocrConfidence'], 1.0),
      parserConfidence: _parseNum(json['parserConfidence'], 1.0),
      verificationStatus:
          FieldVerificationStatus.fromString(json['verificationStatus'] as String?),
      userApprovedValue: json['userApprovedValue'] as String?,
      verificationSource: json['verificationSource'] as String? ?? 'ocrBaseline',
      verifiedAt: json['verifiedAt'] != null
          ? DateTime.tryParse(json['verifiedAt'] as String)
          : null,
      rejectionReason: json['rejectionReason'] as String?,
      uncertaintyReason: json['uncertaintyReason'] as String?,
      side: side,
      processingVersion: json['processingVersion'] as String? ?? '3.2.0',
      evaluatedAt: json['evaluatedAt'] != null
          ? DateTime.tryParse(json['evaluatedAt'] as String) ?? DateTime.now().toUtc()
          : DateTime.now().toUtc(),
    );
  }

  @override
  String toString() {
    return 'FieldEvidence($fieldName: "$normalizedValue", status: ${verificationStatus.displayName}, ocrConf: ${(ocrConfidence * 100).toStringAsFixed(0)}%, obs: ${sourceObservationIds.length}, side: ${side.name})';
  }
}
