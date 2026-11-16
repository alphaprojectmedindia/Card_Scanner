import 'package:flutter/foundation.dart';
import '../../models/business_card_email.dart';

/// Structured representation of a recovered email candidate from OCR.
class EmailCandidate {
  final String raw;
  final String email;
  final String normalized;
  final String? label;
  final double confidence;
  final bool wasSpacedReconstructed;
  final bool wasSplitJoined;
  final bool hasCharacterCorrection;
  final String? diagnosticNote;

  const EmailCandidate({
    required this.raw,
    required this.email,
    required this.normalized,
    this.label,
    this.confidence = 0.90,
    this.wasSpacedReconstructed = false,
    this.wasSplitJoined = false,
    this.hasCharacterCorrection = false,
    this.diagnosticNote,
  });

  BusinessCardEmail toBusinessCardEmail() => BusinessCardEmail(
        email: email,
        normalizedEmail: normalized,
        label: label,
      );

  Map<String, dynamic> toJson() => {
        'raw': raw,
        'email': email,
        'normalized': normalized,
        if (label != null) 'label': label,
        'confidence': double.parse(confidence.toStringAsFixed(2)),
        'wasSpacedReconstructed': wasSpacedReconstructed,
        'wasSplitJoined': wasSplitJoined,
        'hasCharacterCorrection': hasCharacterCorrection,
        if (diagnosticNote != null) 'diagnosticNote': diagnosticNote,
      };

  @override
  String toString() =>
      'EmailCandidate($email, label: $label, conf: ${(confidence * 100).toStringAsFixed(0)}%)';
}

/// Robust, zero-hallucination email recovery engine for business card OCR.
///
/// Handles:
/// 1. Standard single-line emails (e.g. "denil@medindia.net")
/// 2. Spaced email reconstruction (e.g. "denil @ medindia.net", "denil@ medindia.net", "denil@medindia . net")
/// 3. Split-line email reconstruction across 2-3 adjacent lines (e.g. "denil\n@\nmedindia.net")
/// 4. Tightly controlled character confusion correction only inside verified email structures
///    (e.g. ".c0m" -> ".com", ".corn" -> ".com", ".0rg" -> ".org")
/// 5. Label detection (e.g. "Email: ...", "E-mail: ...", "Mail: ...", "E: ...")
/// 6. Strict RFC-like validation and non-email rejection (e.g. websites, dates, street addresses)
/// 7. Normalized deduplication and zero hallucination.
class EmailOcrRecovery {
  // Strict standard email pattern
  static final RegExp standardEmailPattern = RegExp(
    r'\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b',
    caseSensitive: false,
  );

  // Email labels appearing before or near the email address
  static final RegExp emailLabelPattern = RegExp(
    r'(?:^|[^\w])(?:email|e-mail|mail|e)\s*[:\-•|]\s*',
    caseSensitive: false,
  );

  // Spaced email candidate pattern on a single line
  // Catches: "username @ domain . com", "username@ domain.com", "username @domain.com", "username@domain . com"
  static final RegExp spacedEmailPattern = RegExp(
    r'([a-zA-Z0-9._%+-]+)\s*(?:@|\(at\)|\[at\]|[©®])\s*([a-zA-Z0-9.-]+(?:\s*\.\s*[a-zA-Z0-9.-]+)*\s*\.\s*[a-zA-Z0-9]{2,})',
    caseSensitive: false,
  );

  // Known top-level domains for validation and controlled correction
  static const Set<String> commonTlds = {
    'com', 'org', 'net', 'edu', 'gov', 'mil', 'int',
    'io', 'ai', 'co', 'in', 'us', 'uk', 'de', 'fr', 'ca', 'au',
    'biz', 'info', 'tech', 'app', 'dev', 'me', 'tv', 'cc',
  };

  /// Normalizes an email for deduplication (lowercased, trimmed).
  static String normalizeEmail(String email) {
    return email.trim().toLowerCase();
  }

  /// Checks if text contains email-like evidence even if no valid email could be parsed directly.
  static bool hasUnresolvedEmailEvidence(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase().trim();
      if (line.isEmpty) continue;

      // Has email label
      if (emailLabelPattern.hasMatch(line)) return true;

      // Contains isolated @ or (at)
      if (line.contains('@') || line.contains('(at)') || line.contains('[at]')) {
        return true;
      }
    }
    return false;
  }

  /// Extracts, reconstructs, corrects, and validates all email candidates from OCR lines.
  static List<EmailCandidate> extractEmailCandidates(
    List<String> rawLines, {
    String? sourceEngine,
  }) {
    if (rawLines.isEmpty) return const [];

    final candidates = <EmailCandidate>[];
    final seenNormalized = <String>{};

    // Step 1: Pre-process lines and attempt multi-line reconstruction
    final preprocessedLines = _reconstructSplitLines(rawLines);

    // Step 2: Extract from preprocessed lines
    for (int i = 0; i < preprocessedLines.length; i++) {
      final line = preprocessedLines[i];
      if (line.trim().isEmpty) continue;

      // Check for email label in the line or immediately preceding line
      final label = _extractLabel(line) ??
          (i > 0 ? _extractLabel(preprocessedLines[i - 1]) : null);

      // Strip email label prefix if present for candidate parsing
      final cleanLine = line.replaceAll(emailLabelPattern, ' ').trim();

      // Attempt A: Standard strict regex match
      final standardMatches = standardEmailPattern.allMatches(cleanLine);
      for (final match in standardMatches) {
        final rawMatch = match.group(0)!;
        _validateAndAdd(
          rawMatch,
          originalRaw: rawMatch,
          label: label,
          wasSpaced: false,
          wasSplit: line.contains('[SPLIT_JOINED]'),
          hasCorrection: false,
          candidates: candidates,
          seenNormalized: seenNormalized,
        );
      }

      // Attempt B: Spaced email regex match (handles spaces around @ or dots)
      final spacedMatches = spacedEmailPattern.allMatches(cleanLine);
      for (final match in spacedMatches) {
        final local = match.group(1)!.trim().replaceAll(RegExp(r'\s+'), '');
        final rawDomain = match.group(2)!.trim();
        // Remove spaces inside domain
        final cleanDomain = rawDomain.replaceAll(RegExp(r'\s+'), '');
        final rawCandidate = '$local@$cleanDomain';

        // Apply controlled character correction on domain/TLD
        final correction = _applyControlledEmailCorrection(rawCandidate);

        _validateAndAdd(
          correction.corrected,
          originalRaw: match.group(0)!,
          label: label,
          wasSpaced: true,
          wasSplit: line.contains('[SPLIT_JOINED]'),
          hasCorrection: correction.hasCorrection,
          diagnosticNote: correction.note,
          candidates: candidates,
          seenNormalized: seenNormalized,
        );
      }

      // Attempt C: Missing dot before known TLD (e.g. "user@examplecom" -> "user@example.com")
      if (cleanLine.contains('@') && !cleanLine.contains('.')) {
        final missingDotMatch = RegExp(
          r'([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9-]+?)(com|org|net|in|co|io|ai|tech|biz|info|dev|app|edu|gov)\b',
          caseSensitive: false,
        ).firstMatch(cleanLine);
        if (missingDotMatch != null) {
          final local = missingDotMatch.group(1)!;
          final sld = missingDotMatch.group(2)!;
          final tld = missingDotMatch.group(3)!;
          if (sld.isNotEmpty && sld.length >= 2) {
            final reconstructed = '$local@$sld.$tld';
            _validateAndAdd(
              reconstructed,
              originalRaw: missingDotMatch.group(0)!,
              label: label,
              wasSpaced: false,
              wasSplit: false,
              hasCorrection: true,
              diagnosticNote: 'Reconstructed missing dot before TLD: .$tld',
              candidates: candidates,
              seenNormalized: seenNormalized,
            );
          }
        }
      }
    }

    // Step 3: Raw concatenated text fallback for edge cases
    if (candidates.isEmpty) {
      final fullText = rawLines.join(' ');
      final spacedMatches = spacedEmailPattern.allMatches(fullText);
      for (final match in spacedMatches) {
        final local = match.group(1)!.trim().replaceAll(RegExp(r'\s+'), '');
        final rawDomain = match.group(2)!.trim().replaceAll(RegExp(r'\s+'), '');
        final rawCandidate = '$local@$rawDomain';
        final correction = _applyControlledEmailCorrection(rawCandidate);

        _validateAndAdd(
          correction.corrected,
          originalRaw: match.group(0)!,
          label: _extractLabel(fullText),
          wasSpaced: true,
          wasSplit: true,
          hasCorrection: correction.hasCorrection,
          diagnosticNote: correction.note,
          candidates: candidates,
          seenNormalized: seenNormalized,
        );
      }
    }

    return suppressEmailFragments(candidates);
  }

  /// Suppresses truncated, subsumed, or numeric fragment emails.
  /// E.g. "951@gmail.com" and "1951@gmail.com" when "lnazmul.haque1951@gmail.com" is present.
  /// "6@gmail.com" when "tanakagawa86@gmail.com" is present.
  /// "i1973@hotmail.com" when "vardhaman_1973@hotmail.com" is present.
  static List<EmailCandidate> suppressEmailFragments(List<EmailCandidate> candidates) {
    if (candidates.length <= 1) return candidates;

    final results = <EmailCandidate>[];
    for (int i = 0; i < candidates.length; i++) {
      final cand = candidates[i];
      final parts = cand.normalized.split('@');
      if (parts.length != 2) {
        results.add(cand);
        continue;
      }
      final local = parts[0];
      final domain = parts[1];

      bool isSubsumed = false;
      for (int j = 0; j < candidates.length; j++) {
        if (i == j) continue;
        final other = candidates[j];
        final otherParts = other.normalized.split('@');
        if (otherParts.length != 2) continue;
        final otherLocal = otherParts[0];
        final otherDomain = otherParts[1];

        if (domain != otherDomain) continue;
        if (local == otherLocal) continue;

        // 1. Other local ends with this local (e.g. lnazmul.haque1951 ends with 1951 or 951; tanakagawa86 ends with 6)
        if (otherLocal.endsWith(local) && otherLocal.length > local.length) {
          isSubsumed = true;
          break;
        }

        // 2. This local is purely numeric and other local contains it
        if (RegExp(r'^\d+$').hasMatch(local) && otherLocal.contains(local) && otherLocal.length > local.length) {
          isSubsumed = true;
          break;
        }

        // 3. This local stripped of leading single-letter / noise char matches a suffix of other
        // e.g. "i1973" -> "1973", which is suffix of "vardhaman_1973"
        final strippedLocal = local.replaceAll(RegExp(r'^[a-zA-Z_.-]'), '');
        if (strippedLocal.isNotEmpty &&
            strippedLocal.length >= 3 &&
            otherLocal.endsWith(strippedLocal) &&
            otherLocal.length > local.length) {
          isSubsumed = true;
          break;
        }

        // 4. This local is contained within other local, and this local is short (<= 5 chars)
        if (otherLocal.contains(local) && local.length <= 5 && otherLocal.length > local.length) {
          isSubsumed = true;
          break;
        }
      }

      if (!isSubsumed) {
        results.add(cand);
      }
    }
    return results;
  }

  /// Reconstructs emails split across adjacent lines.
  static List<String> _reconstructSplitLines(List<String> lines) {
    final result = <String>[];
    int i = 0;

    while (i < lines.length) {
      final current = lines[i].trim();

      // Pattern 1: 3-line split ("username" \n "@" \n "domain.com")
      if (i + 2 < lines.length) {
        final line2 = lines[i + 1].trim();
        final line3 = lines[i + 2].trim();

        if ((line2 == '@' || line2 == '(at)' || line2 == '[at]' || line2 == '©' || line2 == '®') &&
            _isProbableLocalPart(current) &&
            _isProbableDomainPart(line3)) {
          final joined = '$current@$line3 [SPLIT_JOINED]';
          result.add(joined);
          if (kDebugMode) {
            print('[EmailOCR] Reconstructed 3-line split email: "$current" + "$line2" + "$line3" -> $joined');
          }
          i += 3;
          continue;
        }
      }

      // Pattern 2: 2-line split ("username@" \n "domain.com" OR "username" \n "@domain.com")
      if (i + 1 < lines.length) {
        final next = lines[i + 1].trim();

        if (current.endsWith('@') && _isProbableDomainPart(next)) {
          final joined = '$current$next [SPLIT_JOINED]';
          result.add(joined);
          if (kDebugMode) {
            print('[EmailOCR] Reconstructed split email (trailing @): "$current" + "$next" -> $joined');
          }
          i += 2;
          continue;
        } else if (next.startsWith('@') && _isProbableLocalPart(current)) {
          final joined = '$current$next [SPLIT_JOINED]';
          result.add(joined);
          if (kDebugMode) {
            print('[EmailOCR] Reconstructed split email (leading @): "$current" + "$next" -> $joined');
          }
          i += 2;
          continue;
        } else if (_isProbableLocalPart(current) && _isProbableDomainPart(next) &&
            (current.toLowerCase().contains('email') || next.toLowerCase().contains('.com') || next.toLowerCase().contains('.in') || next.toLowerCase().contains('.org') || next.toLowerCase().contains('.net'))) {
          // Both adjacent pieces look like username and domain without explicit @ symbol (e.g. OCR dropped @ or fused it)
          // DO NOT synthesize @ blindly unless next starts with @ or current has email label
        }
      }

      result.add(current);
      i++;
    }

    return result;
  }

  static bool _isProbableLocalPart(String text) {
    final clean = text.replaceAll(emailLabelPattern, '').trim();
    if (clean.isEmpty || clean.length > 40) return false;
    return RegExp(r'^[a-zA-Z0-9._%+-]+$').hasMatch(clean);
  }

  static bool _isProbableDomainPart(String text) {
    final clean = text.trim();
    if (clean.isEmpty || clean.length > 50) return false;
    return RegExp(r'^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(clean);
  }

  /// Applies tightly controlled OCR corrections ONLY inside strongly email-like candidates.
  static ({String corrected, bool hasCorrection, String? note}) _applyControlledEmailCorrection(
    String rawEmail,
  ) {
    if (!rawEmail.contains('@')) {
      return (corrected: rawEmail, hasCorrection: false, note: null);
    }

    final atIndex = rawEmail.indexOf('@');
    final local = rawEmail.substring(0, atIndex);
    var domain = rawEmail.substring(atIndex + 1);

    bool corrected = false;
    final notes = <String>[];

    // Controlled TLD corrections
    // 1. ".c0m" -> ".com"
    if (domain.endsWith('.c0m')) {
      domain = '${domain.substring(0, domain.length - 4)}.com';
      corrected = true;
      notes.add('c0m->com');
    }
    // 2. ".corn" -> ".com" (OCR often merges 'r' and 'n' into 'm' or vice-versa)
    else if (domain.endsWith('.corn')) {
      domain = '${domain.substring(0, domain.length - 5)}.com';
      corrected = true;
      notes.add('corn->com');
    }
    // 3. ".0rg" -> ".org"
    else if (domain.endsWith('.0rg')) {
      domain = '${domain.substring(0, domain.length - 4)}.org';
      corrected = true;
      notes.add('0rg->org');
    }
    // 4. ".nel" -> ".net"
    else if (domain.endsWith('.nel')) {
      domain = '${domain.substring(0, domain.length - 4)}.net';
      corrected = true;
      notes.add('nel->net');
    }
    // 5. ".c0.in" -> ".co.in"
    else if (domain.endsWith('.c0.in')) {
      domain = '${domain.substring(0, domain.length - 6)}.co.in';
      corrected = true;
      notes.add('c0.in->co.in');
    }

    final result = '$local@$domain';
    return (
      corrected: result,
      hasCorrection: corrected,
      note: corrected ? 'Email OCR correction: ${notes.join(", ")}' : null,
    );
  }

  /// Extracts email label from text.
  static String? _extractLabel(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('personal')) return 'Personal';
    if (lower.contains('work') || lower.contains('office') || lower.contains('official')) {
      return 'Work';
    }
    if (emailLabelPattern.hasMatch(text)) return 'Email';
    return null;
  }

  /// Validates an email candidate against RFC-like structural requirements.
  static bool isValidEmail(String email) {
    if (email.isEmpty || email.length > 254) return false;
    if (email.contains(RegExp(r'\s'))) return false;

    // Disallow URLs
    final lower = email.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('www.')) {
      return false;
    }

    final parts = email.split('@');
    if (parts.length != 2) return false;

    final local = parts[0];
    final domain = parts[1];

    if (local.isEmpty || local.length > 64) return false;
    if (local.startsWith('.') || local.endsWith('.')) return false;
    if (local.contains('..')) return false;
    if (!RegExp(r'^[a-zA-Z0-9._%+-]+$').hasMatch(local)) return false;

    if (domain.isEmpty || domain.length > 253) return false;
    if (domain.startsWith('.') || domain.endsWith('.')) return false;
    if (domain.startsWith('-') || domain.endsWith('-')) return false;
    if (domain.contains('..')) return false;

    final domainLabels = domain.split('.');
    if (domainLabels.length < 2) return false;

    for (int i = 0; i < domainLabels.length; i++) {
      final label = domainLabels[i];
      if (label.isEmpty || label.length > 63) return false;

      if (i == domainLabels.length - 1) {
        // TLD must be alphabetic and at least 2 chars
        if (!RegExp(r'^[a-zA-Z]{2,}$').hasMatch(label)) return false;
      } else {
        if (!RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$').hasMatch(label)) {
          return false;
        }
      }
    }

    return true;
  }

  static void _validateAndAdd(
    String emailCandidate, {
    required String originalRaw,
    required String? label,
    required bool wasSpaced,
    required bool wasSplit,
    required bool hasCorrection,
    String? diagnosticNote,
    required List<EmailCandidate> candidates,
    required Set<String> seenNormalized,
  }) {
    // Clean outer punctuation
    var cleaned = emailCandidate.trim();
    cleaned = cleaned.replaceAll(RegExp(r'''^[\s<>()\[\]{}:;,.`|•✉\-_"']+'''), '');
    cleaned = cleaned.replaceAll(RegExp(r'''[\s<>()\[\]{}:;,.`|•✉\-_"']+$'''), '');

    if (!isValidEmail(cleaned)) return;

    final normalized = normalizeEmail(cleaned);
    if (seenNormalized.contains(normalized)) return;
    seenNormalized.add(normalized);

    candidates.add(EmailCandidate(
      raw: originalRaw,
      email: cleaned,
      normalized: normalized,
      label: label,
      confidence: hasCorrection ? 0.88 : (wasSpaced || wasSplit ? 0.90 : 0.96),
      wasSpacedReconstructed: wasSpaced,
      wasSplitJoined: wasSplit,
      hasCharacterCorrection: hasCorrection,
      diagnosticNote: diagnosticNote,
    ));
  }
}
