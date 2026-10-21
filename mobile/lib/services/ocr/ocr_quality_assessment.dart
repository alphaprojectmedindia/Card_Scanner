import 'email_ocr_recovery.dart';
import 'field_candidate.dart';
import 'field_semantic_evaluator.dart';
import 'ocr_engine.dart';
import 'phone_ocr_recovery.dart';
import '../../models/ocr_side_result.dart';

/// Centralized threshold constants for OCR quality assessment.
/// Avoids scattered magic numbers across the codebase.
class OcrQualityThresholds {
  /// Minimum general quality score (out of 100.0) required to consider an OCR result sufficient.
  /// Standardized to exactly 60.0. PaddleOCR MUST run if ML Kit overall score < 60.0.
  /// Scores >= 60.0 may use fast path ONLY if critical semantic fields are trustworthy.
  static const double sufficiencyScoreThreshold = 60.0;

  /// Minimum total characters (excluding whitespace and newlines) for a valid business card.
  static const int minTotalCharacters = 20;

  /// Minimum number of non-trivial lines required for a complete business card.
  static const int minMeaningfulLines = 3;

  /// Maximum acceptable ratio of single-character lines to total lines (25%).
  static const double maxSingleCharLineRatio = 0.25;

  /// Maximum acceptable non-alphanumeric noise ratio (30%).
  static const double maxNoiseCharacterRatio = 0.30;

  // Positive Signal Weights (sum to 100.0)
  static const double weightValidEmail = 25.0;
  static const double weightValidPhone = 25.0;
  static const double weightPlausibleName = 20.0;
  static const double weightJobTitleOrCompany = 10.0;
  static const double weightAddressOrPostal = 10.0;
  static const double weightValidWebsite = 10.0;

  // Penalties
  static const double penaltyTooFewChars = 30.0;
  static const double penaltyTooFewLines = 25.0;
  static const double penaltyExcessiveSingleChars = 25.0;
  static const double penaltyHighNoiseRatio = 30.0;
  static const double penaltyCorruptedWords = 25.0;
  static const double penaltyMissingAllContactAnchors = 30.0;
  static const double penaltyNoPlausibleName = 15.0;
}

/// Constant names for identified signals.
class OcrSignalNames {
  static const String validEmail = 'valid_email';
  static const String validPhone = 'valid_phone';
  static const String validWebsite = 'valid_website';
  static const String plausiblePersonName = 'plausible_person_name';
  static const String plausibleJobTitle = 'plausible_job_title';
  static const String plausibleCompany = 'plausible_company';
  static const String addressIndicator = 'address_indicator';
  static const String sufficientLines = 'sufficient_lines';
  static const String cleanAlphanumericRatio = 'clean_alphanumeric_ratio';
}

/// Deterministic semantic evaluation of extracted contact identity and fields.
/// Decouples raw character OCR quality from field semantic classification.
class SemanticQualityAssessment {
  /// Whether any critical semantic anomaly or identity uncertainty was flagged.
  final bool hasSemanticWarning;

  /// Diagnostic list of reasons triggering semantic fallback.
  final List<String> warningReasons;

  /// Extracted candidate person name (if any).
  final String? nameCandidate;

  /// Semantic confidence of the extracted person name (0.0 to 1.0).
  final double nameSemanticConfidence;

  /// Whether the person name is deemed trustworthy.
  final bool isNameTrustworthy;

  /// Whether the selected name resembles a city, locality, or address.
  final bool isLocationOrAddressLike;

  /// Whether the selected name resembles a company or corporate organization.
  final bool isCompanyLike;

  /// Whether the selected name resembles an advertising slogan or marketing phrase.
  final bool isSloganLike;

  /// Whether the selected name resembles a job title or role.
  final bool isJobTitleLike;

  /// Whether the identity line contains fused or corrupted characters.
  final bool isCorrupted;

  const SemanticQualityAssessment({
    required this.hasSemanticWarning,
    required this.warningReasons,
    this.nameCandidate,
    this.nameSemanticConfidence = 0.0,
    this.isNameTrustworthy = false,
    this.isLocationOrAddressLike = false,
    this.isCompanyLike = false,
    this.isSloganLike = false,
    this.isJobTitleLike = false,
    this.isCorrupted = false,
  });

  Map<String, dynamic> toJson() => {
        'hasSemanticWarning': hasSemanticWarning,
        'warningReasons': warningReasons,
        if (nameCandidate != null) 'nameCandidate': nameCandidate,
        'nameSemanticConfidence':
            double.parse(nameSemanticConfidence.toStringAsFixed(2)),
        'isNameTrustworthy': isNameTrustworthy,
        'isLocationOrAddressLike': isLocationOrAddressLike,
        'isCompanyLike': isCompanyLike,
        'isSloganLike': isSloganLike,
        'isJobTitleLike': isJobTitleLike,
        'isCorrupted': isCorrupted,
      };

  @override
  String toString() =>
      'SemanticQualityAssessment(warning: $hasSemanticWarning, '
      'name: "$nameCandidate" (${(nameSemanticConfidence * 100).toStringAsFixed(0)}%), '
      'reasons: ${warningReasons.length})';
}

/// Represents the deterministic evaluation of OCR output quality.
class OcrQualityAssessment {
  /// Overall quality score from 0.0 to 100.0.
  final double score;

  /// Whether the OCR result is deemed sufficient to proceed without fallback.
  final bool isSufficient;

  /// Explanatory diagnostic reasons for the score / sufficiency decision.
  final List<String> reasons;

  /// Positive business card signals detected in the text.
  final List<String> detectedSignals;

  /// Expected business card signals that were missing.
  final List<String> missingSignals;

  /// Quantitative metrics (e.g. line count, char count, noise ratio).
  final Map<String, dynamic> metrics;

  /// Semantic field-level evaluation decoupling OCR quality from field assignments.
  final SemanticQualityAssessment? semanticAssessment;

  /// Explicit independent quality evaluation for NAME, PHONE, and EMAIL fields.
  final CriticalFieldCompleteness? criticalFields;

  const OcrQualityAssessment({
    required this.score,
    required this.isSufficient,
    required this.reasons,
    required this.detectedSignals,
    required this.missingSignals,
    this.metrics = const {},
    this.semanticAssessment,
    this.criticalFields,
  });

  Map<String, dynamic> toJson() => {
        'score': score,
        'isSufficient': isSufficient,
        'reasons': reasons,
        'detectedSignals': detectedSignals,
        'missingSignals': missingSignals,
        'metrics': metrics,
        if (semanticAssessment != null)
          'semanticAssessment': semanticAssessment!.toJson(),
        if (criticalFields != null)
          'criticalFields': criticalFields!.toJson(),
      };

  @override
  String toString() =>
      'OcrQualityAssessment(score: ${score.toStringAsFixed(1)}, '
      'sufficient: $isSufficient, signals: ${detectedSignals.length}, '
      'reasons: ${reasons.length})';
}

/// Deterministic quality evaluator for business-card OCR recognition outputs.
/// Evaluates multiple objective signals rather than character count alone.
class OcrQualityEvaluator {
  static final RegExp _emailRegExp = RegExp(
    r'\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b',
    caseSensitive: false,
  );

  static final RegExp _websiteRegExp = RegExp(
    r'(?:https?:\/\/|www\.)[a-zA-Z0-9\-]+(?:\.[a-zA-Z0-9\-]+)+|\b[a-zA-Z0-9\-]+\.(?:com|org|net|in|co\.in|io|ai|tech|biz|gov|edu|me|dev|app|co)\b',
    caseSensitive: false,
  );

  // Common title tokens across all professions
  static final RegExp _titleTokensRegExp = RegExp(
    r'\b(?:director|manager|engineer|developer|consultant|officer|consul|president|vice president|vp|head|lead|founder|co-founder|partner|specialist|analyst|associate|architect|designer|coordinator|advisor|executive|supervisor|administrator|secretary|attorney|counsel|advocate|solicitor|professor|lecturer|scientist|researcher|surgeon|physician|doctor|dr\.|ca|ias|ips|ifs|cpa|cfa|accountant|officer)\b',
    caseSensitive: false,
  );

  // Common organization / company tokens
  static final RegExp _companyTokensRegExp = RegExp(
    r'\b(?:consulate|embassy|technologies|technology|solutions|services|enterprises|industries|systems|laboratories|labs|holdings|group|corporation|corp\.?|inc\.?|incorporated|ltd\.?|limited|pvt\.?|private|llc|llp|gmbh|agency|studio|associates|partners|chambers|hospital|clinic|institute|university|college|foundation|society|undertaking)\b',
    caseSensitive: false,
  );

  // Address indicators: streets, roads, postal pin/zip codes
  static final RegExp _addressTokensRegExp = RegExp(
    r'\b(?:road|rd\.?|street|st\.?|avenue|ave\.?|lane|ln\.?|boulevard|blvd\.?|drive|dr\.?|nagar|salai|marg|chowk|sector|block|floor|suite|plot|building|bldg\.?|tower|cross|main|po box|p\.o\.|pin|zip)\b|\b[1-9][0-9]{2}\s?[0-9]{3}\b|\b\d{5}(?:-\d{4})?\b',
    caseSensitive: false,
  );

  // Corrupted word pattern: interior mixed uppercase following multiple consonants (e.g. ConsulfGpain),
  // or words containing illegal mixed symbols/digits (e.g. L0bo, Snt|ony).
  static final RegExp _corruptedWordRegExp = RegExp(
    r'\b[A-Za-z]+[b-df-hj-np-tv-z]{2,}[A-Z][b-df-hj-np-tv-z]+[a-z]*\b|\b[a-zA-Z]+[0-9|~`!#$%^&*()_+=|\\{}[\];<>?][a-zA-Z]+\b',
  );

  // Words that disqualify a line from being a pure person's name
  static final RegExp _nonNameWordsRegExp = RegExp(
    r'\b(?:tel|phone|mobile|fax|email|web|website|www|http|road|street|nagar|salai|consulate|embassy|company|technologies|solutions|ltd|limited|inc|corp|corporation|pvt|foundation|hospital|university|department|dept|branch|office|floor|group|services|enterprises|industries|holdings|agency|studios|partners|associates|international|undertaking)\b',
    caseSensitive: false,
  );

  /// Assesses an [OcrEngineResult].
  static OcrQualityAssessment assessEngineResult(OcrEngineResult result) {
    if (!result.isSuccess || result.rawText.trim().isEmpty) {
      return OcrQualityAssessment(
        score: 0.0,
        isSufficient: false,
        reasons: ['Engine recognition failed or returned empty text'],
        detectedSignals: const [],
        missingSignals: const [
          OcrSignalNames.validEmail,
          OcrSignalNames.validPhone,
          OcrSignalNames.plausiblePersonName,
        ],
        metrics: {
          'engineName': result.engineName,
          'lineCount': 0,
          'charCount': 0,
          'error': result.error,
        },
      );
    }

    return assessText(
      result.rawText,
      detectedLines: result.detectedLines,
    );
  }

  /// Assesses an [OcrSideResult].
  static OcrQualityAssessment assessSideResult(OcrSideResult result) {
    if (result.isEmpty) {
      return const OcrQualityAssessment(
        score: 0.0,
        isSufficient: false,
        reasons: ['Side result is empty'],
        detectedSignals: [],
        missingSignals: [
          OcrSignalNames.validEmail,
          OcrSignalNames.validPhone,
          OcrSignalNames.plausiblePersonName,
        ],
      );
    }

    return assessText(
      result.rawText,
      detectedLines: result.lines.map((l) => l.text).toList(),
    );
  }

  /// Evaluates raw recognized text and lines deterministically.
  static OcrQualityAssessment assessText(
    String rawText, {
    List<String>? detectedLines,
  }) {
    final text = rawText.trim();
    if (text.isEmpty) {
      return const OcrQualityAssessment(
        score: 0.0,
        isSufficient: false,
        reasons: ['Text is empty'],
        detectedSignals: [],
        missingSignals: [
          OcrSignalNames.validEmail,
          OcrSignalNames.validPhone,
          OcrSignalNames.plausiblePersonName,
        ],
      );
    }

    final rawLines = (detectedLines != null && detectedLines.isNotEmpty)
        ? detectedLines
        : text
            .split(RegExp(r'\r?\n'))
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();

    final lines = rawLines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final cleanChars = text.replaceAll(RegExp(r'\s+'), '');
    final totalChars = cleanChars.length;

    final detectedSignals = <String>[];
    final missingSignals = <String>[];
    final reasons = <String>[];

    // 1. Contact anchors detection
    // Email detection: uses EmailOcrRecovery for spaced, multi-line, and character-corrected detection
    final emailCandidates = EmailOcrRecovery.extractEmailCandidates(lines);
    final hasEmail = emailCandidates.isNotEmpty || _emailRegExp.hasMatch(text);
    if (hasEmail) {
      detectedSignals.add(OcrSignalNames.validEmail);
    } else {
      missingSignals.add(OcrSignalNames.validEmail);
    }

    // Phone detection: uses PhoneOcrRecovery for multi-format, split-line, and character-corrected detection
    final phoneCandidates = PhoneOcrRecovery.extractPhoneCandidates(lines);
    final hasPhone = phoneCandidates.isNotEmpty;
    if (hasPhone) {
      detectedSignals.add(OcrSignalNames.validPhone);
    } else {
      missingSignals.add(OcrSignalNames.validPhone);
    }

    final hasWebsite = _websiteRegExp.hasMatch(text);
    if (hasWebsite) {
      detectedSignals.add(OcrSignalNames.validWebsite);
    }

    // 2. Structured field heuristics (Person Name, Job Title, Company, Address)
    bool hasPlausibleName = false;
    bool hasJobTitle = false;
    bool hasCompany = false;
    bool hasAddress = false;

    int singleCharLineCount = 0;
    int shortLineCount = 0;
    int corruptedWordCount = 0;

    for (final line in lines) {
      final lineLen = line.length;
      if (lineLen == 1) {
        singleCharLineCount++;
      } else if (lineLen <= 2) {
        shortLineCount++;
      }

      // Check corrupted words (skip lines that are pure emails or URLs)
      if (!_emailRegExp.hasMatch(line) && !_websiteRegExp.hasMatch(line)) {
        for (final token in line.split(RegExp(r'\s+'))) {
          // Skip tokens that are phone numbers or contain @ or scheme
          if (token.contains('@') || token.contains('http') || token.contains('www.')) continue;
          if (token.replaceAll(RegExp(r'\D'), '').length >= 7) continue;

          final corruptedMatches = _corruptedWordRegExp.allMatches(token);
          for (final cm in corruptedMatches) {
            final w = cm.group(0)!;
            if (w != 'iPhone' && w != 'iPad' && w != 'eBay') {
              corruptedWordCount++;
            }
          }
        }
      }

      // Plausible Person Name check
      if (!hasPlausibleName && isPlausiblePersonName(line)) {
        hasPlausibleName = true;
      }

      // Job title
      if (!hasJobTitle && _titleTokensRegExp.hasMatch(line)) {
        hasJobTitle = true;
      }

      // Company
      if (!hasCompany && _companyTokensRegExp.hasMatch(line)) {
        hasCompany = true;
      }

      // Address
      if (!hasAddress && _addressTokensRegExp.hasMatch(line)) {
        hasAddress = true;
      }
    }

    if (hasPlausibleName) {
      detectedSignals.add(OcrSignalNames.plausiblePersonName);
    } else {
      missingSignals.add(OcrSignalNames.plausiblePersonName);
    }

    if (hasJobTitle) {
      detectedSignals.add(OcrSignalNames.plausibleJobTitle);
    }
    if (hasCompany) {
      detectedSignals.add(OcrSignalNames.plausibleCompany);
    }
    if (hasAddress) {
      detectedSignals.add(OcrSignalNames.addressIndicator);
    }

    if (lines.length >= OcrQualityThresholds.minMeaningfulLines) {
      detectedSignals.add(OcrSignalNames.sufficientLines);
    }

    // 3. Quantitative metrics
    final alphanumericChars =
        cleanChars.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').length;
    final alphanumericRatio = totalChars > 0 ? alphanumericChars / totalChars : 0.0;
    final noiseChars =
        cleanChars.replaceAll(RegExp(r'[a-zA-Z0-9\s.,+:/\-@()&]'), '').length;
    final noiseRatio = totalChars > 0 ? noiseChars / totalChars : 0.0;
    final singleCharRatio = lines.isNotEmpty ? singleCharLineCount / lines.length : 0.0;

    if (alphanumericRatio >= 0.70 && noiseRatio <= 0.15) {
      detectedSignals.add(OcrSignalNames.cleanAlphanumericRatio);
    }

    // 4. Score Computation
    double score = 0.0;

    if (hasEmail) score += OcrQualityThresholds.weightValidEmail;
    if (hasPhone) score += OcrQualityThresholds.weightValidPhone;
    if (hasPlausibleName) score += OcrQualityThresholds.weightPlausibleName;
    if (hasJobTitle || hasCompany) score += OcrQualityThresholds.weightJobTitleOrCompany;
    if (hasAddress) score += OcrQualityThresholds.weightAddressOrPostal;
    if (hasWebsite) score += OcrQualityThresholds.weightValidWebsite;

    // Apply Penalties
    if (totalChars < OcrQualityThresholds.minTotalCharacters) {
      score -= OcrQualityThresholds.penaltyTooFewChars;
      reasons.add('Too few total characters ($totalChars)');
    }

    if (lines.length < OcrQualityThresholds.minMeaningfulLines) {
      score -= OcrQualityThresholds.penaltyTooFewLines;
      reasons.add('Too few meaningful lines (${lines.length})');
    }

    if (singleCharRatio > OcrQualityThresholds.maxSingleCharLineRatio) {
      score -= OcrQualityThresholds.penaltyExcessiveSingleChars;
      reasons.add('Excessive single-character lines (${(singleCharRatio * 100).toStringAsFixed(0)}%)');
    }

    if (noiseRatio > OcrQualityThresholds.maxNoiseCharacterRatio) {
      score -= OcrQualityThresholds.penaltyHighNoiseRatio;
      reasons.add('Excessive noise/special characters (${(noiseRatio * 100).toStringAsFixed(0)}%)');
    }

    if (corruptedWordCount > 0) {
      score -= (OcrQualityThresholds.penaltyCorruptedWords * corruptedWordCount).clamp(0.0, 40.0);
      reasons.add('Detected $corruptedWordCount corrupted or fragmented word(s)');
    }

    if (!hasEmail && !hasPhone && !hasWebsite) {
      score -= OcrQualityThresholds.penaltyMissingAllContactAnchors;
      reasons.add('Missing all contact anchors (no phone, email, or website)');
    }

    if (!hasPlausibleName) {
      score -= OcrQualityThresholds.penaltyNoPlausibleName;
      reasons.add('No plausible person name detected');
    }

    // Clamp score to [0.0, 100.0]
    final finalScore = score.clamp(0.0, 100.0);

    // 5. Semantic Quality Assessment (Field-level decoupling from raw OCR score)
    final semanticAssessment = assessSemanticQuality(
      lines,
      rawText: text,
      emails: emailCandidates.map((e) => e.email).toList(),
      phones: phoneCandidates.map((p) => p.formatted).toList(),
    );

    // 5b. Critical Field Completeness Evaluation (Section 7)
    final hasValidName = semanticAssessment.isNameTrustworthy &&
        (semanticAssessment.nameCandidate != null &&
            semanticAssessment.nameCandidate!.trim().isNotEmpty);
    final bool nameFieldFailure = !hasValidName;

    final hasValidPhone = phoneCandidates.isNotEmpty;
    final hasWeakPhone =
        hasValidPhone && phoneCandidates.any((p) => p.confidence < 0.85);
    final hasUnresolvedPhone =
        PhoneOcrRecovery.hasUnresolvedPhoneFragments(lines);
    final bool phoneFieldFailure =
        !hasValidPhone || hasWeakPhone || hasUnresolvedPhone;

    final hasValidEmail = emailCandidates.isNotEmpty;
    final hasUnresolvedEmail =
        EmailOcrRecovery.hasUnresolvedEmailEvidence(lines);
    final bool emailFieldFailure = !hasValidEmail && hasUnresolvedEmail;

    final criticalFailures = <String>[];
    if (nameFieldFailure) {
      criticalFailures.add('Name field failure: no trustworthy person name identified');
    }
    if (phoneFieldFailure) {
      if (!hasValidPhone) {
        criticalFailures.add('Phone field failure: no valid phone number detected');
      } else if (hasWeakPhone) {
        criticalFailures.add('Phone field failure: phone candidate confidence < 85%');
      } else if (hasUnresolvedPhone) {
        criticalFailures.add('Phone field failure: unresolved phone fragments detected');
      }
    }
    if (emailFieldFailure) {
      criticalFailures.add('Email field failure: email fragments or cues detected but failed to resolve');
    }

    final criticalFields = CriticalFieldCompleteness(
      hasName: hasValidName,
      hasPhone: hasValidPhone && !hasWeakPhone,
      hasEmail: hasValidEmail,
      nameFieldFailure: nameFieldFailure,
      phoneFieldFailure: phoneFieldFailure,
      emailFieldFailure: emailFieldFailure,
      nameConfidence: semanticAssessment.nameSemanticConfidence,
      phoneConfidence: hasValidPhone ? phoneCandidates.first.confidence : 0.0,
      emailConfidence: hasValidEmail ? emailCandidates.first.confidence : 0.0,
      failureReasons: criticalFailures,
    );

    // 6. Final Deterministic Sufficiency Decision
    // An OCR result is sufficient ONLY if:
    // - Score meets or exceeds sufficiencyScoreThreshold (60.0)
    // - Critical identity fields are semantically trustworthy (NO semantic warning!)
    // - Has at least one strong contact signal (email or phone)
    // - Has plausible person name OR (job title + company)
    // - Not heavily corrupted
    // - Meets minimum line and character count
    final bool hasContact = hasEmail || hasPhone;
    final bool hasIdentity = hasPlausibleName || (hasJobTitle && hasCompany);
    final bool hasLowCorruption = corruptedWordCount == 0 &&
        singleCharRatio <= OcrQualityThresholds.maxSingleCharLineRatio;
    final bool meetsThreshold =
        finalScore >= OcrQualityThresholds.sufficiencyScoreThreshold;

    final isSufficient = meetsThreshold &&
        !semanticAssessment.hasSemanticWarning &&
        hasContact &&
        hasIdentity &&
        hasLowCorruption &&
        totalChars >= OcrQualityThresholds.minTotalCharacters &&
        lines.length >= OcrQualityThresholds.minMeaningfulLines;

    if (semanticAssessment.hasSemanticWarning) {
      reasons.addAll(semanticAssessment.warningReasons);
    }

    if (isSufficient) {
      reasons.add(
          'OCR output meets quality criteria (score: ${finalScore.toStringAsFixed(1)})');
    }

    return OcrQualityAssessment(
      score: finalScore,
      isSufficient: isSufficient,
      reasons: reasons,
      detectedSignals: detectedSignals,
      missingSignals: missingSignals,
      semanticAssessment: semanticAssessment,
      criticalFields: criticalFields,
      metrics: {
        'lineCount': lines.length,
        'characterCount': totalChars,
        'alphanumericRatio': double.parse(alphanumericRatio.toStringAsFixed(2)),
        'noiseRatio': double.parse(noiseRatio.toStringAsFixed(2)),
        'singleCharLineCount': singleCharLineCount,
        'shortLineCount': shortLineCount,
        'corruptedWordCount': corruptedWordCount,
      },
    );
  }

  /// Evaluates semantic field quality of lines, checking whether extracted identity
  /// candidates are trustworthy, location-like, company-like, slogan-like, or corrupted.
  static SemanticQualityAssessment assessSemanticQuality(
    List<String> lines, {
    String? rawText,
    String? website,
    List<String> emails = const [],
    List<String> phones = const [],
  }) {
    final warningReasons = <String>[];

    FieldCandidate? bestName;
    for (int i = 0; i < lines.length; i++) {
      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: lines[i],
        sourceEngine: 'Primary (ML Kit)',
        lineIndex: i,
        totalLines: lines.length,
        website: website,
        detectedEmails: emails,
        detectedPhones: phones,
      );
      if (bestName == null || cand.semanticConfidence > bestName.semanticConfidence) {
        bestName = cand;
      }
    }

    bool isLocationOrAddress = false;
    bool isCompany = false;
    bool isSlogan = false;
    bool isJobTitle = false;
    bool isCorrupted = false;

    if (bestName == null || bestName.value.trim().isEmpty) {
      warningReasons.add('No person name candidate found');
    } else {
      if (bestName.semanticConfidence < 0.40) {
        warningReasons.add(
            'Name semantic confidence is low (${(bestName.semanticConfidence * 100).toStringAsFixed(0)}%)');
      }

      if (bestName.rejectionReasons.any((r) =>
          r.toLowerCase().contains('location') ||
          r.toLowerCase().contains('city') ||
          r.toLowerCase().contains('geographic'))) {
        isLocationOrAddress = true;
        warningReasons.add(
            'Selected name resembles a geographical location or city ("${bestName.value}")');
      }

      if (bestName.rejectionReasons.any((r) =>
          r.toLowerCase().contains('address') ||
          r.toLowerCase().contains('postal'))) {
        isLocationOrAddress = true;
        warningReasons.add(
            'Selected name resembles an address or postal cluster ("${bestName.value}")');
      }

      if (bestName.rejectionReasons.any((r) =>
          r.toLowerCase().contains('corporate') ||
          r.toLowerCase().contains('company'))) {
        isCompany = true;
        warningReasons.add(
            'Selected name resembles a company or organization ("${bestName.value}")');
      }

      if (bestName.rejectionReasons.any((r) =>
          r.toLowerCase().contains('slogan') ||
          r.toLowerCase().contains('tagline'))) {
        isSlogan = true;
        warningReasons.add(
            'Selected name resembles an advertising slogan or tagline ("${bestName.value}")');
      }

      if (bestName.rejectionReasons.any((r) =>
          r.toLowerCase().contains('job title') ||
          r.toLowerCase().contains('occupational'))) {
        isJobTitle = true;
        warningReasons.add(
            'Selected name resembles a job title or role ("${bestName.value}")');
      }

      if (bestName.rejectionReasons.any((r) => r.toLowerCase().contains('corrupted'))) {
        isCorrupted = true;
        warningReasons.add(
            'Selected name contains corrupted OCR characters ("${bestName.value}")');
      }
    }

    // Check if contact information is strong but identity information is weak
    final hasContactInfo = (rawText != null &&
            (rawText.contains('@') ||
                RegExp(r'\b\d{8,12}\b').hasMatch(rawText))) ||
        emails.isNotEmpty ||
        phones.isNotEmpty;
    final hasWeakIdentity = bestName == null || bestName.semanticConfidence < 0.40;
    if (hasContactInfo && hasWeakIdentity && !warningReasons.any((r) => r.contains('identity information is weak'))) {
      warningReasons.add('Contact information is strong but identity information is weak');
    }

    // Check if phone-like fragments or labels exist but no phone was successfully resolved
    final resolvedPhoneCandidates = phones.isNotEmpty
        ? phones
        : PhoneOcrRecovery.extractPhoneCandidates(lines).map((p) => p.formatted).toList();
    if (resolvedPhoneCandidates.isEmpty && PhoneOcrRecovery.hasUnresolvedPhoneFragments(lines)) {
      warningReasons.add('Phone field evidence or fragments detected but no valid phone could be resolved');
    }

    // Check if email-like fragments or labels exist but no email was successfully resolved
    final resolvedEmailCandidates = emails.isNotEmpty
        ? emails
        : EmailOcrRecovery.extractEmailCandidates(lines).map((e) => e.email).toList();
    if (resolvedEmailCandidates.isEmpty && EmailOcrRecovery.hasUnresolvedEmailEvidence(lines)) {
      warningReasons.add('Email field evidence or fragments detected but no valid email could be resolved');
    }

    final hasSemanticWarning = warningReasons.isNotEmpty;

    return SemanticQualityAssessment(
      hasSemanticWarning: hasSemanticWarning,
      warningReasons: warningReasons,
      nameCandidate: bestName?.value,
      nameSemanticConfidence: bestName?.semanticConfidence ?? 0.0,
      isNameTrustworthy: bestName?.isTrustworthy ?? false,
      isLocationOrAddressLike: isLocationOrAddress,
      isCompanyLike: isCompany,
      isSloganLike: isSlogan,
      isJobTitleLike: isJobTitle,
      isCorrupted: isCorrupted,
    );
  }

  /// Checks if a line resembles a plausible human person name.
  static bool isPlausiblePersonName(String line) {
    final trimmed = line.trim();
    if (trimmed.length < 3 || trimmed.length > 40) return false;

    // Disqualify if it has email @ or URL patterns
    if (trimmed.contains('@') || trimmed.contains('http') || trimmed.contains('www.')) {
      return false;
    }

    // Disqualify if it contains numbers
    if (RegExp(r'\d').hasMatch(trimmed)) return false;

    // Disqualify if contains obvious non-name words
    if (_nonNameWordsRegExp.hasMatch(trimmed)) return false;

    // Check token structure: 2 to 4 words (or single word if preceded by honorific Dr./Prof.)
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length < 2 && !RegExp(r'^(?:Dr|Prof|Mr|Mrs|Ms)\.?', caseSensitive: false).hasMatch(trimmed)) {
      return false;
    }
    if (words.length > 5) return false;

    // Each word should start with uppercase and consist of letters (dots/hyphens allowed for initials)
    for (final word in words) {
      final clean = word.replaceAll(RegExp(r'[.,]'), '');
      if (clean.isEmpty) continue;
      if (!RegExp(r"^[A-Z][a-zA-Z'\-]*$").hasMatch(clean)) {
        return false;
      }
    }

    return true;
  }
}
