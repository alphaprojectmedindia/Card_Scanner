import 'dart:io';
import '../models/business_card_data.dart';
import '../models/field_evidence.dart';
import '../models/ocr_side_result.dart';
import 'ocr/ocr_observation.dart';

/// Execution mode for Gemini analysis.
enum AnalysisMode {
  none,
  textOnly, // Path A: Text + 2D Bounding Boxes (Zero image upload cost)
  multimodalVision, // Path B: Multimodal Vision (Original image uploaded to R2)
}

/// The decision produced by [CardAnalysisDecisionService].
class CardAnalysisDecision {
  final bool shouldInvokeGemini;
  final AnalysisMode mode;
  final List<String> triggeredRules;
  final String primaryReason;

  const CardAnalysisDecision({
    required this.shouldInvokeGemini,
    required this.mode,
    this.triggeredRules = const [],
    this.primaryReason = '',
  });

  static const CardAnalysisDecision noInvocation = CardAnalysisDecision(
    shouldInvokeGemini: false,
    mode: AnalysisMode.none,
    triggeredRules: [],
    primaryReason: 'Local parser extracted card details with high confidence.',
  );
}

/// Evaluates local OCR output and parser results against 8 corroborated triggers
/// to selectively decide whether to invoke Gemini API and whether Path A or Path B is required.
class CardAnalysisDecisionService {
  const CardAnalysisDecisionService();

  static final RegExp _businessEntityRegExp = RegExp(
    r'\b(?:ltd|limited|pvt|private\s+limited|inc|incorporated|corp|corporation|solutions|technologies|technology|tech|labs|holdings|enterprises|industries|group|services|llc|gmbh|co\.|consulting|consultancy|associates|partners|hospital|clinic|healthcare|systems|studio|agency|ventures|capital|logistics|interactive|dynamics|innovations|designs|advisory|management|software|hardware)\b',
    caseSensitive: false,
  );

  static final RegExp _honorificPrefixRegExp = RegExp(
    r'^(?:dr\.|dr|prof\.|prof|er\.|er|ca\.|ca|adv\.|adv|advocate|mr\.|mr|mrs\.|mrs|ms\.|ms)\s+',
    caseSensitive: false,
  );

  static final RegExp _phoneIndicatorRegExp = RegExp(
    r'\b(?:tel|ph|phone|mob|mobile|cell|contact|call|m:)\b',
    caseSensitive: false,
  );

  /// Evaluates whether Gemini should be invoked for the given card.
  CardAnalysisDecision evaluate({
    required BusinessCardData cardData,
    required OcrSideResult frontOcr,
    OcrSideResult? backOcr,
  }) {
    final triggeredRules = <String>[];
    bool recommendMultimodal = false;

    final observations = _extractObservations(frontOcr, backOcr);

    // --- TRIGGER 1: Name / Company Inversion or High-Risk Confusion ---
    final name = cardData.fullName?.trim() ?? '';
    final company = cardData.company?.trim() ?? '';
    final isNameUncertain = cardData.fieldConfidenceStates['fullName'] == 'uncertain';
    final isCompanyUncertain = cardData.fieldConfidenceStates['company'] == 'uncertain';
    final hasCompetingNames = (cardData.alternativeCandidates['fullName']?.length ?? 0) > 1;

    if (name.isNotEmpty && _businessEntityRegExp.hasMatch(name)) {
      triggeredRules.add('T1: Person name contains corporate/business legal entity tokens');
      recommendMultimodal = true;
    } else if (company.isNotEmpty && _honorificPrefixRegExp.hasMatch(company)) {
      triggeredRules.add('T1: Company name begins with a personal honorific title');
      recommendMultimodal = true;
    } else if (hasCompetingNames) {
      triggeredRules.add('T1: Multiple competing person name candidates detected on card');
      recommendMultimodal = true;
    } else if (isNameUncertain) {
      triggeredRules.add('T1: Person name marked uncertain during layout disambiguation');
      recommendMultimodal = true;
    } else if (name.isNotEmpty && company.isNotEmpty && isCompanyUncertain) {
      triggeredRules.add('T1: Ambiguous person/company assignment with uncertain confidence');
      recommendMultimodal = true;
    }

    // --- TRIGGER 2: Address Contamination or Suspicion ---
    final address = cardData.address?.trim() ?? '';
    final isAddressUncertain = cardData.fieldConfidenceStates['address'] == 'uncertain';
    if (address.isNotEmpty) {
      if (_businessEntityRegExp.hasMatch(address)) {
        triggeredRules.add('T2: Address contains legal corporate entity indicators');
      } else if (isAddressUncertain) {
        triggeredRules.add('T2: Address was flagged as uncertain during layout parsing');
      } else if (address.length > 130 && !address.contains(RegExp(r'\d{5,6}'))) {
        triggeredRules.add('T2: Address appears excessively merged without valid postal index');
      }
    }

    // --- TRIGGER 3: Missing Core Identity ---
    final isNameMissing = name.isEmpty;
    final isCompanyMissing = company.isEmpty;
    if (isNameMissing && isCompanyMissing) {
      triggeredRules.add('T3: Both primary person name and company name are missing');
      recommendMultimodal = true; // severe failure of local extraction
    } else if (isNameMissing) {
      triggeredRules.add('T3: Primary person name could not be identified by local parser');
      recommendMultimodal = true;
    } else if (name.length <= 2 && !name.contains('.')) {
      triggeredRules.add('T3: Detected person name is suspiciously short (<= 2 characters)');
      recommendMultimodal = true;
    }

    // --- TRIGGER 4: Engine Disagreement or Low Primary OCR Confidence ---
    if (frontOcr.fallbackInvoked || (backOcr != null && backOcr.fallbackInvoked)) {
      triggeredRules.add('T4: Hybrid OCR engine conflict required fallback on card side');
    }

    if (observations.isNotEmpty) {
      final totalConf = observations.fold<double>(0.0, (sum, o) => sum + o.confidence);
      final avgConf = totalConf / observations.length;
      final minConf = observations.map((o) => o.confidence).reduce((a, b) => a < b ? a : b);

      if (avgConf < 0.78) {
        triggeredRules.add('T4: Low average OCR confidence (${(avgConf * 100).toStringAsFixed(1)}%)');
        if (avgConf < 0.68) {
          recommendMultimodal = true;
        }
      } else if (minConf < 0.40) {
        triggeredRules.add('T4: Degraded OCR token confidence (${(minConf * 100).toStringAsFixed(1)}%)');
      }
    }

    // --- TRIGGER 5: Phone / Tenure Collision or Fragmented Phone ---
    final rawText = '${frontOcr.rawText}\n${backOcr?.rawText ?? ''}';
    final notes = cardData.parsingNotes.join(' ').toLowerCase();

    if (notes.contains('tenure') || notes.contains('year range') || notes.contains('date range')) {
      triggeredRules.add('T5: Potential collision between phone numbers and date/tenure range');
    } else if (cardData.phoneNumbers.isEmpty && _phoneIndicatorRegExp.hasMatch(rawText)) {
      triggeredRules.add('T5: Phone labels present in card text but no valid phone extracted');
    } else {
      for (final phone in cardData.phoneNumbers) {
        final digitsOnly = phone.number.replaceAll(RegExp(r'\D'), '');
        if (digitsOnly.length < 7 && digitsOnly.isNotEmpty) {
          triggeredRules.add('T5: Extracted phone contains fewer than 7 digits');
          break;
        }
      }
    }

    // --- TRIGGER 6: Complex Multi-Column Layout ---
    final isMultiColumn = _detectMultiColumnLayout(observations, frontOcr);
    if (isMultiColumn) {
      triggeredRules.add('T6: Multi-column spatial layout detected with reading order ambiguity');
    }

    // --- TRIGGER 7: Email Fragmentation or Suspected Partial Email ---
    final isEmailUncertain = cardData.fieldConfidenceStates['email'] == 'uncertain';
    if (cardData.emailAddresses.isEmpty && (rawText.contains('@') || rawText.toLowerCase().contains('.com'))) {
      triggeredRules.add('T7: Email markers detected in raw text but no email extracted');
    } else if (notes.contains('fragment') || isEmailUncertain) {
      triggeredRules.add('T7: Partial email fragment or reconstruction ambiguity');
    }

    // --- TRIGGER 8: Degraded OCR / High Unclassified Line Ratio ---
    final totalLines = frontOcr.lines.length + (backOcr?.lines.length ?? 0);
    final unclassifiedCount = cardData.unclassifiedLines.length;

    if (unclassifiedCount >= 3) {
      triggeredRules.add('T8: High unclassified line count ($unclassifiedCount lines unassigned)');
    } else if (totalLines >= 5 && (unclassifiedCount / totalLines) > 0.45) {
      triggeredRules.add('T8: Over 45% of recognized card lines remain unclassified');
    }

    final garbageCharsCount = RegExp(r'[~|^`_{}\\]').allMatches(rawText).length;
    if (garbageCharsCount >= 6) {
      triggeredRules.add('T8: Degraded scan with high density of OCR noise characters');
      recommendMultimodal = true;
    }

    // --- TRIGGER 9: Unresolved Uncertain Fields from Stage 3 ---
    final hasReviewRequiredEvidence = cardData.fieldEvidence.values.any(
      (e) => e.verificationStatus == FieldVerificationStatus.reviewRequired,
    );
    if (hasReviewRequiredEvidence) {
      triggeredRules.add('T9: Unresolved uncertain fields from local Stage 3 reconciliation');
      recommendMultimodal = true;
    }

    // Negative Constraint: If all detected fields are verified, skip Gemini
    final allDetectedFieldsVerified = cardData.fieldEvidence.isNotEmpty &&
        cardData.fieldEvidence.values.every((e) =>
            e.verificationStatus == FieldVerificationStatus.verified ||
            e.verificationStatus == FieldVerificationStatus.notFound);

    if (allDetectedFieldsVerified && triggeredRules.isEmpty) {
      return CardAnalysisDecision.noInvocation;
    }

    // If no rules triggered, retain local parser result with 0 API cost
    if (triggeredRules.isEmpty) {
      return CardAnalysisDecision.noInvocation;
    }

    // Determine Path A (textOnly) vs Path B (multimodalVision).
    // IMPORTANT: Always prefer multimodal (Path B) when an image is available.
    // Even if no "recommend multimodal" trigger fired, the image provides far superior
    // accuracy for business cards with logos, mixed layouts, and small font text.
    // Path A (textOnly) is only used as a last resort when no image file exists.
    AnalysisMode selectedMode = AnalysisMode.textOnly;
    final hasImage = (frontOcr.imagePath.isNotEmpty && File(frontOcr.imagePath).existsSync()) ||
        (backOcr != null && backOcr.imagePath.isNotEmpty && File(backOcr.imagePath).existsSync());

    if (hasImage) {
      // Always use multimodal when an image is present — image is the ground truth.
      selectedMode = AnalysisMode.multimodalVision;
    }

    return CardAnalysisDecision(
      shouldInvokeGemini: true,
      mode: selectedMode,
      triggeredRules: triggeredRules,
      primaryReason: triggeredRules.first,
    );
  }

  /// Extracts flat list of [OcrObservation] from both sides.
  List<OcrObservation> _extractObservations(OcrSideResult front, OcrSideResult? back) {
    final list = <OcrObservation>[];
    final frontObs = front.metadata['observations'];
    if (frontObs is List<OcrObservation>) {
      list.addAll(frontObs);
    }
    if (back != null) {
      final backObs = back.metadata['observations'];
      if (backObs is List<OcrObservation>) {
        list.addAll(backObs);
      }
    }
    return list;
  }

  /// Detects whether observations exhibit multi-column horizontal layout
  bool _detectMultiColumnLayout(List<OcrObservation> observations, OcrSideResult frontOcr) {
    if (frontOcr.metadata['isMultiColumn'] == true) return true;
    if (observations.length < 4) return false;

    // Check if there are distinct left-aligned (left < 0.40) and right-aligned (left > 0.55)
    // observations overlapping vertically in Y coordinates
    final leftColumn = observations.where((o) => o.normalizedBoundingBox.right <= 0.48).toList();
    final rightColumn = observations.where((o) => o.normalizedBoundingBox.left >= 0.52).toList();

    if (leftColumn.length >= 2 && rightColumn.length >= 2) {
      for (final l in leftColumn) {
        for (final r in rightColumn) {
          final lMidY = (l.normalizedBoundingBox.top + l.normalizedBoundingBox.bottom) / 2.0;
          final rMidY = (r.normalizedBoundingBox.top + r.normalizedBoundingBox.bottom) / 2.0;
          if ((lMidY - rMidY).abs() < 0.05) {
            return true;
          }
        }
      }
    }

    return false;
  }
}

