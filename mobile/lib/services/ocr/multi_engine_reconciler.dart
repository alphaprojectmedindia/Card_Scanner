import 'dart:math';
import 'dart:ui';
import '../../models/business_card_data.dart';
import '../../models/field_evidence.dart';
import '../../models/recovered_ocr_observation.dart';
import 'targeted_high_res_reocr_service.dart';

/// Structured outcome of multi-engine reconciliation after targeted re-OCR (Part 22 Stage 3).
class ReconciliationResult {
  /// Updated field evidence map incorporating validated recoveries.
  final Map<String, FieldEvidence> updatedFieldEvidence;

  /// Recovered observations produced during targeted re-OCR and accepted or preserved.
  final List<RecoveredOcrObservation> recoveredObservations;

  /// Summary of improvements applied.
  final List<String> improvementsApplied;

  /// Conflicting candidates preserved for auditability.
  final Map<String, List<String>> preservedConflicts;

  const ReconciliationResult({
    required this.updatedFieldEvidence,
    required this.recoveredObservations,
    this.improvementsApplied = const [],
    this.preservedConflicts = const {},
  });
}

/// Context-aware reconciler comparing original PaddleOCR, original ML Kit, and targeted observations (Part 22).
///
/// Implements domain-specific business rules for physical card fields:
/// - Phones: digit sequence verification, ambiguous glyph correction (0/O, 1/l/I), country codes.
/// - Emails: RFC structural verification, TLD validation, never inventing characters.
/// - Names: entity token rejection (no Ltd/Inc/Technologies), honorific detection, spatial sanity.
/// - Company: legal suffixes, corporate taxonomy, separation from personal names.
/// - Address: multi-line locality preservation, postal code integrity.
///
/// CRITICAL RULE:
/// Higher OCR confidence alone never guarantees visual correctness. Semantic and structural
/// validation take precedence over raw confidence numbers.
class MultiEngineReconciler {
  const MultiEngineReconciler();

  static final RegExp _corporateEntityTokens = RegExp(
    r'\b(?:ltd|limited|inc|incorporated|corp|corporation|solutions|technologies|services|llc|gmbh|pvt|private\s+limited|enterprises|industries)\b',
    caseSensitive: false,
  );

  static final RegExp _honorificTokens = RegExp(
    r'^(?:dr\.|dr|prof\.|prof|er\.|er|ca\.|ca|adv\.|adv|advocate|mr\.|mr|mrs\.|mrs|ms\.|ms)\s+',
    caseSensitive: false,
  );

  /// Reconciles targeted recovery results against baseline field evidence.
  ReconciliationResult reconcile({
    required Map<String, FieldEvidence> baselineEvidence,
    required List<TargetedRegionRecoveryResult> recoveryResults,
    BusinessCardData? originalCardData,
    List<Map<String, dynamic>> frontObservations = const [],
    List<Map<String, dynamic>> backObservations = const [],
  }) {
    final updatedEvidence = Map<String, FieldEvidence>.from(baselineEvidence);
    final allRecoveredObs = <RecoveredOcrObservation>[];
    final improvements = <String>[];
    final conflicts = <String, List<String>>{};

    for (final res in recoveryResults) {
      if (!res.isSuccess || res.recoveredObservations.isEmpty) continue;

      allRecoveredObs.addAll(res.recoveredObservations);
      final fieldName = res.request.fieldName;
      final currentEvidence = updatedEvidence[fieldName];
      if (currentEvidence == null) continue;

      // Do NOT overwrite user manual edits!
      if (currentEvidence.isUserEdited) {
        improvements.add(
            'Field "$fieldName" has user manual correction; preserving user value "${currentEvidence.effectiveValue}"');
        continue;
      }

      // Reconcile according to field domain
      final candidateOutcome = _reconcileFieldCandidate(
        fieldName: fieldName,
        currentEvidence: currentEvidence,
        recoveryResult: res,
      );

      if (candidateOutcome.isSuperior && candidateOutcome.winningText.isNotEmpty) {
        // Record improvement
        final oldVal = currentEvidence.normalizedValue;
        final newVal = candidateOutcome.winningText;

        updatedEvidence[fieldName] = currentEvidence.copyWith(
          originalOcrText: newVal,
          normalizedValue: newVal,
          verificationStatus: candidateOutcome.isMultiEngineAgreed
              ? FieldVerificationStatus.verified
              : FieldVerificationStatus.probable,
          sourceEngine: candidateOutcome.winningEngine,
          sourceObservationIds: candidateOutcome.observationIds,
          boundingBoxes: candidateOutcome.boundingBoxes,
          ocrConfidence: candidateOutcome.confidence,
          parserConfidence: min(1.0, currentEvidence.parserConfidence + 0.15),
          uncertaintyReason: null,
          rejectionReason: null,
        );

        improvements.add(
            'Field "$fieldName" improved from "$oldVal" to "$newVal" via ${candidateOutcome.winningEngine}');

        if (candidateOutcome.alternativeCandidates.isNotEmpty) {
          conflicts[fieldName] = candidateOutcome.alternativeCandidates;
        }
      } else if (candidateOutcome.alternativeCandidates.isNotEmpty) {
        conflicts[fieldName] = candidateOutcome.alternativeCandidates;
      }
    }

    return ReconciliationResult(
      updatedFieldEvidence: updatedEvidence,
      recoveredObservations: allRecoveredObs,
      improvementsApplied: improvements,
      preservedConflicts: conflicts,
    );
  }

  _ReconciledCandidate _reconcileFieldCandidate({
    required String fieldName,
    required FieldEvidence currentEvidence,
    required TargetedRegionRecoveryResult recoveryResult,
  }) {
    final observations = recoveryResult.recoveredObservations;
    if (observations.isEmpty) {
      return _ReconciledCandidate(
        isSuperior: false,
        winningText: '',
        winningEngine: '',
        confidence: 0.0,
      );
    }

    switch (fieldName) {
      case 'phone':
      case 'phoneNumbers':
        return _reconcilePhone(currentEvidence, observations);

      case 'email':
      case 'emailAddresses':
        return _reconcileEmail(currentEvidence, observations);

      case 'fullName':
        return _reconcileFullName(currentEvidence, observations);

      case 'company':
        return _reconcileCompany(currentEvidence, observations);

      case 'address':
        return _reconcileAddress(currentEvidence, observations);

      case 'website':
      case 'jobTitle':
      default:
        return _reconcileGenericField(fieldName, currentEvidence, observations);
    }
  }

  _ReconciledCandidate _reconcilePhone(
    FieldEvidence currentEvidence,
    List<RecoveredOcrObservation> observations,
  ) {
    final currentText = currentEvidence.effectiveValue;
    final currentDigits = currentText.replaceAll(RegExp(r'\D'), '');

    // Disambiguate common OCR digit confusions in recovered observations
    final candidates = <_PhoneCandidate>[];
    for (final obs in observations) {
      final text = obs.text.trim();
      if (text.isEmpty) continue;

      // Disambiguate 'O'/'o' to '0', 'l'/'I' to '1', 'S' to '5'
      final disambiguated = _disambiguatePhoneGlyphs(text);
      final digits = disambiguated.replaceAll(RegExp(r'\D'), '');

      // Score candidate
      double score = 0.50;
      if (digits.length >= 10 && digits.length <= 13) {
        score += 0.35;
      }
      if (disambiguated.startsWith('+')) {
        score += 0.15;
      }

      candidates.add(_PhoneCandidate(
        rawText: text,
        cleanedText: disambiguated,
        digits: digits,
        score: score,
        observation: obs,
      ));
    }

    if (candidates.isEmpty) {
      return _ReconciledCandidate(
        isSuperior: false,
        winningText: '',
        winningEngine: '',
        confidence: 0.0,
      );
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;

    // Is best superior to current?
    bool isSuperior = false;
    if (currentDigits.length < 10 && best.digits.length >= 10 && best.digits.length <= 13) {
      // Recovered missing digits!
      isSuperior = true;
    } else if (best.cleanedText.startsWith('+') && !currentText.startsWith('+') && best.digits == currentDigits) {
      // Recovered country code!
      isSuperior = true;
    } else if (best.observation.ocrConfidence > currentEvidence.ocrConfidence + 0.15 &&
        best.digits.length >= currentDigits.length) {
      isSuperior = true;
    }

    // Check cross-engine agreement
    final engines = observations.map((o) => o.sourceEngine).toSet();
    final isAgreed = engines.length > 1;

    final altTexts = candidates
        .skip(1)
        .map((c) => c.cleanedText)
        .where((t) => t != best.cleanedText)
        .toList();

    return _ReconciledCandidate(
      isSuperior: isSuperior,
      winningText: best.cleanedText,
      winningEngine: isAgreed ? 'Multi-Engine (${engines.join(' & ')})' : best.observation.sourceEngine,
      confidence: best.observation.ocrConfidence,
      observationIds: [best.observation.id],
      boundingBoxes: [best.observation.originalCoordinates],
      isMultiEngineAgreed: isAgreed,
      alternativeCandidates: altTexts,
    );
  }

  String _disambiguatePhoneGlyphs(String raw) {
    var s = raw;
    // Replace letter O/o between digits or after + with 0
    s = s.replaceAllMapped(
      RegExp(r'(?<=\d|\+)[oO](?=\d)|(?<=\d)[oO](?=\s*\d)'),
      (_) => '0',
    );
    // Replace letter l/I between digits with 1
    s = s.replaceAllMapped(
      RegExp(r'(?<=\d)[lI](?=\d)|(?<=\d)[lI](?=\s*\d)'),
      (_) => '1',
    );
    // Replace letter S between digits with 5
    s = s.replaceAllMapped(
      RegExp(r'(?<=\d)[S](?=\d)'),
      (_) => '5',
    );
    return s.trim();
  }

  _ReconciledCandidate _reconcileEmail(
    FieldEvidence currentEvidence,
    List<RecoveredOcrObservation> observations,
  ) {
    final currentText = currentEvidence.effectiveValue;
    final emailRegex = RegExp(r'\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b');

    RecoveredOcrObservation? bestObs;
    String bestEmail = '';
    double bestScore = 0.0;

    final altEmails = <String>[];

    for (final obs in observations) {
      var text = obs.text.trim();
      if (text.isEmpty) continue;

      // Fix '(at)' or spaces around @
      text = text.replaceAll(RegExp(r'\s*\(at\)\s*|\s*@\s*'), '@');
      text = text.replaceAll(RegExp(r'\s+'), '');

      final match = emailRegex.firstMatch(text);
      if (match != null) {
        final email = match.group(0)!;
        double score = obs.ocrConfidence;
        if (email.endsWith('.com') || email.endsWith('.org') || email.endsWith('.in')) {
          score += 0.10;
        }
        if (score > bestScore) {
          if (bestEmail.isNotEmpty && bestEmail != email) {
            altEmails.add(bestEmail);
          }
          bestScore = score;
          bestEmail = email;
          bestObs = obs;
        } else if (email != bestEmail) {
          altEmails.add(email);
        }
      }
    }

    if (bestObs == null || bestEmail.isEmpty) {
      return _ReconciledCandidate(
        isSuperior: false,
        winningText: '',
        winningEngine: '',
        confidence: 0.0,
      );
    }

    // Is it superior to current?
    bool isSuperior = false;
    final currentHasValidEmail = emailRegex.hasMatch(currentText);
    if (!currentHasValidEmail && bestEmail.isNotEmpty) {
      isSuperior = true;
    } else if (bestObs.ocrConfidence > currentEvidence.ocrConfidence + 0.10) {
      isSuperior = true;
    }

    return _ReconciledCandidate(
      isSuperior: isSuperior,
      winningText: bestEmail,
      winningEngine: bestObs.sourceEngine,
      confidence: bestObs.ocrConfidence,
      observationIds: [bestObs.id],
      boundingBoxes: [bestObs.originalCoordinates],
      isMultiEngineAgreed: observations.length > 1,
      alternativeCandidates: altEmails,
    );
  }

  _ReconciledCandidate _reconcileFullName(
    FieldEvidence currentEvidence,
    List<RecoveredOcrObservation> observations,
  ) {
    RecoveredOcrObservation? bestObs;
    String bestName = '';
    double bestScore = -1.0;
    final altNames = <String>[];

    for (final obs in observations) {
      final text = obs.text.trim();
      if (text.isEmpty) continue;

      // Reject candidates containing company tokens
      if (_corporateEntityTokens.hasMatch(text)) continue;

      // Reject candidates containing digits
      if (text.contains(RegExp(r'\d'))) continue;

      double score = obs.ocrConfidence;
      // Bonus for honorific prefix
      if (_honorificTokens.hasMatch(text)) {
        score += 0.25;
      }
      // Standard 2-3 word capitalized name
      final words = text.split(RegExp(r'\s+'));
      if (words.length >= 2 && words.length <= 4) {
        score += 0.15;
      }

      if (score > bestScore) {
        if (bestName.isNotEmpty && bestName != text) {
          altNames.add(bestName);
        }
        bestScore = score;
        bestName = text;
        bestObs = obs;
      } else if (text != bestName) {
        altNames.add(text);
      }
    }

    if (bestObs == null || bestName.isEmpty) {
      return _ReconciledCandidate(
        isSuperior: false,
        winningText: '',
        winningEngine: '',
        confidence: 0.0,
      );
    }

    final currentVal = currentEvidence.effectiveValue;
    bool isSuperior = false;

    // If current name contains company tokens or numbers, recovered clean name is superior!
    if (_corporateEntityTokens.hasMatch(currentVal) || currentVal.contains(RegExp(r'\d'))) {
      isSuperior = true;
    } else if (_honorificTokens.hasMatch(bestName) && !_honorificTokens.hasMatch(currentVal)) {
      isSuperior = true;
    } else if (bestObs.ocrConfidence > currentEvidence.ocrConfidence + 0.15) {
      isSuperior = true;
    }

    return _ReconciledCandidate(
      isSuperior: isSuperior,
      winningText: bestName,
      winningEngine: bestObs.sourceEngine,
      confidence: bestObs.ocrConfidence,
      observationIds: [bestObs.id],
      boundingBoxes: [bestObs.originalCoordinates],
      alternativeCandidates: altNames,
    );
  }

  _ReconciledCandidate _reconcileCompany(
    FieldEvidence currentEvidence,
    List<RecoveredOcrObservation> observations,
  ) {
    RecoveredOcrObservation? bestObs;
    String bestComp = '';
    double bestScore = -1.0;
    final altComps = <String>[];

    for (final obs in observations) {
      final text = obs.text.trim();
      if (text.isEmpty) continue;

      double score = obs.ocrConfidence;
      if (_corporateEntityTokens.hasMatch(text)) {
        score += 0.30;
      }

      if (score > bestScore) {
        if (bestComp.isNotEmpty && bestComp != text) {
          altComps.add(bestComp);
        }
        bestScore = score;
        bestComp = text;
        bestObs = obs;
      } else if (text != bestComp) {
        altComps.add(text);
      }
    }

    if (bestObs == null || bestComp.isEmpty) {
      return _ReconciledCandidate(
        isSuperior: false,
        winningText: '',
        winningEngine: '',
        confidence: 0.0,
      );
    }

    final currentVal = currentEvidence.effectiveValue;
    bool isSuperior = false;
    if (_corporateEntityTokens.hasMatch(bestComp) && !_corporateEntityTokens.hasMatch(currentVal)) {
      isSuperior = true;
    } else if (bestObs.ocrConfidence > currentEvidence.ocrConfidence + 0.15) {
      isSuperior = true;
    }

    return _ReconciledCandidate(
      isSuperior: isSuperior,
      winningText: bestComp,
      winningEngine: bestObs.sourceEngine,
      confidence: bestObs.ocrConfidence,
      observationIds: [bestObs.id],
      boundingBoxes: [bestObs.originalCoordinates],
      alternativeCandidates: altComps,
    );
  }

  _ReconciledCandidate _reconcileAddress(
    FieldEvidence currentEvidence,
    List<RecoveredOcrObservation> observations,
  ) {
    if (observations.isEmpty) {
      return _ReconciledCandidate(
        isSuperior: false,
        winningText: '',
        winningEngine: '',
        confidence: 0.0,
      );
    }

    // Sort observations in vertical reading order (top to bottom)
    final sortedObs = List<RecoveredOcrObservation>.from(observations)
      ..sort((a, b) => a.originalCoordinates.top.compareTo(b.originalCoordinates.top));

    final lines = sortedObs.map((o) => o.text.trim()).where((t) => t.isNotEmpty).toList();
    final joinedAddress = lines.join(', ');

    final currentVal = currentEvidence.effectiveValue;
    bool isSuperior = false;

    // If recovered address has more spatial context / postal code, it is superior
    if (joinedAddress.length > currentVal.length + 5 ||
        (joinedAddress.contains(RegExp(r'\b\d{5,6}\b')) && !currentVal.contains(RegExp(r'\b\d{5,6}\b')))) {
      isSuperior = true;
    }

    final avgConf = sortedObs.fold(0.0, (sum, o) => sum + o.ocrConfidence) / sortedObs.length;

    return _ReconciledCandidate(
      isSuperior: isSuperior,
      winningText: joinedAddress,
      winningEngine: sortedObs.first.sourceEngine,
      confidence: avgConf,
      observationIds: sortedObs.map((o) => o.id).toList(),
      boundingBoxes: sortedObs.map((o) => o.originalCoordinates).toList(),
    );
  }

  _ReconciledCandidate _reconcileGenericField(
    String fieldName,
    FieldEvidence currentEvidence,
    List<RecoveredOcrObservation> observations,
  ) {
    if (observations.isEmpty) {
      return _ReconciledCandidate(
        isSuperior: false,
        winningText: '',
        winningEngine: '',
        confidence: 0.0,
      );
    }

    observations.sort((a, b) => b.ocrConfidence.compareTo(a.ocrConfidence));
    final best = observations.first;

    final bool isSuperior = best.ocrConfidence > currentEvidence.ocrConfidence + 0.15;

    return _ReconciledCandidate(
      isSuperior: isSuperior,
      winningText: best.text,
      winningEngine: best.sourceEngine,
      confidence: best.ocrConfidence,
      observationIds: [best.id],
      boundingBoxes: [best.originalCoordinates],
    );
  }
}

class _ReconciledCandidate {
  final bool isSuperior;
  final String winningText;
  final String winningEngine;
  final double confidence;
  final List<String> observationIds;
  final List<Rect> boundingBoxes;
  final bool isMultiEngineAgreed;
  final List<String> alternativeCandidates;

  const _ReconciledCandidate({
    required this.isSuperior,
    required this.winningText,
    required this.winningEngine,
    required this.confidence,
    this.observationIds = const [],
    this.boundingBoxes = const [],
    this.isMultiEngineAgreed = false,
    this.alternativeCandidates = const [],
  });
}

class _PhoneCandidate {
  final String rawText;
  final String cleanedText;
  final String digits;
  final double score;
  final RecoveredOcrObservation observation;

  const _PhoneCandidate({
    required this.rawText,
    required this.cleanedText,
    required this.digits,
    required this.score,
    required this.observation,
  });
}
