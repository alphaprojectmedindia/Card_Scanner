import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../models/business_card_data.dart';
import '../models/business_card_email.dart';
import '../models/business_card_phone.dart';
import '../models/field_evidence.dart';
import '../models/ocr_side_result.dart';
import 'ocr/email_ocr_recovery.dart';
import 'ocr/field_semantic_evaluator.dart';
import 'ocr/phone_ocr_recovery.dart';

/// Conservative layout-aware parser that converts raw recognized OCR text and
/// layout metadata into structured [BusinessCardData].
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

  static final RegExp _departmentPrefixRegExp = RegExp(
    r'^(?:department|dept\.?|division|div\.?|faculty|centre for|center for|school of)\s+(?:of\s+)?(.+)$',
    caseSensitive: false,
  );

  static final RegExp _departmentSuffixRegExp = RegExp(
    r'^(.+)\s+(?:department|dept\.?|division|faculty)$',
    caseSensitive: false,
  );

  static final RegExp _standaloneSpecialtyRegExp = RegExp(
    r'^(?:cardiology|orthopaedics|orthopedics|neurology|pediatrics|paediatrics|oncology|dermatology|gynecology|radiology|anaesthesia|pathology|urology|nephrology|gastroenterology|litigation|taxation|corporate banking)$',
    caseSensitive: false,
  );

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
      r'^(?:we\s+bring\s+performances\s+alive)',
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

  static const Set<String> _publicEmailDomains = {
    'gmail.com',
    'yahoo.com',
    'hotmail.com',
    'outlook.com',
    'icloud.com',
    'rediffmail.com',
    'live.com',
  };

  static const List<String> _jobTitleKeywords = [
    'head of',
    'head of client services',
    'head of engineering',
    'head of operations',
    'head of sales',
    'head of product',
    'head',
    'director of cloud solutions',
    'director of engineering',
    'director of operations',
    'vice president - enterprise services',
    'developer',
    'senior developer',
    'lead developer',
    'software developer',
    'full stack developer',
    'software engineer',
    'senior software engineer',
    'lead engineer',
    'engineer',
    'frontend developer',
    'backend developer',
    'mobile developer',
    'ios developer',
    'android developer',
    'managing director',
    'director',
    'executive director',
    'sales manager',
    'manager',
    'general manager',
    'project manager',
    'product manager',
    'marketing manager',
    'hr manager',
    'operations manager',
    'business development manager',
    'branch manager',
    'account manager',
    'founder & chairman',
    'founder and chairman',
    'chairman & managing director',
    'chairman',
    'director & ceo',
    'founder & ceo',
    'founder',
    'co-founder',
    'ceo',
    'cto',
    'cfo',
    'coo',
    'cmo',
    'cio',
    'doctor',
    'physician',
    'surgeon',
    'transplant surgeon',
    'cardiac surgeon',
    'medical director',
    'nephrologist',
    'urologist',
    'clinical psychologist',
    'cardiologist',
    'neurologist',
    'dermatologist',
    'pediatrician',
    'oncologist',
    'medical officer',
    'consultant',
    'senior consultant',
    'managing trustee',
    'trustee',
    'lead',
    'team lead',
    'tech lead',
    'architect',
    'solution architect',
    'enterprise architect',
    'designer',
    'ui/ux designer',
    'graphic designer',
    'creative director',
    'president',
    'vice president',
    'vp',
    'partner',
    'analyst',
    'business analyst',
    'data scientist',
    'specialist',
    'executive',
    'associate',
    'officer',
    'strategist',
    'professor',
    'associate professor',
    'assistant professor',
    'lecturer',
    'dean',
    'principal',
    'advocate',
    'legal counsel',
    'attorney',
    'solicitor',
    'accountant',
    'chartered accountant',
    'auditor',
    'financial analyst',
    'coordinator',
    'administrator',
    'broker',
    'real estate broker',
    'licensed real estate broker',
    'realtor',
    'commissioner',
    'assistant commissioner',
    'deputy commissioner',
    'international director',
    'hon. consul of spain',
    'consul of spain',
    'hon. consul',
    'hon consul',
    'honorary consul',
    'consul',
  ];

  static const List<String> _companyKeywords = [
    'educational',
    'education',
    'institutions',
    'institution',
    'corporations',
    'holding',
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
    'llp',
    'ltd',
    'limited',
    'pvt ltd',
    'private limited',
    'holdings',
    'group',
    'consulting',
    'consultancy',
    'equipments',
    'equipment',
    'medical',
    'engineering',
    'manufacturing',
    'traders',
    'trader',
    'realty',
    'realtors',
    'brokerage',
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
    'company',
    'co.',
    'co',
    'innovations',
    'innovation',
    'institute',
    'advisory',
    'hospital',
    'healthcare',
    'health',
    'clinic',
    'foundation',
    'trust',
    'architecture',
    'architects',
    'dynamics',
    'logistics',
    'interactive',
    'digital',
    'media',
    'capital',
    'partners',
    'hospitals',
    'clinics',
    'infirmary',
    'dispensary',
    'university',
    'college',
    'school',
    'academy',
    'polytechnic',
    'court',
    'high court',
    'supreme court',
    'tribunal',
    'chambers',
    'law firm',
    'bank',
    'banking',
    'insurance',
    'securities',
    'investments',
    'hotel',
    'hotels',
    'resort',
    'resorts',
    'inn',
    'restaurant',
    'travels',
    'tours',
    'holidays',
    'builders',
    'construction',
    'contractors',
    'electricals',
    'electronics',
    'motors',
    'garage',
    'stores',
    'chronicle',
    'press',
    'publications',
    'ministry',
    'council',
    'authority',
    'works',
    'realty',
    'properties',
    'centre',
    'center',
    'diagnostic',
    'eye care',
    'dental',
    'government',
    'workshop',
    'care',
    'life care',
    'wellness',
    'sanctuary',
    'auto',
    'automotive',
    'commission',
    'secretariat',
    'parliament',
    'laboratories',
    'laboratory',
    'pharmacy',
    'pharma',
    'spa',
    'salon',
    'bakery',
    'undertaking',
    'consulate',
    'embassy',
    'board',
    'federation',
    'society',
    'association',
    'studios',
    'guild',
    'guilds',
    'club',
    'clubs',
    'alliance',
    'league',
    'lions clubs international',
    'lions clubs',
    'lions club',
    'consulate of spain',
  ];

  static const List<String> _addressKeywords = [
    'street',
    'road',
    'avenue',
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
    'broadway',
    'highway',
    'drive',
    'boulevard',
    'way',
    'circle',
    'court',
    'headquarters',
    'hq',
    'salai',
    'marg',
    'bazaar',
    'cross',
    'main',
    'block',
    'layout',
    'estate',
    'sidco',
    'sipcot',
    'enclave',
    'phase',
    'stage',
    'park',
    'po',
    'p.o',
    'pin',
    'pincode',
    'zip',
    'dist',
    'district',
    'state',
    'chennai',
    'bangalore',
    'bengaluru',
    'mumbai',
    'delhi',
    'new delhi',
    'hyderabad',
    'kolkata',
    'pune',
    'tamil nadu',
    'karnataka',
    'maharashtra',
    'telangana',
    'kerala',
    'andhra pradesh',
    'gujarat',
    'rajasthan',
    'west bengal',
    'uttar pradesh',
    'guindy',
    't nagar',
    'velachery',
    'omr',
    'whitefield',
    'koramangala',
    'hitec city',
    'indiranagar',
    'noida',
    'gurugram',
    'gurgaon',
    'ahmedabad',
    'coimbatore',
    'madurai',
    'trichy',
    'kochi',
    'trivandrum',
    'jaipur',
    'chandigarh',
    'lucknow',
    'new york',
    'san francisco',
    'london',
    'singapore',
    'dubai',
    'uae',
    'toronto',
    'canada',
    'sydney',
    'australia',
    'germany',
    'france',
    'tokyo',
    'japan',
    'india',
    'usa',
    'uk',
    'united kingdom',
    'california',
    'texas',
  ];

  /// Legacy single-sided string parser (preserves 100% backward compatibility).
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

    return _parseLineList(rawLines, rawText);
  }

  /// Parses a single side's OCR result with spatial and layout awareness.
  BusinessCardData parseSide(OcrSideResult sideResult) {
    if (sideResult.isEmpty) {
      return BusinessCardData(
        rawRecognizedText: sideResult.rawText,
        frontRawText:
            sideResult.side == CardSide.front ? sideResult.rawText : null,
        backRawText:
            sideResult.side == CardSide.back ? sideResult.rawText : null,
      );
    }

    // If sideResult already carries field-level resolution from HybridOcrPipeline,
    // honor the resolved fields directly!
    if (sideResult.metadata.containsKey('fieldResolution') ||
        sideResult.metadata.containsKey('hybridFieldResolution')) {
      final fieldRes = (sideResult.metadata['fieldResolution'] ??
              sideResult.metadata['hybridFieldResolution'])
          as Map<String, dynamic>?;
      if (fieldRes != null) {
        return _buildFromFieldResolution(
          fieldRes,
          sideResult,
          isFront: sideResult.side == CardSide.front,
        );
      }
    }

    final orderedLines = _getSpatiallyOrderedLines(sideResult);
    return _parseLineList(
      orderedLines,
      sideResult.rawText,
      sideMetadata: sideResult.lines,
      isFront: sideResult.side == CardSide.front,
    );
  }

  /// Builds a strongly-typed [BusinessCardData] from an existing hybrid field resolution.
  BusinessCardData _buildFromFieldResolution(
    Map<String, dynamic> fieldRes,
    OcrSideResult sideResult, {
    bool isFront = true,
  }) {
    final nameObj = fieldRes['name'] as Map<String, dynamic>?;
    final titleObj = fieldRes['jobTitle'] as Map<String, dynamic>?;
    final compObj = fieldRes['company'] as Map<String, dynamic>?;
    final addrObj = fieldRes['address'] as Map<String, dynamic>?;

    final nameVal = nameObj?['value'] as String?;
    final titleVal = titleObj?['value'] as String?;
    final compVal = compObj?['value'] as String?;
    final addrVal = addrObj?['value'] as String?;

    // Phones
    final phonesList = <BusinessCardPhone>[];
    final seenPhoneNorms = <String>{};
    final rawPhones = fieldRes['phones'] as List<dynamic>? ?? const [];
    for (final p in rawPhones) {
      if (p is Map<String, dynamic>) {
        final val = p['value'] as String?;
        if (val != null && val.trim().isNotEmpty) {
          final spatial = p['spatialEvidence'] as Map<String, dynamic>?;
          final norm = spatial?['normalized'] as String? ??
              PhoneOcrRecovery.normalizePhoneNumber(val);
          final label = spatial?['label'] as String? ??
              PhoneOcrRecovery.detectPhoneLabel(val);

          bool isDup = false;
          for (final seen in seenPhoneNorms) {
            if (PhoneOcrRecovery.areEquivalentPhones(norm, seen)) {
              isDup = true;
              break;
            }
          }
          if (isDup) continue;

          seenPhoneNorms.add(norm);
          phonesList.add(BusinessCardPhone(
            number: val.trim(),
            normalizedNumber: norm,
            label: label,
          ));
        }
      }
    }

    // Emails
    final emailsList = <BusinessCardEmail>[];
    final seenEmails = <String>{};
    final rawEmails = fieldRes['emails'] as List<dynamic>? ?? const [];
    for (final e in rawEmails) {
      if (e is Map<String, dynamic>) {
        final val = e['value'] as String?;
        if (val != null && val.trim().isNotEmpty) {
          final norm = BusinessCardEmail.normalize(val.trim());
          if (!seenEmails.contains(norm)) {
            seenEmails.add(norm);
            final spatial = e['spatialEvidence'] as Map<String, dynamic>?;
            final label = spatial?['label'] as String?;
            emailsList.add(BusinessCardEmail(
              email: val.trim(),
              normalizedEmail: norm,
              label: label,
            ));
          }
        }
      }
    }

    // Website
    String? websiteVal;
    final rawWebsites = fieldRes['websites'] as List<dynamic>? ?? const [];
    if (rawWebsites.isNotEmpty && rawWebsites.first is Map<String, dynamic>) {
      websiteVal = rawWebsites.first['value'] as String?;
    }

    // Alternatives & notes
    final alternativeCandidates = <String, List<String>>{};
    final rawAlts = fieldRes['alternatives'] as Map<String, dynamic>?;
    if (rawAlts != null) {
      rawAlts.forEach((k, v) {
        if (v is List<dynamic>) {
          alternativeCandidates[k] = v.map((e) => e.toString()).toList();
        }
      });
    }

    final parsingNotes = <String>[];
    final rawNotes = fieldRes['diagnosticNotes'] as List<dynamic>?;
    if (rawNotes != null) {
      parsingNotes.addAll(rawNotes.map((e) => e.toString()));
    }

    // Fallback line extraction if needed
    final lineTexts = sideResult.lines.map((l) => l.text).toList();
    if (phonesList.isEmpty) {
      phonesList.addAll(_extractPhoneNumbers(lineTexts));
    }
    if (emailsList.isEmpty) {
      emailsList.addAll(_extractEmails(lineTexts, sideResult.rawText));
    }
    final companyVal = (compVal != null && compVal.trim().isNotEmpty)
        ? compVal.trim()
        : null;
    final addressVal = (addrVal != null && addrVal.trim().isNotEmpty)
        ? addrVal.trim()
        : null;

    final fieldConfidenceStates = <String, String>{};
    final rawStates = fieldRes['fieldConfidenceStates'] as Map<String, dynamic>? ??
        sideResult.metadata['fieldConfidenceStates'] as Map<String, dynamic>?;
    if (rawStates != null) {
      rawStates.forEach((k, v) => fieldConfidenceStates[k] = v.toString());
    } else {
      fieldConfidenceStates['fullName'] = (nameVal != null && nameVal.trim().isNotEmpty)
          ? (FieldSemanticEvaluator.computeTextQualityScore(nameVal) >= 0.70 ? 'highConfidence' : 'needsReview')
          : 'notDetected';
      fieldConfidenceStates['jobTitle'] = (titleVal != null && titleVal.trim().isNotEmpty)
          ? (FieldSemanticEvaluator.computeTextQualityScore(titleVal) >= 0.70 ? 'highConfidence' : 'needsReview')
          : 'notDetected';
      fieldConfidenceStates['company'] = (companyVal != null && companyVal.trim().isNotEmpty)
          ? (FieldSemanticEvaluator.computeTextQualityScore(companyVal) >= 0.70 ? 'highConfidence' : 'needsReview')
          : 'notDetected';
      fieldConfidenceStates['address'] = (addressVal != null && addressVal.trim().isNotEmpty)
          ? (addressVal.length >= 10 && FieldSemanticEvaluator.computeTextQualityScore(addressVal) >= 0.70 ? 'highConfidence' : 'needsReview')
          : 'notDetected';
      fieldConfidenceStates['phone'] = phonesList.isNotEmpty
          ? (phonesList.every((p) => p.number.replaceAll(RegExp(r'\D'), '').length >= 7) ? 'highConfidence' : 'needsReview')
          : 'notDetected';
      fieldConfidenceStates['email'] = emailsList.isNotEmpty
          ? (emailsList.every((e) => EmailOcrRecovery.isValidEmail(e.email)) ? 'highConfidence' : 'needsReview')
          : 'notDetected';
      fieldConfidenceStates['website'] = websiteVal != null && websiteVal.isNotEmpty
          ? ((_urlSchemeOrWwwRegExp.hasMatch(websiteVal) || _domainRegExp.hasMatch(websiteVal)) ? 'highConfidence' : 'needsReview')
          : 'notDetected';
    }

    final unclassifiedLines = <String>[];
    final rawUnclassified = fieldRes['unclassifiedLines'] as List<dynamic>? ??
        sideResult.metadata['unclassifiedLines'] as List<dynamic>?;
    if (rawUnclassified != null) {
      for (final u in rawUnclassified) {
        unclassifiedLines.add(u.toString());
      }
    }

    return BusinessCardData(
      fullName: (nameVal != null && nameVal.trim().isNotEmpty)
          ? nameVal.trim()
          : null,
      jobTitle: (titleVal != null && titleVal.trim().isNotEmpty)
          ? titleVal.trim()
          : null,
      company: (companyVal != null && companyVal.trim().isNotEmpty)
          ? companyVal.trim()
          : null,
      address: (addressVal != null && addressVal.trim().isNotEmpty)
          ? addressVal.trim()
          : null,
      phoneNumbers: phonesList,
      emailAddresses: emailsList,
      website: websiteVal,
      rawRecognizedText: sideResult.rawText,
      frontRawText: isFront ? sideResult.rawText : null,
      backRawText: !isFront ? sideResult.rawText : null,
      alternativeCandidates: alternativeCandidates,
      parsingNotes: parsingNotes,
      fieldConfidenceStates: fieldConfidenceStates,
      unclassifiedLines: unclassifiedLines,
    );
  }

  /// Intelligently parses dual-sided card results (front + optional back),
  /// merging both sides using deterministic business rules and preserving layout signals.
  BusinessCardData parseDualSided({
    required OcrSideResult front,
    OcrSideResult? back,
  }) {
    final frontData = parseSide(front);

    if (back == null || back.isEmpty) {
      return frontData.copyWith(
        isDualSided: false,
        frontRawText: front.rawText,
      );
    }

    final backData = parseSide(back);
    return mergeDualSidedData(
      frontData: frontData,
      backData: backData,
      frontRawText: front.rawText,
      backRawText: back.rawText,
    );
  }

  /// Merges structured front and back side data according to strict production business rules.
  BusinessCardData mergeDualSidedData({
    required BusinessCardData frontData,
    required BusinessCardData backData,
    required String frontRawText,
    required String backRawText,
  }) {
    final alternativeCandidates = <String, List<String>>{};
    final parsingNotes = <String>[];

    // Merge notes and candidates from both sides first
    parsingNotes.addAll(frontData.parsingNotes);
    for (final n in backData.parsingNotes) {
      if (!parsingNotes.contains(n)) {
        parsingNotes.add(n);
      }
    }
    frontData.alternativeCandidates.forEach((k, v) {
      alternativeCandidates[k] = List<String>.from(v);
    });
    backData.alternativeCandidates.forEach((k, v) {
      if (alternativeCandidates.containsKey(k)) {
        for (final item in v) {
          if (!alternativeCandidates[k]!.contains(item)) {
            alternativeCandidates[k]!.add(item);
          }
        }
      } else {
        alternativeCandidates[k] = List<String>.from(v);
      }
    });

    // 1. FULL NAME
    // Primary: Front side is authoritative for the cardholder's identity.
    String? chosenName;
    if (frontData.fullName != null && frontData.fullName!.trim().isNotEmpty) {
      chosenName = frontData.fullName;
      if (backData.fullName != null &&
          backData.fullName!.trim().isNotEmpty &&
          backData.fullName!.trim().toLowerCase() !=
              frontData.fullName!.trim().toLowerCase()) {
        final existing = alternativeCandidates['fullName'] ?? [];
        if (!existing.contains(backData.fullName!.trim())) {
          existing.add(backData.fullName!.trim());
        }
        alternativeCandidates['fullName'] = existing;
        parsingNotes.add(
            'Alternative name candidate on back side: "${backData.fullName!.trim()}"');
      }
    } else if (backData.fullName != null &&
        backData.fullName!.trim().isNotEmpty) {
      chosenName = backData.fullName;
    }

    // 2. JOB TITLE
    // Primary: Front side designation.
    String? chosenJobTitle;
    if (frontData.jobTitle != null && frontData.jobTitle!.trim().isNotEmpty) {
      chosenJobTitle = frontData.jobTitle;
      if (backData.jobTitle != null &&
          backData.jobTitle!.trim().isNotEmpty &&
          backData.jobTitle!.trim().toLowerCase() !=
              frontData.jobTitle!.trim().toLowerCase()) {
        final existing = alternativeCandidates['jobTitle'] ?? [];
        if (!existing.contains(backData.jobTitle!.trim())) {
          existing.add(backData.jobTitle!.trim());
        }
        alternativeCandidates['jobTitle'] = existing;
        parsingNotes.add(
            'Alternative designation on back side: "${backData.jobTitle!.trim()}"');
      }
    } else if (backData.jobTitle != null &&
        backData.jobTitle!.trim().isNotEmpty) {
      chosenJobTitle = backData.jobTitle;
    }

    // 3. COMPANY
    // Primary: Clearly identified primary organization.
    String? chosenCompany;
    if (frontData.company != null && frontData.company!.trim().isNotEmpty) {
      chosenCompany = frontData.company;
      if (backData.company != null &&
          backData.company!.trim().isNotEmpty &&
          backData.company!.trim().toLowerCase() !=
              frontData.company!.trim().toLowerCase()) {
        final existing = alternativeCandidates['company'] ?? [];
        if (!existing.contains(backData.company!.trim())) {
          existing.add(backData.company!.trim());
        }
        alternativeCandidates['company'] = existing;
        parsingNotes.add(
            'Alternative organization on back side: "${backData.company!.trim()}"');
      }
    } else if (backData.company != null &&
        backData.company!.trim().isNotEmpty) {
      chosenCompany = backData.company;
    }

    // 4. PHONE NUMBERS (Union of Front + Back with deduplication)
    final mergedPhones = <BusinessCardPhone>[];
    final seenPhoneNorms = <String>{};

    for (final p in [...frontData.phoneNumbers, ...backData.phoneNumbers]) {
      final norm = p.normalizedNumber ?? BusinessCardPhone.normalize(p.number);
      final digitsOnly = norm.replaceAll(RegExp(r'\D'), '');

      if (_isDuplicatePhone(norm, digitsOnly, seenPhoneNorms)) {
        continue;
      }

      seenPhoneNorms.add(norm);
      if (digitsOnly.isNotEmpty) {
        seenPhoneNorms.add(digitsOnly);
      }
      mergedPhones.add(p);
    }

    // 5. EMAIL ADDRESSES (Union of Front + Back with deduplication)
    final mergedEmails = <BusinessCardEmail>[];
    final seenEmailNorms = <String>{};

    for (final e in [...frontData.emailAddresses, ...backData.emailAddresses]) {
      final norm = e.normalizedEmail ?? BusinessCardEmail.normalize(e.email);
      if (seenEmailNorms.contains(norm)) {
        continue;
      }
      seenEmailNorms.add(norm);
      mergedEmails.add(e);
    }

    // 6. WEBSITE
    String? chosenWebsite;
    if (frontData.website != null && frontData.website!.trim().isNotEmpty) {
      chosenWebsite = frontData.website;
      if (backData.website != null && backData.website!.trim().isNotEmpty) {
        final frontDomain = _normalizeDomain(frontData.website!);
        final backDomain = _normalizeDomain(backData.website!);
        if (frontDomain != backDomain) {
          alternativeCandidates['website'] = [backData.website!.trim()];
        }
      }
    } else if (backData.website != null &&
        backData.website!.trim().isNotEmpty) {
      chosenWebsite = backData.website;
    }

    // 7. ADDRESS
    // Back side legitimately contains the full office address.
    String? chosenAddress;
    if (frontData.address != null && backData.address != null) {
      final frontClean = frontData.address!.trim();
      final backClean = backData.address!.trim();
      final frontNorm = frontClean.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final backNorm = backClean.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      if (frontNorm == backNorm) {
        chosenAddress = frontClean;
      } else if (frontNorm.contains(backNorm)) {
        chosenAddress = frontClean;
        alternativeCandidates['address'] = [backClean];
      } else if (backNorm.contains(frontNorm)) {
        chosenAddress = backClean;
        alternativeCandidates['address'] = [frontClean];
      } else {
        // Complementary address lines on front & back: combine them seamlessly!
        chosenAddress = '$frontClean, $backClean';
        alternativeCandidates['address'] = [frontClean, backClean];
        parsingNotes.add('Merged complementary front and back address details');
      }
    } else {
      chosenAddress = frontData.address ?? backData.address;
    }

    final combinedRaw = '''
--- FRONT SIDE ---
${frontRawText.trim()}

--- BACK SIDE ---
${backRawText.trim()}
'''
        .trim();

    final mergedConfidenceStates = Map<String, String>.from(frontData.fieldConfidenceStates);
    backData.fieldConfidenceStates.forEach((k, v) {
      if (!mergedConfidenceStates.containsKey(k) || mergedConfidenceStates[k] == 'notDetected') {
        mergedConfidenceStates[k] = v;
      }
    });

    final mergedUnclassified = List<String>.from(frontData.unclassifiedLines);
    for (final u in backData.unclassifiedLines) {
      if (!mergedUnclassified.contains(u)) {
        mergedUnclassified.add(u);
      }
    }

    final mergedFieldEvidence = <String, FieldEvidence>{};
    mergedFieldEvidence.addAll(frontData.fieldEvidence);
    backData.fieldEvidence.forEach((k, v) {
      if (!mergedFieldEvidence.containsKey(k)) {
        mergedFieldEvidence[k] = v;
      } else {
        mergedFieldEvidence['back_$k'] = v;
      }
    });

    // Explicit alignment: Ensure the primary field evidence key points to the chosen candidate's evidence
    void alignEvidence(String key, String? chosenVal, String? frontVal, String? backVal) {
      if (chosenVal == null) return;
      final frontEv = frontData.fieldEvidence[key];
      final backEv = backData.fieldEvidence[key];

      if (chosenVal == backVal && backVal != frontVal && backEv != null) {
        mergedFieldEvidence[key] = backEv;
        if (frontEv != null) {
          mergedFieldEvidence['front_$key'] = frontEv;
        }
      } else if (chosenVal == frontVal && frontEv != null) {
        mergedFieldEvidence[key] = frontEv;
        if (backEv != null) {
          mergedFieldEvidence['back_$key'] = backEv;
        }
      }
    }

    alignEvidence('fullName', chosenName, frontData.fullName, backData.fullName);
    alignEvidence('company', chosenCompany, frontData.company, backData.company);
    alignEvidence('jobTitle', chosenJobTitle, frontData.jobTitle, backData.jobTitle);
    alignEvidence('website', chosenWebsite, frontData.website, backData.website);

    if (chosenAddress == backData.address &&
        frontData.address != null &&
        backData.fieldEvidence.containsKey('address')) {
      alignEvidence('address', chosenAddress, frontData.address, backData.address);
    } else if (chosenAddress != null &&
        frontData.address != null &&
        backData.address != null &&
        chosenAddress != frontData.address &&
        chosenAddress != backData.address) {
      final frontAddrEv = frontData.fieldEvidence['address'];
      final backAddrEv = backData.fieldEvidence['address'];
      final combinedObsIds = [
        ...?frontAddrEv?.sourceObservationIds,
        ...?backAddrEv?.sourceObservationIds,
      ];
      final combinedBoxes = [
        ...?frontAddrEv?.boundingBoxes,
        ...?backAddrEv?.boundingBoxes,
      ];
      mergedFieldEvidence['address'] = FieldEvidence(
        fieldName: 'address',
        originalOcrText:
            '${frontAddrEv?.originalOcrText ?? ''}\n${backAddrEv?.originalOcrText ?? ''}'.trim(),
        normalizedValue: chosenAddress,
        sourceEngine: frontAddrEv?.sourceEngine ?? backAddrEv?.sourceEngine ?? 'Hybrid Pipeline',
        sourceObservationIds: combinedObsIds,
        boundingBoxes: combinedBoxes,
        ocrConfidence:
            ((frontAddrEv?.ocrConfidence ?? 0.85) + (backAddrEv?.ocrConfidence ?? 0.85)) / 2.0,
        parserConfidence: 0.85,
        verificationStatus: FieldVerificationStatus.probable,
        side: CardSide.both,
      );
    }

    return BusinessCardData(
      fullName: chosenName,
      company: chosenCompany,
      jobTitle: chosenJobTitle,
      phoneNumbers: mergedPhones,
      emailAddresses: mergedEmails,
      website: chosenWebsite,
      address: chosenAddress,
      rawRecognizedText: combinedRaw,
      alternativeCandidates: alternativeCandidates,
      parsingNotes: parsingNotes,
      isDualSided: true,
      frontRawText: frontRawText,
      backRawText: backRawText,
      fieldConfidenceStates: mergedConfidenceStates,
      unclassifiedLines: mergedUnclassified,
      fieldEvidence: mergedFieldEvidence,
    );
  }

  // ---------------------------------------------------------------------------
  // INTERNAL LINE PARSING PIPELINE
  // ---------------------------------------------------------------------------
  BusinessCardData _parseLineList(
    List<String> rawLines,
    String rawText, {
    List<OcrLineMetadata>? sideMetadata,
    bool isFront = true,
  }) {
    final alternativeCandidates = <String, List<String>>{};
    final parsingNotes = <String>[];

    // 1. Extract Emails
    final emails = _extractEmails(rawLines, rawText);

    // 2. Extract Websites (ignoring domains embedded inside email addresses)
    final website = _extractWebsite(rawLines, emails);

    // 3. Extract Phone Numbers (conservative parsing)
    final phoneNumbers = _extractPhoneNumbers(rawLines);

    // 4. Pre-process lines: detect credentials, departments, slogans, certifications, labels
    final processedLines = <String>[];
    String? lineExtractedCredentials;
    final departmentLines = <int, String>{};
    final sloganLines = <int, String>{};
    final pureCredentialLines = <int, String>{};
    final certificationLines = <int, String>{};
    final credentialBoostIndices = <int>{};

    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i].trim();
      if (_isPureCredentialLine(line)) {
        pureCredentialLines[i] = line;
        processedLines.add(line);
        continue;
      }

      if (_isDepartmentLine(line)) {
        departmentLines[i] = line;
        processedLines.add(line);
        continue;
      }

      if (_isSlogan(line)) {
        sloganLines[i] = line;
        processedLines.add(line);
        continue;
      }

      if (RegExp(r'\b(?:iso(?:\s*[:\-\d]|\b)|iso\s*\d+(?::\d+)?|ce\s*\d+|gmp|nabh|nabl)\b', caseSensitive: false).hasMatch(line)) {
        certificationLines[i] = line;
        processedLines.add(line);
        continue;
      }

      final split = _extractNameAndCredentials(line);
      if (split.credentials != null) {
        lineExtractedCredentials = split.credentials;
        processedLines.add(split.name);
        credentialBoostIndices.add(i);
      } else {
        processedLines.add(line);
      }
    }

    // Save pre-extracted credentials non-destructively
    final allCreds = <String>[];
    if (lineExtractedCredentials != null && lineExtractedCredentials.isNotEmpty) {
      allCreds.add(lineExtractedCredentials);
    }
    for (final c in pureCredentialLines.values) {
      if (!allCreds.contains(c)) allCreds.add(c);
    }
    if (allCreds.isNotEmpty) {
      final credStr = allCreds.join(', ');
      alternativeCandidates['credentials'] = [credStr];
      parsingNotes.add('Credentials: $credStr');
    }

    // Save pre-extracted departments non-destructively
    if (departmentLines.isNotEmpty) {
      final deptStr = departmentLines.values.join(', ');
      alternativeCandidates['department'] = [deptStr];
      parsingNotes.add('Department/Specialty: $deptStr');
    }

    // Save pre-extracted slogans non-destructively
    if (sloganLines.isNotEmpty) {
      final sloganStr = sloganLines.values.join(' | ');
      alternativeCandidates['slogan'] = [sloganStr];
      parsingNotes.add('Tagline/Slogan: "$sloganStr"');
    }

    // Save pre-extracted certifications non-destructively
    if (certificationLines.isNotEmpty) {
      alternativeCandidates['certification'] = certificationLines.values.toList();
      final certStr = certificationLines.values.join(' | ');
      parsingNotes.add('Certifications: "$certStr"');
    }

    // 5. Initial Job Title / Designation Classification (across all professions)
    final initialJobTitleCandidate = _findBestJobTitleCandidate(
      processedLines,
      extractedPhones: phoneNumbers,
      extractedEmails: emails,
      website: website,
      departmentIndices: departmentLines.keys.toSet(),
      sloganIndices: sloganLines.keys.toSet(),
      credentialIndices: pureCredentialLines.keys.toSet(),
    );
    final initialJobTitleIndex = initialJobTitleCandidate?.lineIndex;

    // 6. Person Detection (anchored by Job Title adjacency if present)
    final initialPersonCandidates = _findAllPersonCandidates(
      processedLines,
      jobTitleIndex: initialJobTitleIndex,
      extractedPhones: phoneNumbers,
      extractedEmails: emails,
      website: website,
      departmentIndices: departmentLines.keys.toSet(),
      sloganIndices: sloganLines.keys.toSet(),
      credentialIndices: pureCredentialLines.keys.toSet(),
      credentialBoostIndices: credentialBoostIndices,
    );

    final initialPerson = _findBestPersonCandidate(
      processedLines,
      jobTitleIndex: initialJobTitleIndex,
      extractedPhones: phoneNumbers,
      extractedEmails: emails,
      website: website,
      departmentIndices: departmentLines.keys.toSet(),
      sloganIndices: sloganLines.keys.toSet(),
      credentialIndices: pureCredentialLines.keys.toSet(),
      credentialBoostIndices: credentialBoostIndices,
    );

    // 7. Company Detection (anchored by Person & Job Title context)
    final initialCompany = _findBestCompanyCandidate(
      processedLines,
      personIndex: initialPerson?.lineIndex,
      personName: initialPerson?.value,
      jobTitleIndex: initialJobTitleIndex,
      extractedPhones: phoneNumbers,
      extractedEmails: emails,
      website: website,
      departmentIndices: departmentLines.keys.toSet(),
      sloganIndices: sloganLines.keys.toSet(),
      credentialIndices: pureCredentialLines.keys.toSet(),
    );

    // 8. Refine Job Title using Person and Company context
    final refinedJobTitleCandidate = _findBestJobTitleCandidate(
      processedLines,
      personIndex: initialPerson?.lineIndex,
      personName: initialPerson?.value,
      companyIndex: initialCompany?.lineIndex,
      companyName: initialCompany?.value,
      extractedPhones: phoneNumbers,
      extractedEmails: emails,
      website: website,
      departmentIndices: departmentLines.keys.toSet(),
      sloganIndices: sloganLines.keys.toSet(),
      credentialIndices: pureCredentialLines.keys.toSet(),
    );

    final jobTitleCandidate = (refinedJobTitleCandidate != null &&
            (initialJobTitleCandidate == null ||
                refinedJobTitleCandidate.classificationScore >= initialJobTitleCandidate.classificationScore))
        ? refinedJobTitleCandidate
        : initialJobTitleCandidate;

    final chosenJobTitle = jobTitleCandidate?.value;
    final jobTitleIndex = jobTitleCandidate?.lineIndex;

    // Refine Person Name using finalized Job Title and Company context
    _ScoredCandidate? finalPerson = initialPerson;
    List<_ScoredCandidate> finalPersonCandidates = initialPersonCandidates;

    if (jobTitleIndex != null && jobTitleIndex != initialJobTitleIndex) {
      final refinedCandidates = _findAllPersonCandidates(
        processedLines,
        jobTitleIndex: jobTitleIndex,
        companyIndex: initialCompany?.lineIndex,
        extractedPhones: phoneNumbers,
        extractedEmails: emails,
        website: website,
        departmentIndices: departmentLines.keys.toSet(),
        sloganIndices: sloganLines.keys.toSet(),
        credentialIndices: pureCredentialLines.keys.toSet(),
        credentialBoostIndices: credentialBoostIndices,
      );
      if (refinedCandidates.isNotEmpty) {
        finalPersonCandidates = refinedCandidates;
        final refinedPerson = refinedCandidates.first.classificationScore >= 35 ? refinedCandidates.first : null;
        if (refinedPerson != null &&
            (finalPerson == null ||
                refinedPerson.classificationScore >= finalPerson.classificationScore ||
                refinedPerson.lineIndex == jobTitleIndex - 1)) {
          finalPerson = refinedPerson;
        }
      }
    }

    final chosenFullName = (finalPerson != null && finalPerson.classificationScore >= 35)
        ? finalPerson.value
        : '';
    final personIndex = (chosenFullName.isNotEmpty) ? finalPerson?.lineIndex : null;

    // Detect competing person name candidates
    bool isCompetingPersonName = false;
    if (finalPersonCandidates.length >= 2) {
      final c1 = finalPersonCandidates[0];
      final c2 = finalPersonCandidates[1];
      if (c1.classificationScore >= 30 && c2.classificationScore >= 20) {
        final competingList = finalPersonCandidates
            .where((c) => c.classificationScore >= 20)
            .map((c) => c.value)
            .toSet()
            .toList();
        if (competingList.length > 1) {
          alternativeCandidates['fullName'] = competingList;
          if ((c1.classificationScore - c2.classificationScore) <= 40) {
            isCompetingPersonName = true;
            parsingNotes.add('Competing person name candidates detected: "${c1.value}" vs "${c2.value}"');
          }
        }
      }
    }

    // Refine Company using finalized Job Title & Person context
    _ScoredCandidate? finalCompany = initialCompany;
    final refinedCompany = _findBestCompanyCandidate(
      processedLines,
      personIndex: personIndex,
      personName: chosenFullName,
      jobTitleIndex: jobTitleIndex,
      extractedPhones: phoneNumbers,
      extractedEmails: emails,
      website: website,
      departmentIndices: departmentLines.keys.toSet(),
      sloganIndices: sloganLines.keys.toSet(),
      credentialIndices: pureCredentialLines.keys.toSet(),
    );
    if (refinedCompany != null &&
        (finalCompany == null ||
            refinedCompany.classificationScore >= finalCompany.classificationScore ||
            (personIndex != null && finalCompany.lineIndex == personIndex) ||
            (jobTitleIndex != null && finalCompany.lineIndex == jobTitleIndex))) {
      finalCompany = refinedCompany;
    }
    final chosenCompany = finalCompany?.value;

    // 9. Extract Address
    final address = _extractAddress(
      rawLines,
      extractedPhones: phoneNumbers,
      extractedEmails: emails,
      website: website,
      name: chosenFullName,
      company: chosenCompany,
      jobTitle: chosenJobTitle,
    );

    // 10. Record Brand, Certifications & Unclassified Lines non-destructively
    final claimedIndices = <int>{};
    if (personIndex != null) claimedIndices.add(personIndex);
    if (finalCompany?.lineIndex != null) claimedIndices.add(finalCompany!.lineIndex);
    if (jobTitleIndex != null) claimedIndices.add(jobTitleIndex);
    claimedIndices.addAll(departmentLines.keys);
    claimedIndices.addAll(sloganLines.keys);
    claimedIndices.addAll(pureCredentialLines.keys);
    claimedIndices.addAll(certificationLines.keys);

    // Detect distinct brand marks (e.g. "ASTER", "MEDITECH") distinct from the legal company name
    for (int i = 0; i < rawLines.length; i++) {
      if (claimedIndices.contains(i)) continue;
      final line = rawLines[i].trim();
      if (line.isEmpty) continue;
      final words = line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.length == 1 &&
          RegExp(r'^[A-Za-z]{3,20}$').hasMatch(line) &&
          !line.toUpperCase().startsWith('ISO') &&
          !line.toUpperCase().startsWith('CE') &&
          !_isAddressLine(line) &&
          !_isNonPhoneLine(line)) {
        final existingBrands = alternativeCandidates['brand'] ?? [];
        if (!existingBrands.contains(line)) {
          existingBrands.add(line);
          alternativeCandidates['brand'] = existingBrands;
          parsingNotes.add('Brand / Trademark: "$line"');
          claimedIndices.add(i);
        }
      }
    }

    final unclassifiedLines = <String>[];
    for (int i = 0; i < rawLines.length; i++) {
      if (claimedIndices.contains(i)) continue;
      final line = rawLines[i].trim();
      if (line.isEmpty) continue;
      if (_emailRegExp.hasMatch(line) || emails.any((e) => line.contains(e.email))) continue;
      if (_urlSchemeOrWwwRegExp.hasMatch(line) || (website != null && line.contains(website))) continue;
      if (phoneNumbers.any((p) => line.contains(p.number))) continue;
      if (_isAddressLine(line)) continue;
      if (_isNonPhoneLine(line)) {
        // e.g. PIN, GSTIN, CIN, Invoice lines
        continue;
      }
      unclassifiedLines.add(line);
    }

    if (unclassifiedLines.isNotEmpty) {
      alternativeCandidates['unclassified'] = unclassifiedLines;
      for (final u in unclassifiedLines) {
        parsingNotes.add('Unclassified text: "$u"');
      }
    }

    final fieldConfidenceStates = <String, String>{
      'fullName': chosenFullName.isNotEmpty
          ? (!isCompetingPersonName && finalPerson != null && finalPerson.classificationScore >= 45 ? 'highConfidence' : 'uncertain')
          : 'notDetected',
      'jobTitle': (chosenJobTitle != null && chosenJobTitle.isNotEmpty)
          ? (jobTitleCandidate != null && jobTitleCandidate.classificationScore >= 20 ? 'highConfidence' : 'uncertain')
          : 'notDetected',
      'company': (chosenCompany != null && chosenCompany.isNotEmpty)
          ? (finalCompany != null && finalCompany.classificationScore >= 25 ? 'highConfidence' : 'uncertain')
          : 'notDetected',
      'phone': phoneNumbers.isNotEmpty
          ? (phoneNumbers.every((p) => p.number.replaceAll(RegExp(r'\D'), '').length >= 7) ? 'highConfidence' : 'uncertain')
          : 'notDetected',
      'email': emails.isNotEmpty
          ? (emails.every((e) => EmailOcrRecovery.isValidEmail(e.email)) ? 'highConfidence' : 'uncertain')
          : 'notDetected',
      'website': website != null && website.isNotEmpty
          ? ((_urlSchemeOrWwwRegExp.hasMatch(website) || _domainRegExp.hasMatch(website)) ? 'highConfidence' : 'uncertain')
          : 'notDetected',
      'address': address != null && address.isNotEmpty
          ? (address.length >= 10 && FieldSemanticEvaluator.computeTextQualityScore(address) >= 0.70 ? 'highConfidence' : 'uncertain')
          : 'notDetected',
    };

    final fieldEvidence = <String, FieldEvidence>{};
    final currentSide = isFront ? CardSide.front : CardSide.back;
    final sidePrefix = isFront ? 'front' : 'back';
    final defaultEngine = (sideMetadata != null && sideMetadata.isNotEmpty)
        ? 'PaddleOCR / ML Kit'
        : 'PaddleOCR (PP-OCRv5 Mobile)';

    // Full Name Evidence
    if (chosenFullName.isNotEmpty && personIndex != null && personIndex < rawLines.length) {
      final obsId = '${sidePrefix}_$personIndex';
      final box = (sideMetadata != null && personIndex < sideMetadata.length)
          ? sideMetadata[personIndex].boundingBox
          : Rect.zero;
      final ocrConf = (sideMetadata != null && personIndex < sideMetadata.length)
          ? (sideMetadata[personIndex].confidence ?? 0.90)
          : 0.90;
      final parserConf = ((finalPerson?.classificationScore ?? 50) / 100.0).clamp(0.0, 1.0);
      final isAmbiguous = isCompetingPersonName || fieldConfidenceStates['fullName'] == 'uncertain';

      fieldEvidence['fullName'] = FieldEvidence(
        fieldName: 'fullName',
        originalOcrText: rawLines[personIndex],
        normalizedValue: chosenFullName,
        sourceEngine: defaultEngine,
        sourceObservationIds: [obsId],
        boundingBoxes: box != Rect.zero ? [box] : const [],
        ocrConfidence: ocrConf,
        parserConfidence: parserConf,
        verificationStatus: (!isAmbiguous && parserConf >= 0.70 && ocrConf >= 0.70)
            ? FieldVerificationStatus.probable
            : FieldVerificationStatus.reviewRequired,
        uncertaintyReason: isAmbiguous ? 'Multiple competing candidates or layout ambiguity for person name' : null,
        side: currentSide,
      );
    } else {
      fieldEvidence['fullName'] = FieldEvidence.notFound('fullName', side: currentSide);
    }

    // Company Evidence
    if (chosenCompany != null &&
        chosenCompany.isNotEmpty &&
        finalCompany != null &&
        finalCompany.lineIndex < rawLines.length) {
      final idx = finalCompany.lineIndex;
      final obsId = '${sidePrefix}_$idx';
      final box = (sideMetadata != null && idx < sideMetadata.length)
          ? sideMetadata[idx].boundingBox
          : Rect.zero;
      final ocrConf = (sideMetadata != null && idx < sideMetadata.length)
          ? (sideMetadata[idx].confidence ?? 0.90)
          : 0.90;
      final parserConf = (finalCompany.classificationScore / 100.0).clamp(0.0, 1.0);
      fieldEvidence['company'] = FieldEvidence(
        fieldName: 'company',
        originalOcrText: rawLines[idx],
        normalizedValue: chosenCompany,
        sourceEngine: defaultEngine,
        sourceObservationIds: [obsId],
        boundingBoxes: box != Rect.zero ? [box] : const [],
        ocrConfidence: ocrConf,
        parserConfidence: parserConf,
        verificationStatus: (parserConf >= 0.70 && ocrConf >= 0.70)
            ? FieldVerificationStatus.probable
            : FieldVerificationStatus.reviewRequired,
        side: currentSide,
      );
    }

    // Job Title Evidence
    if (chosenJobTitle != null &&
        chosenJobTitle.isNotEmpty &&
        jobTitleCandidate != null &&
        jobTitleCandidate.lineIndex < rawLines.length) {
      final idx = jobTitleCandidate.lineIndex;
      final obsId = '${sidePrefix}_$idx';
      final box = (sideMetadata != null && idx < sideMetadata.length)
          ? sideMetadata[idx].boundingBox
          : Rect.zero;
      final ocrConf = (sideMetadata != null && idx < sideMetadata.length)
          ? (sideMetadata[idx].confidence ?? 0.90)
          : 0.90;
      final parserConf = (jobTitleCandidate.classificationScore / 100.0).clamp(0.0, 1.0);
      fieldEvidence['jobTitle'] = FieldEvidence(
        fieldName: 'jobTitle',
        originalOcrText: rawLines[idx],
        normalizedValue: chosenJobTitle,
        sourceEngine: defaultEngine,
        sourceObservationIds: [obsId],
        boundingBoxes: box != Rect.zero ? [box] : const [],
        ocrConfidence: ocrConf,
        parserConfidence: parserConf,
        verificationStatus: (parserConf >= 0.60 && ocrConf >= 0.70)
            ? FieldVerificationStatus.probable
            : FieldVerificationStatus.reviewRequired,
        side: currentSide,
      );
    }

    // Phone Numbers Evidence
    if (phoneNumbers.isNotEmpty) {
      final phoneObsIds = <String>[];
      final phoneBoxes = <Rect>[];
      final origTexts = <String>[];
      double sumConf = 0.0;
      for (int i = 0; i < rawLines.length; i++) {
        final l = rawLines[i];
        if (phoneNumbers.any((p) =>
            l.contains(p.number) ||
            BusinessCardPhone.normalize(l).contains(BusinessCardPhone.normalize(p.number)))) {
          phoneObsIds.add('${sidePrefix}_$i');
          origTexts.add(l);
          if (sideMetadata != null && i < sideMetadata.length) {
            if (sideMetadata[i].boundingBox != Rect.zero) phoneBoxes.add(sideMetadata[i].boundingBox);
            sumConf += (sideMetadata[i].confidence ?? 0.90);
          } else {
            sumConf += 0.90;
          }
        }
      }
      fieldEvidence['phone'] = FieldEvidence(
        fieldName: 'phone',
        originalOcrText: origTexts.isNotEmpty
            ? origTexts.join(' / ')
            : phoneNumbers.map((p) => p.number).join(', '),
        normalizedValue: phoneNumbers.map((p) => p.number).join(', '),
        sourceEngine: defaultEngine,
        sourceObservationIds: phoneObsIds,
        boundingBoxes: phoneBoxes,
        ocrConfidence:
            phoneObsIds.isNotEmpty ? (sumConf / phoneObsIds.length).clamp(0.0, 1.0) : 0.90,
        parserConfidence: 0.90,
        verificationStatus: FieldVerificationStatus.probable,
        side: currentSide,
      );
    }

    // Email Addresses Evidence
    if (emails.isNotEmpty) {
      final emailObsIds = <String>[];
      final emailBoxes = <Rect>[];
      final origTexts = <String>[];
      double sumConf = 0.0;
      for (int i = 0; i < rawLines.length; i++) {
        final l = rawLines[i];
        if (emails.any((e) => l.toLowerCase().contains(e.email.toLowerCase()))) {
          emailObsIds.add('${sidePrefix}_$i');
          origTexts.add(l);
          if (sideMetadata != null && i < sideMetadata.length) {
            if (sideMetadata[i].boundingBox != Rect.zero) emailBoxes.add(sideMetadata[i].boundingBox);
            sumConf += (sideMetadata[i].confidence ?? 0.90);
          } else {
            sumConf += 0.90;
          }
        }
      }
      fieldEvidence['email'] = FieldEvidence(
        fieldName: 'email',
        originalOcrText: origTexts.isNotEmpty
            ? origTexts.join(' / ')
            : emails.map((e) => e.email).join(', '),
        normalizedValue: emails.map((e) => e.email).join(', '),
        sourceEngine: defaultEngine,
        sourceObservationIds: emailObsIds,
        boundingBoxes: emailBoxes,
        ocrConfidence:
            emailObsIds.isNotEmpty ? (sumConf / emailObsIds.length).clamp(0.0, 1.0) : 0.90,
        parserConfidence: 0.95,
        verificationStatus: FieldVerificationStatus.probable,
        side: currentSide,
      );
    }

    // Website Evidence
    if (website != null && website.isNotEmpty) {
      final wIdx = rawLines.indexWhere((l) => l.toLowerCase().contains(website.toLowerCase()));
      final obsId = wIdx >= 0 ? '${sidePrefix}_$wIdx' : null;
      final box = (wIdx >= 0 && sideMetadata != null && wIdx < sideMetadata.length)
          ? sideMetadata[wIdx].boundingBox
          : Rect.zero;
      final ocrConf = (wIdx >= 0 && sideMetadata != null && wIdx < sideMetadata.length)
          ? (sideMetadata[wIdx].confidence ?? 0.90)
          : 0.90;
      fieldEvidence['website'] = FieldEvidence(
        fieldName: 'website',
        originalOcrText: wIdx >= 0 ? rawLines[wIdx] : website,
        normalizedValue: website,
        sourceEngine: defaultEngine,
        sourceObservationIds: obsId != null ? [obsId] : const [],
        boundingBoxes: box != Rect.zero ? [box] : const [],
        ocrConfidence: ocrConf,
        parserConfidence: 0.90,
        verificationStatus: FieldVerificationStatus.probable,
        side: currentSide,
      );
    }

    // Address Evidence (Supports multiple contributing observations!)
    if (address != null && address.isNotEmpty) {
      final addrObsIds = <String>[];
      final addrBoxes = <Rect>[];
      final origLines = <String>[];
      double sumConf = 0.0;
      for (int i = 0; i < rawLines.length; i++) {
        final l = rawLines[i].trim();
        if (l.isNotEmpty && address.contains(l)) {
          addrObsIds.add('${sidePrefix}_$i');
          origLines.add(l);
          if (sideMetadata != null && i < sideMetadata.length) {
            if (sideMetadata[i].boundingBox != Rect.zero) addrBoxes.add(sideMetadata[i].boundingBox);
            sumConf += (sideMetadata[i].confidence ?? 0.85);
          } else {
            sumConf += 0.85;
          }
        }
      }
      fieldEvidence['address'] = FieldEvidence(
        fieldName: 'address',
        originalOcrText: origLines.isNotEmpty ? origLines.join(', ') : address,
        normalizedValue: address,
        sourceEngine: defaultEngine,
        sourceObservationIds: addrObsIds,
        boundingBoxes: addrBoxes,
        ocrConfidence:
            addrObsIds.isNotEmpty ? (sumConf / addrObsIds.length).clamp(0.0, 1.0) : 0.85,
        parserConfidence: 0.85,
        verificationStatus: FieldVerificationStatus.probable,
        side: currentSide,
      );
    }

    return BusinessCardData(
      fullName: chosenFullName,
      company: chosenCompany,
      jobTitle: chosenJobTitle,
      phoneNumbers: phoneNumbers,
      emailAddresses: emails,
      website: website,
      address: address,
      rawRecognizedText: rawText,
      frontRawText: isFront ? rawText : null,
      backRawText: !isFront ? rawText : null,
      alternativeCandidates: alternativeCandidates,
      parsingNotes: parsingNotes,
      fieldConfidenceStates: fieldConfidenceStates,
      unclassifiedLines: unclassifiedLines,
      fieldEvidence: fieldEvidence,
    );
  }

  /// Uses bounding-box spatial geometry to reconstruct multi-column or vertical order.
  List<String> _getSpatiallyOrderedLines(OcrSideResult sideResult) {
    if (sideResult.lines.isEmpty) {
      return sideResult.rawText
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    }

    final validLines = sideResult.lines
        .where((l) =>
            l.boundingBox.width > 0 &&
            l.boundingBox.height > 0 &&
            l.text.trim().isNotEmpty)
        .toList();

    if (validLines.length < 2) {
      return sideResult.rawText
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    }

    final minLeft =
        validLines.map((l) => l.boundingBox.left).reduce((a, b) => min(a, b));
    final maxRight =
        validLines.map((l) => l.boundingBox.right).reduce((a, b) => max(a, b));
    final cardWidth = maxRight - minLeft;

    // Relative multi-column layout detection using normalized coordinate percentages:
    if (cardWidth > 50) {
      final midX = minLeft + (cardWidth * 0.5);
      final gutterTolerance = cardWidth * 0.08;
      final leftCol =
          validLines.where((l) => l.boundingBox.right <= midX + gutterTolerance).toList();
      final rightCol =
          validLines.where((l) => l.boundingBox.left >= midX - gutterTolerance).toList();

      if (leftCol.length >= 2 &&
          rightCol.length >= 2 &&
          (leftCol.length + rightCol.length) >= (validLines.length * 0.75)) {
        leftCol.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
        rightCol.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

        final ordered = <String>[];
        for (final l in leftCol) {
          final t = l.text.trim();
          if (t.isNotEmpty) ordered.add(t);
        }
        for (final l in rightCol) {
          final t = l.text.trim();
          if (t.isNotEmpty) ordered.add(t);
        }
        return ordered;
      }
    }

    // Default spatial sorting: top-to-bottom, grouping lines on approximately the same Y plane dynamically
    final avgHeight = validLines.map((l) => l.boundingBox.height).reduce((a, b) => a + b) / validLines.length;
    final yTolerance = (avgHeight * 0.45).clamp(6.0, 16.0);
    final sorted = List<OcrLineMetadata>.from(validLines);
    sorted.sort((a, b) {
      final yDiff = (a.boundingBox.top - b.boundingBox.top).abs();
      if (yDiff < yTolerance) {
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      }
      return a.boundingBox.top.compareTo(b.boundingBox.top);
    });

    return sorted.map((l) => l.text.trim()).where((t) => t.isNotEmpty).toList();
  }

  String _normalizeDomain(String url) {
    var s = url.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'^https?:\/\/'), '');
    s = s.replaceAll(RegExp(r'^www\.'), '');
    s = s.replaceAll(RegExp(r'\/+$'), '');
    return s;
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

    // Priority 1: High-precision EmailOcrRecovery engine
    final recovered = EmailOcrRecovery.extractEmailCandidates(lines);
    for (final cand in recovered) {
      if (seenNormalized.contains(cand.normalized)) continue;
      seenNormalized.add(cand.normalized);
      results.add(cand.toBusinessCardEmail());
    }

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

    // 4. Raw text fallback
    _collectEmailCandidatesFromText(
      rawText,
      results: results,
      seenNormalized: seenNormalized,
      candidateLogs: candidateLogs,
      contextLine: rawText,
    );

    return _suppressBusinessCardEmailFragments(results);
  }

  List<BusinessCardEmail> _suppressBusinessCardEmailFragments(List<BusinessCardEmail> emails) {
    if (emails.length <= 1) return emails;
    final filtered = <BusinessCardEmail>[];
    for (int i = 0; i < emails.length; i++) {
      final cand = emails[i];
      final candNorm = (cand.normalizedEmail ?? cand.email).trim().toLowerCase();
      final parts = candNorm.split('@');
      if (parts.length != 2) {
        filtered.add(cand);
        continue;
      }
      final local = parts[0];
      final domain = parts[1];
      bool isSubsumed = false;
      for (int j = 0; j < emails.length; j++) {
        if (i == j) continue;
        final other = emails[j];
        final otherNorm = (other.normalizedEmail ?? other.email).trim().toLowerCase();
        final otherParts = otherNorm.split('@');
        if (otherParts.length != 2) continue;
        final otherLocal = otherParts[0];
        final otherDomain = otherParts[1];
        if (domain != otherDomain || local == otherLocal) continue;

        if (otherLocal.endsWith(local) && otherLocal.length > local.length) {
          isSubsumed = true;
          break;
        }
        if (RegExp(r'^\d+$').hasMatch(local) && otherLocal.contains(local) && otherLocal.length > local.length) {
          isSubsumed = true;
          break;
        }
        final strippedLocal = local.replaceAll(RegExp(r'^[a-zA-Z_.-]'), '');
        if (strippedLocal.isNotEmpty &&
            strippedLocal.length >= 3 &&
            otherLocal.endsWith(strippedLocal) &&
            otherLocal.length > local.length) {
          isSubsumed = true;
          break;
        }
        if (otherLocal.contains(local) && local.length <= 5 && otherLocal.length > local.length) {
          isSubsumed = true;
          break;
        }
      }
      if (!isSubsumed) {
        filtered.add(cand);
      }
    }
    return filtered;
  }

  void _collectEmailCandidatesFromText(
    String text, {
    required List<BusinessCardEmail> results,
    required Set<String> seenNormalized,
    required List<String> candidateLogs,
    required String contextLine,
    String? precedingLine,
  }) {
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

  String _cleanEmailCandidate(String candidate) {
    var s = candidate.trim();

    s = s.replaceAll(
      RegExp(r'\s*(?:\(at\)|\[at\]|[©®])\s*', caseSensitive: false),
      '@',
    );

    s = s.replaceAll(RegExp(r'''^[\s<>()\[\]{}:;,.`|•✉\-_"']+'''), '');
    s = s.replaceAll(RegExp(r'''[\s<>()\[\]{}:;,.`|•✉\-_"']+$'''), '');

    s = s.replaceAllMapped(
      RegExp(r'\s*([@._%+-])\s*'),
      (m) => m.group(1)!,
    );

    if (s.contains('@')) {
      final atIndex = s.indexOf('@');
      final local = s.substring(0, atIndex).replaceAll(RegExp(r'\s+'), '');
      var domain = s.substring(atIndex + 1).replaceAll(RegExp(r'\s+'), '');
      domain = domain.replaceAll(',', '.');
      s = '$local@$domain';
    }

    s = s.replaceAll(RegExp(r'[\.,;:!\-]+$'), '');

    return s.trim();
  }

  bool _isValidEmail(String email) {
    if (email.isEmpty || email.length > 254) return false;
    if (email.contains(RegExp(r'\s'))) return false;

    final lower = email.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('www.')) {
      return false;
    }

    final parts = email.split('@');
    if (parts.length != 2) return false;

    final localPart = parts[0];
    final domainPart = parts[1];

    if (localPart.isEmpty || localPart.length > 64) return false;
    if (localPart.startsWith('.') || localPart.endsWith('.')) return false;
    if (localPart.contains('..')) return false;
    if (!RegExp(r'^[a-zA-Z0-9._%+-]+$').hasMatch(localPart)) return false;

    if (domainPart.isEmpty || domainPart.length > 253) return false;
    if (domainPart.startsWith('.') || domainPart.endsWith('.')) return false;
    if (domainPart.startsWith('-') || domainPart.endsWith('-')) return false;
    if (domainPart.contains('..')) return false;

    final domainLabels = domainPart.split('.');
    if (domainLabels.length < 2) return false;

    for (int i = 0; i < domainLabels.length; i++) {
      final label = domainLabels[i];
      if (label.isEmpty || label.length > 63) return false;

      if (i == domainLabels.length - 1) {
        if (!RegExp(r'^[a-zA-Z]{2,}$').hasMatch(label)) return false;
      } else {
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

      // 3. Standalone domain like "abc.com" or "medindia.net", ensuring it's not purely an email domain
      final domainMatches = _domainRegExp.allMatches(line);
      for (final match in domainMatches) {
        final domainStr = match.group(1)!;

        // Disallow public email domains (e.g. gmail.com) as websites unless starting with www.
        if (_publicEmailDomains.contains(domainStr.toLowerCase())) {
          continue;
        }

        final isEmailDomainOnly = emails.any((e) {
          final parts = e.email.split('@');
          if (parts.length != 2) return false;
          final domainMatch =
              parts[1].toLowerCase() == domainStr.toLowerCase();
          if (!domainMatch) return false;
          return line.contains(e.email) ||
              (line.contains('@') &&
                  line.toLowerCase().contains(parts[1].toLowerCase()));
        });

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
    final candidates = PhoneOcrRecovery.extractPhoneCandidates(lines);
    return candidates.map((c) => c.toBusinessCardPhone()).toList();
  }

  bool _isNonPhoneLine(String line) {
    final upper = line.toUpperCase();
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
        upper.contains('INVOICE') ||
        upper.contains('DATE') ||
        upper.contains('ESTD')) {
      if (!upper.contains('MOBILE') &&
          !upper.contains('MOB:') &&
          !upper.contains('TEL:') &&
          !upper.contains('PHONE:') &&
          !upper.contains('OFFICE:')) {
        return true;
      }
    }

    // Ignore standalone 5 or 6 digit postal codes (e.g. 600028 or 90210)
    if (RegExp(r'^\s*(?:PIN\s*:?)?\s*\d{5,6}\s*$', caseSensitive: false)
        .hasMatch(line)) {
      return true;
    }

    // Ignore standard date formats (e.g. 2024-10-15, 15/10/2024)
    if (RegExp(r'^\s*(?:\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4})\s*$')
        .hasMatch(line)) {
      return true;
    }

    // Ignore tenure year ranges (e.g. 2025-2027) without phone labels
    if (RegExp(r'\b(?:19|20)\d{2}\s*[-–/]\s*(?:(?:19|20)\d{2}|\d{2})\b').hasMatch(line) &&
        !upper.contains('MOBILE') &&
        !upper.contains('MOB:') &&
        !upper.contains('TEL:') &&
        !upper.contains('PHONE:') &&
        !upper.contains('OFFICE:')) {
      return true;
    }

    return false;
  }


  bool _isDuplicatePhone(String norm, String digits, Set<String> seen) {
    if (seen.contains(norm) || (digits.isNotEmpty && seen.contains(digits))) {
      return true;
    }

    for (final s in seen) {
      if (PhoneOcrRecovery.areEquivalentPhones(norm, s)) {
        return true;
      }
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // CONTEXTUAL CLASSIFICATION & EXTRACTION HELPERS
  // ---------------------------------------------------------------------------

  List<_ScoredCandidate> _findAllPersonCandidates(
    List<String> lines, {
    int? jobTitleIndex,
    int? companyIndex,
    required List<BusinessCardPhone> extractedPhones,
    required List<BusinessCardEmail> extractedEmails,
    String? website,
    required Set<int> departmentIndices,
    required Set<int> sloganIndices,
    required Set<int> credentialIndices,
    Set<int>? credentialBoostIndices,
  }) {
    final candidates = <_ScoredCandidate>[];

    // 1. Explicit name label e.g. "Name: Rahul Kumar"
    for (int i = 0; i < lines.length; i++) {
      if (departmentIndices.contains(i) ||
          sloganIndices.contains(i) ||
          credentialIndices.contains(i)) {
        continue;
      }
      final line = lines[i];
      final labelMatch = RegExp(
        r'^name\s*[:\-]\s*([a-zA-Z\s\.\-]+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (labelMatch != null) {
        final val = labelMatch.group(1)!.trim();
        if (val.isNotEmpty) {
          candidates.add(_ScoredCandidate(val, i, 100));
        }
      }
    }

    if (candidates.isNotEmpty) {
      return candidates;
    }

    // 2. Score candidate lines
    for (int i = 0; i < lines.length; i++) {
      if (i == jobTitleIndex ||
          i == companyIndex ||
          departmentIndices.contains(i) ||
          sloganIndices.contains(i) ||
          credentialIndices.contains(i)) {
        continue;
      }

      final line = lines[i];
      final score = _evaluatePersonScore(
        line,
        lineIndex: i,
        jobTitleIndex: jobTitleIndex,
        companyIndex: companyIndex,
        totalLines: lines.length,
        extractedPhones: extractedPhones,
        extractedEmails: extractedEmails,
        website: website,
        hasAttachedCredentials: credentialBoostIndices?.contains(i) ?? false,
      );

      if (score >= 20) {
        candidates.add(_ScoredCandidate(_cleanNameCandidate(line), i, score));
      }
    }

    candidates.sort((a, b) => b.classificationScore.compareTo(a.classificationScore));
    return candidates;
  }

  _ScoredCandidate? _findBestPersonCandidate(
    List<String> lines, {
    int? jobTitleIndex,
    int? companyIndex,
    required List<BusinessCardPhone> extractedPhones,
    required List<BusinessCardEmail> extractedEmails,
    String? website,
    required Set<int> departmentIndices,
    required Set<int> sloganIndices,
    required Set<int> credentialIndices,
    Set<int>? credentialBoostIndices,
  }) {
    final all = _findAllPersonCandidates(
      lines,
      jobTitleIndex: jobTitleIndex,
      companyIndex: companyIndex,
      extractedPhones: extractedPhones,
      extractedEmails: extractedEmails,
      website: website,
      departmentIndices: departmentIndices,
      sloganIndices: sloganIndices,
      credentialIndices: credentialIndices,
      credentialBoostIndices: credentialBoostIndices,
    );
    if (all.isEmpty) return null;
    final best = all.first;
    return best.classificationScore >= 35 ? best : null;
  }

  _ScoredCandidate? _findBestCompanyCandidate(
    List<String> lines, {
    int? personIndex,
    String? personName,
    int? jobTitleIndex,
    required List<BusinessCardPhone> extractedPhones,
    required List<BusinessCardEmail> extractedEmails,
    String? website,
    required Set<int> departmentIndices,
    required Set<int> sloganIndices,
    required Set<int> credentialIndices,
  }) {
    // 1. Explicit company label
    for (int i = 0; i < lines.length; i++) {
      if (i == personIndex ||
          i == jobTitleIndex ||
          departmentIndices.contains(i) ||
          sloganIndices.contains(i) ||
          credentialIndices.contains(i)) {
        continue;
      }
      final line = lines[i];
      final labelMatch = RegExp(
        r'^(?:company|organization|org)\s*[:\-]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (labelMatch != null) {
        final val = labelMatch.group(1)!.trim().replaceAll(RegExp(r'[,;\s]+$'), '').trim();
        if (val.isNotEmpty) {
          return _ScoredCandidate(val, i, 100);
        }
      }
    }

    // 2. Score candidate lines (including adjacent multi-line pairs)
    _ScoredCandidate? best;

    // Check adjacent pairs first (e.g. "CHANDRU" + "MEDICAL EQUIPMENTS" or "UNITED" + "EDUCATIONAL INSTITUTIONS")
    for (int i = 0; i < lines.length - 1; i++) {
      if (departmentIndices.contains(i) ||
          departmentIndices.contains(i + 1) ||
          sloganIndices.contains(i) ||
          sloganIndices.contains(i + 1) ||
          credentialIndices.contains(i) ||
          credentialIndices.contains(i + 1)) {
        continue;
      }
      final line1 = lines[i].trim();
      final line2 = lines[i + 1].trim();

      // Guard: Line 1 must NOT already be a complete corporate entity with legal suffix
      if (RegExp(r'\b(ltd\.?|limited|pvt\.?|private|llc|llp|inc\.?|corp\.?|corporation|gmbh)\b', caseSensitive: false).hasMatch(line1)) {
        continue;
      }
      // Guard: Honorific lines (e.g. Dr., Prof., Mr.) must never be treated as company prefixes
      if (_honorificPrefixRegExp.hasMatch(line1) || _honorificPrefixRegExp.hasMatch(line2)) {
        continue;
      }
      // Guard: Line 2 must not be an address, phone, email, or person name
      if (_isAddressLine(line2) || _emailRegExp.hasMatch(line2) || line2.contains('@')) {
        continue;
      }

      // Guard: Neither line may be a job title or designation
      if (jobTitleIndex != null && (i == jobTitleIndex || i + 1 == jobTitleIndex)) {
        continue;
      }
      if (_jobTitleKeywords.any((kw) => RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false).hasMatch(line1)) ||
          _jobTitleKeywords.any((kw) => RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false).hasMatch(line2))) {
        continue;
      }

      if (personIndex != null && i == personIndex) continue;
      if (personName != null && (line1.toLowerCase() == personName.toLowerCase() || personName.toLowerCase().contains(line1.toLowerCase()))) {
        continue;
      }
      final words1 = line1.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words1.length >= 2 && !words1.any((w) => _companyKeywords.contains(w.toLowerCase()))) {
        continue;
      }

      // Check if line 1 is an entity prefix and line 2 provides category/suffix
      final line1HasCatOrSuffix = RegExp(r'\b(ltd|pvt|limited|technologies|solutions|services|institutions?|educational?|enterprises|industries|systems|laboratories)\b', caseSensitive: false).hasMatch(line1);
      final line2HasCatOrSuffix = RegExp(r'\b(equipments?|medical|technologies|technology|solutions|services|enterprises|institutions?|educational?|industries|systems|laboratories|holdings|corporation|associates|partners|hospital|clinic|university|college|school|institute|academy|bank|ltd|pvt|limited|llc|inc)\b', caseSensitive: false).hasMatch(line2);

      final words2 = line2.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words2.length >= 3 && line2HasCatOrSuffix) continue;

      if (!line1HasCatOrSuffix && line2HasCatOrSuffix) {
        final pair = '$line1 $line2';
        final pairScore = _evaluateCompanyScore(
          pair,
          lineIndex: i,
          personIndex: personIndex,
          jobTitleIndex: jobTitleIndex,
          totalLines: lines.length,
          extractedPhones: extractedPhones,
          extractedEmails: extractedEmails,
          website: website,
        );
        if (pairScore >= 25 && (best == null || pairScore + 15 > best.classificationScore)) {
          best = _ScoredCandidate(pair, i, pairScore + 20);
        }
      }
    }

    for (int i = 0; i < lines.length; i++) {
      if (i == personIndex ||
          i == jobTitleIndex ||
          departmentIndices.contains(i) ||
          sloganIndices.contains(i) ||
          credentialIndices.contains(i)) {
        continue;
      }

      final line = lines[i];
      if (personName != null && line.toLowerCase() == personName.toLowerCase()) {
        continue;
      }

      final score = _evaluateCompanyScore(
        line,
        lineIndex: i,
        personIndex: personIndex,
        jobTitleIndex: jobTitleIndex,
        totalLines: lines.length,
        extractedPhones: extractedPhones,
        extractedEmails: extractedEmails,
        website: website,
      );

      final hasStrongOrgSuffix = RegExp(
        r'\b(pvt\.?\s*ltd\.?|private\s+limited|ltd\.?|limited|llc|llp|inc\.?|corp\.?|corporation|gmbh|foundation|trust|hospital|hospitals|clinic|clinics|health|healthcare|health\s+care|university|college|school|institute|chambers|law\s+firm|bank|government|ministry|services|technologies|solutions|enterprises|undertaking|consulate|embassy|guild|guilds|studio|studios|court|high\s+court|supreme\s+court|realty|realtors|brokerage|workshop|sanctuary|wellness)\b',
        caseSensitive: false,
      ).hasMatch(line);
      final hasKeyword = _companyKeywords.any((kw) =>
          RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false)
              .hasMatch(line.toLowerCase()));

      final currentWords = line.trim().split(RegExp(r'\s+')).length;
      bool shouldReplace = (best == null || score > best.classificationScore);
      if (best != null) {
        final bestWords = best.value.trim().split(RegExp(r'\s+')).length;
        if (bestWords == 1 && currentWords >= 2 && (hasKeyword || hasStrongOrgSuffix)) {
          shouldReplace = true; // Full organizational entity supersedes single-word brand
        } else if (currentWords == 1 && bestWords >= 2 && best.classificationScore >= 20) {
          shouldReplace = false; // Do not let 1-word brand overwrite multi-word company
        }
      }

      if (score >= 20 && shouldReplace) {
        final domainCandidates = <String>[];
        if (website != null) {
          domainCandidates.add(_normalizeDomain(website));
        }
        for (final email in extractedEmails) {
          final parts = email.email.split('@');
          if (parts.length == 2 && !_publicEmailDomains.contains(parts[1].toLowerCase())) {
            domainCandidates.add(parts[1].toLowerCase());
          }
        }
        final cleanLine = line.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        final matchesDomain = domainCandidates.any((dom) {
          final cleanDom = dom.replaceAll(RegExp(r'[^a-z0-9]'), '');
          final domStem = cleanDom.replaceAll(RegExp(r'(?:com|org|net|in|co|io|ai)$'), '');
          return (cleanLine.length >= 4 && cleanDom.length >= 4 &&
              (cleanDom.contains(cleanLine) || (domStem.length >= 4 && cleanLine.contains(domStem))));
        });

        if (!hasStrongOrgSuffix && !hasKeyword && !matchesDomain) {
          final words = line.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
          final isCap = words.every((w) => w[0] == w[0].toUpperCase() || RegExp(r'^[A-Z]+$').hasMatch(w));

          // If no keyword, suffix or domain match:
          // Must not have digits (e.g. rejects "1 Shift", "Desk 4")
          if (RegExp(r'\d').hasMatch(line)) {
            continue;
          }
          if (words.length == 1) {
            // Single-word brand (e.g. "NovaTechify")
            final isAdjacent = (i == 0) ||
                (jobTitleIndex != null && (i == jobTitleIndex + 1 || i == jobTitleIndex - 1)) ||
                (personIndex != null && (i == personIndex + 1 || i == personIndex - 1));
            if (!isCap || line.trim().length < 8 || !isAdjacent || score < 20) {
              continue;
            }
          } else {
            // Multi-word organization (e.g. "Meridian Crest Partners")
            if (!isCap || score < 20 || line.trim().length < 6) {
              continue;
            }
          }
        }

        final cleanedVal = line.trim().replaceAll(RegExp(r'[,;\s]+$'), '').trim();
        best = _ScoredCandidate(cleanedVal, i, score);
      }
    }

    return best;
  }

  _ScoredCandidate? _findBestJobTitleCandidate(
    List<String> lines, {
    int? personIndex,
    String? personName,
    int? companyIndex,
    String? companyName,
    required List<BusinessCardPhone> extractedPhones,
    required List<BusinessCardEmail> extractedEmails,
    String? website,
    required Set<int> departmentIndices,
    required Set<int> sloganIndices,
    required Set<int> credentialIndices,
  }) {
    // 1. Explicit designation label
    for (int i = 0; i < lines.length; i++) {
      if (i == personIndex ||
          i == companyIndex ||
          departmentIndices.contains(i) ||
          sloganIndices.contains(i) ||
          credentialIndices.contains(i)) {
        continue;
      }
      final line = lines[i];
      final labelMatch = RegExp(
        r'^(?:designation|job title|title|role)\s*[:\-]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (labelMatch != null) {
        final val = labelMatch.group(1)!.trim();
        if (val.isNotEmpty) {
          return _ScoredCandidate(val, i, 100);
        }
      }
    }

    // 2. Score candidate lines
    _ScoredCandidate? best;
    for (int i = 0; i < lines.length; i++) {
      if (i == personIndex ||
          i == companyIndex ||
          departmentIndices.contains(i) ||
          sloganIndices.contains(i) ||
          credentialIndices.contains(i)) {
        continue;
      }

      final line = lines[i];
      if (personName != null && line.toLowerCase() == personName.toLowerCase()) {
        continue;
      }
      if (companyName != null && line.toLowerCase() == companyName.toLowerCase()) {
        continue;
      }

      final score = _evaluateDesignationScore(
        line,
        lineIndex: i,
        personIndex: personIndex,
        companyIndex: companyIndex,
        totalLines: lines.length,
        extractedPhones: extractedPhones,
        extractedEmails: extractedEmails,
        website: website,
      );

      if (score >= 20 && (best == null || score > best.classificationScore)) {
        best = _ScoredCandidate(line.trim(), i, score);
      }
    }

    final chosenCandidate = best;
    if (chosenCandidate != null) {
      final idx = chosenCandidate.lineIndex;
      var combinedVal = chosenCandidate.value;

      // Check if previous line was part 1 of compound title (e.g. ends with '/' or '&' or ',')
      if (idx > 0 &&
          !departmentIndices.contains(idx - 1) &&
          !sloganIndices.contains(idx - 1) &&
          !credentialIndices.contains(idx - 1) &&
          idx - 1 != personIndex &&
          idx - 1 != companyIndex) {
        final prevLine = lines[idx - 1].trim();
        if (prevLine.endsWith('/') ||
            prevLine.endsWith('&') ||
            prevLine.endsWith(',') ||
            prevLine.toLowerCase().endsWith(' and')) {
          combinedVal = '$prevLine $combinedVal';
          return _ScoredCandidate(combinedVal, idx, chosenCandidate.classificationScore + 10);
        }
      }

      // Check if next line is part 2 of compound title
      if (idx < lines.length - 1 &&
          !departmentIndices.contains(idx + 1) &&
          !sloganIndices.contains(idx + 1) &&
          !credentialIndices.contains(idx + 1) &&
          idx + 1 != personIndex &&
          idx + 1 != companyIndex) {
        final nextLine = lines[idx + 1].trim();
        if (combinedVal.endsWith('/') ||
            combinedVal.endsWith('&') ||
            combinedVal.endsWith(',') ||
            combinedVal.toLowerCase().endsWith(' and') ||
            nextLine.startsWith('/') ||
            nextLine.startsWith('&')) {
          combinedVal = '$combinedVal $nextLine';
          return _ScoredCandidate(combinedVal, idx, chosenCandidate.classificationScore + 10);
        }
      }
    }

    return best;
  }

  int _evaluateDesignationScore(
    String line, {
    required int lineIndex,
    required int? personIndex,
    required int? companyIndex,
    required int totalLines,
    required List<BusinessCardPhone> extractedPhones,
    required List<BusinessCardEmail> extractedEmails,
    String? website,
  }) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return -100;
    if (_honorificPrefixRegExp.hasMatch(trimmed)) return -100;
    if (_isSlogan(trimmed)) return -100;
    if (_isDepartmentLine(trimmed)) return -100;
    if (_isPureCredentialLine(trimmed)) return -100;
    if (_isAddressLine(trimmed)) return -100;
    if (trimmed.length > 55 || trimmed.length < 3) return -100;
    // Allow '&' (e.g. 'Founder & CEO'), '/' (e.g. 'UI/UX Designer'), and tenure year ranges (e.g. 'International Director 2025-2027')
    final lineWithoutYearRange = trimmed.replaceAll(
      RegExp(r'\b(?:19|20)\d{2}\s*[-–/]\s*(?:(?:19|20)\d{2}|\d{2})\b'),
      '',
    );
    if (RegExp(r'[\d@#\$%\*=\[\]\\<>]').hasMatch(lineWithoutYearRange)) return -100;
    if (_emailRegExp.hasMatch(trimmed) ||
        _urlSchemeOrWwwRegExp.hasMatch(trimmed) ||
        _domainRegExp.hasMatch(trimmed)) {
      return -100;
    }
    if (extractedPhones.any((p) => trimmed.contains(p.number))) return -100;
    if (extractedEmails.any((e) => trimmed.contains(e.email))) return -100;
    if (RegExp(r'[\u0400-\u04FF\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF\u0600-\u06FF\u0900-\u097F]')
        .hasMatch(trimmed)) {
      return -100;
    }

    int score = 0;

    // Explicit label: "Designation: ...", "Title: ...", "Role: ..."
    if (RegExp(r'^(?:designation|job title|title|role)\s*[:\-]', caseSensitive: false)
        .hasMatch(trimmed)) {
      return 100;
    }

    final lower = trimmed.toLowerCase();

    // Signal 1: Known job title dictionary keyword match
    for (final kw in _jobTitleKeywords) {
      if (lower == kw ||
          lower.startsWith('$kw ') ||
          lower.endsWith(' $kw') ||
          lower.contains(' $kw ') ||
          lower.contains('$kw &') ||
          lower.contains('& $kw')) {
        score += 45;
        break;
      }
    }

    // Signal 2: Morphological occupational endings / professional roles
    const nonOccupationalNames = {
      'alexander', 'peter', 'miller', 'christopher', 'kumar', 'chander',
      'oliver', 'walter', 'cooper', 'parker', 'tyler', 'spencer',
      'conner', 'connor', 'carter', 'hunter', 'roger', 'arthur', 'xavier',
      'sunder', 'baker', 'foster', 'butler', 'fletcher', 'chandru', 'david'
    };

    final words = lower.split(RegExp(r'[\s&/,]+')).where((w) => w.isNotEmpty).toList();
    bool hasOccupationalWord = false;
    for (final w in words) {
      if (nonOccupationalNames.contains(w)) continue;

      if (w.endsWith('or') ||
          w.endsWith('er') ||
          w.endsWith('ist') ||
          w.endsWith('ian') ||
          w.endsWith('ant') ||
          w.endsWith('ent') ||
          w == 'advocate' ||
          w == 'architect' ||
          w == 'chef' ||
          w == 'counsel' ||
          w == 'dean' ||
          w == 'principal' ||
          w == 'lead' ||
          w == 'head' ||
          w == 'proprietor' ||
          w == 'partner' ||
          w == 'founder' ||
          w == 'owner' ||
          w == 'fellow' ||
          w == 'associate' ||
          w == 'representative' ||
          w == 'secretary' ||
          w == 'advisor' ||
          w == 'adviser' ||
          w == 'auditor' ||
          w == 'consul' ||
          w == 'ambassador' ||
          w == 'diplomat' ||
          w == 'attache' ||
          w == 'commissioner' ||
          w == 'magistrate' ||
          w == 'judge' ||
          w == 'trustee' ||
          w == 'custodian' ||
          w == 'officer' ||
          w == 'administrator' ||
          w == 'ceo' ||
          w == 'cto' ||
          w == 'cfo' ||
          w == 'coo' ||
          w == 'cio') {
        hasOccupationalWord = true;
        break;
      }
    }
    if (hasOccupationalWord) {
      score += 35;
    }

    // Professional modifiers
    if (words.any((w) => [
          'senior',
          'junior',
          'chief',
          'executive',
          'associate',
          'assistant',
          'lead',
          'head',
          'commercial',
          'licensed',
          'master',
          'freelance',
          'independent',
          'general',
          'managing',
          'under',
          'hon',
          'hon.',
          'honorary',
          'acting',
          'interim',
          'additional',
        ].contains(w))) {
      score += 15;
    }

    // Signal 3: Topology and spatial proximity
    // Topology bonuses should only boost candidates that already have occupational evidence (score > 0)
    // to prevent arbitrary strings from becoming a designation solely by adjacency
    if (score > 0) {
      if (personIndex != null && companyIndex != null) {
        if (personIndex < lineIndex && lineIndex < companyIndex) {
          // [Person] -> [Designation] -> [Company]
          score += 40;
        } else if (companyIndex < personIndex && lineIndex == personIndex + 1) {
          // [Company] -> [Person] -> [Designation]
          score += 40;
        }
      } else if (personIndex != null) {
        if (lineIndex == personIndex + 1) {
          // Immediately follows person
          score += 35;
        }
      }

      // Proper word count (1 to 5 words)
      if (words.isNotEmpty && words.length <= 5) {
        score += 10;
      }
    }

    // Penalize if it contains corporate legal suffixes (e.g. Ltd, LLC, Inc)
    final hasOrgEntitySuffix = RegExp(
      r'\b(pvt\.?\s*ltd\.?|private\s+limited|ltd\.?|limited|llc|inc\.?|corp\.?|corporation|gmbh|foundation|trust|bank)\b',
      caseSensitive: false,
    ).hasMatch(trimmed);
    if (hasOrgEntitySuffix) {
      score -= 80;
    }

    return score;
  }

  int _evaluatePersonScore(
    String line, {
    required int lineIndex,
    required int? jobTitleIndex,
    required int? companyIndex,
    required int totalLines,
    required List<BusinessCardPhone> extractedPhones,
    required List<BusinessCardEmail> extractedEmails,
    String? website,
    bool hasAttachedCredentials = false,
  }) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return -100;
    if (RegExp(r'\b(?:iso(?:\s*[:\-\d]|\b)|iso\s*\d+(?::\d+)?|ce\s*\d+|gmp|nabh|nabl)\b', caseSensitive: false).hasMatch(trimmed)) {
      return -100;
    }
    if (_isSlogan(trimmed) || FieldSemanticEvaluator.isSlogan(trimmed)) return -100;
    if (_isDepartmentLine(trimmed)) return -100;
    if (_isPureCredentialLine(trimmed)) return -100;
    if (_isAddressLine(trimmed) || FieldSemanticEvaluator.isLocationOrAddressLine(trimmed)) return -100;
    if (trimmed.length > 45 || trimmed.length < 3) return -100;
    if (trimmed.endsWith(':') ||
        RegExp(r'^(?:affiliated|contact|office|branch|partner:)\b', caseSensitive: false)
            .hasMatch(trimmed)) {
      return -100;
    }
    // Organization / corporate suffixes must not become Person Name
    if (RegExp(
      r'\b(ltd\.?|limited|pvt\.?|private|llc|llp|inc\.?|corp\.?|corporation|company|companies|technolog(?:y|ies)|tech|solutions?|services?|enterprises?|industr(?:y|ies)|systems?|laborator(?:y|ies)|labs?|holdings?|group|consulting|consultanc(?:y|ies)|associates?|partners?|hospitals?|clinics?|healthcare|health\s+care|university|universities|colleges?|schools?|institutes?|foundations?|events?|equipments?|medical|engineering|manufacturing|traders?|court|high\s+court|supreme\s+court|government|govt|realty|realtors?|brokerages?|institutions?|educational?|support|customer\s+support|delivery|fast\s+delivery|logistics|shipping|travels?|tours?|pharma(?:ceuticals?)?|pharmacy|diagnostics?|dental|optical|studios?|media|digital|creatives?|agenc(?:y|ies)|global|international|express|transport(?:ation)?|cargo|freight|courier|infra(?:structure)?|builders?|developers?|properties|estates?|ventures?|capital|finance|financial|investments?|insurance|wealth|security|securities|staffing|telecom(?:munications?)?|networks?|energy|solar|power|bazaar|supermarket|hypermarket|mart|stores?|shops?|restaurant|cafe|cafes|hotels?|motels?|resorts?|spas?|salons?|garages?|motors?|automotive|auto|center|centers|centre|centres|hub|hubs|zones?|interactive|dynamics?|innovations?|designs?|advisory|advisors?|managements?|software|hardware)\b',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return -100;
    }

    final lower = trimmed.toLowerCase();
    for (final kw in _companyKeywords) {
      if (kw.length >= 3 && RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false).hasMatch(lower)) {
        return -100;
      }
    }
    // Quality & management certifications must not become Person Name
    if (RegExp(r'\b(?:iso(?:\s*[:\-\d]|\b)|iso\s*\d+(?::\d+)?|ce\s*\d+|gmp|nabh|nabl)\b', caseSensitive: false).hasMatch(trimmed)) {
      return -100;
    }
    // Job titles must not become Person Name (unless qualified with personal honorific / credential)
    if (RegExp(r'\b(director|managing\s+director|executive\s+director|manager|engineer|developer|consultant|officer|president|vice\s+president|vp|head|lead|founder|partner|specialist|analyst|associate|architect|designer|coordinator|advisor|secretary|broker|realtor|commissioner)\b', caseSensitive: false).hasMatch(trimmed) &&
        !_honorificPrefixRegExp.hasMatch(trimmed) &&
        !hasAttachedCredentials) {
      return -100;
    }
    if (RegExp(r'[\d@#\$%^&*\+=\[\]\\\/<>]').hasMatch(trimmed)) return -100;
    if (_emailRegExp.hasMatch(trimmed) ||
        _urlSchemeOrWwwRegExp.hasMatch(trimmed) ||
        _domainRegExp.hasMatch(trimmed)) {
      return -100;
    }
    if (extractedPhones.any((p) => trimmed.contains(p.number))) return -100;
    if (extractedEmails.any((e) => trimmed.contains(e.email))) return -100;
    if (RegExp(r'[\u0400-\u04FF\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF\u0600-\u06FF\u0900-\u097F]')
            .hasMatch(trimmed) &&
        !_honorificPrefixRegExp.hasMatch(trimmed)) {
      return -100;
    }

    int score = 0;

    // Explicit label: "Name: ..."
    if (RegExp(r'^name\s*[:\-]', caseSensitive: false).hasMatch(trimmed)) {
      return 100;
    }

    // Check for honorific: "Dr.", "Prof.", "Adv.", "Er.", "CA", "Mr.", "Ms.", "Mrs.", "Shri", "Smt", "Chef"
    if (_honorificPrefixRegExp.hasMatch(trimmed)) {
      score += 50;
    }

    // Check for credential boost (e.g. IAS, IPS, MBBS, MD, PhD attached to name)
    if (hasAttachedCredentials) {
      score += 50;
    }

    // Precedes or succeeds job title (strongest layout signal)
    bool isAdjacentToJobTitle = false;
    if (jobTitleIndex != null) {
      if (lineIndex == jobTitleIndex - 1) {
        score += 40;
        isAdjacentToJobTitle = true;
      } else if (lineIndex == jobTitleIndex + 1) {
        score += 25;
        isAdjacentToJobTitle = true;
      }
    }

    // Follows company at top
    if (companyIndex != null && companyIndex < lineIndex && lineIndex <= 2) {
      score += 25;
    }

    // Word count and capitalization (handles names with initials e.g. "Chandra Kanthan, M", "M. Chandra Kanthan" or "K. S. Raman")
    final words = trimmed
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.replaceAll(RegExp(r'[,;\.]+$'), ''))
        .where((w) => w.isNotEmpty)
        .toList();

    bool hasPersonalSignal = _honorificPrefixRegExp.hasMatch(trimmed) ||
        hasAttachedCredentials ||
        isAdjacentToJobTitle ||
        extractedEmails.any((e) {
          final user = e.email.split('@').first.toLowerCase();
          final cleanLine = lower.replaceAll(RegExp(r'[^a-z]'), '');
          return user.contains(cleanLine) || (cleanLine.length >= 5 && cleanLine.contains(user));
        });

    if (words.length == 1) {
      final matchesEmailUser = extractedEmails.any((e) {
        final user = e.email.split('@').first.toLowerCase();
        return user.contains(lower) || lower.contains(user);
      });
      if (!_honorificPrefixRegExp.hasMatch(trimmed) && !hasAttachedCredentials && !matchesEmailUser) {
        return -100;
      }
    } else if (words.length >= 2 && words.length <= 5) {
      bool isCapitalized = words.every((w) =>
          w.isNotEmpty &&
          (w[0] == w[0].toUpperCase() || RegExp(r'^[A-Za-z]\.?$', caseSensitive: false).hasMatch(w) || RegExp(r'^[A-Z]+$').hasMatch(w)));
      if (isCapitalized) {
        score += 10;
      }
      if (words.any((w) => RegExp(r'^[A-Za-z]\.?$', caseSensitive: false).hasMatch(w))) {
        score += 15; // Initials boost (e.g. Chandra Kanthan, M or M. Chandra Kanthan)
        hasPersonalSignal = true;
      }
      if (isCapitalized && words.length <= 3 && totalLines <= 3 && (extractedPhones.isNotEmpty || extractedEmails.isNotEmpty)) {
        score += 20;
        hasPersonalSignal = true;
      }
    }

    // Top of card boost (moderate position heuristic, NEVER granting personal signal on its own)
    if (lineIndex == 0 || lineIndex == 1) {
      score += 10;
    }

    // Capitalization alone without positive personal signals must NEVER reach the 35 acceptance threshold
    if (!hasPersonalSignal && score >= 35) {
      score = 20;
    }

    // Penalize if it contains job title keywords and no personal honorific or credential
    if (!_honorificPrefixRegExp.hasMatch(trimmed) && !hasAttachedCredentials) {
      final lower = trimmed.toLowerCase();
      for (final kw in _jobTitleKeywords) {
        if (lower == kw || lower.contains(' $kw') || lower.startsWith('$kw ')) {
          score -= 70;
          break;
        }
      }
      final lWords = lower.split(RegExp(r'[\s&/,]+')).where((w) => w.isNotEmpty).toList();
      if (lWords.any((w) => [
            'engineer',
            'developer',
            'consultant',
            'manager',
            'director',
            'officer',
            'specialist',
            'analyst',
            'coordinator',
            'architect',
            'advocate',
            'partner',
            'founder',
            'proprietor',
            'ceo',
            'cto',
            'cfo',
          ].contains(w))) {
        score -= 60;
      }
    }

    // Domain matching:
    // A corporate domain match is disqualified, EXCEPT when a multi-word person name
    // immediately precedes the job title (e.g. "Elena Rostova" -> "Independent UI/UX Designer" matching elenarostova.design)
    final isDirectlyAboveJobTitle = (jobTitleIndex != null && lineIndex == jobTitleIndex - 1);
    if (!isDirectlyAboveJobTitle) {
      if (website != null) {
        final cleanDomain = _normalizeDomain(website);
        final cleanLine = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (cleanLine.length >= 4 && cleanDomain.contains(cleanLine)) {
          return -100;
        }
      }
      for (final email in extractedEmails) {
        final parts = email.email.split('@');
        if (parts.length == 2) {
          final emailDomain = parts[1].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          final cleanLine = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (cleanLine.length >= 4 &&
              emailDomain.contains(cleanLine) &&
              !_publicEmailDomains.contains(parts[1].toLowerCase())) {
            return -100;
          }
        }
      }
    }

    // Immediate rejection if it contains company keywords
    for (final kw in _companyKeywords) {
      if (RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false)
          .hasMatch(trimmed.toLowerCase())) {
        return -100;
      }
    }

    return score;
  }

  int _evaluateCompanyScore(
    String line, {
    required int lineIndex,
    required int? personIndex,
    required int? jobTitleIndex,
    required int totalLines,
    required List<BusinessCardPhone> extractedPhones,
    required List<BusinessCardEmail> extractedEmails,
    String? website,
  }) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return -100;
    if (RegExp(r'\b(?:iso(?:\s*[:\-\d]|\b)|iso\s*\d+(?::\d+)?|ce\s*\d+|gmp|nabh|nabl)\b', caseSensitive: false).hasMatch(trimmed)) {
      return -100;
    }
    if (_isSlogan(trimmed) || FieldSemanticEvaluator.isSlogan(trimmed)) return -100;
    if (_isDepartmentLine(trimmed)) return -100;
    if (_isPureCredentialLine(trimmed)) return -100;
    if (_isAddressLine(trimmed) || FieldSemanticEvaluator.isLocationOrAddressLine(trimmed)) return -100;
    if (trimmed.length > 75 || trimmed.length < 3) return -100;

    // Disqualify non-company background text starting with a digit (e.g. "1 Shift", "2 Unit", "Floor 3")
    if (RegExp(r'^\d+[\s\-\/]+[a-zA-Z]+$').hasMatch(trimmed)) {
      return -100;
    }
    if (RegExp(r'^\d+\s+(?:shift|batch|counter|floor|unit|step|phase|gate|room|slot|lane|terminal|desk|track|day|days|hour|hours|min|mins|sec|secs)\b', caseSensitive: false)
        .hasMatch(trimmed)) {
      return -100;
    }

    if (_emailRegExp.hasMatch(trimmed) ||
        _urlSchemeOrWwwRegExp.hasMatch(trimmed) ||
        _domainRegExp.hasMatch(trimmed)) {
      return -100;
    }
    if (extractedPhones.any((p) => trimmed.contains(p.number))) return -100;
    if (extractedEmails.any((e) => trimmed.contains(e.email))) return -100;

    int score = 0;

    // Explicit label: "Company: ...", "Organization: ...", "Org: ..."
    if (RegExp(r'^(?:company|organization|org)\s*[:\-]', caseSensitive: false)
        .hasMatch(trimmed)) {
      return 100;
    }

    final lower = trimmed.toLowerCase();

    // Check for strict legal corporate entity suffix
    final hasStrictLegalOrgSuffix = RegExp(
      r'\b(pvt\.?\s*ltd\.?|private\s+limited|ltd\.?|limited|llc|llp|inc\.?|corp\.?|corporation|gmbh)\b',
      caseSensitive: false,
    ).hasMatch(trimmed);

    // Institutional org suffix (hospitals, universities, foundations, chambers, etc.)
    final hasInstitutionalOrgSuffix = RegExp(
      r'\b(foundation|trust|hospital|hospitals|clinic|clinics|health|healthcare|health\s+care|medical\s+mission|medical\s+center|medical\s+centre|university|college|school|institute|chambers|law\s+firm|bank|government|ministry|undertaking|consulate|embassy|court|high\s+court|supreme\s+court|realty|realtors|brokerage|workshop|sanctuary|wellness)\b',
      caseSensitive: false,
    ).hasMatch(trimmed);

    // Business descriptor suffix (services, technologies, solutions, enterprises)
    final hasBusinessDescriptor = RegExp(
      r'\b(services|technologies|technology|solutions|enterprises|systems|industries|laboratories|labs|holdings|group|logistics)\b',
      caseSensitive: false,
    ).hasMatch(trimmed);

    final hasStrongOrgSuffix = hasStrictLegalOrgSuffix || hasInstitutionalOrgSuffix;

    if (hasStrongOrgSuffix) {
      score += 45;
    } else if (hasBusinessDescriptor) {
      score += 30;
    }

    // Keyword match
    bool hasCompanyKeyword = false;
    for (final kw in _companyKeywords) {
      if (RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false)
          .hasMatch(lower)) {
        hasCompanyKeyword = true;
        score += 35;
        break;
      }
    }

    // Domain match bonus (from website or private company email domain)
    final domainCandidates = <String>[];
    if (website != null) {
      domainCandidates.add(_normalizeDomain(website));
    }
    final cleanLine = lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final email in extractedEmails) {
      final parts = email.email.split('@');
      if (parts.length == 2) {
        if (!_publicEmailDomains.contains(parts[1].toLowerCase())) {
          domainCandidates.add(parts[1].toLowerCase());
        }
        final local = parts[0].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (cleanLine.length >= 5 && (local.contains(cleanLine) || (local.length >= 6 && cleanLine.contains(local)))) {
          score += 35; // Email local-part matches company name (e.g. chandrumediequip@gmail.com)
        }
      }
    }

    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length >= 2 && (hasCompanyKeyword || hasStrongOrgSuffix || hasBusinessDescriptor)) {
      score += 25; // Prioritize full organizational entities over standalone 1-word brand marks
    }
    for (final dom in domainCandidates) {
      final cleanDom = dom.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final domStem = cleanDom.replaceAll(RegExp(r'(?:com|org|net|in|co|io|ai)$'), '');
      if (cleanLine.length >= 4 && cleanDom.length >= 4) {
        if (cleanDom.contains(cleanLine) || (domStem.length >= 4 && cleanLine.contains(domStem))) {
          score += 40;
          break;
        }
      }
    }

    // Non-Latin script without explicit Latin company keywords should not be guessed as English company
    if (RegExp(r'[\u0400-\u04FF\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF\u0600-\u06FF\u0900-\u097F]')
            .hasMatch(trimmed) &&
        !hasCompanyKeyword &&
        !hasStrongOrgSuffix &&
        !hasBusinessDescriptor) {
      return -100;
    }

    // Top branding heuristic: line 0
    if (lineIndex == 0) {
      score += 30;
    }

    // Immediately beneath job title or department
    if (jobTitleIndex != null &&
        (lineIndex == jobTitleIndex + 1 || lineIndex == jobTitleIndex + 2)) {
      score += 25;
    }

    // Penalty if it starts with personal honorific
    if (_honorificPrefixRegExp.hasMatch(trimmed)) {
      score -= 80;
    }

    // Job title & occupational role detection
    bool containsJobTitleRole = false;
    for (final kw in _jobTitleKeywords) {
      if (lower == kw ||
          lower.startsWith('$kw ') ||
          lower.endsWith(' $kw') ||
          lower.contains(' $kw ') ||
          lower.contains('$kw -') ||
          lower.contains('- $kw') ||
          lower.contains('$kw :') ||
          lower.contains('/$kw') ||
          lower.contains('$kw/')) {
        containsJobTitleRole = true;
        break;
      }
    }
    if (!containsJobTitleRole) {
      final words = lower.split(RegExp(r'[\s&/,\-]+')).where((w) => w.isNotEmpty).toList();
      if (words.any((w) => [
            'engineer',
            'developer',
            'consultant',
            'manager',
            'director',
            'officer',
            'specialist',
            'analyst',
            'coordinator',
            'architect',
            'advocate',
            'partner',
            'founder',
            'proprietor',
            'president',
            'ceo',
            'cto',
            'cfo',
            'coo',
            'vp',
            'head',
            'lead',
          ].contains(w))) {
        containsJobTitleRole = true;
      }
    }

    // Critical: If the line contains a job title/role keyword, it MUST NOT be classified as a company,
    // even if it contains words like Services, Solutions, Technologies, or Enterprises,
    // unless it is an explicit legal entity (e.g. "Managing Directors Ltd").
    if (containsJobTitleRole && !hasStrictLegalOrgSuffix) {
      return -100;
    }

    // If no company keyword, business descriptor, or corporate suffix:
    if (!hasCompanyKeyword && !hasStrongOrgSuffix && !hasBusinessDescriptor) {
      // Disqualify if it has digits
      if (RegExp(r'\d').hasMatch(trimmed)) {
        return -100;
      }
      // Disqualify single word without space if length < 7
      if (!trimmed.contains(' ') && trimmed.length < 7) {
        return -100;
      }
      // If beyond line 2, heavy penalty
      if (lineIndex > 2) {
        score -= 40;
      }
    }

    return score;
  }

  bool _isDepartmentLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    if (_departmentPrefixRegExp.hasMatch(trimmed) ||
        _departmentSuffixRegExp.hasMatch(trimmed) ||
        _standaloneSpecialtyRegExp.hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  bool _isPureCredentialLine(String line) {
    var trimmed = line.trim();
    trimmed = trimmed.replaceAll(RegExp(r'^[•\-\*\>👤\s,]+'), '');
    trimmed = trimmed.replaceAll(RegExp(r'[•\-\*\>👤\s,]+$'), '');
    if (trimmed.isEmpty) return false;

    // Reject if it's an address line
    if (_isAddressLine(trimmed)) return false;

    // Guard: If line contains multiple words before a comma, it's a person name with credentials (e.g. "KUMAR JAYANT, I.A.S.")
    if (trimmed.contains(',')) {
      final beforeComma = trimmed.substring(0, trimmed.indexOf(',')).trim();
      final wordsBefore = beforeComma.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (wordsBefore.length >= 2 && wordsBefore.every((w) => w.length >= 2)) {
        return false;
      }
    }

    final tokens = trimmed
        .split(RegExp(r'[,/|\s]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (tokens.isEmpty) return false;

    bool hasKnownCred = false;
    for (final token in tokens) {
      if (_credentialTokenRegExp.hasMatch(token)) {
        hasKnownCred = true;
      } else if (token.length > 4 && !token.contains('.')) {
        // Normal words with 5+ characters and no dots (e.g. KUMAR, JAYANT) are NOT credentials
        return false;
      } else if (!RegExp(r'^[A-Z]{2,4}\.?$').hasMatch(token) &&
                 !RegExp(r'^[A-Z]\.(?:[A-Z]\.)+$').hasMatch(token)) {
        return false;
      }
    }
    return hasKnownCred;
  }

  _NameAndCredentials _extractNameAndCredentials(String line) {
    var trimmed = line.trim();
    trimmed = trimmed.replaceAll(RegExp(r'[,;\s]+$'), '').trim();
    if (!trimmed.contains(',')) {
      return _NameAndCredentials(name: trimmed, credentials: null);
    }

    final commaIndex = trimmed.indexOf(',');
    final candidateName = trimmed.substring(0, commaIndex).trim().replaceAll(RegExp(r'[,;.]+$'), '');
    var remainder = trimmed.substring(commaIndex + 1).trim();
    remainder = remainder.replaceAll(RegExp(r'[,;\s]+$'), '').trim();

    if (_credentialTokenRegExp.hasMatch(remainder) || _isPureCredentialLine(remainder)) {
      return _NameAndCredentials(name: candidateName, credentials: remainder);
    }

    return _NameAndCredentials(name: trimmed, credentials: null);
  }

  String _cleanNameCandidate(String candidate) {
    var cleaned = candidate.trim();
    cleaned = cleaned.replaceAll(RegExp(r'^[•\-\*\>👤\s,]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[•\-\*\>👤\s,]+$'), '');
    return cleaned.trim();
  }

  bool _isSlogan(String line) {
    final lower = line.trim().toLowerCase();
    if (lower.isEmpty) return false;

    // Guard: lines that end in legal company indicators are not slogans
    if (RegExp(r'\b(ltd|pvt ltd|llc|inc|corp|corporation|gmbh|foundation|trust|hospital|clinic|university|college|school|bank|services|technologies)\b')
        .hasMatch(lower)) {
      return false;
    }

    for (final pattern in _sloganPatterns) {
      if (pattern.hasMatch(lower)) return true;
    }
    return false;
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
    final seenNorm = <String>{};
    final isExplicitAddr = <int, bool>{};

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
      if (jobTitle != null && jobTitle.trim().isNotEmpty) {
        final lTitle = jobTitle.trim().toLowerCase();
        final lTrimmed = trimmed.toLowerCase();
        if (lTrimmed == lTitle || lTrimmed.contains(lTitle) || lTitle.contains(lTrimmed)) continue;
      }
      if (website != null && trimmed.toLowerCase().contains(website.toLowerCase())) continue;
      if (_isSlogan(trimmed) || FieldSemanticEvaluator.isSlogan(trimmed)) continue;
      if (_emailRegExp.hasMatch(trimmed) || trimmed.contains('@') || extractedEmails.any((e) => trimmed.contains(e.email))) continue;
      if (extractedPhones.any((p) => trimmed.contains(p.number))) continue;

      final upperLine = trimmed.toUpperCase();
      if (upperLine.contains('GSTIN') || upperLine.contains('GST:') || upperLine.contains('CIN:') || upperLine.contains('INVOICE:') || upperLine.contains('PAN:') || upperLine.startsWith('ISO') || upperLine.startsWith('CE ')) {
        continue;
      }

      final isExplicitPhone = RegExp(
        r'^(?:m|mob|mobile|p|ph|phone|tel|telephone|fax|whatsapp|cell)\s*[:\-\.]',
        caseSensitive: false,
      ).hasMatch(trimmed);
      if (isExplicitPhone) continue;

      final addrLabelMatch = RegExp(
        r'^(?:address|addr|office address|office|headquarters|hq|location)\s*[:\-]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (addrLabelMatch != null) {
        isExplicitAddr[i] = true;
        continue;
      }

      if (_isAddressLine(trimmed)) {
        isExplicitAddr[i] = true;
      }
    }

    // Second pass: Assemble address block with intermediate line preservation
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
      if (jobTitle != null && jobTitle.trim().isNotEmpty) {
        final lTitle = jobTitle.trim().toLowerCase();
        final lTrimmed = trimmed.toLowerCase();
        if (lTrimmed == lTitle || lTrimmed.contains(lTitle) || lTitle.contains(lTrimmed)) continue;
      }
      if (website != null && trimmed.toLowerCase().contains(website.toLowerCase())) continue;
      if (_isSlogan(trimmed) || FieldSemanticEvaluator.isSlogan(trimmed)) continue;
      if (_emailRegExp.hasMatch(trimmed) || trimmed.contains('@') || extractedEmails.any((e) => trimmed.contains(e.email))) continue;
      if (extractedPhones.any((p) => trimmed.contains(p.number))) continue;

      final upperLine = trimmed.toUpperCase();
      if (upperLine.contains('GSTIN') || upperLine.contains('GST:') || upperLine.contains('CIN:') || upperLine.contains('INVOICE:') || upperLine.contains('PAN:') || upperLine.startsWith('ISO') || upperLine.startsWith('CE ')) continue;
      if (RegExp(r'^(?:m|mob|mobile|p|ph|phone|tel|telephone|fax|whatsapp|cell)\s*[:\-\.]', caseSensitive: false).hasMatch(trimmed)) continue;

      final addrLabelMatch = RegExp(
        r'^(?:address|addr|office address|office|headquarters|hq|location)\s*[:\-]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (addrLabelMatch != null) {
        final val = addrLabelMatch.group(1)!.trim();
        final norm = val.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (norm.isNotEmpty && !seenNorm.contains(norm)) {
          seenNorm.add(norm);
          addressLines.add(val);
        }
        continue;
      }

      bool shouldAdd = isExplicitAddr[i] == true;
      if (!shouldAdd) {
        final lower = trimmed.toLowerCase();
        final bool isOtherEntity = _isSlogan(trimmed) ||
            _isDepartmentLine(trimmed) ||
            _isPureCredentialLine(trimmed) ||
            _honorificPrefixRegExp.hasMatch(trimmed) ||
            _companyKeywords.any((kw) => RegExp(r'\b' + RegExp.escape(kw) + r'\b').hasMatch(lower)) ||
            _jobTitleKeywords.any((kw) => RegExp(r'\b' + RegExp.escape(kw) + r'\b').hasMatch(lower)) ||
            FieldSemanticEvaluator.evaluateNameCandidate(rawLine: trimmed, sourceEngine: 'AddressGuard').semanticConfidence >= 0.40;

        if (!isOtherEntity) {
          final bool precededByAddr = (i > 0 && isExplicitAddr[i - 1] == true) || (i > 1 && isExplicitAddr[i - 2] == true);
          final bool followedByAddr = (i < lines.length - 1 && isExplicitAddr[i + 1] == true) || (i < lines.length - 2 && isExplicitAddr[i + 2] == true);
          if (precededByAddr && followedByAddr) {
            shouldAdd = true;
          } else if (followedByAddr && (trimmed.endsWith(',') || RegExp(r'^\s*(?:#|no\.?|door|flat|plot|survey)?\s*\d+[/0-9a-zA-Z-]*\b', caseSensitive: false).hasMatch(trimmed))) {
            shouldAdd = true;
          }
        }
      }

      if (shouldAdd) {
        final norm = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (norm.isNotEmpty && !seenNorm.contains(norm)) {
          seenNorm.add(norm);
          addressLines.add(trimmed);
        }
      }
    }

    if (addressLines.isEmpty) return null;
    return addressLines.join(', ');
  }

  bool _isAddressLine(String line) {
    if (FieldSemanticEvaluator.isLocationOrAddressLine(line)) {
      return true;
    }
    final lower = line.toLowerCase();

    // Guard against doctors or honorifics: "Dr Jane Doe" is not an address line!
    if (_honorificPrefixRegExp.hasMatch(line.trim())) {
      return false;
    }

    // Guard against quality / statutory certifications: "ISO 9001:2008" is not an address line!
    if (RegExp(r'\b(iso\s*\d+|certified|certification|nabh|gmp)\b', caseSensitive: false).hasMatch(lower)) {
      return false;
    }

    // Guard against real-estate occupational titles: "Licensed Real Estate Broker" is a title, not an address
    if (lower.contains('real estate') && (lower.contains('broker') || lower.contains('agent') || lower.contains('realtor') || lower.contains('consultant'))) {
      return false;
    }

    // Guard against courts of law and governmental / public authorities: "High Court of Kerala", "Government of Karnataka"
    if (RegExp(r'\b(high court|supreme court|district court|court of|government|govt|ministry|department|council|authority|board|tribunal|commission)\b', caseSensitive: false)
        .hasMatch(lower)) {
      return false;
    }

    // Guard against corporate entities: "Pvt Ltd", "Ltd", "Inc", "LLC", "Corp" are organizations, not addresses!
    if (RegExp(r'\b(pvt\.?\s*ltd\.?|private\s+limited|ltd\.?|limited|llc|llp|inc\.?|corp\.?|corporation|gmbh|undertaking|consulate|embassy|court|government|realty|realtors|brokerage)\b', caseSensitive: false)
        .hasMatch(lower)) {
      return false;
    }

    // Check address keywords with whole-word boundary
    for (final kw in _addressKeywords) {
      if (RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false)
          .hasMatch(lower)) {
        return true;
      }
    }

    // Check for postal / PIN code format
    if (RegExp(r'\b\d{5,6}\b').hasMatch(line) &&
        (lower.contains('pin') ||
            lower.contains('zip') ||
            lower.contains(',') ||
            line.contains(RegExp(r'[a-zA-Z]{3,}')))) {
      return true;
    }

    // Check for UK postcode format (e.g. SW1A 1AA or EC1A 1BB)
    if (RegExp(r'\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b', caseSensitive: false)
        .hasMatch(line)) {
      return true;
    }

    return false;
  }
}

class _ScoredCandidate {
  final String value;
  final int lineIndex;
  final int classificationScore;

  const _ScoredCandidate(this.value, this.lineIndex, this.classificationScore);
}

class _NameAndCredentials {
  final String name;
  final String? credentials;

  const _NameAndCredentials({required this.name, this.credentials});
}
