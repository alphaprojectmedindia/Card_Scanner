import 'dart:math';
import 'package:flutter/foundation.dart';
import 'email_ocr_recovery.dart';
import 'field_candidate.dart';
import 'phone_ocr_recovery.dart';

/// Semantic evaluator that scores, penalizes, and resolves business card fields independently.
/// Enforces separation of raw OCR confidence from semantic field confidence.
class FieldSemanticEvaluator {
  static final RegExp _emailRegExp = RegExp(
    r'\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b',
    caseSensitive: false,
  );

  static final RegExp _phoneRegExp = RegExp(
    r'(?:\+?\d{1,4}[\s-]?)?(?:\(?\d{2,5}\)?[\s-]?)?\d{3,5}[\s-]?\d{3,5}',
  );

  static final RegExp _urlSchemeOrWwwRegExp = RegExp(
    r'(https?:\/\/[^\s]+|www\.[a-zA-Z0-9\-]+(?:\.[a-zA-Z0-9\-]+)+(?:\/[^\s]*)?)',
    caseSensitive: false,
  );

  static final RegExp _domainRegExp = RegExp(
    r'\b([a-zA-Z0-9\-]+\.(?:com|org|net|in|co\.in|io|ai|tech|biz|info|gov|edu|me|dev|app|co|co\.uk|org\.uk))\b',
    caseSensitive: false,
  );

  static final RegExp _honorificPrefixRegExp = RegExp(
    r'^(?:dr\.|dr|prof\.|prof|er\.|er|ca|adv\.|adv|advocate|mr\.|mr|mrs\.|mrs|ms\.|ms|shri|smt|chef)\s+',
    caseSensitive: false,
  );

  static final RegExp _credentialTokenRegExp = RegExp(
    r'\b(?:I\.?A\.?S|I\.?P\.?S|I\.?F\.?S|I\.?R\.?S|M\.?B\.?B\.?S|M\.?D|M\.?S|M\.?D\.?S|B\.?D\.?S|D\.?M|M\.?Ch|D\.?N\.?B|Ph\.?D|D\.?Phil|F\.?R\.?C\.?S|F\.?A\.?C\.?S|M\.?R\.?C\.?P|M\.?R\.?C\.?S|M\.?R\.?O\.?C\.?G|F\.?R\.?C\.?O\.?G|L\.?L\.?[BM]|J\.?D|C\.?P\.?A|C\.?F\.?A|P\.?M\.?P|F\.?C\.?A|A\.?C\.?A|B\.?Tech|M\.?Tech|B\.?E|M\.?E|M\.?B\.?A|B\.?B\.?A|B\.?Sc|M\.?Sc|Esq|Retd|Jr|Sr)\b\.?',
    caseSensitive: false,
  );

  // Common corporate legal entity suffixes
  static final RegExp _orgSuffixRegExp = RegExp(
    r'\b(ltd\.?|limited|pvt\.?|private|llc|llp|inc\.?|incorporated|corp\.?|corporation|company|co\.?|gmbh|sa|ag|undertaking|foundation|trust|society|federation|association|council|board|ministry|department|consulate|embassy)\b',
    caseSensitive: false,
  );

  // Common organization / industry category keywords
  static final RegExp _companyTypeTokensRegExp = RegExp(
    r'\b(technologies|technology|solutions|services|enterprises|industries|systems|laboratories|labs|holdings|group|consulting|consultancy|agency|studio|studios|associates|partners|chambers|law\s+firm|hospital|hospitals|clinic|clinics|infirmary|dispensary|university|college|school|institute|academy|bank|banking|insurance|securities|investments|builders|construction|contractors|motors|garage|realty|properties|events|electronics|global|international|shipping|logistics|freight|dispatch|trading|corporation|hardware|software)\b',
    caseSensitive: false,
  );

  // Common job titles and occupational designations
  static final RegExp _titleTokensRegExp = RegExp(
    r'\b(director|managing\s+director|executive\s+director|manager|general\s+manager|sales\s+manager|project\s+manager|product\s+manager|marketing\s+manager|engineer|software\s+engineer|developer|consultant|senior\s+consultant|officer|consul|hon\.\s*consul|president|vice\s+president|vp|head|lead|founder|co-founder|partner|specialist|analyst|associate|architect|designer|coordinator|advisor|executive|supervisor|administrator|secretary|additional\s+chief\s+secretary|attorney|counsel|advocate|solicitor|professor|associate\s+professor|assistant\s+professor|lecturer|scientist|researcher|surgeon|physician|doctor|cardiologist|neurologist|dermatologist|pediatrician|oncologist|accountant|chartered\s+accountant|auditor|proprietor|trustee)\b',
    caseSensitive: false,
  );

  // Common occupational title modifiers
  static final RegExp _titleModifierRegExp = RegExp(
    r'\b(senior|sr\.?|junior|jr\.?|chief|lead|head|principal|executive|assistant|associate|deputy|vice|general|regional|global|group|managing|operations|technical|strategy|strategic|business|marketing|sales|product|project)\b',
    caseSensitive: false,
  );

  // Structural address indicators (streets, roads, numbers, postal codes, locality patterns)
  static final RegExp _addressTokensRegExp = RegExp(
    r'\b(road|rd\.?|street|st\.?|avenue|ave\.?|lane|ln\.?|boulevard|blvd\.?|drive|dr\.?|way|circle|nagar|salai|marg|chowk|sector|block|floor|suite|plot|building|bldg\.?|tower|towers|plaza|complex|cross|main|po\s+box|p\.o\.|pin|zip|post|colony|layout|enclave|opp\.?|opposite|near|behind)\b|\b(?<!real\s)estate\b|\b\d{1,4}[A-Za-z]?[\s,\-\/]+(?:road|rd|street|st|avenue|ave|lane|ln|drive|dr|nagar|salai|marg|sector|block|cross|main)\b|\b\d{5,6}\b|\b[1-9][0-9]{2}\s?[0-9]{3}\b|\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b',
    caseSensitive: false,
  );

  // Prominent geographical names / major world & Indian cities (generic heuristic support)
  static final RegExp _majorGeographicalTokensRegExp = RegExp(
    r'\b(chennai|bangalore|bengaluru|mumbai|delhi|new\s+delhi|hyderabad|kolkata|pune|ahmedabad|jaipur|kochi|coimbatore|madurai|trichy|mysore|calicut|chandigarh|lucknow|kanpur|nagpur|indore|bhopal|patna|vadodara|surat|visakhapatnam|thiruvananthapuram|new\s+york|san\s+francisco|los\s+angeles|chicago|houston|austin|seattle|london|paris|berlin|tokyo|singapore|dubai|abu\s+dhabi|sydney|melbourne|toronto|vancouver|california|texas|florida|tamil\s+nadu|karnataka|maharashtra|kerala|andhra\s+pradesh|telangana|gujarat|india|usa|uk|united\s+states|united\s+kingdom|germany|france|spain|italy|australia|canada)\b',
    caseSensitive: false,
  );

  // Slogan & marketing phrase indicators
  static final List<RegExp> _sloganPatterns = [
    RegExp(
      r'^(?:we|i)\s+(?:bring|make|create|deliver|help|build|connect|inspire|serve|care|empower|believe|transform|shape|provide)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\bperformances?\s+alive\b',
      caseSensitive: false,
    ),
    RegExp(
      r'^(?:building|transforming|creating|delivering|empowering|innovating|connecting|inspiring|shaping|providing|making|protecting|helping|enabling|promoting|serving|leading|driving|securing|advancing|fostering|pioneering)\s+[a-zA-Z\s]{2,}\b',
      caseSensitive: false,
    ),
    RegExp(
      r'^(?:health information for all|excellence in (?:service|technology|healthcare|care|innovation|quality|design)|building the future|your trusted partner|transforming (?:healthcare|business|technology)|quality first|together we grow|innovating for tomorrow|shaping the future|powering possibilities|delivering excellence|committed to quality|care and compassion|always (?:by your side|with you)|where quality meets|passion for (?:excellence|service|work)|dedicated to (?:excellence|service|care))\b',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:for all|in service|our passion|we believe|solutions for tomorrow|better communities|trusted partner|world class|better tomorrow|all rights reserved)\s*$',
      caseSensitive: false,
    ),
    RegExp(
      r'^(?:since|estd\.?|established)\s+\d{4}',
      caseSensitive: false,
    ),
  ];

  // OCR corruption indicators
  static final RegExp _corruptedWordRegExp = RegExp(
    r'\b[A-Za-z]+[b-df-hj-np-tv-z]{2,}[A-Z][b-df-hj-np-tv-z]+[a-z]*\b|\b[a-zA-Z]+[0-9|~`!#$%^&*()_+=|\\{}[\];<>?][a-zA-Z]+\b',
  );

  // ---------------------------------------------------------------------------
  // NAME CANDIDATE EVALUATION
  // ---------------------------------------------------------------------------

  /// Evaluates and scores a single text line as a person name candidate.
  /// Generates positive evidence, identifies negative signals, and computes semantic confidence.
  static FieldCandidate evaluateNameCandidate({
    required String rawLine,
    required String sourceEngine,
    int lineIndex = 0,
    int totalLines = 1,
    int? jobTitleIndex,
    String? surroundingText,
    String? website,
    List<String> detectedEmails = const [],
    List<String> detectedPhones = const [],
    double ocrConfidence = 0.90,
  }) {
    final trimmed = rawLine.trim();
    final positiveEvidence = <String>[];
    final rejectionReasons = <String>[];

    if (trimmed.isEmpty) {
      return FieldCandidate(
        field: 'fullName',
        value: '',
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        rejectionReasons: const ['Line is empty'],
      );
    }

    // Pre-extract credentials attached via comma (e.g. "Kumar Jayant, I.A.S.")
    String cleanName = trimmed;
    String? attachedCredentials;
    if (cleanName.contains(',')) {
      final parts = cleanName.split(',');
      final beforeComma = parts[0].trim();
      final afterComma = parts.sublist(1).join(',').trim();
      if (_credentialTokenRegExp.hasMatch(afterComma)) {
        cleanName = beforeComma;
        attachedCredentials = afterComma;
        positiveEvidence.add('Has verified credential suffix: "$afterComma"');
      }
    }

    // Strip leading/trailing bullet points or icons
    cleanName = cleanName
        .replaceAll(RegExp(r'^[•\-\*\>👤\s,]+'), '')
        .replaceAll(RegExp(r'[•\-\*\>👤\s,]+$'), '')
        .trim();

    double score = 0.0;

    // 1. Contact / URL / Noise Disqualification
    if (_emailRegExp.hasMatch(trimmed) || trimmed.contains('@')) {
      rejectionReasons.add('Contains email address');
      return _buildRejectedNameCandidate(cleanName, sourceEngine, ocrConfidence, rejectionReasons);
    }

    if (_urlSchemeOrWwwRegExp.hasMatch(trimmed) || _domainRegExp.hasMatch(trimmed)) {
      rejectionReasons.add('Contains URL or web domain');
      return _buildRejectedNameCandidate(cleanName, sourceEngine, ocrConfidence, rejectionReasons);
    }

    if (detectedPhones.any((p) => trimmed.contains(p)) ||
        RegExp(r'\b\d{7,15}\b').hasMatch(trimmed.replaceAll(RegExp(r'\D'), ''))) {
      rejectionReasons.add('Contains phone number or excessive digits');
      return _buildRejectedNameCandidate(cleanName, sourceEngine, ocrConfidence, rejectionReasons);
    }

    // 2. Location / Address Rejection (CRITICAL)
    final bool looksLikeAddress = isLocationOrAddressLine(trimmed);
    if (looksLikeAddress) {
      rejectionReasons.add('Contains structural location or address indicator');
    }

    final bool hasPostalCode = RegExp(r'\b\d{5,6}\b').hasMatch(trimmed) ||
        RegExp(r'\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b', caseSensitive: false).hasMatch(trimmed);
    if (hasPostalCode) {
      rejectionReasons.add('Contains postal code / PIN / ZIP');
    }

    final bool matchesGeographical = _majorGeographicalTokensRegExp.hasMatch(trimmed);
    if (matchesGeographical) {
      // Check if it's purely a location line (e.g. "Chennai", "Chennai - 600004", "New Delhi")
      final words = cleanName.split(RegExp(r'[\s\-,\.]+')).where((w) => w.isNotEmpty).toList();
      final nonGeoWords = words.where((w) => !_majorGeographicalTokensRegExp.hasMatch(w) && !RegExp(r'^\d+$').hasMatch(w)).toList();
      if (nonGeoWords.isEmpty) {
        rejectionReasons.add('Line consists purely of city / geographic location ("$cleanName")');
        return FieldCandidate(
          field: 'fullName',
          value: cleanName,
          sourceEngine: sourceEngine,
          ocrConfidence: ocrConfidence,
          semanticConfidence: 0.05, // Virtually zero!
          positiveEvidence: positiveEvidence,
          rejectionReasons: rejectionReasons,
          spatialEvidence: {'lineIndex': lineIndex, 'isPureLocation': true},
        );
      } else {
        rejectionReasons.add('Contains prominent city / geographical name');
      }
    }

    // 3. Organization / Brand Suffix Rejection
    final bool hasOrgSuffix = _orgSuffixRegExp.hasMatch(trimmed);
    if (hasOrgSuffix) {
      rejectionReasons.add('Contains corporate organization suffix (e.g. Ltd, Pvt, LLC, Inc)');
      return _buildRejectedNameCandidate(cleanName, sourceEngine, ocrConfidence, rejectionReasons);
    }

    final bool hasCompanyType = _companyTypeTokensRegExp.hasMatch(trimmed);
    if (hasCompanyType) {
      rejectionReasons.add('Contains corporate business category / company token');
      return _buildRejectedNameCandidate(cleanName, sourceEngine, ocrConfidence, rejectionReasons);
    }

    // Website or email domain match
    if (website != null) {
      final normDomain = _normalizeDomain(website);
      final normName = cleanName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normName.length >= 4 && normDomain.contains(normName)) {
        rejectionReasons.add('Matches website domain ("$website")');
      }
    }

    for (final email in detectedEmails) {
      if (email.contains('@')) {
        final domainPart = email.split('@').last.split('.').first.toLowerCase();
        final normName = cleanName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (domainPart.length >= 3 && (normName == domainPart || (normName.length >= 4 && normName.contains(domainPart)))) {
          rejectionReasons.add('Matches domain of email ("$domainPart")');
          score -= 0.60;
          break;
        }
      }
    }

    // 4. Slogan Rejection
    final bool isSloganLine = isSlogan(trimmed);
    if (isSloganLine) {
      rejectionReasons.add('Matches advertising tagline / slogan pattern');
    }

    // 5. Job Title Rejection
    final bool isTitle = _titleTokensRegExp.hasMatch(trimmed);
    if (isTitle && !_honorificPrefixRegExp.hasMatch(trimmed) && attachedCredentials == null) {
      rejectionReasons.add('Matches job title / occupational designation');
    }

    // 6. OCR Corruption Check
    final corruptedMatches = _corruptedWordRegExp.allMatches(trimmed);
    int corruptionCount = 0;
    for (final cm in corruptedMatches) {
      final w = cm.group(0)!;
      if (w != 'iPhone' && w != 'iPad' && w != 'eBay') {
        corruptionCount++;
      }
    }
    if (corruptionCount > 0) {
      rejectionReasons.add('Contains $corruptionCount corrupted / fragmented word token(s)');
    }

    // --- POSITIVE SIGNALS & HEURISTICS ---

    // Signal: Explicit label "Name: John Doe"
    final labelMatch = RegExp(r'^name\s*[:\-]\s*(.+)$', caseSensitive: false).firstMatch(cleanName);
    if (labelMatch != null) {
      cleanName = labelMatch.group(1)!.trim();
      positiveEvidence.add('Has explicit "Name:" prefix');
      score += 0.50;
    }

    // Signal: Personal honorific (Dr., Prof., Mr., Ms., Adv., etc.)
    if (_honorificPrefixRegExp.hasMatch(cleanName)) {
      positiveEvidence.add('Contains professional or personal honorific');
      score += 0.35;
    }

    // Signal: Attached credentials
    if (attachedCredentials != null) {
      score += 0.30;
    }

    // Token analysis
    final words = cleanName.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final wordCount = words.length;

    // Plausible human name token count: 2 to 4 words (or 1 with honorific)
    if (wordCount >= 2 && wordCount <= 4) {
      positiveEvidence.add('Has natural 2-4 token human name structure');
      score += 0.30;
    } else if (wordCount == 1 && _honorificPrefixRegExp.hasMatch(cleanName)) {
      positiveEvidence.add('Single word preceded by personal honorific');
      score += 0.20;
    } else if (wordCount > 5) {
      rejectionReasons.add('Excessive word count ($wordCount words) for a person name');
      score -= 0.30;
    }

    // Signal: Matches email username / local-part token(s) (strong person name evidence)
    for (final email in detectedEmails) {
      if (email.contains('@')) {
        final localPart = email.split('@').first.toLowerCase();
        final localTokens = localPart
            .split(RegExp(r'[\._\-\d]+'))
            .where((t) => t.length >= 3)
            .toList();
        for (final w in words) {
          final cleanWord = w.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
          if (cleanWord.length >= 3 &&
              localTokens.any((t) =>
                  t == cleanWord ||
                  (cleanWord.length >= 4 && t.contains(cleanWord)))) {
            positiveEvidence.add('Matches email username token "$cleanWord" from email "$email"');
            score += 0.35;
            break;
          }
        }
      }
    }

    // Initials support (e.g. "A. Kumar", "K. S. Raman", "Chandra Kanthan. M", "A K Last")
    // Do NOT give an artificial score bonus to initials over full names!
    final hasInitials = words.any((w) =>
        RegExp(r'^[A-Z]\.?$').hasMatch(w) ||
        RegExp(r'^[A-Z]\.[A-Z]\.?$').hasMatch(w));
    if (hasInitials) {
      positiveEvidence.add('Contains standard name initial(s)');
      // Abbreviated initial is valid, but full names beat initials when evidence exists
      score -= 0.10;
    } else if (wordCount >= 2 && words.every((w) => w.length >= 3)) {
      positiveEvidence.add('Fully expanded multi-character name tokens');
      score += 0.15;
    }

    // Capitalization check: Title Case or ALL CAPS
    final isAllCaps = RegExp(r'^[A-Z\s\.\,\-]+$').hasMatch(cleanName) && cleanName.length >= 4;
    final isTitleCase = words.every((w) {
      final clean = w.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      if (clean.isEmpty) return true;
      return clean[0] == clean[0].toUpperCase();
    });

    if (isTitleCase || isAllCaps) {
      positiveEvidence.add(isAllCaps ? 'ALL CAPS person name formatting' : 'Title Case person name formatting');
      score += 0.15;
    } else {
      rejectionReasons.add('Irregular lowercase capitalization');
      score -= 0.20;
    }

    // Spatial Layout Prominence
    if (jobTitleIndex != null && lineIndex == jobTitleIndex - 1) {
      positiveEvidence.add('Positioned immediately above job title');
      score += 0.30;
    } else if (lineIndex <= 2) {
      positiveEvidence.add('Positioned in prominent upper section of card (line $lineIndex)');
      score += 0.15;
    }

    // Character length reasonableness
    if (cleanName.length >= 4 && cleanName.length <= 35) {
      score += 0.10;
    } else if (cleanName.length < 3 || cleanName.length > 50) {
      rejectionReasons.add('Unusual character length (${cleanName.length})');
      score -= 0.30;
    }

    // Apply Penalties from negative signals
    if (looksLikeAddress) score -= 0.50;
    if (hasPostalCode) score -= 0.60;
    if (matchesGeographical) score -= 0.40;
    if (hasOrgSuffix) score -= 0.60;
    if (hasCompanyType) score -= 0.60;
    if (isSloganLine) score -= 0.60;
    if (isTitle && !_honorificPrefixRegExp.hasMatch(cleanName) && attachedCredentials == null) {
      score -= 0.45;
    }
    if (corruptionCount > 0) score -= (0.20 * corruptionCount);

    final semanticConfidence = score.clamp(0.0, 1.0);

    return FieldCandidate(
      field: 'fullName',
      value: cleanName,
      sourceEngine: sourceEngine,
      ocrConfidence: ocrConfidence,
      semanticConfidence: semanticConfidence,
      positiveEvidence: positiveEvidence,
      rejectionReasons: rejectionReasons,
      spatialEvidence: {
        'lineIndex': lineIndex,
        'totalLines': totalLines,
        'jobTitleIndex': ?jobTitleIndex,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // JOB TITLE CANDIDATE EVALUATION
  // ---------------------------------------------------------------------------

  static FieldCandidate evaluateJobTitleCandidate({
    required String rawLine,
    required String sourceEngine,
    int lineIndex = 0,
    int? personIndex,
    double ocrConfidence = 0.90,
  }) {
    final trimmed = rawLine.trim();
    final positiveEvidence = <String>[];
    final rejectionReasons = <String>[];

    if (trimmed.isEmpty) {
      return FieldCandidate(
        field: 'jobTitle',
        value: '',
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
      );
    }

    double score = 0.0;

    // Explicit label e.g. "Title: Managing Director"
    final labelMatch = RegExp(r'^(?:designation|job\s+title|title|role)\s*[:\-]\s*(.+)$', caseSensitive: false)
        .firstMatch(trimmed);
    String cleanTitle = trimmed;
    if (labelMatch != null) {
      cleanTitle = labelMatch.group(1)!.trim();
      positiveEvidence.add('Has explicit "Title:" prefix');
      score += 0.50;
    }

    // Keyword match
    if (_titleTokensRegExp.hasMatch(cleanTitle)) {
      positiveEvidence.add('Matches known occupational / title keywords');
      score += 0.40;

      final words = cleanTitle.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.length <= 4 && words.every((w) => _titleTokensRegExp.hasMatch(w) || _titleModifierRegExp.hasMatch(w))) {
        positiveEvidence.add('Pure occupational title phrase');
        score += 0.35;
      }
    }

    // Proximity to person name
    if (personIndex != null && lineIndex == personIndex + 1) {
      positiveEvidence.add('Positioned immediately beneath person name');
      score += 0.30;
    }

    // Penalize if contains org suffix (Ltd, LLC, Inc)
    if (_orgSuffixRegExp.hasMatch(cleanTitle)) {
      rejectionReasons.add('Contains corporate legal entity suffix');
      score -= 0.50;
    }

    // Penalize if address
    if (isLocationOrAddressLine(cleanTitle)) {
      rejectionReasons.add('Contains address or location indicators');
      score -= 0.60;
    }

    final semanticConfidence = score.clamp(0.0, 1.0);
    return FieldCandidate(
      field: 'jobTitle',
      value: cleanTitle,
      sourceEngine: sourceEngine,
      ocrConfidence: ocrConfidence,
      semanticConfidence: semanticConfidence,
      positiveEvidence: positiveEvidence,
      rejectionReasons: rejectionReasons,
      spatialEvidence: {'lineIndex': lineIndex},
    );
  }

  // ---------------------------------------------------------------------------
  // COMPANY CANDIDATE EVALUATION
  // ---------------------------------------------------------------------------

  static FieldCandidate evaluateCompanyCandidate({
    required String rawLine,
    required String sourceEngine,
    int lineIndex = 0,
    String? website,
    List<String> emails = const [],
    double ocrConfidence = 0.90,
  }) {
    final trimmed = rawLine.trim();
    final positiveEvidence = <String>[];
    final rejectionReasons = <String>[];

    if (trimmed.isEmpty) {
      return FieldCandidate(
        field: 'company',
        value: '',
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
      );
    }

    double score = 0.0;

    // Explicit label e.g. "Company: Medindia"
    final labelMatch = RegExp(r'^(?:company|organization|org)\s*[:\-]\s*(.+)$', caseSensitive: false)
        .firstMatch(trimmed);
    String cleanCompany = trimmed;
    if (labelMatch != null) {
      cleanCompany = labelMatch.group(1)!.trim();
      positiveEvidence.add('Has explicit "Company:" prefix');
      score += 0.50;
    }

    // Corporate entity suffix (Ltd, Pvt Ltd, Inc, Corp, LLC)
    if (_orgSuffixRegExp.hasMatch(cleanCompany)) {
      positiveEvidence.add('Contains formal corporate suffix (Ltd, Inc, LLC)');
      score += 0.45;
    }

    // Industry / organization category
    if (_companyTypeTokensRegExp.hasMatch(cleanCompany)) {
      positiveEvidence.add('Contains organization category keyword');
      score += 0.35;
    }

    // Website domain match
    if (website != null) {
      final normDomain = _normalizeDomain(website);
      final normComp = cleanCompany.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normComp.length >= 4 && normDomain.contains(normComp)) {
        positiveEvidence.add('Matches domain of official website ("$website")');
        score += 0.40;
      }
    }

    // Email domain match
    for (final email in emails) {
      if (email.contains('@')) {
        final domainPart = email.split('@').last.split('.').first.toLowerCase();
        final normComp = cleanCompany.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (domainPart.length >= 3 && normComp.contains(domainPart)) {
          positiveEvidence.add('Matches domain of email ("$domainPart")');
          score += 0.40;
          break;
        }
      }
    }

    // Top branding position
    if (lineIndex == 0) {
      positiveEvidence.add('Positioned at top of card (line 0)');
      score += 0.20;
    }

    // Well-capitalized company / organization name structure
    final words = cleanCompany.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isNotEmpty && words.length <= 4) {
      final capitalized = words.where((w) => w[0].toUpperCase() == w[0]).length;
      if (capitalized == words.length) {
        positiveEvidence.add('Well-capitalized entity name');
        score += 0.15;
      }
    }

    // Penalize if it's a known job title (e.g. "Chief Technology Officer")
    if (_titleTokensRegExp.hasMatch(cleanCompany)) {
      rejectionReasons.add('Matches job title pattern ("$cleanCompany")');
      score -= 0.60;
    }

    // Penalize if it's a person name with personal honorific
    if (_honorificPrefixRegExp.hasMatch(cleanCompany)) {
      rejectionReasons.add('Starts with personal honorific');
      score -= 0.60;
    }

    // Penalize if address
    if (isLocationOrAddressLine(cleanCompany)) {
      rejectionReasons.add('Contains address indicators');
      score -= 0.60;
    }

    final semanticConfidence = score.clamp(0.0, 1.0);
    return FieldCandidate(
      field: 'company',
      value: cleanCompany,
      sourceEngine: sourceEngine,
      ocrConfidence: ocrConfidence,
      semanticConfidence: semanticConfidence,
      positiveEvidence: positiveEvidence,
      rejectionReasons: rejectionReasons,
      spatialEvidence: {'lineIndex': lineIndex},
    );
  }

  // ---------------------------------------------------------------------------
  // ADDRESS CANDIDATE EVALUATION
  // ---------------------------------------------------------------------------

  static FieldCandidate evaluateAddressCandidate({
    required List<String> addressLines,
    required String sourceEngine,
    double ocrConfidence = 0.90,
  }) {
    if (addressLines.isEmpty) {
      return FieldCandidate(
        field: 'address',
        value: '',
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
      );
    }

    final positiveEvidence = <String>[];
    final combined = addressLines.join(', ');
    double score = 0.20;

    if (_addressTokensRegExp.hasMatch(combined)) {
      positiveEvidence.add('Contains street/road/avenue/floor anchors');
      score += 0.35;
    }

    if (RegExp(r'\b\d{5,6}\b').hasMatch(combined) ||
        RegExp(r'\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b', caseSensitive: false).hasMatch(combined)) {
      positiveEvidence.add('Contains valid postal PIN / ZIP code');
      score += 0.30;
    }

    if (addressLines.length >= 2) {
      positiveEvidence.add('Multi-line address cluster (${addressLines.length} lines)');
      score += 0.20;
    }

    final semanticConfidence = score.clamp(0.0, 1.0);
    return FieldCandidate(
      field: 'address',
      value: combined,
      sourceEngine: sourceEngine,
      ocrConfidence: ocrConfidence,
      semanticConfidence: semanticConfidence,
      positiveEvidence: positiveEvidence,
    );
  }

  // ---------------------------------------------------------------------------
  // HELPER CHECKERS (Generic & Contextual)
  // ---------------------------------------------------------------------------

  static bool isLocationOrAddressLine(String line) {
    final lower = line.toLowerCase().trim();
    if (lower.isEmpty) return false;

    // Exclude personal honorifics
    if (_honorificPrefixRegExp.hasMatch(line.trim())) return false;

    // Exclude occupational titles like "Licensed Real Estate Broker / Agent"
    if (lower.contains('real estate') && (lower.contains('broker') || lower.contains('agent') || lower.contains('realtor') || lower.contains('consultant'))) {
      return false;
    }

    if (_addressTokensRegExp.hasMatch(lower)) return true;

    // PIN/ZIP code with preceding locality or number
    if (RegExp(r'\b\d{5,6}\b').hasMatch(line) &&
        (lower.contains('pin') || lower.contains('zip') || lower.contains('-') || lower.contains(','))) {
      return true;
    }

    // Pure geographic line (e.g. "Chennai", "Chennai - 600004", "New Delhi - 110001")
    if (_majorGeographicalTokensRegExp.hasMatch(lower)) {
      final words = lower.split(RegExp(r'[\s\-,\.]+')).where((w) => w.isNotEmpty).toList();
      final nonGeo = words.where((w) => !_majorGeographicalTokensRegExp.hasMatch(w) && !RegExp(r'^\d+$').hasMatch(w)).toList();
      if (nonGeo.isEmpty) return true;
    }

    return false;
  }

  static bool isSlogan(String line) {
    final lower = line.toLowerCase().trim();
    if (lower.isEmpty) return false;

    if (_orgSuffixRegExp.hasMatch(lower)) return false;

    for (final p in _sloganPatterns) {
      if (p.hasMatch(lower)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // FIELD-LEVEL RESOLVER (No Global Engine Winner)
  // ---------------------------------------------------------------------------

  /// Performs independent field-level resolution across primary (ML Kit) and secondary (PaddleOCR) outputs.
  /// Each field is evaluated strictly on semantic evidence rather than overall engine scores.
  static FieldResolutionResult resolveFields({
    required List<String> primaryLines,
    required String primaryEngineName,
    required double primaryOcrQualityScore,
    required List<String> secondaryLines,
    required String secondaryEngineName,
    required double secondaryOcrQualityScore,
  }) {
    final agreedSignals = <String>[];
    final alternatives = <String, List<String>>{};
    final diagnosticNotes = <String>[];

    // 1. EXTRACT & RESOLVE PHONES (Union + Cross-Engine Deduplication + Label Preservation)
    final primaryPhones = PhoneOcrRecovery.extractPhoneCandidates(
      primaryLines,
      sourceEngine: primaryEngineName,
    );
    final secondaryPhones = PhoneOcrRecovery.extractPhoneCandidates(
      secondaryLines,
      sourceEngine: secondaryEngineName,
    );

    if (kDebugMode) {
      debugPrint('[$primaryEngineName] Raw phone candidates: '
          '${primaryPhones.isEmpty ? "none" : primaryPhones.map((p) => p.formatted).join(", ")}');
      debugPrint('[$secondaryEngineName] Raw phone candidates: '
          '${secondaryPhones.isEmpty ? "none" : secondaryPhones.map((p) => p.formatted).join(", ")}');
    }

    final resolvedPhones = <FieldCandidate>[];
    final seenNormalizedPhones = <String>{};

    for (final cand in [...primaryPhones, ...secondaryPhones]) {
      // Check if duplicate of already seen phone
      bool isDup = false;
      for (final seen in seenNormalizedPhones) {
        if (PhoneOcrRecovery.areEquivalentPhones(cand.normalized, seen)) {
          isDup = true;
          break;
        }
      }
      if (isDup) continue;

      seenNormalizedPhones.add(cand.normalized);

      // Check cross-engine agreement
      final fromPrimary = primaryPhones.any(
        (p) => PhoneOcrRecovery.areEquivalentPhones(p.normalized, cand.normalized),
      );
      final fromSecondary = secondaryPhones.any(
        (p) => PhoneOcrRecovery.areEquivalentPhones(p.normalized, cand.normalized),
      );

      final String source = (fromPrimary && fromSecondary)
          ? 'Both ($primaryEngineName & $secondaryEngineName)'
          : (fromPrimary ? primaryEngineName : secondaryEngineName);

      if (fromPrimary && fromSecondary) {
        agreedSignals.add('phone: ${cand.formatted}');
      }

      resolvedPhones.add(FieldCandidate(
        field: 'phone',
        value: cand.formatted,
        sourceEngine: source,
        ocrConfidence: cand.confidence,
        semanticConfidence: cand.confidence,
        spatialEvidence: {
          if (cand.label != null) 'label': cand.label,
          'normalized': cand.normalized,
          'wasSplitJoined': cand.wasSplitJoined,
          'hasCharacterCorrection': cand.hasCharacterCorrection,
        },
        positiveEvidence: [
          if (cand.label != null) 'Label: ${cand.label}',
          if (cand.hasCharacterCorrection) 'Character correction applied',
          if (cand.wasSplitJoined) 'Split lines joined',
          if (cand.diagnosticNote != null) cand.diagnosticNote!,
        ],
      ));
    }

    // 2. EXTRACT & RESOLVE EMAILS (Union + Deduplicate via EmailOcrRecovery)
    final primaryEmailCandidates = EmailOcrRecovery.extractEmailCandidates(
      primaryLines,
      sourceEngine: primaryEngineName,
    );
    final secondaryEmailCandidates = EmailOcrRecovery.extractEmailCandidates(
      secondaryLines,
      sourceEngine: secondaryEngineName,
    );

    if (kDebugMode) {
      debugPrint('[$primaryEngineName] Raw email candidates: '
          '${primaryEmailCandidates.isEmpty ? "none" : primaryEmailCandidates.map((e) => e.email).join(", ")}');
      debugPrint('[$secondaryEngineName] Raw email candidates: '
          '${secondaryEmailCandidates.isEmpty ? "none" : secondaryEmailCandidates.map((e) => e.email).join(", ")}');
    }

    final resolvedEmails = <FieldCandidate>[];
    final seenNormalizedEmails = <String>{};

    for (final cand in [...primaryEmailCandidates, ...secondaryEmailCandidates]) {
      if (seenNormalizedEmails.contains(cand.normalized)) continue;
      seenNormalizedEmails.add(cand.normalized);

      final fromPrimary = primaryEmailCandidates.any((pe) => pe.normalized == cand.normalized);
      final fromSecondary = secondaryEmailCandidates.any((se) => se.normalized == cand.normalized);
      final source = (fromPrimary && fromSecondary)
          ? 'Both ($primaryEngineName & $secondaryEngineName)'
          : (fromPrimary ? primaryEngineName : secondaryEngineName);

      if (fromPrimary && fromSecondary) {
        agreedSignals.add('email: ${cand.email}');
      }

      resolvedEmails.add(FieldCandidate(
        field: 'email',
        value: cand.email,
        sourceEngine: source,
        ocrConfidence: cand.confidence,
        semanticConfidence: cand.confidence,
        spatialEvidence: {
          if (cand.label != null) 'label': cand.label,
          'normalized': cand.normalized,
          'wasSpacedReconstructed': cand.wasSpacedReconstructed,
          'wasSplitJoined': cand.wasSplitJoined,
          'hasCharacterCorrection': cand.hasCharacterCorrection,
        },
        positiveEvidence: [
          if (cand.label != null) 'Label: ${cand.label}',
          if (cand.wasSpacedReconstructed) 'Spaced characters reconstructed',
          if (cand.wasSplitJoined) 'Split lines joined',
          if (cand.hasCharacterCorrection) 'Character confusion corrected',
          if (cand.diagnosticNote != null) cand.diagnosticNote!,
        ],
      ));
    }

    final allEmails = <String>[
      ...primaryEmailCandidates.map((e) => e.email),
      ...secondaryEmailCandidates.map((e) => e.email),
    ];

    // 3. EXTRACT & RESOLVE WEBSITES (Union + Deduplicate)
    final primaryWebsites = _extractWebsiteCandidates(primaryLines);
    final secondaryWebsites = _extractWebsiteCandidates(secondaryLines);
    final resolvedWebsites = <FieldCandidate>[];
    final seenWebsites = <String>{};

    for (final w in [...primaryWebsites, ...secondaryWebsites]) {
      final norm = _normalizeDomain(w);
      if (seenWebsites.contains(norm)) continue;
      seenWebsites.add(norm);

      final isFromPrimary = primaryWebsites.any((pw) => _normalizeDomain(pw) == norm);
      final isFromSecondary = secondaryWebsites.any((sw) => _normalizeDomain(sw) == norm);
      final source = (isFromPrimary && isFromSecondary)
          ? 'Both ($primaryEngineName & $secondaryEngineName)'
          : (isFromPrimary ? primaryEngineName : secondaryEngineName);

      if (isFromPrimary && isFromSecondary) {
        agreedSignals.add('website: $w');
      }

      resolvedWebsites.add(FieldCandidate(
        field: 'website',
        value: w,
        sourceEngine: source,
        ocrConfidence: 0.90,
        semanticConfidence: 0.90,
      ));
    }

    final topWebsite = resolvedWebsites.isNotEmpty ? resolvedWebsites.first.value : null;

    // 4. EXTRACT & RESOLVE JOB TITLE FIRST (helps evaluate adjacent person name!)
    final primaryTitleCand = _findBestCandidateInLines(
      primaryLines,
      evaluator: (line, idx) => evaluateJobTitleCandidate(
        rawLine: line,
        sourceEngine: primaryEngineName,
        lineIndex: idx,
      ),
    );

    final secondaryTitleCand = _findBestCandidateInLines(
      secondaryLines,
      evaluator: (line, idx) => evaluateJobTitleCandidate(
        rawLine: line,
        sourceEngine: secondaryEngineName,
        lineIndex: idx,
      ),
    );

    FieldCandidate? resolvedTitle;
    if (primaryTitleCand != null && secondaryTitleCand != null) {
      final normP = primaryTitleCand.value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      final normS = secondaryTitleCand.value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (normP == normS && normP.isNotEmpty) {
        agreedSignals.add('jobTitle: ${primaryTitleCand.value}');
        resolvedTitle = secondaryTitleCand;
      } else if (secondaryTitleCand.semanticConfidence > primaryTitleCand.semanticConfidence) {
        resolvedTitle = secondaryTitleCand;
        if (primaryTitleCand.value.isNotEmpty && primaryTitleCand.value != secondaryTitleCand.value) {
          alternatives['jobTitle'] = [primaryTitleCand.value];
        }
      } else {
        resolvedTitle = primaryTitleCand;
        if (secondaryTitleCand.value.isNotEmpty && secondaryTitleCand.value != primaryTitleCand.value) {
          alternatives['jobTitle'] = [secondaryTitleCand.value];
        }
      }
    } else {
      resolvedTitle = primaryTitleCand ?? secondaryTitleCand;
    }

    if (resolvedTitle != null && resolvedTitle.semanticConfidence < 0.30) {
      resolvedTitle = null;
    }

    // 5. EXTRACT & RESOLVE NAME CANDIDATES (aware of job title adjacency)
    final primaryJobTitleIndex = primaryTitleCand?.spatialEvidence['lineIndex'] as int?;
    final secondaryJobTitleIndex = secondaryTitleCand?.spatialEvidence['lineIndex'] as int?;

    final primaryNameCand = _findBestCandidateInLines(
      primaryLines,
      evaluator: (line, idx) => evaluateNameCandidate(
        rawLine: line,
        sourceEngine: primaryEngineName,
        lineIndex: idx,
        totalLines: primaryLines.length,
        jobTitleIndex: primaryJobTitleIndex,
        website: topWebsite,
        detectedEmails: allEmails,
      ),
    );

    final secondaryNameCand = _findBestCandidateInLines(
      secondaryLines,
      evaluator: (line, idx) => evaluateNameCandidate(
        rawLine: line,
        sourceEngine: secondaryEngineName,
        lineIndex: idx,
        totalLines: secondaryLines.length,
        jobTitleIndex: secondaryJobTitleIndex,
        website: topWebsite,
        detectedEmails: allEmails,
      ),
    );

    FieldCandidate? resolvedName;

    if (primaryNameCand != null && secondaryNameCand != null) {
      final normP = _normalizeName(primaryNameCand.value);
      final normS = _normalizeName(secondaryNameCand.value);

      if (normP == normS && normP.isNotEmpty) {
        // Both engines agree on the same person name!
        agreedSignals.add('fullName: ${primaryNameCand.value}');
        resolvedName = FieldCandidate(
          field: 'fullName',
          value: secondaryNameCand.value, // prefer clean casing
          sourceEngine: 'Agreed ($primaryEngineName & $secondaryEngineName)',
          ocrConfidence: max(primaryNameCand.ocrConfidence, secondaryNameCand.ocrConfidence),
          semanticConfidence: min(1.0, max(primaryNameCand.semanticConfidence, secondaryNameCand.semanticConfidence) + 0.15),
          positiveEvidence: [...primaryNameCand.positiveEvidence, 'Both engines independently recognized name'],
        );
      } else {
        // Disagreement: Compare candidate semantic confidence directly!
        // NEVER let global engine score dictate this field!
        // First check if one candidate is an abbreviation/initial of the other (e.g. "Sonia Mathew" vs "Sonia M.")
        final bool pHasInitials = primaryNameCand.value
            .split(RegExp(r'\s+'))
            .any((w) => RegExp(r'^[A-Z]\.?$').hasMatch(w));
        final bool sHasInitials = secondaryNameCand.value
            .split(RegExp(r'\s+'))
            .any((w) => RegExp(r'^[A-Z]\.?$').hasMatch(w));

        if (!pHasInitials && sHasInitials && primaryNameCand.isTrustworthy) {
          // Primary is full unabbreviated name while secondary has initials -> prefer primary!
          resolvedName = primaryNameCand;
          diagnosticNotes.add(
              'Selected full unabbreviated Name "${primaryNameCand.value}" from ${primaryNameCand.sourceEngine} '
              'over abbreviated candidate "${secondaryNameCand.value}" from ${secondaryNameCand.sourceEngine}');
          alternatives['fullName'] = [secondaryNameCand.value];
        } else if (pHasInitials && !sHasInitials && secondaryNameCand.isTrustworthy) {
          // Secondary is full unabbreviated name while primary has initials -> prefer secondary!
          resolvedName = secondaryNameCand;
          diagnosticNotes.add(
              'Selected full unabbreviated Name "${secondaryNameCand.value}" from ${secondaryNameCand.sourceEngine} '
              'over abbreviated candidate "${primaryNameCand.value}" from ${primaryNameCand.sourceEngine}');
          alternatives['fullName'] = [primaryNameCand.value];
        } else if (secondaryNameCand.semanticConfidence > primaryNameCand.semanticConfidence) {
          resolvedName = secondaryNameCand;
          diagnosticNotes.add(
              'Selected Name from ${secondaryNameCand.sourceEngine} (semConf: ${(secondaryNameCand.semanticConfidence * 100).toStringAsFixed(0)}%) '
              'over ${primaryNameCand.sourceEngine} candidate "${primaryNameCand.value}" (semConf: ${(primaryNameCand.semanticConfidence * 100).toStringAsFixed(0)}%)');
          if (primaryNameCand.value.isNotEmpty && primaryNameCand.value != secondaryNameCand.value) {
            alternatives['fullName'] = [primaryNameCand.value];
          }
        } else {
          resolvedName = primaryNameCand;
          diagnosticNotes.add(
              'Selected Name from ${primaryNameCand.sourceEngine} (semConf: ${(primaryNameCand.semanticConfidence * 100).toStringAsFixed(0)}%) '
              'over ${secondaryNameCand.sourceEngine} candidate "${secondaryNameCand.value}" (semConf: ${(secondaryNameCand.semanticConfidence * 100).toStringAsFixed(0)}%)');
          if (secondaryNameCand.value.isNotEmpty && secondaryNameCand.value != primaryNameCand.value) {
            alternatives['fullName'] = [secondaryNameCand.value];
          }
        }
      }
    } else {
      resolvedName = primaryNameCand ?? secondaryNameCand;
    }

    // Zero-hallucination guard: If winning candidate semantic confidence < 0.35, leave Name empty!
    if (resolvedName != null && !resolvedName.isTrustworthy) {
      diagnosticNotes.add('Zero-hallucination rule: Name candidate "${resolvedName.value}" discarded (confidence below threshold: ${(resolvedName.semanticConfidence * 100).toStringAsFixed(0)}%)');
      resolvedName = null;
    }

    // 6. EXTRACT & RESOLVE COMPANY
    final primaryCompanyCand = _findBestCandidateInLines(
      primaryLines,
      evaluator: (line, idx) => evaluateCompanyCandidate(
        rawLine: line,
        sourceEngine: primaryEngineName,
        lineIndex: idx,
        website: topWebsite,
        emails: allEmails,
      ),
    );

    final secondaryCompanyCand = _findBestCandidateInLines(
      secondaryLines,
      evaluator: (line, idx) => evaluateCompanyCandidate(
        rawLine: line,
        sourceEngine: secondaryEngineName,
        lineIndex: idx,
        website: topWebsite,
        emails: allEmails,
      ),
    );

    FieldCandidate? resolvedCompany;
    if (primaryCompanyCand != null && secondaryCompanyCand != null) {
      final normP = primaryCompanyCand.value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final normS = secondaryCompanyCand.value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normP == normS && normP.isNotEmpty) {
        agreedSignals.add('company: ${primaryCompanyCand.value}');
        resolvedCompany = secondaryCompanyCand;
      } else if (secondaryCompanyCand.semanticConfidence > primaryCompanyCand.semanticConfidence) {
        resolvedCompany = secondaryCompanyCand;
        if (primaryCompanyCand.value.isNotEmpty && primaryCompanyCand.value != secondaryCompanyCand.value) {
          alternatives['company'] = [primaryCompanyCand.value];
        }
      } else {
        resolvedCompany = primaryCompanyCand;
        if (secondaryCompanyCand.value.isNotEmpty && secondaryCompanyCand.value != primaryCompanyCand.value) {
          alternatives['company'] = [secondaryCompanyCand.value];
        }
      }
    } else {
      resolvedCompany = primaryCompanyCand ?? secondaryCompanyCand;
    }

    if (resolvedCompany != null && resolvedCompany.semanticConfidence < 0.30) {
      resolvedCompany = null;
    }

    // 7. EXTRACT & RESOLVE ADDRESS
    final primaryAddrLines = _collectAddressLines(primaryLines, resolvedName?.value, resolvedCompany?.value, resolvedTitle?.value);
    final secondaryAddrLines = _collectAddressLines(secondaryLines, resolvedName?.value, resolvedCompany?.value, resolvedTitle?.value);

    final primaryAddrCand = evaluateAddressCandidate(addressLines: primaryAddrLines, sourceEngine: primaryEngineName);
    final secondaryAddrCand = evaluateAddressCandidate(addressLines: secondaryAddrLines, sourceEngine: secondaryEngineName);

    FieldCandidate? resolvedAddress;
    if (primaryAddrCand.value.isNotEmpty && secondaryAddrCand.value.isNotEmpty) {
      if (secondaryAddrCand.semanticConfidence > primaryAddrCand.semanticConfidence) {
        resolvedAddress = secondaryAddrCand;
        alternatives['address'] = [primaryAddrCand.value];
      } else {
        resolvedAddress = primaryAddrCand;
        alternatives['address'] = [secondaryAddrCand.value];
      }
    } else {
      resolvedAddress = primaryAddrCand.value.isNotEmpty ? primaryAddrCand : (secondaryAddrCand.value.isNotEmpty ? secondaryAddrCand : null);
    }

    return FieldResolutionResult(
      name: resolvedName,
      jobTitle: resolvedTitle,
      company: resolvedCompany,
      address: resolvedAddress,
      phones: resolvedPhones,
      emails: resolvedEmails,
      websites: resolvedWebsites,
      agreedSignals: agreedSignals,
      alternatives: alternatives,
      diagnosticNotes: diagnosticNotes,
    );
  }

  // --- Utility Helpers ---

  static FieldCandidate? _findBestCandidateInLines(
    List<String> lines, {
    required FieldCandidate Function(String line, int index) evaluator,
  }) {
    FieldCandidate? best;
    for (int i = 0; i < lines.length; i++) {
      final cand = evaluator(lines[i], i);
      if (best == null || cand.semanticConfidence > best.semanticConfidence) {
        best = cand;
      }
    }
    return best;
  }

  static FieldCandidate _buildRejectedNameCandidate(
    String value,
    String sourceEngine,
    double ocrConfidence,
    List<String> rejectionReasons,
  ) {
    return FieldCandidate(
      field: 'fullName',
      value: value,
      sourceEngine: sourceEngine,
      ocrConfidence: ocrConfidence,
      semanticConfidence: 0.0,
      rejectionReasons: rejectionReasons,
    );
  }



  static List<String> _extractWebsiteCandidates(List<String> lines) {
    final websites = <String>[];
    for (final l in lines) {
      if (l.contains('@')) continue;
      for (final m in _urlSchemeOrWwwRegExp.allMatches(l)) {
        websites.add(m.group(0)!.trim().replaceAll(RegExp(r'[,\.;:!]+$'), ''));
      }
      for (final m in _domainRegExp.allMatches(l)) {
        final dom = m.group(1)!.trim();
        if (!dom.contains('@') && !dom.toLowerCase().endsWith('gmail.com')) {
          websites.add(dom.replaceAll(RegExp(r'[,\.;:!]+$'), ''));
        }
      }
    }
    return websites;
  }

  static List<String> _collectAddressLines(
    List<String> lines,
    String? name,
    String? company,
    String? title,
  ) {
    final addr = <String>[];
    for (final l in lines) {
      final trimmed = l.trim();
      if (trimmed.isEmpty) continue;
      if (name != null && trimmed.toLowerCase() == name.toLowerCase()) continue;
      if (company != null && trimmed.toLowerCase() == company.toLowerCase()) continue;
      if (title != null && trimmed.toLowerCase() == title.toLowerCase()) continue;
      if (_emailRegExp.hasMatch(trimmed) || _phoneRegExp.hasMatch(trimmed)) continue;

      if (isLocationOrAddressLine(trimmed)) {
        addr.add(trimmed);
      }
    }
    return addr;
  }

  static String _normalizeDomain(String url) {
    return url
        .toLowerCase()
        .replaceAll(RegExp(r'^https?:\/\/'), '')
        .replaceAll(RegExp(r'^www\.'), '')
        .replaceAll(RegExp(r'\/.*$'), '');
  }

  static String _normalizeName(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '').trim();
  }
}
