import 'dart:ui';
import '../../models/business_card_data.dart';
import '../../models/field_evidence.dart';
import '../../models/ocr_side_result.dart';

/// Structured request for a targeted high-resolution re-OCR execution on a specific region.
class TargetedReOcrRequest {
  /// Field name ('fullName', 'company', 'jobTitle', 'phoneNumbers', 'emailAddresses', 'website', 'address').
  final String fieldName;

  /// Card side where the target region resides (front or back).
  final CardSide side;

  /// Original bounding box (or union of bounding boxes) in original image coordinates.
  final Rect targetBoundingBox;

  /// Current extracted or candidate text.
  final String candidateText;

  /// Human-readable diagnostic reason for triggering targeted re-OCR.
  final String triggerReason;

  /// Observation IDs that contributed to the uncertain candidate.
  final List<String> sourceObservationIds;

  /// Execution priority (1 = highest, e.g. phones/names; 5 = lower, e.g. website).
  final int priority;

  const TargetedReOcrRequest({
    required this.fieldName,
    required this.side,
    required this.targetBoundingBox,
    required this.candidateText,
    required this.triggerReason,
    this.sourceObservationIds = const [],
    this.priority = 3,
  });

  @override
  String toString() =>
      'TargetedReOcrRequest($fieldName, side: ${side.name}, reason: "$triggerReason", box: $targetBoundingBox)';
}

/// Detects suspicious, incomplete, conflicting, or low-confidence fields that warrant targeted re-OCR (Part 22).
///
/// CRITICAL RULE:
/// Targeted re-OCR is NEVER triggered for fields absent from the card (FieldVerificationStatus.notFound).
/// It is ONLY triggered when OCR evidence exists on the card but exhibits ambiguity, low confidence,
/// engine disagreement, or structural incompleteness.
class TargetedReOcrUncertaintyDetector {
  const TargetedReOcrUncertaintyDetector();

  /// Analyzes field evidence, parsed data, and OCR observations to produce prioritized re-OCR requests.
  List<TargetedReOcrRequest> detectUncertainFields({
    required Map<String, FieldEvidence> fieldEvidence,
    BusinessCardData? cardData,
    OcrSideResult? frontOcr,
    OcrSideResult? backOcr,
  }) {
    final requests = <TargetedReOcrRequest>[];

    // Evaluate each standard field
    for (final entry in fieldEvidence.entries) {
      final key = entry.key;
      final ev = entry.value;

      // Rule: Skip absent fields
      if (ev.verificationStatus == FieldVerificationStatus.notFound ||
          ev.normalizedValue.trim().isEmpty) {
        continue;
      }

      // Rule: Skip already verified fields unless there is active engine disagreement
      if (ev.verificationStatus == FieldVerificationStatus.verified &&
          !_hasEngineDisagreement(ev, cardData)) {
        continue;
      }

      // Find target bounding box
      final box = _computeTargetBox(ev, frontOcr, backOcr);
      if (box == null || box.width <= 0 || box.height <= 0) {
        continue;
      }

      final candidateText = ev.effectiveValue.trim();

      // Check field-specific triggers
      final trigger = _evaluateFieldTrigger(
        fieldName: key,
        evidence: ev,
        candidateText: candidateText,
        cardData: cardData,
      );

      if (trigger != null) {
        requests.add(TargetedReOcrRequest(
          fieldName: key,
          side: ev.side == CardSide.both ? CardSide.front : ev.side,
          targetBoundingBox: box,
          candidateText: candidateText,
          triggerReason: trigger.reason,
          sourceObservationIds: ev.sourceObservationIds,
          priority: trigger.priority,
        ));
      }
    }

    // Sort by priority (1 = highest priority)
    requests.sort((a, b) => a.priority.compareTo(b.priority));

    // Limit to max 4 re-OCR regions per card to preserve mobile responsiveness
    return requests.take(4).toList();
  }

  _TriggerDetail? _evaluateFieldTrigger({
    required String fieldName,
    required FieldEvidence evidence,
    required String candidateText,
    BusinessCardData? cardData,
  }) {
    // 1. Check for low OCR confidence (< 0.70)
    if (evidence.ocrConfidence < 0.70) {
      return _TriggerDetail(
        reason:
            'Low OCR confidence (${(evidence.ocrConfidence * 100).toStringAsFixed(0)}%)',
        priority: 2,
      );
    }

    // 2. Check for parser confidence uncertainty or reviewRequired status
    if (evidence.verificationStatus == FieldVerificationStatus.reviewRequired) {
      return _TriggerDetail(
        reason: evidence.uncertaintyReason ?? 'Field marked ReviewRequired by parser',
        priority: 2,
      );
    }

    // 3. Engine disagreement / competing alternatives
    if (_hasEngineDisagreement(evidence, cardData)) {
      return _TriggerDetail(
        reason: 'PaddleOCR and ML Kit disagreement / competing candidates detected',
        priority: 1,
      );
    }

    // 4. Field-specific syntactic and character ambiguity checks
    switch (fieldName) {
      case 'phone':
      case 'phoneNumbers':
        // Check for ambiguous digit characters (e.g. 984O5 instead of 98405)
        if (RegExp(r'\d+[oOlISB]\d+|\d+[oOlISB]|[oOlISB]\d+').hasMatch(candidateText)) {
          return _TriggerDetail(
            reason: 'Phone number contains ambiguous alpha-numeric glyphs (0/O, 1/l/I)',
            priority: 1,
          );
        }
        final digits = candidateText.replaceAll(RegExp(r'\D'), '');
        // Incomplete phone number (7 to 9 digits where standard is 10-12)
        if (digits.length >= 6 && digits.length < 10) {
          return _TriggerDetail(
            reason: 'Incomplete phone sequence (${digits.length} digits detected)',
            priority: 1,
          );
        }
        break;

      case 'email':
      case 'emailAddresses':
        // Check for email missing @ or using (at)
        if (candidateText.contains('(at)') ||
            (candidateText.contains('@') && !candidateText.contains('.')) ||
            (candidateText.contains(' ') && candidateText.contains('@'))) {
          return _TriggerDetail(
            reason: 'Malformed or incomplete email structure',
            priority: 1,
          );
        }
        // Missing top-level domain
        if (!RegExp(r'\.[a-zA-Z]{2,}\b').hasMatch(candidateText)) {
          return _TriggerDetail(
            reason: 'Email missing top-level domain extension',
            priority: 2,
          );
        }
        break;

      case 'fullName':
        // Name containing corporate markers or numeric digits
        if (RegExp(r'\b(?:ltd|limited|inc|corp|solutions|technologies|services|llc|pvt)\b',
                caseSensitive: false)
            .hasMatch(candidateText)) {
          return _TriggerDetail(
            reason: 'Person name candidate contains corporate entity tokens',
            priority: 1,
          );
        }
        if (candidateText.contains(RegExp(r'\d'))) {
          return _TriggerDetail(
            reason: 'Person name candidate contains numeric digits',
            priority: 2,
          );
        }
        if (candidateText.length < 3 && candidateText.isNotEmpty) {
          return _TriggerDetail(
            reason: 'Person name candidate is unusually short / dangling character',
            priority: 3,
          );
        }
        break;

      case 'company':
        // Company candidate with garbled or truncated text
        if (candidateText.length < 3 && candidateText.isNotEmpty) {
          return _TriggerDetail(
            reason: 'Company name is incomplete or truncated',
            priority: 3,
          );
        }
        break;

      case 'website':
        if (candidateText.contains(' ') ||
            (!candidateText.contains('.') && !candidateText.startsWith('http'))) {
          return _TriggerDetail(
            reason: 'Website URL is malformed or fragmented',
            priority: 4,
          );
        }
        break;

      case 'address':
        // Address without digits or very short (< 10 chars)
        if (candidateText.length < 12 && !candidateText.contains(RegExp(r'\d'))) {
          return _TriggerDetail(
            reason: 'Address fragment lacks street number or postal identifiers',
            priority: 4,
          );
        }
        break;
    }

    return null;
  }

  bool _hasEngineDisagreement(
      FieldEvidence evidence, BusinessCardData? cardData) {
    if (evidence.sourceEngine.contains('&') ||
        evidence.sourceEngine.contains('Recovered')) {
      return false;
    }
    if (cardData != null && cardData.alternativeCandidates.isNotEmpty) {
      final alts = cardData.alternativeCandidates[evidence.fieldName];
      if (alts != null && alts.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Rect? _computeTargetBox(
    FieldEvidence evidence,
    OcrSideResult? frontOcr,
    OcrSideResult? backOcr,
  ) {
    if (evidence.boundingBoxes.isNotEmpty) {
      Rect unionBox = evidence.boundingBoxes.first;
      for (int i = 1; i < evidence.boundingBoxes.length; i++) {
        unionBox = unionBox.expandToInclude(evidence.boundingBoxes[i]);
      }
      return unionBox;
    }

    // Try finding box from source observation IDs in OcrSideResults
    final targetSide = evidence.side == CardSide.back ? backOcr : frontOcr;
    if (targetSide != null) {
      final boxes = <Rect>[];
      for (final id in evidence.sourceObservationIds) {
        for (final obs in targetSide.observations) {
          if (obs['id'] == id && obs['boundingBox'] is Map) {
            final b = obs['boundingBox'] as Map;
            boxes.add(Rect.fromLTWH(
              (b['left'] as num).toDouble(),
              (b['top'] as num).toDouble(),
              (b['width'] as num).toDouble(),
              (b['height'] as num).toDouble(),
            ));
          }
        }
      }
      if (boxes.isNotEmpty) {
        Rect unionBox = boxes.first;
        for (int i = 1; i < boxes.length; i++) {
          unionBox = unionBox.expandToInclude(boxes[i]);
        }
        return unionBox;
      }
    }

    return null;
  }
}

class _TriggerDetail {
  final String reason;
  final int priority;

  const _TriggerDetail({
    required this.reason,
    required this.priority,
  });
}
