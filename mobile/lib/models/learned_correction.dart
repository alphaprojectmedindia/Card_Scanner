import 'dart:ui';
import 'ocr_side_result.dart';

/// Categories/tiers of learned corrections according to Stage 5 specification.
enum CorrectionTier {
  /// Exact same image SHA-256 and card side with verified processing version.
  /// Highest precedence (below direct user manual edits on current contact).
  exactImageReuse,

  /// Contextual / layout pattern suggestion for cards with similar layout.
  /// Remains a suggestion until explicitly confirmed by the user.
  contextualSuggestion,

  /// General parser rule (e.g. recurring OCR character substitution, domain fix)
  /// confirmed across multiple cards.
  generalParserRule,

  /// Direct manual correction by the user on the current contact record.
  userApprovedManual,
}

/// A persistent record of a user-approved field correction.
class LearnedCorrectionRecord {
  final String id;
  final String userId;
  final String imageFingerprint;
  final CardSide? cardSide;
  final String fieldName;
  final String originalExtractedValue;
  final String approvedValue;
  final List<String> relevantObservationIds;
  final List<Rect> boundingBoxes;
  final String processingVersion;
  final DateTime createdAt;
  final DateTime? lastAppliedAt;
  final String source;
  final bool isApproved;
  final CorrectionTier tier;
  final String patternType; // 'exact_image', 'char_substitution', 'boundary_fix', 'multiline_address'
  final int confirmationCount;
  final int rejectionCount;
  final bool isActive;

  const LearnedCorrectionRecord({
    required this.id,
    this.userId = 'default_user',
    required this.imageFingerprint,
    this.cardSide,
    required this.fieldName,
    required this.originalExtractedValue,
    required this.approvedValue,
    this.relevantObservationIds = const [],
    this.boundingBoxes = const [],
    this.processingVersion = '5.0.0',
    required this.createdAt,
    this.lastAppliedAt,
    this.source = 'userManualEdit',
    this.isApproved = true,
    this.tier = CorrectionTier.exactImageReuse,
    this.patternType = 'exact_image',
    this.confirmationCount = 1,
    this.rejectionCount = 0,
    this.isActive = true,
  });

  LearnedCorrectionRecord copyWith({
    String? id,
    String? userId,
    String? imageFingerprint,
    CardSide? cardSide,
    String? fieldName,
    String? originalExtractedValue,
    String? approvedValue,
    List<String>? relevantObservationIds,
    List<Rect>? boundingBoxes,
    String? processingVersion,
    DateTime? createdAt,
    DateTime? lastAppliedAt,
    String? source,
    bool? isApproved,
    CorrectionTier? tier,
    String? patternType,
    int? confirmationCount,
    int? rejectionCount,
    bool? isActive,
  }) {
    return LearnedCorrectionRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      imageFingerprint: imageFingerprint ?? this.imageFingerprint,
      cardSide: cardSide ?? this.cardSide,
      fieldName: fieldName ?? this.fieldName,
      originalExtractedValue: originalExtractedValue ?? this.originalExtractedValue,
      approvedValue: approvedValue ?? this.approvedValue,
      relevantObservationIds: relevantObservationIds ?? this.relevantObservationIds,
      boundingBoxes: boundingBoxes ?? this.boundingBoxes,
      processingVersion: processingVersion ?? this.processingVersion,
      createdAt: createdAt ?? this.createdAt,
      lastAppliedAt: lastAppliedAt ?? this.lastAppliedAt,
      source: source ?? this.source,
      isApproved: isApproved ?? this.isApproved,
      tier: tier ?? this.tier,
      patternType: patternType ?? this.patternType,
      confirmationCount: confirmationCount ?? this.confirmationCount,
      rejectionCount: rejectionCount ?? this.rejectionCount,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'imageFingerprint': imageFingerprint,
      if (cardSide != null) 'cardSide': cardSide!.name,
      'fieldName': fieldName,
      'originalExtractedValue': originalExtractedValue,
      'approvedValue': approvedValue,
      'relevantObservationIds': relevantObservationIds,
      'boundingBoxes': boundingBoxes
          .map((b) => {
                'left': b.left,
                'top': b.top,
                'width': b.width,
                'height': b.height,
              })
          .toList(),
      'processingVersion': processingVersion,
      'createdAt': createdAt.toIso8601String(),
      if (lastAppliedAt != null) 'lastAppliedAt': lastAppliedAt!.toIso8601String(),
      'source': source,
      'isApproved': isApproved,
      'tier': tier.name,
      'patternType': patternType,
      'confirmationCount': confirmationCount,
      'rejectionCount': rejectionCount,
      'isActive': isActive,
    };
  }

  factory LearnedCorrectionRecord.fromJson(Map<String, dynamic> json) {
    CardSide? parsedSide;
    if (json['cardSide'] != null) {
      final s = json['cardSide'].toString().toLowerCase();
      if (s.contains('back')) {
        parsedSide = CardSide.back;
      } else {
        parsedSide = CardSide.front;
      }
    }

    CorrectionTier parsedTier = CorrectionTier.exactImageReuse;
    if (json['tier'] != null) {
      final t = json['tier'].toString();
      for (final val in CorrectionTier.values) {
        if (val.name == t) {
          parsedTier = val;
          break;
        }
      }
    }

    final boxes = (json['boundingBoxes'] as List<dynamic>?)
            ?.map((b) {
              final m = b as Map<String, dynamic>;
              return Rect.fromLTWH(
                (m['left'] as num).toDouble(),
                (m['top'] as num).toDouble(),
                (m['width'] as num).toDouble(),
                (m['height'] as num).toDouble(),
              );
            })
            .toList() ??
        const [];

    return LearnedCorrectionRecord(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? 'default_user',
      imageFingerprint: json['imageFingerprint'] as String? ?? '',
      cardSide: parsedSide,
      fieldName: json['fieldName'] as String? ?? '',
      originalExtractedValue: json['originalExtractedValue'] as String? ?? '',
      approvedValue: json['approvedValue'] as String? ?? '',
      relevantObservationIds: (json['relevantObservationIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      boundingBoxes: boxes,
      processingVersion: json['processingVersion'] as String? ?? '5.0.0',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastAppliedAt: json['lastAppliedAt'] != null
          ? DateTime.tryParse(json['lastAppliedAt'] as String)
          : null,
      source: json['source'] as String? ?? 'userManualEdit',
      isApproved: json['isApproved'] as bool? ?? true,
      tier: parsedTier,
      patternType: json['patternType'] as String? ?? 'exact_image',
      confirmationCount: (json['confirmationCount'] as num?)?.toInt() ?? 1,
      rejectionCount: (json['rejectionCount'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

