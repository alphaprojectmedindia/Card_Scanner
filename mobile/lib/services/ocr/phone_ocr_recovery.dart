import 'package:flutter/foundation.dart';
import '../../models/business_card_phone.dart';

/// Represents a phone candidate discovered or recovered by [PhoneOcrRecovery].
class RecoveredPhoneCandidate {
  final String raw;
  final String formatted;
  final String normalized;
  final String? label;
  final double confidence;
  final String sourceEngine;
  final bool hasCharacterCorrection;
  final bool wasSplitJoined;
  final String? diagnosticNote;

  const RecoveredPhoneCandidate({
    required this.raw,
    required this.formatted,
    required this.normalized,
    this.label,
    required this.confidence,
    required this.sourceEngine,
    this.hasCharacterCorrection = false,
    this.wasSplitJoined = false,
    this.diagnosticNote,
  });

  BusinessCardPhone toBusinessCardPhone() {
    return BusinessCardPhone(
      number: formatted,
      normalizedNumber: normalized,
      label: label,
    );
  }

  Map<String, dynamic> toJson() => {
        'raw': raw,
        'formatted': formatted,
        'normalized': normalized,
        'label': label,
        'confidence': confidence,
        'sourceEngine': sourceEngine,
        'hasCharacterCorrection': hasCharacterCorrection,
        'wasSplitJoined': wasSplitJoined,
        if (diagnosticNote != null) 'diagnosticNote': diagnosticNote,
      };

  @override
  String toString() =>
      'RecoveredPhoneCandidate($formatted, label: $label, engine: $sourceEngine, conf: ${(confidence * 100).toStringAsFixed(0)}%)';
}

/// Phone-specific OCR Recovery & Resolution Engine.
///
/// Features:
/// 1. Comprehensive International & National Phone Pattern Recognition.
/// 2. Controlled In-Candidate Character Confusion Correction (e.g. S->5, O->0, I/l/|->1, B->8, G->6, Z->2).
///    Strictly local to phone-like tokens; never modifies general text or person names (e.g. "Sonia" is untouched).
/// 3. Spatially & Sequentially Adjacent Split-Number Reconstruction.
/// 4. Robust Phone Label Detection (Mobile, Mob, M, Cell, Phone, Ph, Tel, Telephone, Office, Direct, WhatsApp).
/// 5. Normalized Comparison & Multi-Number Preservation (preserves multiple distinct numbers, deduplicates equivalents).
/// 6. Zero-Hallucination Safeguards (leaves field blank if no trustworthy evidence exists).
/// 7. Detailed Debug Diagnostics in [kDebugMode] (no PII in production).
class PhoneOcrRecovery {
  // Regex for extracting pure digits
  static final RegExp _digitsOnlyRegExp = RegExp(r'\D');

  // Phone label prefixes / patterns
  static final RegExp _phoneLabelPrefixRegExp = RegExp(
    r'^(?:'
    r'mobile|mob\.?|cell\.?|m\.?|'
    r'phone|ph\.?|p\.?|tel\.?|telephone|call\.?|'
    r'office|off\.?|work\.?|'
    r'direct|dir\.?|d\.?|'
    r'whatsapp|wa\.?'
    r')\s*[:\-\.]?\s*',
    caseSensitive: false,
  );

  // Common address / business words that immediately disqualify a line from being a pure phone number
  static final RegExp _addressDisqualifiersRegExp = RegExp(
    r'\b(?:road|rd\.?|street|st\.?|avenue|ave\.?|lane|ln\.?|boulevard|blvd\.?|'
    r'nagar|salai|marg|chowk|sector|block|floor|suite|plot|building|bldg\.?|'
    r'tower|cross|main|po box|p\.o\.|pin\s*code|pincode|zip\s*code|zip)\b',
    caseSensitive: false,
  );

  // Common tax and legal registration numbers that must NOT be extracted as phone numbers
  static final RegExp _nonPhoneIdentifiersRegExp = RegExp(
    r'\b(?:gstin|gst|cin|reg\s*no|reg\.|registration|invoice|estd|tin|pan|date|iso(?:\s*[:\-\d]|\b)|iso\s*\d+(?::\d+)?|cert(?:ified|ification)?|ce\s*\d+|gmp|nabh|nabl|halal|kosher|fda|isi|bis)\b',
    caseSensitive: false,
  );

  // Standard date patterns (e.g. 2024-10-15, 15/10/2024, 15-10-2024, Date: 2024-10-15)
  static final RegExp _datePatternRegExp = RegExp(
    r'^(?:date\s*[:\-\.]?\s*)?(?:\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4})$',
    caseSensitive: false,
  );

  // Tenure year range patterns (e.g. 2025-2027, 2024 - 2026, 2023/2025)
  static final RegExp _yearRangeRegExp = RegExp(
    r'\b(?:19|20)\d{2}\s*[-–/]\s*(?:(?:19|20)\d{2}|\d{2})\b',
  );

  /// Inspects OCR lines and recovers all valid phone candidates.
  static List<RecoveredPhoneCandidate> extractPhoneCandidates(
    List<String> rawLines, {
    String sourceEngine = 'OCR',
  }) {
    final candidates = <RecoveredPhoneCandidate>[];
    final seenNormalized = <String>{};

    // 1. First Pass: Single-line extraction & controlled correction
    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i].trim();
      if (line.isEmpty) continue;
      if (_isNonPhoneLine(line)) continue;

      // Check for split segments within line (e.g. "Tel: 2345 6789 / Mob: 98765 43210")
      String? activeStdCode;
      final segments = line.split(RegExp(r'\s*(?:[\|\/,;]|&|\band\b)\s*'));
      for (final segment in segments) {
        final cands = _evaluateSegmentCandidates(
          segment,
          sourceEngine: sourceEngine,
          previousStdCode: activeStdCode,
        );
        for (final cand in cands) {
          final std = extractStdCode(cand.formatted);
          if (std != null) activeStdCode = std;

          // Check if candidate is equivalent to an existing candidate
          int existingIndex = -1;
          for (int cIdx = 0; cIdx < candidates.length; cIdx++) {
            if (areEquivalentPhones(cand.normalized, candidates[cIdx].normalized)) {
              existingIndex = cIdx;
              break;
            }
          }

          if (existingIndex != -1) {
            final existingDigits = candidates[existingIndex].normalized.replaceAll(_digitsOnlyRegExp, '');
            final candDigits = cand.normalized.replaceAll(_digitsOnlyRegExp, '');
            if (candDigits.length > existingDigits.length) {
              seenNormalized.remove(candidates[existingIndex].normalized);
              candidates[existingIndex] = cand;
              seenNormalized.add(cand.normalized);
            }
            continue;
          }

          if (_isDuplicate(cand.normalized, seenNormalized)) {
            if (kDebugMode) {
              debugPrint('[$sourceEngine] Duplicate phone discarded: ${cand.formatted}');
            }
            continue;
          }
          seenNormalized.add(cand.normalized);
          candidates.add(cand);
        }
      }


    }

    // 2. Second Pass: Split-line reconstruction
    // OCR engines often place "+91 98765" on line i and "43210" on line i+1
    for (int i = 0; i < rawLines.length - 1; i++) {
      final line1 = rawLines[i].trim();
      final line2 = rawLines[i + 1].trim();

      if (line1.isEmpty || line2.isEmpty) continue;
      if (_isNonPhoneLine(line1)) continue;

      final joinedCandidate = _evaluateSplitPair(
        line1,
        line2,
        sourceEngine: sourceEngine,
      );

      if (joinedCandidate != null) {
        // Remove any partial incomplete candidate from pass 1 that is part of this joined candidate
        candidates.removeWhere((c) =>
            joinedCandidate.normalized.contains(c.normalized) ||
            areEquivalentPhones(c.normalized, joinedCandidate.normalized));

        if (_isDuplicate(joinedCandidate.normalized, seenNormalized)) {
          continue;
        }
        seenNormalized.add(joinedCandidate.normalized);
        candidates.add(joinedCandidate);

        if (kDebugMode) {
          debugPrint('[$sourceEngine] Reconstructed split phone: '
              'Line 1: "$line1" + Line 2: "$line2" -> ${joinedCandidate.formatted}');
        }
      }
    }

    return candidates;
  }

  /// Evaluates whether OCR output contains phone-like fragments or labels
  /// that could not be resolved, indicating phone field weakness or failure.
  static bool hasUnresolvedPhoneFragments(List<String> rawLines) {
    final candidates = extractPhoneCandidates(rawLines);
    if (candidates.isNotEmpty) {
      return false;
    }

    // Check if any line has explicit phone labels or phone-like digit sequences
    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (_isNonPhoneLine(trimmed)) continue;

      if (_phoneLabelPrefixRegExp.hasMatch(trimmed) ||
          trimmed.contains('Mobile') ||
          trimmed.contains('Phone') ||
          trimmed.contains('Tel:') ||
          trimmed.contains('+')) {
        return true;
      }

      // Digit clusters with >= 5 digits
      final digits = trimmed.replaceAll(_digitsOnlyRegExp, '');
      if (digits.length >= 6) {
        return true;
      }
    }

    return false;
  }

  /// Extracts the Indian STD area code (e.g. 0422, 044, 080) from a formatted phone string.
  static String? extractStdCode(String phone) {
    final clean = phone.trim();
    final sepMatch = RegExp(r'^\(?0([1-9]\d{1,3})\)?[\s\-\.]').firstMatch(clean);
    if (sepMatch != null) {
      return '0${sepMatch.group(1)}';
    }
    final digits = clean.replaceAll(_digitsOnlyRegExp, '');
    if (digits.startsWith('0') && digits.length >= 9 && digits.length <= 12) {
      if (digits.length == 11) {
        return digits.substring(0, 4);
      } else if (digits.length == 10) {
        return digits.substring(0, 3);
      }
    }
    return null;
  }

  /// Evaluates a segment which may contain one or multiple phone candidates.
  static List<RecoveredPhoneCandidate> _evaluateSegmentCandidates(
    String segment, {
    required String sourceEngine,
    String? previousStdCode,
  }) {
    final results = <RecoveredPhoneCandidate>[];
    final trimmed = segment.trim();
    if (trimmed.isEmpty || _isNonPhoneLine(trimmed)) return results;

    // 1. Try single segment evaluation
    final single = _evaluateSingleSegment(
      trimmed,
      sourceEngine: sourceEngine,
      previousStdCode: previousStdCode,
    );
    if (single != null) {
      results.add(single);
      String remaining = '';
      if (trimmed.contains(single.formatted)) {
        remaining = trimmed.replaceFirst(single.formatted, '').trim();
      } else if (trimmed.contains(single.raw)) {
        remaining = trimmed.replaceFirst(single.raw, '').trim();
      }
      if (remaining.isNotEmpty && remaining != trimmed && remaining.length >= 6 && !_isNonPhoneLine(remaining)) {
        final nextStd = extractStdCode(single.formatted) ?? previousStdCode;
        final sub = _evaluateSegmentCandidates(
          remaining,
          sourceEngine: sourceEngine,
          previousStdCode: nextStd,
        );
        results.addAll(sub);
      }
      return results;
    }

    // 2. Try whitespace/comma sub-splitting if segment has multiple number candidates
    final spaceParts = trimmed.split(RegExp(r'\s{2,}|\s*,\s*|\s*;\s*'));
    if (spaceParts.length > 1) {
      String? currentStd = previousStdCode;
      for (final part in spaceParts) {
        final cands = _evaluateSegmentCandidates(
          part,
          sourceEngine: sourceEngine,
          previousStdCode: currentStd,
        );
        for (final c in cands) {
          results.add(c);
          currentStd = extractStdCode(c.formatted) ?? currentStd;
        }
      }
    }

    return results;
  }

  /// Evaluates a single candidate segment.
  static RecoveredPhoneCandidate? _evaluateSingleSegment(
    String segment, {
    required String sourceEngine,
    String? previousStdCode,
  }) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) return null;
    if (_isNonPhoneLine(trimmed)) return null;

    final label = detectPhoneLabel(trimmed);

    // 1. Try direct extraction without character correction
    final direct = _parseDirectCandidate(
      trimmed,
      label: label,
      sourceEngine: sourceEngine,
      previousStdCode: previousStdCode,
    );
    if (direct != null) {
      return direct;
    }

    // 2. Try controlled in-candidate character correction ONLY if strongly phone-like!
    if (_isStronglyPhoneLike(trimmed)) {
      final (correctedText, hadCorrection, correctionsApplied) =
          _applyContextualCorrection(trimmed);

      if (hadCorrection) {
        final correctedCandidate = _parseDirectCandidate(
          correctedText,
          label: label,
          sourceEngine: sourceEngine,
          hadCorrection: true,
          correctionsApplied: correctionsApplied,
          previousStdCode: previousStdCode,
        );
        if (correctedCandidate != null) {
          if (kDebugMode) {
            debugPrint('[$sourceEngine] Contextual OCR character correction: '
                '"$trimmed" -> "${correctedCandidate.formatted}" '
                '(Corrections: ${correctionsApplied.join(", ")})');
          }
          return correctedCandidate;
        }
      }
    }

    return null;
  }

  /// Parses phone formats directly from text.
  static RecoveredPhoneCandidate? _parseDirectCandidate(
    String text, {
    String? label,
    required String sourceEngine,
    bool hadCorrection = false,
    List<String> correctionsApplied = const [],
    String? previousStdCode,
  }) {
    final clean = text.trim();

    // Guard: Standalone 5 or 6 digits without phone prefix is a postal code
    if (label == null && RegExp(r'^\d{5,6}$').hasMatch(clean)) {
      return null;
    }

    // Guard: Dates (e.g. 2024-10-15 or 15/10/2024) must never be extracted as phones
    if (RegExp(r'^(?:date\s*[:\-\.]?\s*)?(?:\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4})$', caseSensitive: false).hasMatch(clean)) {
      return null;
    }

    // Guard: Tenure year ranges (e.g. 2025-2027) must never be extracted as phones unless explicitly labeled
    if (label == null && _yearRangeRegExp.hasMatch(clean)) {
      return null;
    }

    // 1. International format with '+': e.g. +91 98765 43210, +44 20 7946 0958, +1 (415) 555-2671
    final plusPattern = RegExp(
      r'(\+\d{1,4}[\s\-\.]?\(?\d{1,5}\)?(?:[\s\-\.]?\d{2,6}){1,5})',
    );
    final plusMatch = plusPattern.firstMatch(clean);
    if (plusMatch != null) {
      final numStr = plusMatch.group(1)!.trim();
      final digits = numStr.replaceAll(_digitsOnlyRegExp, '');
      if (digits.length >= 8 && digits.length <= 16) {
        return RecoveredPhoneCandidate(
          raw: clean,
          formatted: numStr,
          normalized: normalizePhoneNumber(numStr),
          label: label,
          confidence: hadCorrection ? 0.88 : 0.98,
          sourceEngine: sourceEngine,
          hasCharacterCorrection: hadCorrection,
          diagnosticNote: hadCorrection
              ? 'International (+) with corrections: ${correctionsApplied.join(", ")}'
              : 'International (+) format',
        );
      }
    }

    // 2. Parenthesized area code (US/Intl): e.g. (044) 2345 6789, (415) 555-2671
    final parenPattern = RegExp(
      r'(\(\d{2,5}\)[\s\-\.]?\d{2,5}(?:[\s\-\.]?\d{2,5})?)',
    );
    final parenMatch = parenPattern.firstMatch(clean);
    if (parenMatch != null) {
      final numStr = parenMatch.group(1)!.trim();
      final digits = numStr.replaceAll(_digitsOnlyRegExp, '');
      if (digits.length >= 8 && digits.length <= 14) {
        return RecoveredPhoneCandidate(
          raw: clean,
          formatted: numStr,
          normalized: normalizePhoneNumber(numStr),
          label: label,
          confidence: hadCorrection ? 0.85 : 0.95,
          sourceEngine: sourceEngine,
          hasCharacterCorrection: hadCorrection,
          diagnosticNote: hadCorrection
              ? 'Area code parentheses with corrections: ${correctionsApplied.join(", ")}'
              : 'Area code parentheses format',
        );
      }
    }

    // 3. Indian Mobile Number (all variations: +91, 91, leading 0, 5+5, 4+6, 3+3+4, continuous 10-digit)
    final indianMobilePattern = RegExp(
      r'(?:(?:\+91|91|0)[\s\-\.]?)?\b([6-9]\d{4}[\s\-\.]?\d{5}|[6-9]\d{3}[\s\-\.]?\d{6}|[6-9]\d{2}[\s\-\.]?\d{3}[\s\-\.]?\d{4}|[6-9]\d{9})\b',
    );
    final indianMatch = indianMobilePattern.firstMatch(clean);
    if (indianMatch != null) {
      final formatted = indianMatch.group(0)!.trim();
      final subDigits = indianMatch.group(1)!.replaceAll(_digitsOnlyRegExp, '');
      if (subDigits.length == 10 && RegExp(r'^[6-9]').hasMatch(subDigits)) {
        final assignedLabel = label ?? (detectPhoneLabel(clean) ?? 'Mobile');
        return RecoveredPhoneCandidate(
          raw: clean,
          formatted: formatted,
          normalized: normalizePhoneNumber(formatted),
          label: assignedLabel,
          confidence: hadCorrection ? 0.88 : 0.96,
          sourceEngine: sourceEngine,
          hasCharacterCorrection: hadCorrection,
          diagnosticNote: hadCorrection
              ? 'Indian mobile with corrections: '
              : 'Indian mobile format ($assignedLabel)',
        );
      }
    }
    // 3b. Indian Landline with STD area code: e.g. 0422-3508080, 044-28281234, (0422) 3508080, 080 23456789
    final indianLandlinePattern = RegExp(
      r'(?:\b|\()(0[1-9]\d{1,3})\)?[-\s.]?(\d{6,8})\b|(?:\b|\()(0[1-9]\d{1,3})\)?[-\s.]?(\d{3,4})[-\s.]?(\d{3,4})\b',
    );
    final landlineMatch = indianLandlinePattern.firstMatch(clean);
    if (landlineMatch != null) {
      final stdCode = landlineMatch.group(1) ?? landlineMatch.group(3)!;
      final formatted = landlineMatch.group(0)!.trim();
      final digits = formatted.replaceAll(_digitsOnlyRegExp, '');
      if (digits.length >= 8 && digits.length <= 13) {
        return RecoveredPhoneCandidate(
          raw: clean,
          formatted: formatted,
          normalized: normalizePhoneNumber(formatted),
          label: label ?? 'Phone',
          confidence: hadCorrection ? 0.88 : 0.96,
          sourceEngine: sourceEngine,
          hasCharacterCorrection: hadCorrection,
          diagnosticNote: hadCorrection
              ? 'Indian STD landline with corrections: ${correctionsApplied.join(", ")}'
              : 'Indian STD landline format ($stdCode)',
        );
      }
    }

    // 3c. Bangladesh Mobile Number: e.g. +88 01713 032845, +8801713032845, +880 1713-032845, 01713 032845
    final bangladeshMobilePattern = RegExp(
      r'(?:(?:\+?880?|880)[\s\-\.]?)?\b(0?1[3-9]\d{2}[\s\-\.]?\d{6}|0?1[3-9]\d{8})\b',
    );
    final bangladeshMatch = bangladeshMobilePattern.firstMatch(clean);
    if (bangladeshMatch != null) {
      final formatted = bangladeshMatch.group(0)!.trim();
      final subDigits = bangladeshMatch.group(1)!.replaceAll(_digitsOnlyRegExp, '');
      if (subDigits.length >= 10 && subDigits.length <= 11) {
        final assignedLabel = label ?? (detectPhoneLabel(clean) ?? 'Mobile');
        return RecoveredPhoneCandidate(
          raw: clean,
          formatted: formatted,
          normalized: normalizePhoneNumber(formatted),
          label: assignedLabel,
          confidence: hadCorrection ? 0.88 : 0.96,
          sourceEngine: sourceEngine,
          hasCharacterCorrection: hadCorrection,
          diagnosticNote: hadCorrection
              ? 'Bangladesh mobile with corrections: ${correctionsApplied.join(", ")}'
              : 'Bangladesh mobile format ($assignedLabel)',
        );
      }
    }

    // 3c. Inherited STD area code for secondary telephone number: e.g. "0422-3508080, 3508051"
    if (previousStdCode != null) {
      final subMatch = RegExp(r'^\b(\d{3,4}[-\s.]?\d{3,4}|\d{6,8})\b$').firstMatch(clean);
      if (subMatch != null) {
        final subDigits = subMatch.group(1)!.replaceAll(_digitsOnlyRegExp, '');
        if (subDigits.length >= 6 && subDigits.length <= 8) {
          final formatted = '$previousStdCode-$subDigits';
          return RecoveredPhoneCandidate(
            raw: clean,
            formatted: formatted,
            normalized: normalizePhoneNumber(formatted),
            label: label ?? 'Phone',
            confidence: 0.92,
            sourceEngine: sourceEngine,
            diagnosticNote: 'Inherited STD code ($previousStdCode)',
          );
        }
      }
    }

    // 4. National format with leading 0 (UK/Europe/Asia landlines): 044 2345 6789 or 020 7946 0958
    final nationalZeroPattern = RegExp(
      r'\b(0\d{2,4}[\s\-\.]?\d{3,4}[\s\-\.]?\d{3,4})\b',
    );
    final zeroMatch = nationalZeroPattern.firstMatch(clean);
    if (zeroMatch != null) {
      final numStr = zeroMatch.group(1)!.trim();
      final digits = numStr.replaceAll(_digitsOnlyRegExp, '');
      if (digits.length >= 8 && digits.length <= 13) {
        return RecoveredPhoneCandidate(
          raw: clean,
          formatted: numStr,
          normalized: normalizePhoneNumber(numStr),
          label: label ?? 'Phone',
          confidence: hadCorrection ? 0.85 : 0.94,
          sourceEngine: sourceEngine,
          hasCharacterCorrection: hadCorrection,
          diagnosticNote: hadCorrection
              ? 'National leading-zero with corrections: ${correctionsApplied.join(", ")}'
              : 'National leading-zero format',
        );
      }
    }

    // 5. Generic international or labeled telephone number: e.g. "M: 9876543210" or "Tel: 45242424"
    if (label != null || _phoneLabelPrefixRegExp.hasMatch(clean)) {
      final trailingNumMatch =
          RegExp(r'(?:[:\-\s])\s*([+]?[\d\s\-\.\(\)]{7,18})').firstMatch(clean);
      if (trailingNumMatch != null) {
        final numStr = trailingNumMatch.group(1)!.trim();
        final digits = numStr.replaceAll(_digitsOnlyRegExp, '');
        if (digits.length >= 7 && digits.length <= 16) {
          return RecoveredPhoneCandidate(
            raw: clean,
            formatted: numStr,
            normalized: normalizePhoneNumber(numStr),
            label: label ?? 'Phone',
            confidence: hadCorrection ? 0.84 : 0.93,
            sourceEngine: sourceEngine,
            hasCharacterCorrection: hadCorrection,
            diagnosticNote: hadCorrection
                ? 'Labeled phone with corrections: ${correctionsApplied.join(", ")}'
                : 'Labeled phone format ($label)',
          );
        }
      }
    }

    // 6. Generic formatted phone sequence: e.g. 123-456-7890 or 1234 5678
    final genericHyphenPattern = RegExp(
      r'\b(\d{3,5}[\s\-\.]\d{3,5}[\s\-\.]\d{3,5})\b|\b(\d{4,5}[\s\-\.]\d{4,5})\b',
    );
    final genericMatch = genericHyphenPattern.firstMatch(clean);
    if (genericMatch != null) {
      final numStr = (genericMatch.group(1) ?? genericMatch.group(2))!.trim();
      if (_yearRangeRegExp.hasMatch(numStr) || _yearRangeRegExp.hasMatch(clean)) {
        return null;
      }
      final digits = numStr.replaceAll(_digitsOnlyRegExp, '');
      if (digits.length >= 7 && digits.length <= 14) {
        return RecoveredPhoneCandidate(
          raw: clean,
          formatted: numStr,
          normalized: normalizePhoneNumber(numStr),
          label: label,
          confidence: hadCorrection ? 0.80 : 0.90,
          sourceEngine: sourceEngine,
          hasCharacterCorrection: hadCorrection,
          diagnosticNote: 'Generic formatted digits',
        );
      }
    }

    return null;
  }

  /// Determines whether a string is strongly phone-like and safe for controlled character correction.
  /// Strict safety guard: Ensures person names like "Sonia Mathew" are NEVER modified.
  static bool _isStronglyPhoneLike(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    // Disqualify if contains email @ or website
    if (trimmed.contains('@') ||
        trimmed.contains('http') ||
        trimmed.contains('www.')) {
      return false;
    }

    // Disqualify if it has multiple common dictionary words or address words
    if (_addressDisqualifiersRegExp.hasMatch(trimmed)) {
      return false;
    }

    // Case A: Preceded by an explicit phone label (e.g. "M: 9876S 432I0", "Mobile : 9876S 43210")
    if (_phoneLabelPrefixRegExp.hasMatch(trimmed) ||
        detectPhoneLabel(trimmed) != null) {
      return true;
    }

    // Case B: Starts with '+' followed by numbers / characters
    if (trimmed.startsWith('+')) {
      final digits = trimmed.replaceAll(_digitsOnlyRegExp, '');
      if (digits.length >= 4) {
        return true;
      }
    }

    // Case C: Predominantly numeric token containing at least 5 digits and isolated confusion characters
    final digits = trimmed.replaceAll(_digitsOnlyRegExp, '');
    final totalLen = trimmed.length;
    if (digits.length >= 5 && totalLen <= 25) {
      // Must not consist of letters forming regular words
      final letterClusters = RegExp(r'[a-zA-Z]{3,}').allMatches(trimmed);
      if (letterClusters.isEmpty) {
        return true;
      }
    }

    return false;
  }

  /// Performs controlled, contextual in-candidate character correction ONLY.
  /// Characters:
  /// S/s -> 5
  /// O/o -> 0
  /// I/l/| -> 1
  /// B -> 8
  /// G -> 6
  /// Z/z -> 2
  static (String, bool, List<String>) _applyContextualCorrection(String text) {
    final corrections = <String>[];
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      final prevChar = i > 0 ? text[i - 1] : '';
      final nextChar = i < text.length - 1 ? text[i + 1] : '';

      final isPrevDigit = RegExp(r'\d').hasMatch(prevChar);
      final isNextDigit = RegExp(r'\d').hasMatch(nextChar);
      final isAdjacentToDigit = isPrevDigit || isNextDigit;

      // S ↔ 5 (ONLY if adjacent to digits or inside digit sequence, e.g. 9876S -> 98765)
      if ((ch == 'S' || ch == 's') && isAdjacentToDigit) {
        buffer.write('5');
        corrections.add('S->5');
        continue;
      }

      // O/o ↔ 0 (inside digit sequence, e.g. 432O0 -> 43200, 98765 4321O -> 98765 43210)
      if ((ch == 'O' || ch == 'o') && isAdjacentToDigit) {
        buffer.write('0');
        corrections.add('O->0');
        continue;
      }

      // I, l, | ↔ 1 (inside digit sequence, e.g. 432I0 -> 43210)
      if ((ch == 'I' || ch == 'l' || ch == '|') && (isAdjacentToDigit || (prevChar == '+' && isNextDigit))) {
        buffer.write('1');
        corrections.add('$ch->1');
        continue;
      }

      // B ↔ 8 (inside digit sequence, e.g. 9876B43210 -> 9876843210)
      if (ch == 'B' && isAdjacentToDigit) {
        buffer.write('8');
        corrections.add('B->8');
        continue;
      }

      // G ↔ 6 (inside digit sequence, e.g. 987G543210 -> 9876543210)
      if (ch == 'G' && isAdjacentToDigit) {
        buffer.write('6');
        corrections.add('G->6');
        continue;
      }

      // Z/z ↔ 2 (inside digit sequence, e.g. 9876543Z10 -> 9876543210)
      if ((ch == 'Z' || ch == 'z') && isAdjacentToDigit) {
        buffer.write('2');
        corrections.add('Z->2');
        continue;
      }

      buffer.write(ch);
    }

    final corrected = buffer.toString();
    final hadCorrection = corrections.isNotEmpty && corrected != text;
    return (corrected, hadCorrection, corrections);
  }

  /// Evaluates two consecutive lines for split-line phone reconstruction.
  /// Line 1: "+91 98765" or "M: 98765" or "+1 (415)"
  /// Line 2: "43210" or "555-2671"
  static RecoveredPhoneCandidate? _evaluateSplitPair(
    String line1,
    String line2, {
    required String sourceEngine,
  }) {
    // Safety guard: line2 must NOT be an address or date or legal identifier
    if (_addressDisqualifiersRegExp.hasMatch(line2) ||
        _nonPhoneIdentifiersRegExp.hasMatch(line2) ||
        _datePatternRegExp.hasMatch(line2)) {
      return null;
    }

    final digits1 = line1.replaceAll(_digitsOnlyRegExp, '');
    final digits2 = line2.replaceAll(_digitsOnlyRegExp, '');

    // Line 1 should have 3 to 10 digits; Line 2 should have 3 to 7 digits
    if (digits1.length < 3 || digits1.length > 10) return null;
    if (digits2.length < 3 || digits2.length > 7) return null;

    final combinedDigitsLen = digits1.length + digits2.length;
    if (combinedDigitsLen < 7 || combinedDigitsLen > 16) return null;

    // Check that line1 ends with an incomplete sequence, or has a phone label
    final hasLabel1 = detectPhoneLabel(line1) != null;
    final isPlus1 = line1.contains('+');
    final endsWithIncomplete = line1.endsWith('-') ||
        line1.endsWith(' ') ||
        line1.endsWith('/') ||
        RegExp(r'\d$').hasMatch(line1);

    if (!hasLabel1 && !isPlus1 && !endsWithIncomplete) {
      return null;
    }

    // Line 2 must be predominantly numeric (pure digits, spaces, hyphens)
    final nonDigitCharsInLine2 = line2.replaceAll(RegExp(r'[\d\s\-\.]'), '');
    if (nonDigitCharsInLine2.isNotEmpty) {
      return null;
    }

    // Combine lines
    final combined = '$line1 $line2';
    final candidate = _evaluateSingleSegment(combined, sourceEngine: sourceEngine);
    if (candidate != null) {
      return RecoveredPhoneCandidate(
        raw: '$line1\n$line2',
        formatted: candidate.formatted,
        normalized: candidate.normalized,
        label: candidate.label,
        confidence: 0.90,
        sourceEngine: sourceEngine,
        hasCharacterCorrection: candidate.hasCharacterCorrection,
        wasSplitJoined: true,
        diagnosticNote: 'Split lines successfully joined: "$line1" + "$line2"',
      );
    }

    return null;
  }

  /// Detects the semantic phone label from a string.
  /// Labels supported:
  /// Mobile, Mob, M, Phone, Ph, Tel, Telephone, Cell, Office, Direct, WhatsApp
  static String? detectPhoneLabel(String text) {
    final lower = text.toLowerCase();

    // WhatsApp
    if (lower.startsWith('whatsapp') ||
        lower.contains('whatsapp:') ||
        lower.contains('wa:') ||
        lower.contains('wa ')) {
      return 'WhatsApp';
    }

    // Mobile / Cell
    if (lower.startsWith('mobile') ||
        lower.contains('mobile:') ||
        lower.contains('mobile ') ||
        lower.contains('mob:') ||
        lower.contains('mob.') ||
        lower.contains('mob ') ||
        lower.startsWith('m:') ||
        lower.startsWith('m.') ||
        lower.startsWith('m ') ||
        lower.contains(' m:') ||
        lower.contains('cell:') ||
        lower.contains('cell.') ||
        lower.contains('cell ')) {
      return 'Mobile';
    }

    // Office / Work
    if (lower.startsWith('office') ||
        lower.contains('office:') ||
        lower.contains('off:') ||
        lower.contains('off.') ||
        lower.startsWith('work') ||
        lower.contains('work:')) {
      return 'Office';
    }

    // Direct
    if (lower.startsWith('direct') ||
        lower.contains('direct:') ||
        lower.contains('dir:') ||
        lower.contains('dir.')) {
      return 'Direct';
    }

    // Telephone / General Phone
    if (lower.startsWith('phone') ||
        lower.contains('phone:') ||
        lower.contains('phone ') ||
        lower.contains('ph:') ||
        lower.contains('ph.') ||
        lower.contains('ph ') ||
        lower.startsWith('p:') ||
        lower.contains('tel:') ||
        lower.contains('tel.') ||
        lower.contains('tel ') ||
        lower.contains('telephone') ||
        lower.contains('call:')) {
      return 'Phone';
    }

    // Fax
    if (lower.startsWith('fax') || lower.contains('fax:')) {
      return 'Fax';
    }

    return null;
  }

  /// Normalizes a phone number for consistent cross-engine comparison and deduplication.
  /// Preserves international format with leading '+' if present.
  static String normalizePhoneNumber(String raw) {
    final clean = raw.trim();
    final hasPlus = clean.startsWith('+');
    final digits = clean.replaceAll(_digitsOnlyRegExp, '');

    if (digits.isEmpty) return '';

    if (hasPlus) {
      return '+$digits';
    }

    return digits;
  }

  /// Checks whether two phone numbers represent the same contact number.
  /// Handles international prefix matching (e.g. +91 98765 43210 and 9876543210),
  /// while ensuring different numbers (e.g. 9876543210 and 9876543211) remain distinct.
  static bool areEquivalentPhones(String a, String b) {
    final normA = normalizePhoneNumber(a);
    final normB = normalizePhoneNumber(b);

    if (normA.isEmpty || normB.isEmpty) return false;
    if (normA == normB) return true;

    final digitsA = normA.replaceAll(_digitsOnlyRegExp, '');
    final digitsB = normB.replaceAll(_digitsOnlyRegExp, '');

    if (digitsA == digitsB) return true;

    // Check if one has country code (e.g. 919876543210 vs 9876543210)
    if (digitsA.length >= 10 && digitsB.length >= 10) {
      final suffixA = digitsA.substring(digitsA.length - 10);
      final suffixB = digitsB.substring(digitsB.length - 10);
      if (suffixA == suffixB) {
        return true;
      }
    }

    // National leading 0 vs international format
    if (digitsA.startsWith('0') && digitsB.endsWith(digitsA.substring(1))) {
      return true;
    }
    if (digitsB.startsWith('0') && digitsA.endsWith(digitsB.substring(1))) {
      return true;
    }

    // Landline / national subscriber suffix matching (e.g. 044-24342596 vs 24342596 or +91-44-42107657 vs 42107657)
    if (digitsA.length >= 6 && digitsB.length >= 6) {
      if (digitsA.endsWith(digitsB) || digitsB.endsWith(digitsA)) {
        return true;
      }
    }

    return false;
  }

  static bool _isDuplicate(String normalized, Set<String> seenNormalized) {
    if (seenNormalized.contains(normalized)) return true;

    for (final seen in seenNormalized) {
      if (areEquivalentPhones(normalized, seen)) {
        return true;
      }
    }
    return false;
  }

  /// Disqualifies non-phone lines such as PIN codes, GSTIN, dates, etc.
  static bool _isNonPhoneLine(String line) {
    final upper = line.toUpperCase();

    // Guard: If it has explicit phone label, do NOT disqualify
    if (upper.contains('MOBILE') ||
        upper.contains('MOB:') ||
        upper.contains('TEL:') ||
        upper.contains('PHONE:') ||
        upper.contains('OFFICE:') ||
        upper.contains('WHATSAPP') ||
        upper.startsWith('M:') ||
        upper.startsWith('PH:')) {
      return false;
    }

    if (upper.contains('PIN:') ||
        upper.contains('PIN CODE') ||
        upper.contains('PINCODE') ||
        upper.contains('POSTAL CODE') ||
        upper.contains('ZIP:') ||
        upper.contains('ZIP CODE') ||
        upper.contains('ISO') ||
        upper.contains('CERTIFIED') ||
        upper.contains('CERTIFICATION') ||
        _nonPhoneIdentifiersRegExp.hasMatch(upper)) {
      return true;
    }

    // Standalone 5 or 6 digit postal codes (e.g. 600028 or 90210)
    if (RegExp(r'^\s*(?:PIN\s*:?)?\s*\d{5,6}\s*$', caseSensitive: false)
        .hasMatch(line)) {
      return true;
    }

    // Standard date formats
    if (_datePatternRegExp.hasMatch(line)) {
      return true;
    }

    // Tenure year range patterns without explicit phone label
    if (_yearRangeRegExp.hasMatch(line) && detectPhoneLabel(line) == null) {
      return true;
    }

    return false;
  }
}
