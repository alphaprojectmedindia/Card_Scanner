import 'business_card_data.dart';
import 'business_card_email.dart';
import 'business_card_phone.dart';
import 'field_evidence.dart';
import 'ocr_side_result.dart';

/// Structured response model from the backend Gemini Card Analysis service.
class CardAnalysisResult {
  final String clientRequestId;
  final String analysisCacheKey;
  final ExtractedField? fullName;
  final ExtractedField? company;
  final ExtractedField? jobTitle;
  final ExtractedAddress? address;
  final List<ExtractedPhone> phoneNumbers;
  final List<ExtractedEmail> emailAddresses;
  final List<ExtractedWebsite> websites;
  final String? department;
  final String? credentials;
  final List<String> unclassifiedLines;
  final double overallConfidence;
  final bool requiresManualReview;
  final List<String> reviewWarnings;
  final String modelId;
  final bool fromCache;
  final int processingDurationMs;
  final bool fallbackToLocalBaseline;
  final bool visualVerificationPerformed;
  final bool frontImageVerified;
  final bool backImageVerified;
  final String? imageVerificationFailureReason;
  final Map<String, FieldVerificationResult> fieldVerifications;
  final bool geminiApiExecuted;
  final String geminiExecutionStatus;
  final bool frontImageReceived;
  final bool backImageReceived;
  final int? promptTokens;
  final int? candidateTokens;
  final int? totalTokens;

  const CardAnalysisResult({
    required this.clientRequestId,
    required this.analysisCacheKey,
    this.fullName,
    this.company,
    this.jobTitle,
    this.address,
    this.phoneNumbers = const [],
    this.emailAddresses = const [],
    this.websites = const [],
    this.department,
    this.credentials,
    this.unclassifiedLines = const [],
    this.overallConfidence = 1.0,
    this.requiresManualReview = false,
    this.reviewWarnings = const [],
    this.modelId = '',
    this.fromCache = false,
    this.processingDurationMs = 0,
    this.fallbackToLocalBaseline = false,
    this.visualVerificationPerformed = false,
    this.frontImageVerified = false,
    this.backImageVerified = false,
    this.imageVerificationFailureReason,
    this.fieldVerifications = const {},
    this.geminiApiExecuted = false,
    this.geminiExecutionStatus = '',
    this.frontImageReceived = false,
    this.backImageReceived = false,
    this.promptTokens,
    this.candidateTokens,
    this.totalTokens,
  });

  factory CardAnalysisResult.fromJson(Map<String, dynamic> json) {
    Map<String, FieldVerificationResult> parseFieldVerifications(dynamic raw) {
      if (raw is! Map<String, dynamic>) return const {};
      return raw.map((k, v) => MapEntry(
            k,
            FieldVerificationResult.fromJson(v as Map<String, dynamic>),
          ));
    }

    final usage = json['usageMetadata'] as Map<String, dynamic>?;

    return CardAnalysisResult(
      clientRequestId: json['clientRequestId'] as String? ?? '',
      analysisCacheKey: json['analysisCacheKey'] as String? ?? '',
      fullName: json['fullName'] != null
          ? ExtractedField.fromJson(json['fullName'] as Map<String, dynamic>)
          : null,
      company: json['company'] != null
          ? ExtractedField.fromJson(json['company'] as Map<String, dynamic>)
          : null,
      jobTitle: json['jobTitle'] != null
          ? ExtractedField.fromJson(json['jobTitle'] as Map<String, dynamic>)
          : null,
      address: json['address'] != null
          ? ExtractedAddress.fromJson(json['address'] as Map<String, dynamic>)
          : null,
      phoneNumbers: (json['phoneNumbers'] as List<dynamic>?)
              ?.map((p) => ExtractedPhone.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
      emailAddresses: (json['emailAddresses'] as List<dynamic>?)
              ?.map((e) => ExtractedEmail.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      websites: (json['websites'] as List<dynamic>?)
              ?.map((w) => ExtractedWebsite.fromJson(w as Map<String, dynamic>))
              .toList() ??
          const [],
      department: json['department'] as String?,
      credentials: json['credentials'] as String?,
      unclassifiedLines: (json['unclassifiedLines'] as List<dynamic>?)
              ?.map((l) => l.toString())
              .toList() ??
          const [],
      overallConfidence: (json['overallConfidence'] as num?)?.toDouble() ?? 1.0,
      requiresManualReview: json['requiresManualReview'] as bool? ?? false,
      reviewWarnings: (json['reviewWarnings'] as List<dynamic>?)
              ?.map((w) => w.toString())
              .toList() ??
          const [],
      modelId: json['modelId'] as String? ?? '',
      fromCache: json['fromCache'] as bool? ?? false,
      processingDurationMs:
          (json['processingDurationMs'] as num?)?.toInt() ?? 0,
      fallbackToLocalBaseline:
          json['fallbackToLocalBaseline'] as bool? ?? false,
      visualVerificationPerformed:
          json['visualVerificationPerformed'] as bool? ?? false,
      frontImageVerified: json['frontImageVerified'] as bool? ?? false,
      backImageVerified: json['backImageVerified'] as bool? ?? false,
      imageVerificationFailureReason:
          json['imageVerificationFailureReason'] as String?,
      fieldVerifications:
          parseFieldVerifications(json['fieldVerifications']),
      geminiApiExecuted: json['geminiApiExecuted'] as bool? ?? false,
      geminiExecutionStatus: json['geminiExecutionStatus'] as String? ?? '',
      frontImageReceived: json['frontImageReceived'] as bool? ?? false,
      backImageReceived: json['backImageReceived'] as bool? ?? false,
      promptTokens: (usage?['promptTokenCount'] as num?)?.toInt() ??
          (json['promptTokens'] as num?)?.toInt(),
      candidateTokens: (usage?['candidatesTokenCount'] as num?)?.toInt() ??
          (json['candidateTokens'] as num?)?.toInt(),
      totalTokens: (usage?['totalTokenCount'] as num?)?.toInt() ??
          (json['totalTokens'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'clientRequestId': clientRequestId,
      'analysisCacheKey': analysisCacheKey,
      if (fullName != null) 'fullName': fullName!.toJson(),
      if (company != null) 'company': company!.toJson(),
      if (jobTitle != null) 'jobTitle': jobTitle!.toJson(),
      if (address != null) 'address': address!.toJson(),
      'phoneNumbers': phoneNumbers.map((p) => p.toJson()).toList(),
      'emailAddresses': emailAddresses.map((e) => e.toJson()).toList(),
      'websites': websites.map((w) => w.toJson()).toList(),
      if (department != null) 'department': department,
      if (credentials != null) 'credentials': credentials,
      'unclassifiedLines': unclassifiedLines,
      'overallConfidence': overallConfidence,
      'requiresManualReview': requiresManualReview,
      'reviewWarnings': reviewWarnings,
      'modelId': modelId,
      'fromCache': fromCache,
      'processingDurationMs': processingDurationMs,
      'fallbackToLocalBaseline': fallbackToLocalBaseline,
      'visualVerificationPerformed': visualVerificationPerformed,
      'frontImageVerified': frontImageVerified,
      'backImageVerified': backImageVerified,
      if (imageVerificationFailureReason != null)
        'imageVerificationFailureReason': imageVerificationFailureReason,
      'fieldVerifications':
          fieldVerifications.map((k, v) => MapEntry(k, v.toJson())),
      'geminiApiExecuted': geminiApiExecuted,
      'geminiExecutionStatus': geminiExecutionStatus,
      'frontImageReceived': frontImageReceived,
      'backImageReceived': backImageReceived,
      if (promptTokens != null) 'promptTokens': promptTokens,
      if (candidateTokens != null) 'candidateTokens': candidateTokens,
      if (totalTokens != null) 'totalTokens': totalTokens,
    };
  }

  /// Non-destructively merges the AI analysis result into the local baseline [BusinessCardData].
  /// Preserves evidence and flags fields requiring user verification.
  BusinessCardData toBusinessCardData(BusinessCardData baseline) {
    if (fallbackToLocalBaseline) {
      return baseline;
    }

    // Merge names, respecting Gemini's visual verification status
    String? resolvedFullName;
    if (fullName != null) {
      if (fullName!.verificationStatus == 'notFound' || fullName!.verificationStatus == 'rejected') {
        // Visually confirmed not to be a person name or absent from card
        resolvedFullName = (fullName!.proposedValue != null && fullName!.proposedValue!.trim().isNotEmpty)
            ? fullName!.proposedValue!.trim()
            : null;
      } else if (fullName!.value != null && fullName!.value!.trim().isNotEmpty) {
        resolvedFullName = fullName!.value!.trim();
      } else if (fullName!.proposedValue != null && fullName!.proposedValue!.trim().isNotEmpty) {
        resolvedFullName = fullName!.proposedValue!.trim();
      } else {
        resolvedFullName = baseline.fullName;
      }
    } else {
      resolvedFullName = baseline.fullName;
    }

    String? resolvedCompany;
    if (company != null) {
      if (company!.verificationStatus == 'notFound') {
        resolvedCompany = null;
      } else if (company!.value != null && company!.value!.trim().isNotEmpty) {
        resolvedCompany = company!.value!.trim();
      } else if (company!.proposedValue != null && company!.proposedValue!.trim().isNotEmpty) {
        resolvedCompany = company!.proposedValue!.trim();
      } else {
        resolvedCompany = baseline.company;
      }
    } else {
      resolvedCompany = baseline.company;
    }

    final resolvedJobTitle = (jobTitle?.value != null && jobTitle!.value!.trim().isNotEmpty)
        ? jobTitle!.value!.trim()
        : baseline.jobTitle;

    // Safe, normalized union merging for phone numbers
    final mergedPhones = <BusinessCardPhone>[];
    final seenPhoneDigits = <String>{};

    String normalizePhoneDigits(String num) =>
        num.replaceAll(RegExp(r'\D'), '');

    for (final basePhone in baseline.phoneNumbers) {
      final digits = normalizePhoneDigits(basePhone.number);
      if (digits.length >= 7) {
        if (!seenPhoneDigits.contains(digits)) {
          seenPhoneDigits.add(digits);
          mergedPhones.add(basePhone);
        }
      } else if (basePhone.number.trim().isNotEmpty) {
        mergedPhones.add(basePhone);
      }
    }

    for (final aiPhone in phoneNumbers) {
      final trimmedNum = aiPhone.number.trim();
      if (trimmedNum.isEmpty) continue;
      final digits = normalizePhoneDigits(trimmedNum);
      if (digits.length >= 7) {
        final existingIndex = mergedPhones.indexWhere(
          (p) => normalizePhoneDigits(p.number) == digits,
        );
        if (existingIndex >= 0) {
          final existing = mergedPhones[existingIndex];
          final existingLabel = existing.label;
          final aiLabel = aiPhone.label;
          if ((existingLabel == null || existingLabel.isEmpty || existingLabel == 'Phone') &&
              aiLabel.trim().isNotEmpty) {
            mergedPhones[existingIndex] = BusinessCardPhone(
              number: existing.number,
              label: aiLabel.trim(),
            );
          }
        } else {
          seenPhoneDigits.add(digits);
          mergedPhones.add(BusinessCardPhone(
            number: trimmedNum,
            label: aiPhone.label,
          ));
        }
      } else if (!mergedPhones.any((p) => p.number == trimmedNum)) {
        mergedPhones.add(BusinessCardPhone(
          number: trimmedNum,
          label: aiPhone.label,
        ));
      }
    }

    // Safe, normalized union merging for email addresses
    final mergedEmails = <BusinessCardEmail>[];
    final seenEmails = <String>{};

    for (final baseEmail in baseline.emailAddresses) {
      final normalized = baseEmail.email.trim().toLowerCase();
      if (normalized.isNotEmpty && !seenEmails.contains(normalized)) {
        seenEmails.add(normalized);
        mergedEmails.add(baseEmail);
      }
    }

    for (final aiEmail in emailAddresses) {
      final trimmedEmail = aiEmail.email.trim();
      if (trimmedEmail.isEmpty) continue;
      final normalized = trimmedEmail.toLowerCase();
      final existingIndex = mergedEmails.indexWhere(
        (e) => e.email.trim().toLowerCase() == normalized,
      );
      if (existingIndex >= 0) {
        final existing = mergedEmails[existingIndex];
        final existingLabel = existing.label;
        final aiLabel = aiEmail.label;
        if ((existingLabel == null || existingLabel.isEmpty) &&
            aiLabel.trim().isNotEmpty) {
          mergedEmails[existingIndex] = BusinessCardEmail(
            email: existing.email,
            label: aiLabel.trim(),
          );
        }
      } else {
        seenEmails.add(normalized);
        mergedEmails.add(BusinessCardEmail(
          email: trimmedEmail,
          label: aiEmail.label,
        ));
      }
    }

    List<BusinessCardPhone> resolvedPhones = mergedPhones;
    List<BusinessCardEmail> resolvedEmails = mergedEmails;

    // Merge website
    String? resolvedWebsite = baseline.website;
    if (websites.isNotEmpty && websites.first.url.trim().isNotEmpty) {
      resolvedWebsite = websites.first.url.trim();
    }

    // Merge address
    String? resolvedAddress = baseline.address;
    if (address?.fullAddress != null && address!.fullAddress!.trim().isNotEmpty) {
      resolvedAddress = address!.fullAddress!.trim();
    }

    // Build field confidence states
    final updatedConfidence = Map<String, String>.from(baseline.fieldConfidenceStates);

    if (resolvedFullName != null && resolvedFullName.isNotEmpty) {
      final isRev = fullName?.reviewRequired ?? false;
      final conf = fullName?.confidence ?? 0.9;
      updatedConfidence['fullName'] = (isRev || conf < 0.75) ? 'uncertain' : 'highConfidence';
    }

    if (resolvedCompany != null && resolvedCompany.isNotEmpty) {
      final isRev = company?.reviewRequired ?? false;
      final conf = company?.confidence ?? 0.9;
      updatedConfidence['company'] = (isRev || conf < 0.75) ? 'uncertain' : 'highConfidence';
    }

    if (resolvedJobTitle != null && resolvedJobTitle.isNotEmpty) {
      final isRev = jobTitle?.reviewRequired ?? false;
      final conf = jobTitle?.confidence ?? 0.9;
      updatedConfidence['jobTitle'] = (isRev || conf < 0.75) ? 'uncertain' : 'highConfidence';
    }

    if (resolvedAddress != null && resolvedAddress.isNotEmpty) {
      final isRev = address?.reviewRequired ?? false;
      final conf = address?.confidence ?? 0.9;
      updatedConfidence['address'] = (isRev || conf < 0.75) ? 'uncertain' : 'highConfidence';
    }

    // Stage 4: Update FieldEvidence with visual verification ground truth
    final updatedEvidence = Map<String, FieldEvidence>.from(baseline.fieldEvidence);

    void updateEvidenceForField({
      required String fieldName,
      required String? resolvedValue,
      required ExtractedField? extractedField,
      required double defaultConfidence,
    }) {
      final existingEv = updatedEvidence[fieldName];

      // Negative Constraint: Never overwrite user-approved value!
      if (existingEv != null && existingEv.userApprovedValue != null && existingEv.userApprovedValue!.trim().isNotEmpty) {
        return;
      }

      final isVisuallyConfirmed = visualVerificationPerformed && (extractedField?.isVisuallyVerified ?? false);
      final fieldReview = extractedField?.reviewRequired ?? (extractedField == null);
      final fieldConf = extractedField?.confidence ?? defaultConfidence;

      FieldVerificationStatus status;
      if (resolvedValue == null || resolvedValue.trim().isEmpty) {
        status = FieldVerificationStatus.notFound;
      } else if (isVisuallyConfirmed && !fieldReview) {
        status = FieldVerificationStatus.verified;
      } else if (fieldReview || fieldConf < 0.75) {
        status = FieldVerificationStatus.reviewRequired;
      } else {
        status = FieldVerificationStatus.probable;
      }

      final side = (extractedField?.supportingCardSide.toLowerCase() == 'back') ? CardSide.back : CardSide.front;

      updatedEvidence[fieldName] = FieldEvidence(
        fieldName: fieldName,
        originalOcrText: existingEv?.originalOcrText ?? extractedField?.rawEvidence ?? (resolvedValue ?? ''),
        normalizedValue: resolvedValue ?? '',
        sourceEngine: isVisuallyConfirmed ? 'Gemini Multimodal Vision' : (existingEv?.sourceEngine ?? 'Gemini TextAndLayout'),
        sourceObservationIds: extractedField?.sourceObservationIds ?? (existingEv?.sourceObservationIds ?? const []),
        boundingBoxes: existingEv?.boundingBoxes ?? const [],
        ocrConfidence: existingEv?.ocrConfidence ?? fieldConf,
        parserConfidence: fieldConf,
        verificationStatus: status,
        userApprovedValue: existingEv?.userApprovedValue,
        verificationSource: isVisuallyConfirmed
            ? 'geminiAiVisualVerification'
            : (visualVerificationPerformed ? 'geminiAiVisionProbable' : 'geminiAiTextVerification'),
        verifiedAt: isVisuallyConfirmed ? DateTime.now().toUtc() : existingEv?.verifiedAt,
        uncertaintyReason: fieldReview ? (extractedField?.correctionReason ?? 'Flagged for visual inspection') : null,
        side: side,
        processingVersion: '4.0.0',
      );
    }

    updateEvidenceForField(
      fieldName: 'fullName',
      resolvedValue: resolvedFullName,
      extractedField: fullName,
      defaultConfidence: 0.90,
    );

    updateEvidenceForField(
      fieldName: 'company',
      resolvedValue: resolvedCompany,
      extractedField: company,
      defaultConfidence: 0.90,
    );

    updateEvidenceForField(
      fieldName: 'jobTitle',
      resolvedValue: resolvedJobTitle,
      extractedField: jobTitle,
      defaultConfidence: 0.90,
    );

    // Build notes
    final notes = List<String>.from(baseline.parsingNotes);
    final visualTag = visualVerificationPerformed
        ? '(Visual Verification Performed: front=$frontImageVerified, back=$backImageVerified)'
        : '(Text-Only Analysis; Visual Verification Not Performed)';
    notes.add(
      'Gemini AI analysis applied $visualTag [Model: $modelId, Cached: $fromCache, Confidence: ${(overallConfidence * 100).toStringAsFixed(0)}%]',
    );
    for (final warning in reviewWarnings) {
      notes.add('[Review Warning] $warning');
    }

    return BusinessCardData(
      fullName: resolvedFullName,
      company: resolvedCompany,
      jobTitle: resolvedJobTitle,
      phoneNumbers: resolvedPhones,
      emailAddresses: resolvedEmails,
      website: resolvedWebsite,
      address: resolvedAddress,
      rawRecognizedText: baseline.rawRecognizedText,
      alternativeCandidates: baseline.alternativeCandidates,
      parsingNotes: notes,
      isDualSided: baseline.isDualSided,
      frontRawText: baseline.frontRawText,
      backRawText: baseline.backRawText,
      fieldConfidenceStates: updatedConfidence,
      fieldEvidence: updatedEvidence,
      unclassifiedLines: unclassifiedLines.isNotEmpty
          ? unclassifiedLines
          : baseline.unclassifiedLines,
      recoveredObservations: baseline.recoveredObservations,
    );
  }
}

class FieldVerificationResult {
  final String fieldName;
  final String? proposedValue;
  final String? originalLocalParserValue;
  final String supportingCardSide;
  final String? visualEvidenceDescription;
  final FieldVerificationStatus verificationStatus;
  final String? correctionReason;
  final bool isGenuinelyReadable;
  final bool isVisuallyVerified;
  final double confidence;
  final List<String> sourceObservationIds;
  final bool wasCorrected;
  final bool reviewRequired;

  const FieldVerificationResult({
    required this.fieldName,
    this.proposedValue,
    this.originalLocalParserValue,
    this.supportingCardSide = 'front',
    this.visualEvidenceDescription,
    this.verificationStatus = FieldVerificationStatus.probable,
    this.correctionReason,
    this.isGenuinelyReadable = true,
    this.isVisuallyVerified = false,
    this.confidence = 1.0,
    this.sourceObservationIds = const [],
    this.wasCorrected = false,
    this.reviewRequired = false,
  });

  factory FieldVerificationResult.fromJson(Map<String, dynamic> json) {
    return FieldVerificationResult(
      fieldName: json['fieldName'] as String? ?? '',
      proposedValue: json['proposedValue'] as String?,
      originalLocalParserValue: json['originalLocalParserValue'] as String?,
      supportingCardSide: json['supportingCardSide'] as String? ?? 'front',
      visualEvidenceDescription: json['visualEvidenceDescription'] as String?,
      verificationStatus:
          FieldVerificationStatus.fromString(json['verificationStatus'] as String?),
      correctionReason: json['correctionReason'] as String?,
      isGenuinelyReadable: json['isGenuinelyReadable'] as bool? ?? true,
      isVisuallyVerified: json['isVisuallyVerified'] as bool? ?? false,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      sourceObservationIds: (json['sourceObservationIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      wasCorrected: json['wasCorrected'] as bool? ?? false,
      reviewRequired: json['reviewRequired'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fieldName': fieldName,
      if (proposedValue != null) 'proposedValue': proposedValue,
      if (originalLocalParserValue != null)
        'originalLocalParserValue': originalLocalParserValue,
      'supportingCardSide': supportingCardSide,
      if (visualEvidenceDescription != null)
        'visualEvidenceDescription': visualEvidenceDescription,
      'verificationStatus': verificationStatus.name,
      if (correctionReason != null) 'correctionReason': correctionReason,
      'isGenuinelyReadable': isGenuinelyReadable,
      'isVisuallyVerified': isVisuallyVerified,
      'confidence': confidence,
      'sourceObservationIds': sourceObservationIds,
      'wasCorrected': wasCorrected,
      'reviewRequired': reviewRequired,
    };
  }
}

class ExtractedField {
  final String? value;
  final double confidence;
  final String? rawEvidence;
  final List<String> sourceObservationIds;
  final bool wasCorrected;
  final bool reviewRequired;
  final String? proposedValue;
  final String? originalLocalParserValue;
  final String supportingCardSide;
  final String? visualEvidenceDescription;
  final String verificationStatus;
  final String? correctionReason;
  final bool? isGenuinelyReadable;
  final bool isVisuallyVerified;

  const ExtractedField({
    this.value,
    this.confidence = 1.0,
    this.rawEvidence,
    this.sourceObservationIds = const [],
    this.wasCorrected = false,
    this.reviewRequired = false,
    this.proposedValue,
    this.originalLocalParserValue,
    this.supportingCardSide = 'front',
    this.visualEvidenceDescription,
    this.verificationStatus = 'probable',
    this.correctionReason,
    this.isGenuinelyReadable = true,
    this.isVisuallyVerified = false,
  });

  factory ExtractedField.fromJson(Map<String, dynamic> json) {
    return ExtractedField(
      value: json['value'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      rawEvidence: json['rawEvidence'] as String?,
      sourceObservationIds: (json['sourceObservationIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      wasCorrected: json['wasCorrected'] as bool? ?? false,
      reviewRequired: json['reviewRequired'] as bool? ?? false,
      proposedValue: json['proposedValue'] as String?,
      originalLocalParserValue: json['originalLocalParserValue'] as String?,
      supportingCardSide: json['supportingCardSide'] as String? ?? 'front',
      visualEvidenceDescription: json['visualEvidenceDescription'] as String?,
      verificationStatus: json['verificationStatus'] as String? ?? 'probable',
      correctionReason: json['correctionReason'] as String?,
      isGenuinelyReadable: json['isGenuinelyReadable'] as bool? ?? true,
      isVisuallyVerified: json['isVisuallyVerified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (value != null) 'value': value,
      'confidence': confidence,
      if (rawEvidence != null) 'rawEvidence': rawEvidence,
      'sourceObservationIds': sourceObservationIds,
      'wasCorrected': wasCorrected,
      'reviewRequired': reviewRequired,
      if (proposedValue != null) 'proposedValue': proposedValue,
      if (originalLocalParserValue != null)
        'originalLocalParserValue': originalLocalParserValue,
      'supportingCardSide': supportingCardSide,
      if (visualEvidenceDescription != null)
        'visualEvidenceDescription': visualEvidenceDescription,
      'verificationStatus': verificationStatus,
      if (correctionReason != null) 'correctionReason': correctionReason,
      if (isGenuinelyReadable != null)
        'isGenuinelyReadable': isGenuinelyReadable,
      'isVisuallyVerified': isVisuallyVerified,
    };
  }
}

class ExtractedPhone {
  final String number;
  final String normalizedNumber;
  final String label;
  final double confidence;
  final String? rawEvidence;
  final List<String> sourceObservationIds;
  final bool reviewRequired;
  final String? proposedValue;
  final String? originalLocalParserValue;
  final String supportingCardSide;
  final String? visualEvidenceDescription;
  final String verificationStatus;
  final String? correctionReason;
  final bool? isGenuinelyReadable;
  final bool isVisuallyVerified;
  final bool wasCorrected;

  const ExtractedPhone({
    required this.number,
    this.normalizedNumber = '',
    this.label = 'Mobile',
    this.confidence = 1.0,
    this.rawEvidence,
    this.sourceObservationIds = const [],
    this.reviewRequired = false,
    this.proposedValue,
    this.originalLocalParserValue,
    this.supportingCardSide = 'front',
    this.visualEvidenceDescription,
    this.verificationStatus = 'probable',
    this.correctionReason,
    this.isGenuinelyReadable = true,
    this.isVisuallyVerified = false,
    this.wasCorrected = false,
  });

  factory ExtractedPhone.fromJson(Map<String, dynamic> json) {
    return ExtractedPhone(
      number: json['number'] as String? ?? '',
      normalizedNumber: json['normalizedNumber'] as String? ?? '',
      label: json['label'] as String? ?? 'Mobile',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      rawEvidence: json['rawEvidence'] as String?,
      sourceObservationIds: (json['sourceObservationIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      reviewRequired: json['reviewRequired'] as bool? ?? false,
      proposedValue: json['proposedValue'] as String?,
      originalLocalParserValue: json['originalLocalParserValue'] as String?,
      supportingCardSide: json['supportingCardSide'] as String? ?? 'front',
      visualEvidenceDescription: json['visualEvidenceDescription'] as String?,
      verificationStatus: json['verificationStatus'] as String? ?? 'probable',
      correctionReason: json['correctionReason'] as String?,
      isGenuinelyReadable: json['isGenuinelyReadable'] as bool? ?? true,
      isVisuallyVerified: json['isVisuallyVerified'] as bool? ?? false,
      wasCorrected: json['wasCorrected'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'normalizedNumber': normalizedNumber,
      'label': label,
      'confidence': confidence,
      if (rawEvidence != null) 'rawEvidence': rawEvidence,
      'sourceObservationIds': sourceObservationIds,
      'reviewRequired': reviewRequired,
      if (proposedValue != null) 'proposedValue': proposedValue,
      if (originalLocalParserValue != null)
        'originalLocalParserValue': originalLocalParserValue,
      'supportingCardSide': supportingCardSide,
      if (visualEvidenceDescription != null)
        'visualEvidenceDescription': visualEvidenceDescription,
      'verificationStatus': verificationStatus,
      if (correctionReason != null) 'correctionReason': correctionReason,
      if (isGenuinelyReadable != null)
        'isGenuinelyReadable': isGenuinelyReadable,
      'isVisuallyVerified': isVisuallyVerified,
      'wasCorrected': wasCorrected,
    };
  }
}

class ExtractedEmail {
  final String email;
  final String normalizedEmail;
  final String label;
  final double confidence;
  final String? rawEvidence;
  final List<String> sourceObservationIds;
  final bool reviewRequired;
  final String? proposedValue;
  final String? originalLocalParserValue;
  final String supportingCardSide;
  final String? visualEvidenceDescription;
  final String verificationStatus;
  final String? correctionReason;
  final bool? isGenuinelyReadable;
  final bool isVisuallyVerified;
  final bool wasCorrected;

  const ExtractedEmail({
    required this.email,
    this.normalizedEmail = '',
    this.label = 'Work',
    this.confidence = 1.0,
    this.rawEvidence,
    this.sourceObservationIds = const [],
    this.reviewRequired = false,
    this.proposedValue,
    this.originalLocalParserValue,
    this.supportingCardSide = 'front',
    this.visualEvidenceDescription,
    this.verificationStatus = 'probable',
    this.correctionReason,
    this.isGenuinelyReadable = true,
    this.isVisuallyVerified = false,
    this.wasCorrected = false,
  });

  factory ExtractedEmail.fromJson(Map<String, dynamic> json) {
    return ExtractedEmail(
      email: json['email'] as String? ?? '',
      normalizedEmail: json['normalizedEmail'] as String? ?? '',
      label: json['label'] as String? ?? 'Work',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      rawEvidence: json['rawEvidence'] as String?,
      sourceObservationIds: (json['sourceObservationIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      reviewRequired: json['reviewRequired'] as bool? ?? false,
      proposedValue: json['proposedValue'] as String?,
      originalLocalParserValue: json['originalLocalParserValue'] as String?,
      supportingCardSide: json['supportingCardSide'] as String? ?? 'front',
      visualEvidenceDescription: json['visualEvidenceDescription'] as String?,
      verificationStatus: json['verificationStatus'] as String? ?? 'probable',
      correctionReason: json['correctionReason'] as String?,
      isGenuinelyReadable: json['isGenuinelyReadable'] as bool? ?? true,
      isVisuallyVerified: json['isVisuallyVerified'] as bool? ?? false,
      wasCorrected: json['wasCorrected'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'normalizedEmail': normalizedEmail,
      'label': label,
      'confidence': confidence,
      if (rawEvidence != null) 'rawEvidence': rawEvidence,
      'sourceObservationIds': sourceObservationIds,
      'reviewRequired': reviewRequired,
      if (proposedValue != null) 'proposedValue': proposedValue,
      if (originalLocalParserValue != null)
        'originalLocalParserValue': originalLocalParserValue,
      'supportingCardSide': supportingCardSide,
      if (visualEvidenceDescription != null)
        'visualEvidenceDescription': visualEvidenceDescription,
      'verificationStatus': verificationStatus,
      if (correctionReason != null) 'correctionReason': correctionReason,
      if (isGenuinelyReadable != null)
        'isGenuinelyReadable': isGenuinelyReadable,
      'isVisuallyVerified': isVisuallyVerified,
      'wasCorrected': wasCorrected,
    };
  }
}

class ExtractedWebsite {
  final String url;
  final double confidence;
  final String? rawEvidence;
  final List<String> sourceObservationIds;
  final String? proposedValue;
  final String? originalLocalParserValue;
  final String supportingCardSide;
  final String? visualEvidenceDescription;
  final String verificationStatus;
  final String? correctionReason;
  final bool? isGenuinelyReadable;
  final bool isVisuallyVerified;
  final bool wasCorrected;

  const ExtractedWebsite({
    required this.url,
    this.confidence = 1.0,
    this.rawEvidence,
    this.sourceObservationIds = const [],
    this.proposedValue,
    this.originalLocalParserValue,
    this.supportingCardSide = 'front',
    this.visualEvidenceDescription,
    this.verificationStatus = 'probable',
    this.correctionReason,
    this.isGenuinelyReadable = true,
    this.isVisuallyVerified = false,
    this.wasCorrected = false,
  });

  factory ExtractedWebsite.fromJson(Map<String, dynamic> json) {
    return ExtractedWebsite(
      url: json['url'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      rawEvidence: json['rawEvidence'] as String?,
      sourceObservationIds: (json['sourceObservationIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      proposedValue: json['proposedValue'] as String?,
      originalLocalParserValue: json['originalLocalParserValue'] as String?,
      supportingCardSide: json['supportingCardSide'] as String? ?? 'front',
      visualEvidenceDescription: json['visualEvidenceDescription'] as String?,
      verificationStatus: json['verificationStatus'] as String? ?? 'probable',
      correctionReason: json['correctionReason'] as String?,
      isGenuinelyReadable: json['isGenuinelyReadable'] as bool? ?? true,
      isVisuallyVerified: json['isVisuallyVerified'] as bool? ?? false,
      wasCorrected: json['wasCorrected'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'confidence': confidence,
      if (rawEvidence != null) 'rawEvidence': rawEvidence,
      'sourceObservationIds': sourceObservationIds,
      if (proposedValue != null) 'proposedValue': proposedValue,
      if (originalLocalParserValue != null)
        'originalLocalParserValue': originalLocalParserValue,
      'supportingCardSide': supportingCardSide,
      if (visualEvidenceDescription != null)
        'visualEvidenceDescription': visualEvidenceDescription,
      'verificationStatus': verificationStatus,
      if (correctionReason != null) 'correctionReason': correctionReason,
      if (isGenuinelyReadable != null)
        'isGenuinelyReadable': isGenuinelyReadable,
      'isVisuallyVerified': isVisuallyVerified,
      'wasCorrected': wasCorrected,
    };
  }
}

class ExtractedAddress {
  final String? fullAddress;
  final String? street;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;
  final double confidence;
  final List<String> sourceObservationIds;
  final bool reviewRequired;
  final String? proposedValue;
  final String? originalLocalParserValue;
  final String supportingCardSide;
  final String? visualEvidenceDescription;
  final String verificationStatus;
  final String? correctionReason;
  final bool? isGenuinelyReadable;
  final bool isVisuallyVerified;
  final bool wasCorrected;

  const ExtractedAddress({
    this.fullAddress,
    this.street,
    this.city,
    this.state,
    this.postalCode,
    this.country,
    this.confidence = 1.0,
    this.sourceObservationIds = const [],
    this.reviewRequired = false,
    this.proposedValue,
    this.originalLocalParserValue,
    this.supportingCardSide = 'front',
    this.visualEvidenceDescription,
    this.verificationStatus = 'probable',
    this.correctionReason,
    this.isGenuinelyReadable = true,
    this.isVisuallyVerified = false,
    this.wasCorrected = false,
  });

  factory ExtractedAddress.fromJson(Map<String, dynamic> json) {
    return ExtractedAddress(
      fullAddress: json['fullAddress'] as String?,
      street: json['street'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      postalCode: json['postalCode'] as String?,
      country: json['country'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      sourceObservationIds: (json['sourceObservationIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      reviewRequired: json['reviewRequired'] as bool? ?? false,
      proposedValue: json['proposedValue'] as String?,
      originalLocalParserValue: json['originalLocalParserValue'] as String?,
      supportingCardSide: json['supportingCardSide'] as String? ?? 'front',
      visualEvidenceDescription: json['visualEvidenceDescription'] as String?,
      verificationStatus: json['verificationStatus'] as String? ?? 'probable',
      correctionReason: json['correctionReason'] as String?,
      isGenuinelyReadable: json['isGenuinelyReadable'] as bool? ?? true,
      isVisuallyVerified: json['isVisuallyVerified'] as bool? ?? false,
      wasCorrected: json['wasCorrected'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (fullAddress != null) 'fullAddress': fullAddress,
      if (street != null) 'street': street,
      if (city != null) 'city': city,
      if (state != null) 'state': state,
      if (postalCode != null) 'postalCode': postalCode,
      if (country != null) 'country': country,
      'confidence': confidence,
      'sourceObservationIds': sourceObservationIds,
      'reviewRequired': reviewRequired,
      if (proposedValue != null) 'proposedValue': proposedValue,
      if (originalLocalParserValue != null)
        'originalLocalParserValue': originalLocalParserValue,
      'supportingCardSide': supportingCardSide,
      if (visualEvidenceDescription != null)
        'visualEvidenceDescription': visualEvidenceDescription,
      'verificationStatus': verificationStatus,
      if (correctionReason != null) 'correctionReason': correctionReason,
      if (isGenuinelyReadable != null)
        'isGenuinelyReadable': isGenuinelyReadable,
      'isVisuallyVerified': isVisuallyVerified,
      'wasCorrected': wasCorrected,
    };
  }
}

