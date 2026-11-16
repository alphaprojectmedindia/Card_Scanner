import '../../models/business_card_data.dart';
import '../../models/ocr_side_result.dart';

enum FieldConfidenceLevel {
  high,
  medium,
  low,
}

class FieldConfidenceDetail {
  final String fieldName;
  final FieldConfidenceLevel level;
  final double score; // 0.0 to 1.0
  final String? extractedValue;
  final List<String> evidence;
  final List<String> alternativeCandidates;
  final List<String> uncertaintyReasons;

  const FieldConfidenceDetail({
    required this.fieldName,
    required this.level,
    required this.score,
    this.extractedValue,
    this.evidence = const [],
    this.alternativeCandidates = const [],
    this.uncertaintyReasons = const [],
  });

  bool get isHigh => level == FieldConfidenceLevel.high;
  bool get isMedium => level == FieldConfidenceLevel.medium;
  bool get isLow => level == FieldConfidenceLevel.low;
}

class FieldConfidenceReport {
  final Map<String, FieldConfidenceDetail> fields;
  final double overallScore;
  final bool isOverallReliable;
  final List<String> generalUncertaintyReasons;

  const FieldConfidenceReport({
    required this.fields,
    required this.overallScore,
    required this.isOverallReliable,
    this.generalUncertaintyReasons = const [],
  });

  FieldConfidenceDetail? operator [](String fieldName) => fields[fieldName];

  bool get hasLowConfidenceCriticalFields {
    final name = fields['fullName'];
    final company = fields['company'];
    final phone = fields['phoneNumbers'];
    final email = fields['emailAddresses'];

    final isNameLow = name == null || name.isLow || (name.extractedValue?.isEmpty ?? true);
    final isCompanyLow = company == null || company.isLow || (company.extractedValue?.isEmpty ?? true);
    final isContactChannelsLow =
        (phone == null || phone.isLow) && (email == null || email.isLow);

    // Critical fields are low confidence if person name is low/missing, company is low/missing, or contact channels are unresolved
    return isNameLow || isCompanyLow || isContactChannelsLow;
  }
}

/// Centralized evaluator that computes field-level confidence grades (HIGH/MEDIUM/LOW)
/// and determines whether local extraction is sufficiently high-confidence to bypass Gemini.
class FieldConfidenceEvaluator {
  const FieldConfidenceEvaluator();

  static final RegExp _businessEntityRegExp = RegExp(
    r'\b(?:ltd|limited|pvt|private\s+limited|inc|incorporated|corp|corporation|solutions|technologies|technology|tech|labs|holdings|enterprises|industries|group|services|llc|gmbh|co\.|consulting|consultancy|associates|partners|hospital|clinic|healthcare|systems|studio|agency|ventures|capital|logistics|interactive|dynamics|innovations|designs|advisory|management|software|hardware)\b',
    caseSensitive: false,
  );

  static final RegExp _honorificPrefixRegExp = RegExp(
    r'^(?:dr\.|dr|prof\.|prof|er\.|er|ca\.|ca|adv\.|adv|advocate|mr\.|mr|mrs\.|mrs|ms\.|ms)\s+',
    caseSensitive: false,
  );

  static final RegExp _knownJobTitleTaxonomy = RegExp(
    r'\b(?:director|founder|ceo|cto|cfo|cmo|coo|president|vice\s+president|vp|manager|engineer|developer|architect|consultant|specialist|officer|partner|head|lead|analyst|executive|designer|representative)\b',
    caseSensitive: false,
  );

  /// Evaluates extracted [BusinessCardData] against OCR observations and structural heuristics.
  FieldConfidenceReport evaluate({
    required BusinessCardData cardData,
    OcrSideResult? frontOcr,
    OcrSideResult? backOcr,
  }) {
    final fields = <String, FieldConfidenceDetail>{};
    final generalReasons = <String>[];

    // 1. Full Name
    fields['fullName'] = _evaluateFullName(cardData);

    // 2. Company
    fields['company'] = _evaluateCompany(cardData);

    // 3. Job Title
    fields['jobTitle'] = _evaluateJobTitle(cardData);

    // 4. Phone Numbers
    fields['phoneNumbers'] = _evaluatePhoneNumbers(cardData);

    // 5. Email Addresses
    fields['emailAddresses'] = _evaluateEmailAddresses(cardData);

    // 6. Website
    fields['website'] = _evaluateWebsite(cardData);

    // 7. Address
    fields['address'] = _evaluateAddress(cardData);

    // Calculate overall score
    double totalWeight = 0.0;
    double weightedScore = 0.0;

    const weights = {
      'fullName': 0.25,
      'company': 0.20,
      'phoneNumbers': 0.20,
      'emailAddresses': 0.15,
      'jobTitle': 0.10,
      'website': 0.05,
      'address': 0.05,
    };

    weights.forEach((key, weight) {
      final detail = fields[key];
      if (detail != null) {
        totalWeight += weight;
        weightedScore += detail.score * weight;
        if (detail.isLow && detail.uncertaintyReasons.isNotEmpty) {
          generalReasons.addAll(detail.uncertaintyReasons);
        }
      }
    });

    final overall = totalWeight > 0 ? (weightedScore / totalWeight) : 0.0;
    final isReliable = overall >= 0.75 &&
        (fields['fullName']?.level != FieldConfidenceLevel.low ||
            fields['company']?.level != FieldConfidenceLevel.low);

    return FieldConfidenceReport(
      fields: fields,
      overallScore: double.parse(overall.toStringAsFixed(3)),
      isOverallReliable: isReliable,
      generalUncertaintyReasons: generalReasons,
    );
  }

  FieldConfidenceDetail _evaluateFullName(BusinessCardData cardData) {
    final val = cardData.fullName?.trim() ?? '';
    final alts = cardData.alternativeCandidates['fullName'] ?? const [];
    final reasons = <String>[];
    final evidence = <String>[];

    if (val.isEmpty) {
      return FieldConfidenceDetail(
        fieldName: 'fullName',
        level: FieldConfidenceLevel.low,
        score: 0.0,
        uncertaintyReasons: ['Person name was not detected by local parser.'],
        alternativeCandidates: alts,
      );
    }

    evidence.add('Extracted: "$val"');
    double score = 0.85;

    if (_businessEntityRegExp.hasMatch(val)) {
      score -= 0.65;
      reasons.add('Person name contains corporate entity tokens (e.g. Ltd/Inc/Technologies).');
    }

    if (val.contains(RegExp(r'\d'))) {
      score -= 0.40;
      reasons.add('Person name contains numeric digits.');
    }

    if (cardData.fieldConfidenceStates['fullName'] == 'uncertain') {
      score -= 0.35;
      reasons.add('Flagged as uncertain during layout disambiguation.');
    }

    if (alts.length > 1) {
      score -= 0.25;
      reasons.add('Multiple competing person name candidates were detected (${alts.join(", ")}).');
    }

    final wordCount = val.split(RegExp(r'\s+')).length;
    if (wordCount >= 2 && wordCount <= 4) {
      score += 0.10;
      evidence.add('Standard 2-4 word name pattern.');
    }

    score = score.clamp(0.0, 1.0);
    final level = score >= 0.80
        ? FieldConfidenceLevel.high
        : (score >= 0.50 ? FieldConfidenceLevel.medium : FieldConfidenceLevel.low);

    return FieldConfidenceDetail(
      fieldName: 'fullName',
      level: level,
      score: score,
      extractedValue: val,
      evidence: evidence,
      alternativeCandidates: alts,
      uncertaintyReasons: reasons,
    );
  }

  FieldConfidenceDetail _evaluateCompany(BusinessCardData cardData) {
    final val = cardData.company?.trim() ?? '';
    final alts = cardData.alternativeCandidates['company'] ?? const [];
    final reasons = <String>[];
    final evidence = <String>[];

    if (val.isEmpty) {
      return FieldConfidenceDetail(
        fieldName: 'company',
        level: FieldConfidenceLevel.low,
        score: 0.0,
        uncertaintyReasons: ['Company name was not detected.'],
        alternativeCandidates: alts,
      );
    }

    evidence.add('Extracted: "$val"');
    double score = 0.80;

    if (_honorificPrefixRegExp.hasMatch(val)) {
      score -= 0.50;
      reasons.add('Company begins with personal honorific prefix (e.g. Dr./Mr.).');
    }

    if (_businessEntityRegExp.hasMatch(val)) {
      score += 0.15;
      evidence.add('Contains recognized legal corporate suffix.');
    }

    if (cardData.fieldConfidenceStates['company'] == 'uncertain') {
      score -= 0.20;
      reasons.add('Flagged as uncertain during layout parsing.');
    }

    score = score.clamp(0.0, 1.0);
    final level = score >= 0.80
        ? FieldConfidenceLevel.high
        : (score >= 0.50 ? FieldConfidenceLevel.medium : FieldConfidenceLevel.low);

    return FieldConfidenceDetail(
      fieldName: 'company',
      level: level,
      score: score,
      extractedValue: val,
      evidence: evidence,
      alternativeCandidates: alts,
      uncertaintyReasons: reasons,
    );
  }

  FieldConfidenceDetail _evaluateJobTitle(BusinessCardData cardData) {
    final val = cardData.jobTitle?.trim() ?? '';
    final alts = cardData.alternativeCandidates['jobTitle'] ?? const [];
    final reasons = <String>[];
    final evidence = <String>[];

    if (val.isEmpty) {
      return FieldConfidenceDetail(
        fieldName: 'jobTitle',
        level: FieldConfidenceLevel.medium, // Optional field
        score: 0.50,
        alternativeCandidates: alts,
      );
    }

    double score = 0.75;
    if (_knownJobTitleTaxonomy.hasMatch(val)) {
      score += 0.20;
      evidence.add('Matches professional title vocabulary.');
    }

    if (val.length > 55) {
      score -= 0.35;
      reasons.add('Job title text is unusually long; may be merged with slogan or address.');
    }

    score = score.clamp(0.0, 1.0);
    final level = score >= 0.80
        ? FieldConfidenceLevel.high
        : (score >= 0.50 ? FieldConfidenceLevel.medium : FieldConfidenceLevel.low);

    return FieldConfidenceDetail(
      fieldName: 'jobTitle',
      level: level,
      score: score,
      extractedValue: val,
      evidence: evidence,
      alternativeCandidates: alts,
      uncertaintyReasons: reasons,
    );
  }

  FieldConfidenceDetail _evaluatePhoneNumbers(BusinessCardData cardData) {
    final phones = cardData.phoneNumbers;
    final reasons = <String>[];
    final evidence = <String>[];

    if (phones.isEmpty) {
      return const FieldConfidenceDetail(
        fieldName: 'phoneNumbers',
        level: FieldConfidenceLevel.low,
        score: 0.20,
        uncertaintyReasons: ['No phone numbers found on the card.'],
      );
    }

    int validCount = 0;
    for (final p in phones) {
      final digits = p.number.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 7 && digits.length <= 15) {
        validCount++;
        evidence.add('Valid phone: ${p.number} (${digits.length} digits)');
      } else {
        reasons.add('Phone "${p.number}" has abnormal digit length (${digits.length}).');
      }
    }

    final double score = validCount > 0 ? 0.90 : 0.40;
    final level = score >= 0.80 ? FieldConfidenceLevel.high : FieldConfidenceLevel.medium;

    return FieldConfidenceDetail(
      fieldName: 'phoneNumbers',
      level: level,
      score: score,
      extractedValue: phones.map((p) => p.number).join(', '),
      evidence: evidence,
      uncertaintyReasons: reasons,
    );
  }

  FieldConfidenceDetail _evaluateEmailAddresses(BusinessCardData cardData) {
    final emails = cardData.emailAddresses;
    final reasons = <String>[];
    final evidence = <String>[];

    if (emails.isEmpty) {
      return const FieldConfidenceDetail(
        fieldName: 'emailAddresses',
        level: FieldConfidenceLevel.low,
        score: 0.20,
        uncertaintyReasons: ['No email address found on card.'],
      );
    }

    final emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    int validCount = 0;

    for (final e in emails) {
      if (emailRegExp.hasMatch(e.email.trim())) {
        validCount++;
        evidence.add('Valid RFC-like email: ${e.email}');
      } else {
        reasons.add('Email "${e.email}" appears malformed.');
      }
    }

    final double score = validCount > 0 ? 0.95 : 0.35;
    final level = score >= 0.80 ? FieldConfidenceLevel.high : FieldConfidenceLevel.low;

    return FieldConfidenceDetail(
      fieldName: 'emailAddresses',
      level: level,
      score: score,
      extractedValue: emails.map((e) => e.email).join(', '),
      evidence: evidence,
      uncertaintyReasons: reasons,
    );
  }

  FieldConfidenceDetail _evaluateWebsite(BusinessCardData cardData) {
    final val = cardData.website?.trim() ?? '';
    if (val.isEmpty) {
      return const FieldConfidenceDetail(
        fieldName: 'website',
        level: FieldConfidenceLevel.medium,
        score: 0.60,
      );
    }

    final hasDot = val.contains('.');
    final score = hasDot ? 0.90 : 0.40;
    return FieldConfidenceDetail(
      fieldName: 'website',
      level: score >= 0.80 ? FieldConfidenceLevel.high : FieldConfidenceLevel.low,
      score: score,
      extractedValue: val,
      evidence: ['Extracted website: $val'],
      uncertaintyReasons: hasDot ? const [] : ['Website is missing standard top-level domain.'],
    );
  }

  FieldConfidenceDetail _evaluateAddress(BusinessCardData cardData) {
    final val = cardData.address?.trim() ?? '';
    final reasons = <String>[];
    final evidence = <String>[];

    if (val.isEmpty) {
      return const FieldConfidenceDetail(
        fieldName: 'address',
        level: FieldConfidenceLevel.medium,
        score: 0.50,
      );
    }

    double score = 0.75;
    evidence.add('Extracted address length: ${val.length}');

    if (_businessEntityRegExp.hasMatch(val)) {
      score -= 0.40;
      reasons.add('Address contains legal corporate entity tokens; likely contaminated.');
    }

    if (cardData.fieldConfidenceStates['address'] == 'uncertain') {
      score -= 0.20;
      reasons.add('Flagged as uncertain during layout parsing.');
    }

    score = score.clamp(0.0, 1.0);
    final level = score >= 0.75
        ? FieldConfidenceLevel.high
        : (score >= 0.45 ? FieldConfidenceLevel.medium : FieldConfidenceLevel.low);

    return FieldConfidenceDetail(
      fieldName: 'address',
      level: level,
      score: score,
      extractedValue: val,
      evidence: evidence,
      uncertaintyReasons: reasons,
    );
  }
}
