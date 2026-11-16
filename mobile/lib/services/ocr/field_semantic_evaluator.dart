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
    r'\b(ltd\.?|limited|pvt\.?|private|llc|llp|inc\.?|incorporated|corp\.?|corporation|company|co\.?|gmbh|sa|ag|plc|bhd|srl|pty|nv|bv|undertaking|foundation|trust|society|federation|association|council|board|ministry|department|consulate|embassy|government|govt\.?|court|high\s+court|supreme\s+court|realty|realtors|brokerage)\b',
    caseSensitive: false,
  );

  // Common organization / industry category keywords
  static final RegExp _companyTypeTokensRegExp = RegExp(
    r'\b(technologies|technology|solutions|services|enterprises|industries|systems|laboratories|labs|holdings|holding|group|consulting|consultancy|agency|studio|studios|associates|partners|chambers|law\s+firm|healthcare|health\s+care|hospital|hospitals|clinic|clinics|infirmary|dispensary|medical|medical\s+mission|medical\s+center|medical\s+centre|equipments|equipment|engineering|manufacturing|traders|trader|foundation|trust|society|mission|university|college|school|institute|academy|institutions|institution|educational|education|bank|banking|insurance|securities|investments|builders|construction|contractors|motors|garage|realty|properties|events|electronics|global|international|worldwide|shipping|logistics|freight|dispatch|trading|corporation|corporations|hardware|software|assistance|emergency|helpline|support|networks|network|ventures|innovations|innovation|dynamics|infotech|interactive|communications|capital|finance|financial|works|pharma|pharmaceuticals|diagnostics|dental|medicare|opticals|creations|designs|apparel|textiles|jewellers|jewellery|furnishings|interiors|security|production|press|publications|publishers|news|broadcasting|automation|energy|power|solar|biotech|chemicals|metals|minerals|agro|farms|foods|beverages|hospitality|hotels|hotel|resorts|resort|travels|travel|tours|tour|express|courier|consultants|realtors|developers|management|advisory|analytics|club|clubs|federation|association|alliance|league)\b',
    caseSensitive: false,
  );

  // Common quality, management and professional certifications (must not become name, company, or phone)
  static final RegExp _certificationRegExp = RegExp(
    r'\b(?:iso(?:\s*[:\-\d]|\b)|iso\s*\d+(?::\d+)?|ce\s*\d+|gmp|nabh|nabl|halal|kosher|fda|isi|bis)\b',
    caseSensitive: false,
  );

  // Common job titles and occupational designations
  static final RegExp _titleTokensRegExp = RegExp(
    r'\b(director|managing\s+director|executive\s+director|international\s+director|medical\s+director|manager|general\s+manager|sales\s+manager|project\s+manager|product\s+manager|marketing\s+manager|engineer|software\s+engineer|developer|consultant|senior\s+consultant|officer|hon\.\s*consul\s+of\s+spain|consul\s+of\s+spain|hon\.\s*consul|hon\s+consul|honorary\s+consul|consul|president|vice\s+president|vp|head|lead|founder\s*&\s*chairman|founder\s+and\s+chairman|chairman\s*&\s*managing\s+director|director\s*&\s*ceo|founder\s*&\s*ceo|chairman|founder|co-founder|partner|specialist|analyst|associate|architect|designer|coordinator|advisor|executive|supervisor|administrator|secretary|additional\s+chief\s+secretary|attorney|counsel|advocate|solicitor|professor|associate\s+professor|assistant\s+professor|lecturer|scientist|researcher|transplant\s+surgeon|cardiac\s+surgeon|neuro\s+surgeon|orthopedic\s+surgeon|surgeon|physician|doctor|cardiologist|neurologist|dermatologist|pediatrician|oncologist|nephrologist|urologist|pathologist|radiologist|anesthesiologist|clinical\s+psychologist|psychologist|therapist|nurse|practitioner|accountant|chartered\s+accountant|auditor|proprietor|trustee|managing\s+trustee|ceo|cto|cfo|coo|cmo|cio|data\s+scientist|tech\s+lead|solution\s+architect|enterprise\s+architect|ui\/ux\s+designer|graphic\s+designer|creative\s+director|legal\s+counsel|general\s+counsel|managing\s+partner|senior\s+partner|physiotherapist|optometrist|pharmacist|dean|principal|fellow|magistrate|judge|barrister|broker|realtor|chef|curator|editor|journalist|correspondent|trainer|instructor)\b',
    caseSensitive: false,
  );

  // Common occupational title modifiers
  static final RegExp _titleModifierRegExp = RegExp(
    r'\b(senior|sr\.?|junior|jr\.?|chief|lead|head|principal|executive|assistant|associate|deputy|vice|general|regional|global|group|managing|operations|technical|strategy|strategic|business|marketing|sales|product|project|international)\b',
    caseSensitive: false,
  );

  // Structural address indicators (streets, roads, numbers, postal codes, locality patterns)
  static final RegExp _addressTokensRegExp = RegExp(
    r'\b(road|rd\.?|street|st\.?|avenue|ave\.?|lane|ln\.?|boulevard|blvd\.?|drive|dr\.?|broadway|highway|hwy\.?|expressway|way|circle|nagar|salai|marg|chowk|rasta|gali|mohalla|bazaar|mandi|peth|thottam|alley|sector|block|pocket|wing|stage|floor|ground\s+floor|first\s+floor|second\s+floor|third\s+floor|basement|mezzanine|suite|plot|site|survey\s*no|sy\.?\s*no|s\.?f\.?\s*no|door\s*no|d\.?\s*no|d\/no|flat\s*no|shop\s*no|unit\s*no|shed\s*no|premises|building|bldg\.?|tower|towers|plaza|complex|mall|arcade|court|house|mansion|mansions|enclave|apartment|apartments|apt\.?|flat|residency|villa|villas|heights|cross|main|headquarters|hq|office|po\s*box|p\.?o\.?\s*box|pin|pincode|pin\s*code|zip|zipcode|zip\s*code|postal\s*code|post|colony|layout|extension|extn\.?|opp\.?|opposite|near|behind|adjacent|beside|next\s+to|above|below|palayam|koundampalayam|puram|patti|patty|halli|wadi|baug|cheri|kulam|pet|industrial\s+(?:area|estate|park|zone|layout|phase)|sez|tech\s+park|it\s+park|cyber\s+city|cyber\s+park|infocity|campus|phase\s+[0-9a-zA-Z]+|[a-zA-Z]{3,}\s+(?:east|west|north|south)|district|dist\.?|mandal|taluk|taluka|tehsil|panchayat|village|division|circle|house\s*[-–#]?\s*\d+|road\s*[-–#]?\s*\d+|block\s*[-–#]?\s*[a-zA-Z0-9]+|new\s+no\.?\s*\d+|old\s+no\.?\s*[0-9a-zA-Z-]+)\b|\b(?<!real\s)estate\b|\b\d{1,4}[A-Za-z]?[\s,\-\/]+(?:road|rd|street|st|avenue|ave|lane|ln|drive|dr|broadway|nagar|salai|marg|sector|block|cross|main)\b|\b\d{5,6}\b|\b[1-9][0-9]{2}\s?[0-9]{3}\b|\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b',
    caseSensitive: false,
  );

  // Prominent geographical names / major world & Indian cities (generic heuristic support)
  static final RegExp _majorGeographicalTokensRegExp = RegExp(
    r'\b(dhaka|banani|bangladesh|chennai|bangalore|bengaluru|mumbai|delhi|new\s+delhi|hyderabad|secunderabad|kolkata|pune|ahmedabad|jaipur|kochi|coimbatore|madurai|trichy|tiruchirappalli|mysore|mysuru|calicut|kozhikode|trivandrum|thiruvananthapuram|chandigarh|lucknow|kanpur|nagpur|indore|bhopal|patna|vadodara|surat|visakhapatnam|noida|greater\s+noida|gurgaon|gurugram|faridabad|ghaziabad|navi\s+mumbai|thane|kalyan|nashik|aurangabad|solapur|kolhapur|rajkot|bhavnagar|jamnagar|gandhinagar|jabalpur|gwalior|ujjain|raipur|bilaspur|jodhpur|kota|bikaner|ajmer|udaipur|varanasi|prayagraj|allahabad|agra|meerut|bareilly|aligarh|moradabad|gorakhpur|gaya|bhagalpur|muzaffarpur|ranchi|jamshedpur|dhanbad|bhubaneswar|cuttack|rourkela|howrah|durgapur|asansol|siliguri|guwahati|ludhiana|amritsar|jalandhar|dehradun|haridwar|shimla|jammu|srinagar|warangal|nizamabad|karimnagar|vijayawada|guntur|nellore|kurnool|tirupati|kakinada|hubli|hubballi|dharwad|mangaluru|mangalore|belgaum|belagavi|gulbarga|kalaburagi|davanagere|bellary|ballari|thrissur|kollam|kannur|alappuzha|palakkad|kottayam|salem|tirunelveli|tiruppur|tirupur|erode|vellore|thoothukudi|dindigul|thanjavur|ranipet|sivakasi|karur|ooty|udhagamandalam|hosur|nagercoil|kanchipuram|kumarapalayam|karaikkudi|neyveli|cuddalore|kumbakonam|tiruvannamalai|pollachi|rajapalayam|pudukkottai|puducherry|pondicherry|new\s+york|san\s+francisco|los\s+angeles|chicago|houston|austin|seattle|dallas|boston|miami|atlanta|denver|london|manchester|birmingham|leeds|paris|berlin|frankfurt|munich|tokyo|singapore|dubai|abu\s+dhabi|doha|riyadh|sydney|melbourne|brisbane|toronto|vancouver|montreal|california|texas|florida|new\s+jersey|illinois|washington|new\s+south\s+wales|victoria|ontario|quebec|tamil\s+nadu|karnataka|maharashtra|kerala|andhra\s+pradesh|telangana|gujarat|rajasthan|uttar\s+pradesh|madhya\s+pradesh|west\s+bengal|punjab|haryana|bihar|odisha|assam|goa|uttarakhand|himachal\s+pradesh|jharkhand|chhattisgarh|india|usa|uk|united\s+states|united\s+kingdom|germany|france|spain|italy|australia|canada|japan|uae|united\s+arab\s+emirates|saudi\s+arabia|netherlands|switzerland|sweden|ireland|new\s+zealand)\b',
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

  /// Computes a conservative text-quality score (0.0 to 1.0) without requiring a dictionary.
  /// Penalizes suspicious OCR artifacts: mixed digits & letters, bizarre punctuation,
  /// excessive isolated chars, corruption, and impossible consonant runs.
  /// Preserves legitimate personal names, Indian/international names, initials,
  /// abbreviations, company names, and medical terminology.
  static double computeTextQualityScore(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0.0;
    if (trimmed.length < 2) {
      if (RegExp(r'^[A-Za-z&]$').hasMatch(trimmed)) return 0.70;
      return 0.10;
    }

    double score = 1.0;
    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    // 1. Mixed alphanumeric tokens (e.g. "9Word", "T0ken", "Item123")
    // Allow legitimate ordinals (1st, 2nd, 3rd, 4th...) and short abbreviations (3M, B2B, 4G, 5G, A4, V8)
    final ordinalPattern = RegExp(r'^\d+(?:st|nd|rd|th)$', caseSensitive: false);
    final validAlphaNumPattern =
        RegExp(r'^(?:3m|b2b|b2c|4g|5g|a4|v8|mp3|mp4|2d|3d)$', caseSensitive: false);

    int mixedWordCount = 0;
    for (final w in words) {
      final clean = w.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '');
      if (clean.length >= 2 &&
          clean.contains(RegExp(r'[a-zA-Z]')) &&
          clean.contains(RegExp(r'\d')) &&
          !ordinalPattern.hasMatch(clean) &&
          !validAlphaNumPattern.hasMatch(clean)) {
        mixedWordCount++;
      }
    }
    if (mixedWordCount > 0) {
      score -= (0.45 * mixedWordCount);
    }

    // 2. Impossible or bizarre punctuation / symbols (e.g. "!!", "~~", "||", "$$", "%%", "#", "^", "{", "}")
    if (RegExp(r'[!~|%#$^<>{}=\\]{2,}').hasMatch(trimmed) ||
        RegExp(r'[~|%#$^<>{}=\\]').hasMatch(trimmed)) {
      score -= 0.35;
    }

    // 3. Trailing OCR corruption / cutoffs (e.g. "Text!!", "Word...", "John...")
    if (RegExp(r'\.{2,}$').hasMatch(trimmed) || RegExp(r'!+$').hasMatch(trimmed)) {
      score -= 0.20;
    }

    // 4. Excessive isolated single characters (e.g. "a b c d e")
    if (words.length >= 3) {
      final singleCharWords = words.where((w) {
        final clean = w.replaceAll(RegExp(r'[^a-zA-Z]'), '');
        return clean.length == 1;
      }).length;
      if (singleCharWords / words.length > 0.40) {
        score -= 0.35;
      }
    }

    // 5. Improbable consonant clusters without vowels (>= 5 consonants, e.g. "bcdfgh")
    // Exclude uppercase acronyms/credentials like "MBBS", "FRCS", "LLC", "IAS", "Pvt"
    for (final w in words) {
      final clean = w.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      if (clean.length >= 5 &&
          clean != clean.toUpperCase() &&
          RegExp(r'[bcdfghjklmnpqrstvwxyzBCDFGHJKLMNPQRSTVWXYZ]{5,}').hasMatch(clean)) {
        score -= 0.35;
        break;
      }
    }

    // 6. Multiple case flips inside a single word (e.g. "wOrD", "bOad")
    for (final w in words) {
      final clean = w.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      if (clean.length >= 4) {
        int caseChanges = 0;
        for (int i = 0; i < clean.length - 1; i++) {
          final isUpper1 = clean[i] == clean[i].toUpperCase();
          final isUpper2 = clean[i + 1] == clean[i + 1].toUpperCase();
          if (isUpper1 != isUpper2) caseChanges++;
        }
        if (caseChanges >= 3) {
          score -= 0.30;
          break;
        }
      }
    }

    return score.clamp(0.0, 1.0);
  }

  /// Evaluates formatting quality for cross-engine reconciliation.
  /// Prefers clean word separation over fused/camelCase strings.
  /// e.g. "Senior Consultant" (clean spaced) > "Seniorconsultant" (fused)
  /// e.g. "Apex Healthcare" (clean spaced) > "ApexHealthcare" (fused)
  /// e.g. "Global Medical Center" > "GlobalMedicalCenter"
  static double scoreFormattingQuality(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0.0;
    double score = 1.0;

    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    // Reward proper multi-word spacing for natural phrases
    if (words.length >= 2) {
      score += 0.30;
    }

    // Penalize fused CamelCase words (e.g. "MedicalCenter", "ApexHealthcare")
    for (final w in words) {
      if (RegExp(r'[a-z][A-Z]').hasMatch(w) ||
          RegExp(r'[A-Z]{2,}[A-Z][a-z]').hasMatch(w)) {
        score -= 0.40;
      }
    }

    // Penalize fused words where a known compound root is glued without space
    // (e.g. "Transplantsurgeon", "Medicalmission", "Healthcarecentre")
    final fusedRoots = [
      'surgeon',
      'mission',
      'healthcare',
      'hospital',
      'doctor',
      'consultant',
      'director',
      'manager',
      'engineer',
      'technologies',
    ];
    for (final root in fusedRoots) {
      for (final w in words) {
        final wLower = w.toLowerCase();
        if (wLower != root && wLower.endsWith(root) && wLower.length > root.length + 2) {
          score -= 0.45;
        }
      }
    }

    // Penalize trailing ellipsis or cutoffs (e.g. "Shro...")
    if (trimmed.endsWith('...') || trimmed.endsWith('..')) {
      score -= 0.30;
    }

    // Reward Title Case or clean Capitalization
    if (words.every((w) => w.isNotEmpty && w[0] == w[0].toUpperCase())) {
      score += 0.15;
    }

    return score.clamp(0.0, 2.0);
  }

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
      } else if (RegExp(r'^[A-Za-z]\.?$', caseSensitive: false).hasMatch(afterComma)) {
        // Legitimate name with trailing initial e.g. "Chandra Kanthan, M"
        positiveEvidence.add('Has personal name initial suffix: "$afterComma"');
      }
    }

    // Strip leading/trailing bullet points or icons
    cleanName = cleanName
        .replaceAll(RegExp(r'^[•\-\*\>👤\s,]+'), '')
        .replaceAll(RegExp(r'[•\-\*\>👤\s,]+$'), '')
        .trim();

    final alphaLetters = cleanName.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (alphaLetters.length < 2) {
      rejectionReasons.add('Does not contain sufficient alphabetic characters for a person name');
      return _buildRejectedNameCandidate(cleanName, sourceEngine, ocrConfidence, rejectionReasons);
    }

    double score = 0.0;

    // 0. Certification Disqualification (CRITICAL)
    if (_certificationRegExp.hasMatch(trimmed)) {
      rejectionReasons.add('Matches certification standard (e.g. ISO, CE, GMP)');
      return _buildRejectedNameCandidate(cleanName, sourceEngine, ocrConfidence, rejectionReasons);
    }

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

    if (surroundingText != null &&
        cleanName.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length == 1 &&
        !_titleTokensRegExp.hasMatch(surroundingText) &&
        (_companyTypeTokensRegExp.hasMatch(surroundingText) || _orgSuffixRegExp.hasMatch(surroundingText))) {
      rejectionReasons.add('Single word forms prefix of adjacent multi-line company name ("$trimmed $surroundingText")');
      return _buildRejectedNameCandidate(cleanName, sourceEngine, ocrConfidence, rejectionReasons);
    }

    // Reject ampersands ("&") which characterize partnerships, companies, or subject lines
    if (trimmed.contains('&')) {
      rejectionReasons.add('Contains ampersand symbol ("&")');
      return _buildRejectedNameCandidate(cleanName, sourceEngine, ocrConfidence, rejectionReasons);
    }

    // Token analysis
    final words = cleanName.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final wordCount = words.length;

    // Website or email domain match: If cleanName matches an organization domain,
    // it is compelling evidence of a COMPANY / ORGANIZATION, NOT a Person Name!
    // Exception: Personal portfolio / vanity domain for individuals (e.g. "Elena Rostova" -> "elenarostova.design")
    // when positioned immediately above a job title without any corporate suffix.
    if (website != null) {
      final normDomain = _normalizeDomain(website).replaceAll(RegExp(r'[^a-z0-9]'), '');
      final normName = cleanName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normName.length >= 3 && (normDomain.contains(normName) || normName.contains(normDomain))) {
        if (wordCount == 1 || hasOrgSuffix || hasCompanyType) {
          rejectionReasons.add('Single word or corporate name matches website domain ("$website")');
          return _buildRejectedNameCandidate(cleanName, sourceEngine, ocrConfidence, rejectionReasons);
        }
        if (jobTitleIndex != null && lineIndex == jobTitleIndex - 1) {
          positiveEvidence.add('Personal portfolio domain matches cardholder name');
        } else {
          rejectionReasons.add('Matches corporate website domain ("$website")');
          score -= 0.35;
        }
      }
    }

    const publicDomains = {'gmail', 'yahoo', 'hotmail', 'outlook', 'icloud', 'rediffmail', 'live'};
    for (final email in detectedEmails) {
      if (email.contains('@')) {
        final domainPart = email.split('@').last.split('.').first.toLowerCase();
        if (publicDomains.contains(domainPart)) continue;
        final normName = cleanName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (normName.length >= 3 && (domainPart.contains(normName) || normName.contains(domainPart))) {
          if (wordCount == 1 || hasOrgSuffix || hasCompanyType) {
            rejectionReasons.add('Single word or corporate name matches company email domain ("$domainPart")');
            return _buildRejectedNameCandidate(cleanName, sourceEngine, ocrConfidence, rejectionReasons);
          }
          if (jobTitleIndex != null && lineIndex == jobTitleIndex - 1) {
            positiveEvidence.add('Personal email vanity domain matches cardholder name');
          } else {
            rejectionReasons.add('Matches company email domain ("$domainPart")');
            score -= 0.35;
          }
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

    // Single-word check: A person name must have >= 2 words, OR an honorific, OR match an email username
    if (wordCount == 1 && !_honorificPrefixRegExp.hasMatch(cleanName) && attachedCredentials == null) {
      bool matchesUsername = false;
      for (final email in detectedEmails) {
        if (email.contains('@')) {
          final localPart = email.split('@').first.toLowerCase();
          if (localPart.contains(cleanName.toLowerCase())) {
            matchesUsername = true;
            break;
          }
        }
      }
      if (!matchesUsername) {
        rejectionReasons.add('Single word without personal honorific or email username is likely a brand or company');
        return _buildRejectedNameCandidate(cleanName, sourceEngine, ocrConfidence, rejectionReasons);
      }
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

    // Plausible human name token count: 2 to 4 words (or 1 with honorific/username)
    if (wordCount >= 2 && wordCount <= 4) {
      positiveEvidence.add('Has natural 2-4 token human name structure');
      score += 0.30;
    } else if (wordCount == 1 && (_honorificPrefixRegExp.hasMatch(cleanName) || attachedCredentials != null)) {
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

    // Initials support (e.g. "D. S. Sharma", "A. Kumar", "K. S. Raman", "Chandra Kanthan. M")
    final hasInitials = words.any((w) =>
        RegExp(r'^[A-Z]\.?$').hasMatch(w) ||
        RegExp(r'^[A-Z]\.[A-Z]\.?$').hasMatch(w));
    if (hasInitials) {
      positiveEvidence.add('Contains standard name initial(s)');
      if (words.length >= 2) {
        positiveEvidence.add('Initial(s) accompanied by given/surname');
        score += 0.10;
      }
    } else if (wordCount >= 2 && words.every((w) => w.length >= 3)) {
      positiveEvidence.add('Fully expanded multi-character name tokens');
      score += 0.20;
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

    // Garbled text & mixed alphanumeric checks (e.g. "9Word B123 Corrupted")
    int mixedAlphaNumCount = 0;
    for (final w in words) {
      final clean = w.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '');
      if (clean.length >= 2 &&
          clean.contains(RegExp(r'[a-zA-Z]')) &&
          clean.contains(RegExp(r'\d')) &&
          !RegExp(r'^\d+(?:st|nd|rd|th)$', caseSensitive: false).hasMatch(clean)) {
        mixedAlphaNumCount++;
      }
    }
    if (mixedAlphaNumCount > 0) {
      rejectionReasons.add('Word token contains mixed digits and letters');
      score -= (0.70 * mixedAlphaNumCount);
    }

    // Text quality evaluation
    final textQuality = computeTextQualityScore(cleanName);
    if (textQuality < 0.60) {
      rejectionReasons.add('Low text quality score (${(textQuality * 100).toStringAsFixed(0)}%)');
      score -= (1.0 - textQuality) * 0.60;
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

    final maxConfidence = hasInitials ? 0.88 : 1.0;
    final semanticConfidence = score.clamp(0.0, maxConfidence);

    return FieldCandidate(
      field: 'fullName',
      value: cleanName,
      sourceEngine: sourceEngine,
      ocrConfidence: ocrConfidence,
      semanticConfidence: semanticConfidence,
      textQualityScore: textQuality,
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
        textQualityScore: 0.0,
      );
    }

    final textQuality = computeTextQualityScore(trimmed);

    final alphaLetters = trimmed.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (alphaLetters.length < 2) {
      return FieldCandidate(
        field: 'jobTitle',
        value: trimmed,
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        textQualityScore: textQuality,
        rejectionReasons: const ['Does not contain sufficient alphabetic characters for a job title'],
        spatialEvidence: {'lineIndex': lineIndex},
      );
    }

    // Explicit label e.g. "Title: Managing Director"
    final labelMatch = RegExp(r'^(?:designation|job\s+title|title|role)\s*[:\-]\s*(.+)$', caseSensitive: false)
        .firstMatch(trimmed);
    String cleanTitle = trimmed;
    if (labelMatch != null) {
      cleanTitle = labelMatch.group(1)!.trim();
      positiveEvidence.add('Has explicit "Title:" prefix');
    }

    final lowerTitle = cleanTitle.toLowerCase();
    final bool hasTitleMatch = _titleTokensRegExp.hasMatch(cleanTitle);
    final words = lowerTitle.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final bool hasFusedOccupational = words.any((w) => [
          'surgeon',
          'physician',
          'doctor',
          'consultant',
          'director',
          'manager',
          'engineer',
          'technologist',
          'nephrologist',
          'urologist',
          'psychologist',
          'radiologist',
          'pathologist',
          'pediatrician',
        ].any((root) => w.contains(root)));

    // Critical: If no title keyword, no fused occupational root, and no explicit label,
    // a meaningless arbitrary string MUST NOT be scored as a job title!
    if (labelMatch == null && !hasTitleMatch && !hasFusedOccupational) {
      rejectionReasons.add('No occupational title keyword or structure recognized');
      return FieldCandidate(
        field: 'jobTitle',
        value: cleanTitle,
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        textQualityScore: textQuality,
        positiveEvidence: positiveEvidence,
        rejectionReasons: rejectionReasons,
        spatialEvidence: {'lineIndex': lineIndex},
      );
    }

    double score = 0.0;
    if (labelMatch != null) {
      score += 0.50;
    }

    // Keyword match
    if (hasTitleMatch || hasFusedOccupational) {
      positiveEvidence.add('Matches known occupational / title keywords');
      score += 0.40;

      if (_titleTokensRegExp.hasMatch(cleanTitle) ||
          (words.length <= 4 && words.every((w) => _titleTokensRegExp.hasMatch(w) || _titleModifierRegExp.hasMatch(w)))) {
        positiveEvidence.add('Pure occupational title phrase');
        score += 0.35;
      }
    }

    // Proximity to person name (only if occupational indicators exist!)
    if (personIndex != null && lineIndex == personIndex + 1 && (hasTitleMatch || hasFusedOccupational)) {
      positiveEvidence.add('Positioned immediately beneath person name');
      score += 0.30;
    }

    // Penalize if contains org suffix (Ltd, LLC, Inc) - unless part of a "to/of <entity>" title modifier
    if (_orgSuffixRegExp.hasMatch(cleanTitle)) {
      final isTitleToEntity = RegExp(
        r'\b(?:to|of|for|in|at)\s+(?:the\s+)?(?:government|govt|board|council|ministry|department)\b',
        caseSensitive: false,
      ).hasMatch(cleanTitle);
      if (!isTitleToEntity) {
        rejectionReasons.add('Contains corporate legal entity suffix');
        score -= 0.50;
      }
    }

    // Penalize if address
    if (isLocationOrAddressLine(cleanTitle)) {
      rejectionReasons.add('Contains address or location indicators');
      score -= 0.60;
    }

    // Text quality penalty
    if (textQuality < 0.60) {
      score -= (1.0 - textQuality) * 0.40;
    }

    final semanticConfidence = score.clamp(0.0, 1.0);
    return FieldCandidate(
      field: 'jobTitle',
      value: cleanTitle,
      sourceEngine: sourceEngine,
      ocrConfidence: ocrConfidence,
      semanticConfidence: semanticConfidence,
      textQualityScore: textQuality,
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
    String? personName,
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
        textQualityScore: 0.0,
      );
    }

    final textQuality = computeTextQualityScore(trimmed);

    if (personName != null && trimmed.toLowerCase() == personName.toLowerCase()) {
      return FieldCandidate(
        field: 'company',
        value: trimmed,
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        textQualityScore: textQuality,
        rejectionReasons: const ['Line is the person name, not a company name'],
        spatialEvidence: {'lineIndex': lineIndex},
      );
    }

    final alphaLetters = trimmed.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (alphaLetters.length < 2) {
      return FieldCandidate(
        field: 'company',
        value: trimmed,
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        textQualityScore: textQuality,
        rejectionReasons: const ['Does not contain sufficient alphabetic characters for a company name'],
        spatialEvidence: {'lineIndex': lineIndex},
      );
    }

    // Explicit rejection: A line containing an email, website URL, phone digits, or marketing slogan is not a company
    if (trimmed.contains('@')) {
      return FieldCandidate(
        field: 'company',
        value: trimmed,
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        textQualityScore: textQuality,
        rejectionReasons: const ['Line is an email address, not a company name'],
        spatialEvidence: {'lineIndex': lineIndex},
      );
    }

    if (RegExp(r'(?:https?:\/\/|www\.)\S+', caseSensitive: false).hasMatch(trimmed)) {
      return FieldCandidate(
        field: 'company',
        value: trimmed,
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        textQualityScore: textQuality,
        rejectionReasons: const ['Line is a URL/website, not a company name'],
        spatialEvidence: {'lineIndex': lineIndex},
      );
    }

    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 7 && (digits.length / trimmed.length) > 0.45) {
      return FieldCandidate(
        field: 'company',
        value: trimmed,
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        textQualityScore: textQuality,
        rejectionReasons: const ['Line is primarily a phone or fax number'],
        spatialEvidence: {'lineIndex': lineIndex},
      );
    }

    if (_certificationRegExp.hasMatch(trimmed)) {
      return FieldCandidate(
        field: 'company',
        value: trimmed,
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        textQualityScore: textQuality,
        rejectionReasons: const ['Line is a quality, management or statutory certification (e.g. ISO, CE, GMP)'],
        spatialEvidence: {'lineIndex': lineIndex, 'isCertification': true},
      );
    }

    if (_sloganPatterns.any((p) => p.hasMatch(trimmed))) {
      return FieldCandidate(
        field: 'company',
        value: trimmed,
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        textQualityScore: textQuality,
        rejectionReasons: const ['Line matches a marketing slogan or tagline'],
        spatialEvidence: {'lineIndex': lineIndex},
      );
    }

    // Explicit label e.g. "Company: Medindia"
    final labelMatch = RegExp(r'^(?:company|organization|org)\s*[:\-]\s*(.+)$', caseSensitive: false)
        .firstMatch(trimmed);
    String cleanCompany = trimmed;
    if (labelMatch != null) {
      cleanCompany = labelMatch.group(1)!.trim();
      positiveEvidence.add('Has explicit "Company:" prefix');
    }

    final words = cleanCompany.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final bool hasOrgSuffix = _orgSuffixRegExp.hasMatch(cleanCompany);
    final bool hasCompanyType = _companyTypeTokensRegExp.hasMatch(cleanCompany);
    final bool hasDomainMatch = (website != null && cleanCompany.length >= 4 && _normalizeDomain(website).contains(cleanCompany.toLowerCase())) ||
        emails.any((e) => e.contains('@') && cleanCompany.length >= 4 && e.toLowerCase().contains(cleanCompany.toLowerCase()));

    // Reject single isolated words that have no corporate suffix, category keyword, or domain match
    if (words.length == 1 && labelMatch == null && !hasOrgSuffix && !hasCompanyType && !hasDomainMatch) {
      rejectionReasons.add('Single isolated word lacks corporate or institutional keywords');
      return FieldCandidate(
        field: 'company',
        value: cleanCompany,
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        textQualityScore: textQuality,
        positiveEvidence: positiveEvidence,
        rejectionReasons: rejectionReasons,
        spatialEvidence: {'lineIndex': lineIndex},
      );
    }

    double score = 0.0;
    if (labelMatch != null) {
      score += 0.50;
    }

    // Corporate entity suffix (Ltd, Pvt Ltd, Inc, Corp, LLC)
    if (hasOrgSuffix) {
      positiveEvidence.add('Contains formal corporate suffix (Ltd, Inc, LLC)');
      score += 0.45;
    }

    // Industry / organization category
    if (hasCompanyType) {
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

        // Also check if company words appear in email local-part (e.g. chandrumediequip@gmail.com)
        final localPart = email.split('@').first.toLowerCase();
        if (normComp.length >= 5 && (localPart.contains(normComp) || (localPart.length >= 6 && normComp.contains(localPart)))) {
          positiveEvidence.add('Matches company name in email local-part ("$localPart")');
          score += 0.35;
          break;
        }
      }
    }

    // Explicit preference: Multi-word entity with organization/industry category outscores standalone single-word brand
    if (words.length >= 2 && (hasCompanyType || hasOrgSuffix)) {
      positiveEvidence.add('Multi-word organizational entity with category indicators');
      score += 0.25;
    } else if (words.length == 1 && !hasOrgSuffix && !hasCompanyType) {
      // Single-word brand penalty when competing with full legal entities
      score -= 0.10;
    }

    // Top branding position - only for established multi-word phrases or lines with category/suffix
    if (lineIndex == 0 && (hasOrgSuffix || hasCompanyType || words.length >= 2 || hasDomainMatch)) {
      positiveEvidence.add('Positioned at top of card (line 0)');
      score += 0.20;
    }

    // Well-capitalized company / organization name structure
    if (words.isNotEmpty && words.length <= 4) {
      final capitalized = words.where((w) => w[0].toUpperCase() == w[0]).length;
      if (capitalized == words.length) {
        positiveEvidence.add('Well-capitalized entity name');
        score += 0.15;
      }
    }

    // Disqualify if it's an occupational job title (e.g. "Software Engineer", "Chief Technology Officer")
    if (_titleTokensRegExp.hasMatch(cleanCompany) && !hasOrgSuffix) {
      rejectionReasons.add('Matches job title pattern ("$cleanCompany")');
      return FieldCandidate(
        field: 'company',
        value: cleanCompany,
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        textQualityScore: textQuality,
        positiveEvidence: positiveEvidence,
        rejectionReasons: rejectionReasons,
        spatialEvidence: {'lineIndex': lineIndex},
      );
    }

    // Disqualify if it's a person name with personal honorific
    if (_honorificPrefixRegExp.hasMatch(cleanCompany)) {
      rejectionReasons.add('Starts with personal honorific');
      return FieldCandidate(
        field: 'company',
        value: cleanCompany,
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        textQualityScore: textQuality,
        positiveEvidence: positiveEvidence,
        rejectionReasons: rejectionReasons,
        spatialEvidence: {'lineIndex': lineIndex},
      );
    }

    // Disqualify if it's a location, street, or address line
    if (isLocationOrAddressLine(cleanCompany)) {
      rejectionReasons.add('Contains address or location indicators');
      return FieldCandidate(
        field: 'company',
        value: cleanCompany,
        sourceEngine: sourceEngine,
        ocrConfidence: ocrConfidence,
        semanticConfidence: 0.0,
        textQualityScore: textQuality,
        positiveEvidence: positiveEvidence,
        rejectionReasons: rejectionReasons,
        spatialEvidence: {'lineIndex': lineIndex},
      );
    }

    // Text quality penalty
    if (textQuality < 0.60) {
      score -= (1.0 - textQuality) * 0.40;
    }

    final semanticConfidence = score.clamp(0.0, 1.0);
    return FieldCandidate(
      field: 'company',
      value: cleanCompany,
      sourceEngine: sourceEngine,
      ocrConfidence: ocrConfidence,
      semanticConfidence: semanticConfidence,
      textQualityScore: textQuality,
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
        textQualityScore: 0.0,
      );
    }

    final positiveEvidence = <String>[];
    final combined = addressLines.join(', ');
    double score = 0.20;

    if (_addressTokensRegExp.hasMatch(combined)) {
      positiveEvidence.add('Contains street/road/avenue/floor anchors');
      score += 0.35;
    }

    if (RegExp(r'\b\d{4,6}\b').hasMatch(combined) ||
        RegExp(r'\b\d{3}\s*\d{3}\b').hasMatch(combined) ||
        RegExp(r'\b[A-Za-z]+[-–]\s*\d{4,6}\b').hasMatch(combined) ||
        RegExp(r'\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b', caseSensitive: false).hasMatch(combined)) {
      positiveEvidence.add('Contains valid postal PIN / ZIP code');
      score += 0.30;
    }

    if (addressLines.length >= 2) {
      positiveEvidence.add('Multi-line address cluster (${addressLines.length} lines)');
      score += 0.20;
    }

    final textQuality = computeTextQualityScore(combined);
    final semanticConfidence = score.clamp(0.0, 1.0);
    return FieldCandidate(
      field: 'address',
      value: combined,
      sourceEngine: sourceEngine,
      ocrConfidence: ocrConfidence,
      semanticConfidence: semanticConfidence,
      textQualityScore: textQuality,
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

    // Exclude certifications (e.g. ISO 9001, CE, GMP)
    if (_certificationRegExp.hasMatch(lower)) return false;

    // Exclude occupational titles like "Licensed Real Estate Broker / Agent"
    if (lower.contains('real estate') && (lower.contains('broker') || lower.contains('agent') || lower.contains('realtor') || lower.contains('consultant'))) {
      return false;
    }

    // Exclude formal corporate names with legal entity suffixes
    if (_orgSuffixRegExp.hasMatch(lower)) return false;

    // Exclude judicial, governmental, institutional and public bodies
    if (RegExp(r'\b(government|govt|court|high\s+court|supreme\s+court|ministry|council|authority|board|tribunal|department|commission)\b', caseSensitive: false).hasMatch(lower)) {
      return false;
    }

    // Exclude clear occupational titles
    if (_titleTokensRegExp.hasMatch(lower) && !lower.contains('road') && !lower.contains('street') && !lower.contains('office') && !lower.contains('building')) {
      return false;
    }

    // Address lines must contain at least 2 alphabetic characters (rejects raw phone numbers/digits)
    final alphaLetters = lower.replaceAll(RegExp(r'[^a-z]'), '');
    if (alphaLetters.length < 2) return false;

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

  /// Checks whether a line represents a company, job title, person name, or slogan,
  /// preventing it from being accidentally merged into an address cluster.
  static bool isLikelyOtherEntity(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    return _orgSuffixRegExp.hasMatch(trimmed) ||
        _companyTypeTokensRegExp.hasMatch(trimmed) ||
        _titleTokensRegExp.hasMatch(trimmed) ||
        _honorificPrefixRegExp.hasMatch(trimmed) ||
        _credentialTokenRegExp.hasMatch(trimmed) ||
        isSlogan(trimmed) ||
        evaluateNameCandidate(rawLine: trimmed, sourceEngine: 'OtherEntityGuard').semanticConfidence >= 0.40;
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

    for (final cand in [...primaryPhones, ...secondaryPhones]) {
      // Check if duplicate of already seen phone
      int existingIndex = -1;
      for (int i = 0; i < resolvedPhones.length; i++) {
        final existingNorm = resolvedPhones[i].spatialEvidence['normalized'] as String? ?? '';
        final existingDigits = existingNorm.replaceAll(RegExp(r'\D'), '');
        final candDigits = cand.normalized.replaceAll(RegExp(r'\D'), '');
        final bool isEquivalent = PhoneOcrRecovery.areEquivalentPhones(cand.normalized, existingNorm);
        final bool isPrefixOf = (existingDigits.length >= 8 && candDigits.length >= 8) &&
            (candDigits.startsWith(existingDigits) || existingDigits.startsWith(candDigits));

        if (isEquivalent || isPrefixOf) {
          existingIndex = i;
          break;
        }
      }

      if (existingIndex != -1) {
        // If the new candidate has more digits (e.g. recovered missing digit), replace the shorter one!
        final existingDigits = (resolvedPhones[existingIndex].spatialEvidence['normalized'] as String? ?? '')
            .replaceAll(RegExp(r'\D'), '');
        final candDigits = cand.normalized.replaceAll(RegExp(r'\D'), '');
        if (candDigits.length > existingDigits.length) {
          final existingPhone = resolvedPhones[existingIndex];
          resolvedPhones[existingIndex] = FieldCandidate(
            field: 'phone',
            value: cand.formatted,
            sourceEngine: 'Recovered (${existingPhone.sourceEngine} & ${cand.sourceEngine})',
            ocrConfidence: max(existingPhone.ocrConfidence, cand.confidence),
            semanticConfidence: max(existingPhone.semanticConfidence, cand.confidence),
            spatialEvidence: {
              if (cand.label != null || existingPhone.spatialEvidence['label'] != null)
                'label': cand.label ?? existingPhone.spatialEvidence['label'],
              'normalized': cand.normalized,
              'wasSplitJoined': cand.wasSplitJoined,
              'hasCharacterCorrection': cand.hasCharacterCorrection,
              'recoveryUpgraded': true,
            },
            positiveEvidence: [
              ...existingPhone.positiveEvidence,
              'Recovered missing digits from ${cand.sourceEngine}',
            ],
          );
        }
        continue;
      }

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
        agreedSignals.add('phone');
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
      debugPrint('[$primaryEngineName] Email candidates found: ${primaryEmailCandidates.length}');
      debugPrint('[$secondaryEngineName] Email candidates found: ${secondaryEmailCandidates.length}');
    }

    final resolvedEmails = <FieldCandidate>[];
    final seenNormalizedEmails = <String>{};

    final combinedEmailCandidates = EmailOcrRecovery.suppressEmailFragments([
      ...primaryEmailCandidates,
      ...secondaryEmailCandidates,
    ]);

    for (final cand in combinedEmailCandidates) {
      if (seenNormalizedEmails.contains(cand.normalized)) continue;
      seenNormalizedEmails.add(cand.normalized);

      final fromPrimary = primaryEmailCandidates.any((pe) => pe.normalized == cand.normalized);
      final fromSecondary = secondaryEmailCandidates.any((se) => se.normalized == cand.normalized);
      final source = (fromPrimary && fromSecondary)
          ? 'Both ($primaryEngineName & $secondaryEngineName)'
          : (fromPrimary ? primaryEngineName : secondaryEngineName);

      if (fromPrimary && fromSecondary) {
        agreedSignals.add('email');
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
        agreedSignals.add('website');
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

    final bool primaryIsPaddle = primaryEngineName.toLowerCase().contains('paddle');
    final bool secondaryIsPaddle = secondaryEngineName.toLowerCase().contains('paddle');

    final FieldCandidate? resolvedTitle = _arbitrateCandidateField(
      fieldName: 'jobTitle',
      candP: primaryTitleCand,
      candS: secondaryTitleCand,
      primaryIsPaddle: primaryIsPaddle,
      secondaryIsPaddle: secondaryIsPaddle,
      agreedSignals: agreedSignals,
      diagnosticNotes: diagnosticNotes,
      alternatives: alternatives,
      minAcceptableSemanticConfidence: 0.30,
      minAcceptableTextQuality: 0.40,
    );

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
        surroundingText: idx < primaryLines.length - 1 ? primaryLines[idx + 1] : null,
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
        surroundingText: idx < secondaryLines.length - 1 ? secondaryLines[idx + 1] : null,
        website: topWebsite,
        detectedEmails: allEmails,
      ),
    );

    final FieldCandidate? resolvedName = _arbitrateCandidateField(
      fieldName: 'fullName',
      candP: primaryNameCand,
      candS: secondaryNameCand,
      primaryIsPaddle: primaryIsPaddle,
      secondaryIsPaddle: secondaryIsPaddle,
      agreedSignals: agreedSignals,
      diagnosticNotes: diagnosticNotes,
      alternatives: alternatives,
      minAcceptableSemanticConfidence: 0.35,
      minAcceptableTextQuality: 0.50,
      isNameField: true,
    );

    // 6. EXTRACT & RESOLVE COMPANY
    final primaryCompanyCand = _findBestCandidateInLines(
      primaryLines,
      evaluateAdjacentPairs: true,
      evaluator: (line, idx) => evaluateCompanyCandidate(
        rawLine: line,
        sourceEngine: primaryEngineName,
        lineIndex: idx,
        website: topWebsite,
        personName: resolvedName?.value,
        emails: allEmails,
      ),
    );

    final secondaryCompanyCand = _findBestCandidateInLines(
      secondaryLines,
      evaluateAdjacentPairs: true,
      evaluator: (line, idx) => evaluateCompanyCandidate(
        rawLine: line,
        sourceEngine: secondaryEngineName,
        lineIndex: idx,
        website: topWebsite,
        personName: resolvedName?.value,
        emails: allEmails,
      ),
    );

    final FieldCandidate? resolvedCompany = _arbitrateCandidateField(
      fieldName: 'company',
      candP: primaryCompanyCand,
      candS: secondaryCompanyCand,
      primaryIsPaddle: primaryIsPaddle,
      secondaryIsPaddle: secondaryIsPaddle,
      agreedSignals: agreedSignals,
      diagnosticNotes: diagnosticNotes,
      alternatives: alternatives,
      minAcceptableSemanticConfidence: 0.30,
      minAcceptableTextQuality: 0.45,
    );

    // 7. EXTRACT & RESOLVE ADDRESS (Cross-engine multi-line clustering & merging)
    final primaryAddrLines = _collectAddressLines(primaryLines, resolvedName?.value, resolvedCompany?.value, resolvedTitle?.value);
    final secondaryAddrLines = _collectAddressLines(secondaryLines, resolvedName?.value, resolvedCompany?.value, resolvedTitle?.value);

    final primaryAddrCand = evaluateAddressCandidate(addressLines: primaryAddrLines, sourceEngine: primaryEngineName);
    final secondaryAddrCand = evaluateAddressCandidate(addressLines: secondaryAddrLines, sourceEngine: secondaryEngineName);

    // Merge complementary address lines from both engines
    final mergedAddrLines = <String>[];
    final seenNormAddr = <String>[];

    void addUniqueAddressLine(String line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;
      final norm = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (norm.isEmpty) return;

      bool isSubsumed = false;
      for (int i = 0; i < seenNormAddr.length; i++) {
        final existing = seenNormAddr[i];
        if (existing == norm) {
          isSubsumed = true;
          break;
        }
        if (existing.contains(norm) && (existing.length - norm.length) < 25) {
          isSubsumed = true;
          break;
        }
        if (norm.contains(existing) && (norm.length - existing.length) < 25) {
          seenNormAddr[i] = norm;
          mergedAddrLines[i] = trimmed;
          isSubsumed = true;
          break;
        }
      }
      if (!isSubsumed) {
        seenNormAddr.add(norm);
        mergedAddrLines.add(trimmed);
      }
    }

    for (final l in primaryAddrLines) {
      addUniqueAddressLine(l);
    }
    for (final l in secondaryAddrLines) {
      addUniqueAddressLine(l);
    }

    FieldCandidate? resolvedAddress;
    if (mergedAddrLines.isNotEmpty) {
      final bool hasPrimary = primaryAddrLines.isNotEmpty;
      final bool hasSecondary = secondaryAddrLines.isNotEmpty;
      final String source;
      if (hasPrimary && hasSecondary) {
        agreedSignals.add('address');
        source = 'Both ($primaryEngineName & $secondaryEngineName)';
      } else if (hasPrimary) {
        source = primaryEngineName;
      } else {
        source = secondaryEngineName;
      }

      final mergedCand = evaluateAddressCandidate(
        addressLines: mergedAddrLines,
        sourceEngine: source,
      );

      resolvedAddress = mergedCand;

      if (hasPrimary && hasSecondary && primaryAddrCand.value != secondaryAddrCand.value) {
        alternatives['address'] = [
          if (primaryAddrCand.value.isNotEmpty && primaryAddrCand.value != mergedCand.value)
            primaryAddrCand.value,
          if (secondaryAddrCand.value.isNotEmpty && secondaryAddrCand.value != mergedCand.value)
            secondaryAddrCand.value,
        ];
      }
    }

    // 8. PRESERVE UNCLASSIFIED LINES (Part 15)
    final claimedLineTexts = <String>{};
    if (resolvedName != null) claimedLineTexts.add(resolvedName.value.toLowerCase());
    if (resolvedTitle != null) claimedLineTexts.add(resolvedTitle.value.toLowerCase());
    if (resolvedCompany != null) claimedLineTexts.add(resolvedCompany.value.toLowerCase());
    if (resolvedAddress != null) {
      for (final part in resolvedAddress.value.split(',')) {
        claimedLineTexts.add(part.trim().toLowerCase());
      }
    }
    for (final p in resolvedPhones) {
      claimedLineTexts.add(p.value.toLowerCase());
    }
    for (final e in resolvedEmails) {
      claimedLineTexts.add(e.value.toLowerCase());
    }
    for (final w in resolvedWebsites) {
      claimedLineTexts.add(w.value.toLowerCase());
    }

    final unclassified = <String>[];
    final seenUnclassified = <String>{};
    for (final line in [...primaryLines, ...secondaryLines]) {
      final trimmed = line.trim();
      final lower = trimmed.toLowerCase();
      if (trimmed.isEmpty) continue;
      if (isSlogan(trimmed)) continue;
      if (_emailRegExp.hasMatch(trimmed) || _phoneRegExp.hasMatch(trimmed)) continue;
      if (claimedLineTexts.any((c) => lower == c || lower.contains(c) || c.contains(lower))) continue;
      if (seenUnclassified.contains(lower)) continue;
      seenUnclassified.add(lower);
      unclassified.add(trimmed);
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
      unclassifiedLines: unclassified,
    );
  }

  // --- Utility Helpers ---

  static FieldCandidate? _findBestCandidateInLines(
    List<String> lines, {
    required FieldCandidate Function(String line, int index) evaluator,
    bool evaluateAdjacentPairs = false,
  }) {
    FieldCandidate? best;
    for (int i = 0; i < lines.length; i++) {
      final cand = evaluator(lines[i], i);
      if (best == null || cand.semanticConfidence > best.semanticConfidence) {
        best = cand;
      }
    }
    if (evaluateAdjacentPairs && lines.length >= 2) {
      for (int i = 0; i < lines.length - 1; i++) {
        final line1 = lines[i].trim();
        final line2 = lines[i + 1].trim();
        if (_orgSuffixRegExp.hasMatch(line1)) continue;
        if (isLocationOrAddressLine(line2)) continue;
        if (_titleTokensRegExp.hasMatch(line1) || _titleTokensRegExp.hasMatch(line2)) continue;

        final line1HasCat = _companyTypeTokensRegExp.hasMatch(line1);
        final line2HasCat = _companyTypeTokensRegExp.hasMatch(line2) || _orgSuffixRegExp.hasMatch(line2);

        final words1 = line1.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        if (words1.length >= 2 && !_companyTypeTokensRegExp.hasMatch(line1)) {
          continue;
        }

        final words2 = line2.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        // If line 2 is already a complete multi-word company (e.g. "CHANDRU MEDICAL EQUIPMENTS" or "APEX MEDICAL SYSTEMS"),
        // do not prepend a brand mark from line 1
        if (words2.length >= 3 && line2HasCat) continue;

        if (!line1HasCat && line2HasCat) {
          final pairText = '$line1 $line2';
          final pairCand = evaluator(pairText, i);
          if (pairCand.semanticConfidence >= 0.35 &&
              (best == null || pairCand.semanticConfidence > best.semanticConfidence)) {
            best = pairCand;
          }
        }
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
      textQualityScore: computeTextQualityScore(value),
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
    final isExplicitAddrLine = <int, bool>{};

    for (int i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) continue;
      if (name != null && name.trim().isNotEmpty) {
        final lName = name.trim().toLowerCase();
        final lTrimmed = trimmed.toLowerCase();
        if (lTrimmed == lName || lTrimmed.contains(lName) || lName.contains(lTrimmed)) continue;
      }
      if (company != null && company.trim().isNotEmpty) {
        final lComp = company.trim().toLowerCase();
        final lTrimmed = trimmed.toLowerCase();
        if (lTrimmed == lComp || lTrimmed.contains(lComp) || lComp.contains(lTrimmed)) continue;
      }
      if (title != null && title.trim().isNotEmpty) {
        final lTitle = title.trim().toLowerCase();
        final lTrimmed = trimmed.toLowerCase();
        if (lTrimmed == lTitle || lTrimmed.contains(lTitle) || lTitle.contains(lTrimmed)) continue;
      }
      if (_emailRegExp.hasMatch(trimmed) || trimmed.contains('@')) continue;
      if (_urlSchemeOrWwwRegExp.hasMatch(trimmed)) continue;

      // Skip explicit phone labels
      final isExplicitPhone = RegExp(
        r'^(?:m|mob|mobile|p|ph|phone|tel|telephone|fax|whatsapp|cell)\s*[:\-\.]',
        caseSensitive: false,
      ).hasMatch(trimmed);
      if (isExplicitPhone) continue;

      // Skip pure phone numbers
      if (RegExp(r'^(?:\+?\d{1,4}[-\s.]?)?\(?\d{2,5}\)?[-\s.]?\d{3,5}[-\s.]?\d{3,5}$').hasMatch(trimmed)) {
        continue;
      }

      // Skip tax & statutory numbers
      final upper = trimmed.toUpperCase();
      if (upper.contains('GSTIN') || upper.contains('GST:') || upper.contains('CIN:') || upper.contains('INVOICE:') || upper.contains('PAN:') || upper.startsWith('ISO') || upper.startsWith('CE ')) {
        continue;
      }

      final addrLabelMatch = RegExp(
        r'^(?:address|addr|office address|office|headquarters|hq|location)\s*[:\-]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (addrLabelMatch != null) {
        isExplicitAddrLine[i] = true;
        continue;
      }

      if (isLocationOrAddressLine(trimmed)) {
        isExplicitAddrLine[i] = true;
      }
    }

    // Preserve intermediate address lines within address clusters
    for (int i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) continue;
      if (name != null && name.trim().isNotEmpty) {
        final lName = name.trim().toLowerCase();
        final lTrimmed = trimmed.toLowerCase();
        if (lTrimmed == lName || lTrimmed.contains(lName) || lName.contains(lTrimmed)) continue;
      }
      if (company != null && company.trim().isNotEmpty) {
        final lComp = company.trim().toLowerCase();
        final lTrimmed = trimmed.toLowerCase();
        if (lTrimmed == lComp || lTrimmed.contains(lComp) || lComp.contains(lTrimmed)) continue;
      }
      if (title != null && title.trim().isNotEmpty) {
        final lTitle = title.trim().toLowerCase();
        final lTrimmed = trimmed.toLowerCase();
        if (lTrimmed == lTitle || lTrimmed.contains(lTitle) || lTitle.contains(lTrimmed)) continue;
      }
      if (_emailRegExp.hasMatch(trimmed) || trimmed.contains('@')) continue;
      if (_urlSchemeOrWwwRegExp.hasMatch(trimmed)) continue;
      if (RegExp(r'^(?:m|mob|mobile|p|ph|phone|tel|telephone|fax|whatsapp|cell)\s*[:\-\.]', caseSensitive: false).hasMatch(trimmed)) continue;
      if (RegExp(r'^(?:\+?\d{1,4}[-\s.]?)?\(?\d{2,5}\)?[-\s.]?\d{3,5}[-\s.]?\d{3,5}$').hasMatch(trimmed)) continue;
      final upper = trimmed.toUpperCase();
      if (upper.contains('GSTIN') || upper.contains('GST:') || upper.contains('CIN:') || upper.contains('INVOICE:') || upper.contains('PAN:') || upper.startsWith('ISO') || upper.startsWith('CE ')) continue;

      final addrLabelMatch = RegExp(
        r'^(?:address|addr|office address|office|headquarters|hq|location)\s*[:\-]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (addrLabelMatch != null) {
        final val = addrLabelMatch.group(1)!.trim();
        if (val.isNotEmpty) addr.add(val);
        continue;
      }

      bool shouldAdd = isExplicitAddrLine[i] == true;

      // Intermediate line preservation: line i is flanked by address lines within a window of 2
      if (!shouldAdd) {
        final bool isOtherEntity = _orgSuffixRegExp.hasMatch(trimmed) ||
            _companyTypeTokensRegExp.hasMatch(trimmed) ||
            _titleTokensRegExp.hasMatch(trimmed) ||
            _honorificPrefixRegExp.hasMatch(trimmed) ||
            _credentialTokenRegExp.hasMatch(trimmed) ||
            isSlogan(trimmed) ||
            evaluateNameCandidate(rawLine: trimmed, sourceEngine: 'AddressGuard').semanticConfidence >= 0.40;

        if (!isOtherEntity) {
          final bool precededByAddr = (i > 0 && isExplicitAddrLine[i - 1] == true) || (i > 1 && isExplicitAddrLine[i - 2] == true);
          final bool followedByAddr = (i < lines.length - 1 && isExplicitAddrLine[i + 1] == true) || (i < lines.length - 2 && isExplicitAddrLine[i + 2] == true);
          if (precededByAddr && followedByAddr) {
            shouldAdd = true;
          } else if (followedByAddr && (trimmed.endsWith(',') || RegExp(r'^\s*(?:#|no\.?|door|flat|plot|survey)?\s*\d+[/0-9a-zA-Z-]*\b', caseSensitive: false).hasMatch(trimmed))) {
            shouldAdd = true;
          }
        }
      }

      if (shouldAdd) {
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

  static String _normalizeConfusionCharacters(String s) {
    return s
        .replaceAll('0', 'O')
        .replaceAll('1', 'I')
        .replaceAll('5', 'S')
        .replaceAll('8', 'B')
        .replaceAll('2', 'Z')
        .replaceAll('6', 'G')
        .replaceAll('7', 'T')
        .replaceAll('l', 'I')
        .replaceAll('L', 'I')
        .replaceAll('|', 'I')
        .replaceAll(RegExp(r'rn', caseSensitive: false), 'M')
        .replaceAll(RegExp(r'vv', caseSensitive: false), 'W')
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z]'), '');
  }

  static String _normalizeForComparison(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
  }

  static FieldCandidate? _arbitrateCandidateField({
    required String fieldName,
    required FieldCandidate? candP,
    required FieldCandidate? candS,
    required bool primaryIsPaddle,
    required bool secondaryIsPaddle,
    required List<String> agreedSignals,
    required List<String> diagnosticNotes,
    required Map<String, List<String>> alternatives,
    double minAcceptableSemanticConfidence = 0.30,
    double minAcceptableTextQuality = 0.40,
    bool isNameField = false,
  }) {
    if (candP == null && candS == null) return null;
    if (candP == null) {
      final s = candS!;
      if (s.semanticConfidence >= minAcceptableSemanticConfidence &&
          s.textQualityScore >= minAcceptableTextQuality) {
        return s;
      }
      return null;
    }
    if (candS == null) {
      final p = candP;
      if (p.semanticConfidence >= minAcceptableSemanticConfidence &&
          p.textQualityScore >= minAcceptableTextQuality) {
        return p;
      }
      return null;
    }

    final FieldCandidate p = candP;
    final FieldCandidate s = candS;

    // Both candidates exist. Check near-equivalence first.
    final normP = _normalizeForComparison(p.value);
    final normS = _normalizeForComparison(s.value);

    final normConfP = _normalizeConfusionCharacters(p.value);
    final normConfS = _normalizeConfusionCharacters(s.value);
    final bool isConfusionEquivalent = normConfP.isNotEmpty &&
        normConfS.isNotEmpty &&
        normConfP.length >= 4 &&
        normConfP == normConfS;

    final bool isNearEquivalent = isConfusionEquivalent ||
        (normP.isNotEmpty &&
            normS.isNotEmpty &&
            (normP == normS ||
                (normP.length >= 4 &&
                    normS.length >= 4 &&
                    (normP.contains(normS) || normS.contains(normP)) &&
                    (normP.length - normS.length).abs() <= 2)));

    if (isNearEquivalent) {
      final baseSemantic = max(p.semanticConfidence, s.semanticConfidence);
      if (baseSemantic < minAcceptableSemanticConfidence) {
        diagnosticNotes.add(
          'Discarded near-equivalent $fieldName "${p.value}" because base semantic confidence (${baseSemantic.toStringAsFixed(2)}) < $minAcceptableSemanticConfidence',
        );
        return null;
      }

      if (!agreedSignals.contains(fieldName)) agreedSignals.add(fieldName);
      if (fieldName == 'fullName' && !agreedSignals.contains('name')) {
        agreedSignals.add('name');
      }

      // Compare formatting quality (prefer clean spaces, Title Case over fused camel/lowercasing)
      final fmtP = scoreFormattingQuality(p.value);
      final fmtS = scoreFormattingQuality(s.value);

      final pWordDigits = p.value.replaceAll(RegExp(r'[^0-9]'), '').length;
      final sWordDigits = s.value.replaceAll(RegExp(r'[^0-9]'), '').length;

      final FieldCandidate winner;
      final FieldCandidate loser;
      if (pWordDigits != sWordDigits) {
        winner = pWordDigits < sWordDigits ? p : s;
        loser = pWordDigits < sWordDigits ? s : p;
      } else if ((fmtP - fmtS).abs() > 0.05) {
        winner = fmtP >= fmtS ? p : s;
        loser = fmtP >= fmtS ? s : p;
      } else if (p.ocrConfidence != s.ocrConfidence) {
        winner = p.ocrConfidence >= s.ocrConfidence ? p : s;
        loser = p.ocrConfidence >= s.ocrConfidence ? s : p;
      } else {
        winner = p.textQualityScore >= s.textQualityScore ? p : s;
        loser = p.textQualityScore >= s.textQualityScore ? s : p;
      }

      final boostedSemantic =
          min(1.0, max(p.semanticConfidence, s.semanticConfidence) + 0.15);
      final mergedCandidate = FieldCandidate(
        field: fieldName,
        value: winner.value,
        sourceEngine: 'Agreed (${p.sourceEngine} & ${s.sourceEngine})',
        ocrConfidence: max(p.ocrConfidence, s.ocrConfidence),
        semanticConfidence: boostedSemantic,
        textQualityScore: max(p.textQualityScore, s.textQualityScore),
        positiveEvidence: [
          ...winner.positiveEvidence,
          'Cross-engine consensus with clean formatting preferred over ${loser.value}',
        ],
        spatialEvidence: winner.spatialEvidence,
      );

      if (loser.value.isNotEmpty && loser.value != winner.value) {
        alternatives[fieldName] = [loser.value];
      }
      diagnosticNotes.add(
        'Reconciled duplicate/near-equivalent $fieldName: "${winner.value}" (fmt: ${fmtP.toStringAsFixed(2)}) preferred over "${loser.value}" (fmt: ${fmtS.toStringAsFixed(2)})',
      );

      if (mergedCandidate.textQualityScore < minAcceptableTextQuality) {
        return null;
      }

      return mergedCandidate;
    }

    // Disagreement between different candidate strings
    // Compute composite quality-weighted score: 65% semantic, 35% text quality
    final compositeP =
        (p.semanticConfidence * 0.65) + (p.textQualityScore * 0.35);
    final compositeS =
        (s.semanticConfidence * 0.65) + (s.textQualityScore * 0.35);

    // Severe garbled-text check: if one candidate is garbled, clean candidate wins immediately!
    final bool pIsGarbled = p.textQualityScore < 0.55 ||
        p.rejectionReasons.any((r) =>
            r.contains('mixed digits') ||
            r.contains('Low text quality') ||
            r.contains('corrupt'));
    final bool sIsGarbled = s.textQualityScore < 0.55 ||
        s.rejectionReasons.any((r) =>
            r.contains('mixed digits') ||
            r.contains('Low text quality') ||
            r.contains('corrupt'));

    FieldCandidate? selected;
    FieldCandidate? alternate;

    if (pIsGarbled && !sIsGarbled && s.semanticConfidence >= minAcceptableSemanticConfidence) {
      selected = s;
      alternate = p;
      diagnosticNotes.add(
          'Selected clean $fieldName "${s.value}" over garbled candidate "${p.value}"');
    } else if (sIsGarbled && !pIsGarbled && p.semanticConfidence >= minAcceptableSemanticConfidence) {
      selected = p;
      alternate = s;
      diagnosticNotes.add(
          'Selected clean $fieldName "${p.value}" over garbled candidate "${s.value}"');
    } else if (isNameField) {
      // Special rule for name field: full name vs initials
      final pHasInitials = p.value
          .split(RegExp(r'\s+'))
          .any((w) => RegExp(r'^[A-Z]\.?$').hasMatch(w));
      final sHasInitials = s.value
          .split(RegExp(r'\s+'))
          .any((w) => RegExp(r'^[A-Z]\.?$').hasMatch(w));
      if (!pHasInitials && sHasInitials && p.isTrustworthy && (compositeP - compositeS).abs() < 0.20) {
        selected = p;
        alternate = s;
      } else if (pHasInitials && !sHasInitials && s.isTrustworthy && (compositeS - compositeP).abs() < 0.20) {
        selected = s;
        alternate = p;
      }
    } else if (fieldName == 'jobTitle') {
      final pHasOccupational = _titleTokensRegExp.hasMatch(p.value);
      final sHasOccupational = _titleTokensRegExp.hasMatch(s.value);
      if (pHasOccupational && !sHasOccupational && p.isTrustworthy) {
        selected = p;
        alternate = s;
        diagnosticNotes.add(
            'Selected job title "${p.value}" with occupational evidence over non-occupational "${s.value}"');
      } else if (sHasOccupational && !pHasOccupational && s.isTrustworthy) {
        selected = s;
        alternate = p;
        diagnosticNotes.add(
            'Selected job title "${s.value}" with occupational evidence over non-occupational "${p.value}"');
      }
    } else if (fieldName == 'company') {
      final pHasOrg = _companyTypeTokensRegExp.hasMatch(p.value);
      final sHasOrg = _companyTypeTokensRegExp.hasMatch(s.value);
      if (pHasOrg && !sHasOrg && p.isTrustworthy) {
        selected = p;
        alternate = s;
        diagnosticNotes.add(
            'Selected company "${p.value}" with organization indicator over non-organization "${s.value}"');
      } else if (sHasOrg && !pHasOrg && s.isTrustworthy) {
        selected = s;
        alternate = p;
        diagnosticNotes.add(
            'Selected company "${s.value}" with organization indicator over non-organization "${p.value}"');
      }
    }

    if (selected == null) {
      final scoreDelta = compositeP - compositeS;
      if (scoreDelta.abs() >= 0.05) {
        // Clear winner by score
        if (scoreDelta > 0) {
          selected = p;
          alternate = s;
        } else {
          selected = s;
          alternate = p;
        }
        diagnosticNotes.add(
          'Selected $fieldName "${selected.value}" (comp: ${max(compositeP, compositeS).toStringAsFixed(2)}) '
          'decisively over "${alternate.value}" (comp: ${min(compositeP, compositeS).toStringAsFixed(2)})',
        );
      } else {
        // Score is very close (< 0.05 difference, effectively a tie).
        // If primary engine candidate is solid (good quality & confidence), prefer primary as tie-breaker
        if ((p.textQualityScore - s.textQualityScore).abs() >= 0.05) {
          selected = p.textQualityScore > s.textQualityScore ? p : s;
          alternate = p.textQualityScore > s.textQualityScore ? s : p;
          diagnosticNotes.add('Text quality tie-break selected $fieldName: "${selected.value}"');
        } else {
          selected = compositeP >= compositeS ? p : s;
          alternate = compositeP >= compositeS ? s : p;
        }
      }
    }

    final winningCandidate = selected;

    if (alternate != null && alternate.value.isNotEmpty && alternate.value != winningCandidate.value) {
      alternatives[fieldName] = [alternate.value];
    }

    // Minimum acceptance filter
    if (winningCandidate.semanticConfidence < minAcceptableSemanticConfidence ||
        winningCandidate.textQualityScore < minAcceptableTextQuality) {
      diagnosticNotes.add(
          'Discarded winning $fieldName "${winningCandidate.value}" because confidence or text quality failed minimum threshold');
      return null;
    }

    return winningCandidate;
  }
}
