import 'package:flutter/foundation.dart';
import '../models/business_card_data.dart';
import '../models/business_card_email.dart';
import '../models/business_card_phone.dart';

/// Conservative heuristic parser that converts raw recognized OCR text into
/// structured [BusinessCardData].
class BusinessCardParser {
  const BusinessCardParser();

  static final RegExp _emailRegExp = RegExp(
    r'\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b',
    caseSensitive: false,
  );

  static final RegExp _urlSchemeOrWwwRegExp = RegExp(
    r'(https?:\/\/[^\s]+|www\.[a-zA-Z0-9\-]+(?:\.[a-zA-Z0-9\-]+)+(?:\/[^\s]*)?)',
    caseSensitive: false,
  );

  static final RegExp _domainRegExp = RegExp(
    r'\b([a-zA-Z0-9\-]+\.(?:com|org|net|in|co\.in|io|ai|tech|biz|info|gov|edu|me|dev|app|co))\b',
    caseSensitive: false,
  );

  static const List<String> _jobTitleKeywords = [
    'developer',
    'senior developer',
    'software engineer',
    'senior software engineer',
    'engineer',
    'managing director',
    'director',
    'executive director',
    'sales manager',
    'manager',
    'general manager',
    'project manager',
    'product manager',
    'founder',
    'co-founder',
    'ceo',
    'cto',
    'cfo',
    'coo',
    'cmo',
    'doctor',
    'consultant',
    'senior consultant',
    'lead',
    'team lead',
    'tech lead',
    'architect',
    'designer',
    'ui/ux designer',
    'president',
    'vice president',
    'vp',
    'partner',
    'analyst',
    'specialist',
    'executive',
    'associate',
    'officer',
  ];

  static const List<String> _companyKeywords = [
    'technologies',
    'technology',
    'tech',
    'solutions',
    'services',
    'enterprises',
    'corporation',
    'corp',
    'inc',
    'llc',
    'ltd',
    'limited',
    'pvt ltd',
    'private limited',
    'holdings',
    'group',
    'consulting',
    'studio',
    'labs',
    'agency',
    'ventures',
    'systems',
    'software',
    'industries',
    'global',
    'international',
    'associates',
    'infotech',
  ];

  static const List<String> _addressKeywords = [
    'street',
    'st',
    'road',
    'rd',
    'avenue',
    'ave',
    'lane',
    'floor',
    'suite',
    'bldg',
    'building',
    'nagar',
    'colony',
    'plot',
    'sector',
    'tower',
    'towers',
    'plaza',
    'complex',
    'opposite',
    'opp',
    'near',
    'post',
    'chennai',
    'bangalore',
    'bengaluru',
    'mumbai',
    'delhi',
    'hyderabad',
    'kolkata',
    'pune',
    'india',
    'usa',
  ];

  /// Parses raw OCR text into structured [BusinessCardData].
  BusinessCardData parse(String rawText) {
    if (rawText.trim().isEmpty) {
      return BusinessCardData(rawRecognizedText: rawText);
    }

    final rawLines = rawText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (rawLines.isEmpty) {
      return BusinessCardData(rawRecognizedText: rawText);
    }

    // 1. Extract Emails
    final emails = _extractEmails(rawLines, rawText);

    // 2. Extract Websites (ignoring domains embedded inside email addresses)
    final website = _extractWebsite(rawLines, emails);

    // 3. Extract Phone Numbers (conservative parsing)
    final phoneNumbers = _extractPhoneNumbers(rawLines);

    // 4. Extract Job Title
    final jobTitleMatch = _extractJobTitle(rawLines);
    final jobTitle = jobTitleMatch?.value;

    // 5. Extract Company
    final companyMatch = _extractCompany(rawLines, jobTitleMatch?.lineIndex);
    final company = companyMatch?.value;

    // 6. Extract Full Name
    final fullName = _extractFullName(
      rawLines,
      jobTitleIndex: jobTitleMatch?.lineIndex,
      companyIndex: companyMatch?.lineIndex,
      extractedPhones: phoneNumbers,
      extractedEmails: emails,
      website: website,
    );

    // 7. Extract Address
    final address = _extractAddress(
      rawLines,
      extractedPhones: phoneNumbers,
      extractedEmails: emails,
      website: website,
      name: fullName,
      company: company,
      jobTitle: jobTitle,
    );

    return BusinessCardData(
      fullName: fullName,
      company: company,
      jobTitle: jobTitle,
      phoneNumbers: phoneNumbers,
      emailAddresses: emails,
      website: website,
      address: address,
      rawRecognizedText: rawText,
    );
  }

  // ---------------------------------------------------------------------------
  // EMAIL EXTRACTION & CANDIDATE RECOVERY
  // ---------------------------------------------------------------------------
  static final RegExp _emailCandidateSpacedRegExp = RegExp(
    r'[a-zA-Z0-9._%+-]+(?:\s*[._%+-]\s*[a-zA-Z0-9]+)*\s*(?:@|\(at\)|\[at\]|[©®])\s*[a-zA-Z0-9]+(?:\s*[-]\s*[a-zA-Z0-9]+)*(?:\s*[\.,]\s*[a-zA-Z0-9]+(?:\s*[-]\s*[a-zA-Z0-9]+)*)*\s*[\.,]\s*[a-zA-Z]{2,}',
    caseSensitive: false,
  );

  List<BusinessCardEmail> _extractEmails(List<String> lines, String rawText) {
    final results = <BusinessCardEmail>[];
    final seenNormalized = <String>{};
    final candidateLogs = <String>[];

    // 1. Single line extraction
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final preceding = i > 0 ? lines[i - 1] : null;
      _collectEmailCandidatesFromText(
        line,
        results: results,
        seenNormalized: seenNormalized,
        candidateLogs: candidateLogs,
        contextLine: line,
        precedingLine: preceding,
      );
    }

    // 2. Adjacent line recovery (2 adjacent lines)
    for (int i = 0; i < lines.length - 1; i++) {
      final line1 = lines[i];
      final line2 = lines[i + 1];
      final combined = '$line1 $line2';
      final preceding = i > 0 ? lines[i - 1] : null;
      _collectEmailCandidatesFromText(
        combined,
        results: results,
        seenNormalized: seenNormalized,
        candidateLogs: candidateLogs,
        contextLine: combined,
        precedingLine: preceding,
      );
    }

    // 3. Adjacent line recovery (3 adjacent lines with mid OCR symbol)
    for (int i = 0; i < lines.length - 2; i++) {
      final line1 = lines[i].trim();
      final line2 = lines[i + 1].trim();
      final line3 = lines[i + 2].trim();

      if (line2 == '@' ||
          line2 == '(at)' ||
          line2 == '[at]' ||
          line2 == '©' ||
          line2 == '®' ||
          line1.endsWith('@') ||
          line3.startsWith('@')) {
        final combined = '$line1 $line2 $line3';
        final preceding = i > 0 ? lines[i - 1] : null;
        _collectEmailCandidatesFromText(
          combined,
          results: results,
          seenNormalized: seenNormalized,
          candidateLogs: candidateLogs,
          contextLine: combined,
          precedingLine: preceding,
        );
      }
    }

    // 4. Raw text fallback (handling block or line breaks within text)
    _collectEmailCandidatesFromText(
      rawText,
      results: results,
      seenNormalized: seenNormalized,
      candidateLogs: candidateLogs,
      contextLine: rawText,
    );

    // Section 11: Concise Diagnostic Logging (debug builds only)
    if (kDebugMode) {
      debugPrint('[OCR_EMAIL] RAW OCR TEXT:\n$rawText');
      debugPrint('[OCR_EMAIL] EMAIL CANDIDATES: $candidateLogs');
      debugPrint('[OCR_EMAIL] VALID EMAILS: ${results.map((e) => e.email).toList()}');
    }

    return results;
  }

  void _collectEmailCandidatesFromText(
    String text, {
    required List<BusinessCardEmail> results,
    required Set<String> seenNormalized,
    required List<String> candidateLogs,
    required String contextLine,
    String? precedingLine,
  }) {
    // 1. Strict RFC regex matches
    final strictMatches = _emailRegExp.allMatches(text);
    for (final match in strictMatches) {
      final rawMatch = match.group(0)!;
      _processAndAddCandidate(
        rawMatch,
        results: results,
        seenNormalized: seenNormalized,
        candidateLogs: candidateLogs,
        contextLine: contextLine,
        precedingLine: precedingLine,
      );
    }

    // 2. OCR-spaced candidate matches
    final spacedMatches = _emailCandidateSpacedRegExp.allMatches(text);
    for (final match in spacedMatches) {
      final rawMatch = match.group(0)!;
      _processAndAddCandidate(
        rawMatch,
        results: results,
        seenNormalized: seenNormalized,
        candidateLogs: candidateLogs,
        contextLine: contextLine,
        precedingLine: precedingLine,
      );
    }
  }

  void _processAndAddCandidate(
    String rawCandidate, {
    required List<BusinessCardEmail> results,
    required Set<String> seenNormalized,
    required List<String> candidateLogs,
    required String contextLine,
    String? precedingLine,
  }) {
    if (kDebugMode && !candidateLogs.contains(rawCandidate)) {
      candidateLogs.add(rawCandidate);
    }

    final cleaned = _cleanEmailCandidate(rawCandidate);
    if (!_isValidEmail(cleaned)) {
      return;
    }

    final normalized = BusinessCardEmail.normalize(cleaned);
    if (seenNormalized.contains(normalized)) {
      return;
    }

    seenNormalized.add(normalized);
    final label = _detectEmailLabel(contextLine, precedingLine: precedingLine);

    results.add(BusinessCardEmail(
      email: cleaned,
      normalizedEmail: normalized,
      label: label,
    ));
  }

  /// Conservative email preprocessing for OCR noise, spaces around separators,
  /// surrounding wrappers/punctuation, and domain commas.
  String _cleanEmailCandidate(String candidate) {
    var s = candidate.trim();

    // 1. Replace OCR @ glyph variations in email context
    s = s.replaceAll(
      RegExp(r'\s*(?:\(at\)|\[at\]|[©®])\s*', caseSensitive: false),
      '@',
    );

    // 2. Strip surrounding punctuation, brackets, quotes, bullet points, email icons
    s = s.replaceAll(RegExp(r'''^[\s<>()\[\]{}:;,.`|•✉\-_"']+'''), '');
    s = s.replaceAll(RegExp(r'''[\s<>()\[\]{}:;,.`|•✉\-_"']+$'''), '');

    // 3. Compress whitespace around email separators (@, ., _, -, +)
    s = s.replaceAllMapped(
      RegExp(r'\s*([@._%+-])\s*'),
      (m) => m.group(1)!,
    );

    // 4. Correct OCR comma-for-dot confusion in domain portion
    if (s.contains('@')) {
      final atIndex = s.indexOf('@');
      final local = s.substring(0, atIndex);
      var domain = s.substring(atIndex + 1);
      domain = domain.replaceAll(',', '.');
      s = '$local@$domain';
    }

    // 5. Final trim of any remaining trailing punctuation
    s = s.replaceAll(RegExp(r'[\.,;:!\-]+$'), '');

    return s.trim();
  }

  /// Strict email validator ensuring exactly one @, valid local part,
  /// valid domain labels, and alphabetical TLD >= 2 chars.
  bool _isValidEmail(String email) {
    if (email.isEmpty || email.length > 254) return false;

    // Reject any internal whitespace
    if (email.contains(RegExp(r'\s'))) return false;

    // Reject URLs
    final lower = email.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('www.')) {
      return false;
    }

    // Exactly one @
    final parts = email.split('@');
    if (parts.length != 2) return false;

    final localPart = parts[0];
    final domainPart = parts[1];

    // Local part constraints (RFC 5321)
    if (localPart.isEmpty || localPart.length > 64) return false;
    if (localPart.startsWith('.') || localPart.endsWith('.')) return false;
    if (localPart.contains('..')) return false;
    if (!RegExp(r'^[a-zA-Z0-9._%+-]+$').hasMatch(localPart)) return false;

    // Domain part constraints
    if (domainPart.isEmpty || domainPart.length > 253) return false;
    if (domainPart.startsWith('.') || domainPart.endsWith('.')) return false;
    if (domainPart.startsWith('-') || domainPart.endsWith('-')) return false;
    if (domainPart.contains('..')) return false;

    final domainLabels = domainPart.split('.');
    if (domainLabels.length < 2) return false;

    for (int i = 0; i < domainLabels.length; i++) {
      final label = domainLabels[i];
      if (label.isEmpty || label.length > 63) return false;

      // Last label is TLD: must be strictly alphabetical, >= 2 chars
      if (i == domainLabels.length - 1) {
        if (!RegExp(r'^[a-zA-Z]{2,}$').hasMatch(label)) return false;
      } else {
        // Domain label: alphanumeric with hyphens, cannot start/end with hyphen
        if (!RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$')
            .hasMatch(label)) {
          return false;
        }
      }
    }

    return true;
  }

  String? _detectEmailLabel(String contextText, {String? precedingLine}) {
    final lower = contextText.toLowerCase();
    if (lower.contains('personal')) {
      return 'Personal';
    } else if (lower.contains('work') || lower.contains('office')) {
      return 'Work';
    }

    if (precedingLine != null) {
      final preLower = precedingLine.toLowerCase();
      if (preLower.contains('personal')) {
        return 'Personal';
      } else if (preLower.contains('work') || preLower.contains('office')) {
        return 'Work';
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // WEBSITE EXTRACTION
  // ---------------------------------------------------------------------------
  String? _extractWebsite(List<String> lines, List<BusinessCardEmail> emails) {
    for (final line in lines) {
      // 1. Explicit http://, https:// or www.
      final urlMatch = _urlSchemeOrWwwRegExp.firstMatch(line);
      if (urlMatch != null) {
        var url = urlMatch.group(0)!;
        // Trim trailing punctuation
        url = url.replaceAll(RegExp(r'[,\.;:!]+$'), '');
        return url;
      }

      // 2. Line indicator: "Website: abc.com" or "Web: abc.com"
      final webIndicatorMatch = RegExp(
        r'(?:website|web|site|url)\s*[:\-]?\s*([a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(?:\/[^\s]*)?)',
        caseSensitive: false,
      ).firstMatch(line);
      if (webIndicatorMatch != null) {
        var url = webIndicatorMatch.group(1)!;
        url = url.replaceAll(RegExp(r'[,\.;:!]+$'), '');
        return url;
      }

      // 3. Standalone domain like "abc.com", ensuring it's not part of an email address
      final domainMatches = _domainRegExp.allMatches(line);
      for (final match in domainMatches) {
        final domainStr = match.group(1)!;
        // Check if this domain is only appearing as part of an email in this line
        final isEmailDomainOnly = emails.any((e) {
          final parts = e.email.split('@');
          if (parts.length != 2) return false;
          final domainMatch = parts[1].toLowerCase() == domainStr.toLowerCase();
          if (!domainMatch) return false;
          return line.contains(e.email) ||
              (line.contains('@') && line.toLowerCase().contains(parts[1].toLowerCase()));
        });

        // Also check if line has '@' preceding this token
        final atIndex = line.indexOf('@');
        final domainIndex = line.indexOf(domainStr);
        final hasAtBefore = atIndex != -1 && atIndex < domainIndex;

        if (!isEmailDomainOnly && !hasAtBefore) {
          return domainStr.replaceAll(RegExp(r'[,\.;:!]+$'), '');
        }
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // PHONE EXTRACTION
  // ---------------------------------------------------------------------------
  List<BusinessCardPhone> _extractPhoneNumbers(List<String> lines) {
    final results = <BusinessCardPhone>[];
    final seenNormalized = <String>{};

    for (final line in lines) {
      // Reject noisy lines containing non-phone identifiers like PIN, CIN, GST, Reg No
      if (_isNonPhoneLine(line)) {
        continue;
      }

      // Split line by delimiters if multiple numbers exist (e.g., / , | , or ;)
      final segments = line.split(RegExp(r'\s*[\|\/,;]\s*'));
      for (final segment in segments) {
        final phone = _extractPhoneFromSegment(segment);
        if (phone != null) {
          final norm = phone.normalizedNumber ?? BusinessCardPhone.normalize(phone.number);
          final digitsOnly = norm.replaceAll(RegExp(r'\D'), '');

          // Check if already captured or duplicate representation
          if (_isDuplicatePhone(norm, digitsOnly, seenNormalized)) {
            continue;
          }

          seenNormalized.add(norm);
          if (digitsOnly.isNotEmpty) {
            seenNormalized.add(digitsOnly);
          }

          results.add(phone);
        }
      }
    }

    return results;
  }

  bool _isNonPhoneLine(String line) {
    final upper = line.toUpperCase();
    // Indian postal PIN code or CIN / GST / Reg number / Invoice
    if (upper.contains('PIN:') ||
        upper.contains('PIN CODE') ||
        upper.contains('PINCODE') ||
        upper.contains('POSTAL CODE') ||
        upper.contains('ZIP:') ||
        upper.contains('ZIP CODE') ||
        upper.contains('CIN:') ||
        upper.contains('CIN ') ||
        upper.contains('GSTIN') ||
        upper.contains('GST:') ||
        upper.contains('REG NO') ||
        upper.contains('REG.') ||
        upper.contains('REGISTRATION') ||
        upper.contains('INVOICE')) {
      // Only treat as non-phone line if it doesn't also have an explicit phone indicator
      if (!upper.contains('MOBILE') &&
          !upper.contains('MOB:') &&
          !upper.contains('TEL:') &&
          !upper.contains('PHONE:') &&
          !upper.contains('OFFICE:')) {
        return true;
      }
    }

    // Ignore lines that are pure 5-digit or 6-digit postal codes
    if (RegExp(r'^\s*(?:PIN\s*:?)?\s*\d{5,6}\s*$', caseSensitive: false).hasMatch(line)) {
      return true;
    }

    return false;
  }

  BusinessCardPhone? _extractPhoneFromSegment(String segment) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) return null;

    // Detect label if present
    final label = _detectPhoneLabel(trimmed);

    // Patterns for valid phone numbers:
    // 1. International with '+': +91 98765 43210, +1 415 555 0123, +91 (98765) 43210, +91-98765-43210
    final plusPattern = RegExp(
      r'(\+\d{1,4}[\s\-\.]?\(?\d{1,5}\)?(?:[\s\-\.]?\d{2,6}){1,4})',
    );
    final plusMatch = plusPattern.firstMatch(trimmed);
    if (plusMatch != null) {
      final numStr = plusMatch.group(1)!.trim();
      final digits = numStr.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 7 && digits.length <= 15) {
        return BusinessCardPhone(
          number: numStr,
          normalizedNumber: BusinessCardPhone.normalize(numStr),
          label: label,
        );
      }
    }

    // 2. National with leading 0 or STD code: 044 2345 6789, 044-23456789
    final stdPattern = RegExp(
      r'\b(0\d{2,4}[\s\-\.]?\d{3,4}[\s\-\.]?\d{3,4})\b',
    );
    final stdMatch = stdPattern.firstMatch(trimmed);
    if (stdMatch != null) {
      final numStr = stdMatch.group(1)!.trim();
      final digits = numStr.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 8 && digits.length <= 12) {
        return BusinessCardPhone(
          number: numStr,
          normalizedNumber: BusinessCardPhone.normalize(numStr),
          label: label,
        );
      }
    }

    // 3. Indian standard 10-digit mobile number: 9876543210, 98765 43210, 98765-43210
    // Starts with 6, 7, 8, 9
    final indianMobilePattern = RegExp(
      r'\b([6-9]\d{4}[\s\-\.]?\d{5})\b|\b([6-9]\d{9})\b',
    );
    final indianMatch = indianMobilePattern.firstMatch(trimmed);
    if (indianMatch != null) {
      final numStr = (indianMatch.group(1) ?? indianMatch.group(2))!.trim();
      final digits = numStr.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 10) {
        return BusinessCardPhone(
          number: numStr,
          normalizedNumber: BusinessCardPhone.normalize(numStr),
          label: label,
        );
      }
    }

    // 4. US / Intl format with parentheses: (415) 555 0123, (415) 555-0123
    final parenPattern = RegExp(
      r'(\(\d{3}\)[\s\-\.]?\d{3}[\s\-\.]?\d{4})',
    );
    final parenMatch = parenPattern.firstMatch(trimmed);
    if (parenMatch != null) {
      final numStr = parenMatch.group(1)!.trim();
      return BusinessCardPhone(
        number: numStr,
        normalizedNumber: BusinessCardPhone.normalize(numStr),
        label: label,
      );
    }

    // 5. If segment had an explicit phone label (e.g. "Phone: 2345 6789" or "Tel: 23456789")
    if (label != null) {
      final trailingNumMatch = RegExp(r'(?:[:\-])\s*([\d\s\-\.\(\)\+]{7,16})').firstMatch(trimmed);
      if (trailingNumMatch != null) {
        final numStr = trailingNumMatch.group(1)!.trim();
        final digits = numStr.replaceAll(RegExp(r'\D'), '');
        if (digits.length >= 7 && digits.length <= 15) {
          return BusinessCardPhone(
            number: numStr,
            normalizedNumber: BusinessCardPhone.normalize(numStr),
            label: label,
          );
        }
      }
    }

    return null;
  }

  String? _detectPhoneLabel(String text) {
    final lower = text.toLowerCase();
    if (lower.startsWith('mobile') ||
        lower.contains('mobile:') ||
        lower.contains('mob:') ||
        lower.contains('cell:') ||
        lower.contains('cell ')) {
      return 'Mobile';
    }
    if (lower.startsWith('office') ||
        lower.contains('office:') ||
        lower.contains('off:')) {
      return 'Office';
    }
    if (lower.startsWith('work') || lower.contains('work:')) {
      return 'Work';
    }
    if (lower.startsWith('personal') || lower.contains('personal:')) {
      return 'Personal';
    }
    if (lower.startsWith('phone') ||
        lower.contains('phone:') ||
        lower.contains('ph:') ||
        lower.contains('tel:') ||
        lower.contains('telephone') ||
        lower.contains('call:')) {
      return 'Phone';
    }
    return null;
  }

  bool _isDuplicatePhone(String norm, String digits, Set<String> seen) {
    if (seen.contains(norm) || (digits.isNotEmpty && seen.contains(digits))) {
      return true;
    }

    // Also check cross representation:
    // e.g. +919876543210 vs 9876543210
    for (final s in seen) {
      final sDigits = s.replaceAll(RegExp(r'\D'), '');
      if (sDigits.isEmpty || digits.isEmpty) continue;

      if (sDigits == digits) return true;

      // Indian mobile suffix match (10 digits)
      if (digits.length == 10 && sDigits.length == 12 && sDigits.endsWith(digits)) {
        return true;
      }
      if (sDigits.length == 10 && digits.length == 12 && digits.endsWith(sDigits)) {
        return true;
      }

      // National 0 prefix vs international +91 or +country code
      if (digits.startsWith('0') && sDigits.endsWith(digits.substring(1))) {
        return true;
      }
      if (sDigits.startsWith('0') && digits.endsWith(sDigits.substring(1))) {
        return true;
      }
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // JOB TITLE EXTRACTION
  // ---------------------------------------------------------------------------
  _ExtractionResult? _extractJobTitle(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Check for explicit label e.g., "Designation: Senior Developer"
      final labelMatch = RegExp(
        r'^(?:designation|job title|title|role)\s*[:\-]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (labelMatch != null) {
        return _ExtractionResult(labelMatch.group(1)!.trim(), i);
      }

      final lower = line.toLowerCase();
      // Line matches known job title
      for (final title in _jobTitleKeywords) {
        if (lower == title ||
            lower.startsWith('$title ') ||
            lower.endsWith(' $title') ||
            lower.contains(' $title ')) {
          // Verify it does not look like an address or full sentence
          if (!_isAddressLine(line) && line.length < 50) {
            return _ExtractionResult(line, i);
          }
        }
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // COMPANY EXTRACTION
  // ---------------------------------------------------------------------------
  _ExtractionResult? _extractCompany(List<String> lines, int? jobTitleIndex) {
    for (int i = 0; i < lines.length; i++) {
      if (i == jobTitleIndex) continue;
      final line = lines[i];

      // Explicit label e.g. "Company: ABC Technologies"
      final labelMatch = RegExp(
        r'^(?:company|organization|org)\s*[:\-]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (labelMatch != null) {
        return _ExtractionResult(labelMatch.group(1)!.trim(), i);
      }

      final lower = line.toLowerCase();
      for (final kw in _companyKeywords) {
        if (lower.contains(kw) && !_isAddressLine(line) && line.length < 60) {
          // Reject if it is a website URL or email
          if (!_emailRegExp.hasMatch(line) &&
              !line.contains('@') &&
              !_urlSchemeOrWwwRegExp.hasMatch(line)) {
            return _ExtractionResult(line, i);
          }
        }
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // FULL NAME EXTRACTION
  // ---------------------------------------------------------------------------
  String? _extractFullName(
    List<String> lines, {
    int? jobTitleIndex,
    int? companyIndex,
    required List<BusinessCardPhone> extractedPhones,
    required List<BusinessCardEmail> extractedEmails,
    String? website,
  }) {
    // 1. Check for explicit name label e.g. "Name: Rahul Kumar"
    for (final line in lines) {
      final labelMatch = RegExp(
        r'^name\s*[:\-]\s*([a-zA-Z\s\.\-]+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (labelMatch != null) {
        final val = labelMatch.group(1)!.trim();
        if (val.isNotEmpty) return val;
      }
    }

    // 2. If job title was found, line immediately above it is very commonly the name!
    if (jobTitleIndex != null && jobTitleIndex > 0) {
      final candidateIndex = jobTitleIndex - 1;
      final candidate = lines[candidateIndex];
      if (_isValidNameCandidate(
        candidate,
        companyIndex: companyIndex,
        extractedPhones: extractedPhones,
        extractedEmails: extractedEmails,
        website: website,
      )) {
        return candidate;
      }
    }

    // 3. Search eligible candidate lines from top of card
    for (int i = 0; i < lines.length; i++) {
      if (i == jobTitleIndex || i == companyIndex) continue;
      final line = lines[i];

      if (_isValidNameCandidate(
        line,
        companyIndex: companyIndex,
        extractedPhones: extractedPhones,
        extractedEmails: extractedEmails,
        website: website,
      )) {
        return line;
      }
    }

    return null;
  }

  bool _isValidNameCandidate(
    String line, {
    int? companyIndex,
    required List<BusinessCardPhone> extractedPhones,
    required List<BusinessCardEmail> extractedEmails,
    String? website,
  }) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.length > 35) return false;

    // Disallow numbers or special characters in names
    if (RegExp(r'[\d@#\$%^&*\+=\[\]\\\/<>]').hasMatch(trimmed)) return false;

    // Disallow emails or websites
    if (_emailRegExp.hasMatch(trimmed) ||
        _urlSchemeOrWwwRegExp.hasMatch(trimmed) ||
        _domainRegExp.hasMatch(trimmed)) {
      return false;
    }

    final lower = trimmed.toLowerCase();

    // Disallow address words
    for (final kw in _addressKeywords) {
      if (lower == kw || lower.contains(' $kw') || lower.startsWith('$kw ')) {
        return false;
      }
    }

    // Disallow company keywords
    for (final kw in _companyKeywords) {
      if (lower.contains(kw)) return false;
    }

    // Disallow job title keywords
    for (final kw in _jobTitleKeywords) {
      if (lower == kw || lower.contains(kw)) return false;
    }

    // Must consist of 1 to 4 alphabetical words
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.isEmpty || words.length > 4) return false;

    for (final w in words) {
      // Must be letters (allowing period like Dr. or M.)
      if (!RegExp(r'^[a-zA-Z\.]+$').hasMatch(w)) return false;
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // ADDRESS EXTRACTION
  // ---------------------------------------------------------------------------
  String? _extractAddress(
    List<String> lines, {
    required List<BusinessCardPhone> extractedPhones,
    required List<BusinessCardEmail> extractedEmails,
    String? website,
    String? name,
    String? company,
    String? jobTitle,
  }) {
    final addressLines = <String>[];

    for (final line in lines) {
      // Skip lines matching phone, email, website, name, company, or job title
      if (name != null && line.toLowerCase() == name.toLowerCase()) continue;
      if (company != null && line.toLowerCase() == company.toLowerCase()) continue;
      if (jobTitle != null && line.toLowerCase() == jobTitle.toLowerCase()) continue;
      if (website != null && line.toLowerCase().contains(website.toLowerCase())) continue;
      if (_emailRegExp.hasMatch(line) ||
          line.contains('@') ||
          extractedEmails.any((e) => line.contains(e.email))) {
        continue;
      }
      if (extractedPhones.any((p) => line.contains(p.number))) continue;

      // Check for explicit Address: label
      final addrLabelMatch = RegExp(
        r'^(?:address|addr|office address)\s*[:\-]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (addrLabelMatch != null) {
        addressLines.add(addrLabelMatch.group(1)!.trim());
        continue;
      }

      if (_isAddressLine(line)) {
        addressLines.add(line);
      }
    }

    if (addressLines.isEmpty) return null;
    return addressLines.join(', ');
  }

  bool _isAddressLine(String line) {
    final lower = line.toLowerCase();
    for (final kw in _addressKeywords) {
      if (lower.contains(kw)) {
        return true;
      }
    }
    return false;
  }
}

class _ExtractionResult {
  final String value;
  final int lineIndex;

  _ExtractionResult(this.value, this.lineIndex);
}
