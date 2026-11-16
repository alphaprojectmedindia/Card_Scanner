import '../../models/business_card_data.dart';
import '../../models/business_card_email.dart';
import '../../models/business_card_phone.dart';
import '../../models/card_analysis_result.dart';
import '../../models/field_evidence.dart';
import '../../models/learned_correction.dart';
import '../../models/ocr_side_result.dart';

/// Individual field reconciliation outcome.
class ReconciliationFieldDecision {
  final String fieldName;
  final String? chosenValue;
  final String source; // 'userApprovedCorrection', 'geminiExtraction', 'localParserBaseline', 'hybridConsensus', 'notFound'
  final FieldVerificationStatus verificationStatus;
  final double confidence;
  final bool reviewRequired;
  final String auditReason;
  final List<String> sourceObservationIds;
  final List<String> alternatives;

  const ReconciliationFieldDecision({
    required this.fieldName,
    this.chosenValue,
    required this.source,
    required this.verificationStatus,
    required this.confidence,
    required this.reviewRequired,
    required this.auditReason,
    this.sourceObservationIds = const [],
    this.alternatives = const [],
  });

  Map<String, dynamic> toJson() => {
        'fieldName': fieldName,
        'chosenValue': chosenValue,
        'source': source,
        'verificationStatus': verificationStatus.name,
        'confidence': confidence,
        'reviewRequired': reviewRequired,
        'auditReason': auditReason,
        'sourceObservationIds': sourceObservationIds,
        'alternatives': alternatives,
      };
}

/// Comprehensive outcome of evidence-based multi-source reconciliation.
class GeminiOcrReconciliationResult {
  final BusinessCardData reconciledData;
  final Map<String, ReconciliationFieldDecision> fieldDecisions;
  final List<String> auditTrail;
  final bool requiresReview;
  final bool geminiAssisted;
  final int fieldsCorrectedByGemini;
  final int fieldsDiscoveredByGemini;
  final int userCorrectionsProtected;

  const GeminiOcrReconciliationResult({
    required this.reconciledData,
    required this.fieldDecisions,
    required this.auditTrail,
    required this.requiresReview,
    required this.geminiAssisted,
    required this.fieldsCorrectedByGemini,
    required this.fieldsDiscoveredByGemini,
    required this.userCorrectionsProtected,
  });
}

/// Production Field-by-Field Evidence Reconciliation Engine.
///
/// Harmonizes extraction results across:
/// 1. User-approved corrections (highest precedence, strictly protected).
/// 2. Gemini Multimodal visual extraction (grounded in image pixels and visual evidence).
/// 3. PaddleOCR PP-OCRv5 Mobile (on-device primary OCR engine).
/// 4. Google ML Kit OCR (on-device secondary OCR engine).
/// 5. Local BusinessCardParser baseline.
class GeminiOcrReconciliationEngine {
  const GeminiOcrReconciliationEngine();

  GeminiOcrReconciliationResult reconcile({
    required BusinessCardData localCardData,
    required OcrSideResult frontOcr,
    OcrSideResult? backOcr,
    CardAnalysisResult? geminiResult,
    List<LearnedCorrectionRecord> learnedCorrections = const [],
    String? currentCardFingerprint,
  }) {
    final auditTrail = <String>[];
    final decisions = <String, ReconciliationFieldDecision>{};
    int fieldsCorrected = 0;
    int fieldsDiscovered = 0;
    int userProtected = 0;

    final cardFingerprint = currentCardFingerprint ??
        (frontOcr.metadata['imageHash'] as String?) ??
        (frontOcr.metadata['sha256'] as String?) ??
        (frontOcr.metadata['fingerprint'] as String?);

    final rawAllOcr = '${frontOcr.rawText}\n${backOcr?.rawText ?? ''}'.toLowerCase();
    final bool geminiAvailable = geminiResult != null && !geminiResult.fallbackToLocalBaseline;

    final updatedEvidence = Map<String, FieldEvidence>.from(localCardData.fieldEvidence);
    final updatedConfidenceStates = Map<String, String>.from(localCardData.fieldConfidenceStates);
    final updatedAlternatives = Map<String, List<String>>.from(localCardData.alternativeCandidates);

    // 1. RECONCILE FULL NAME
    final nameDecision = _reconcileScalarField(
      fieldName: 'fullName',
      localValue: localCardData.fullName,
      geminiField: geminiResult?.fullName,
      rawOcrText: rawAllOcr,
      frontOcr: frontOcr,
      backOcr: backOcr,
      geminiAvailable: geminiAvailable,
      learnedCorrections: learnedCorrections,
      currentFingerprint: cardFingerprint,
      isCorporateDisqualified: _isCorporateDisqualified(localCardData.fullName),
    );
    decisions['fullName'] = nameDecision;
    auditTrail.add('[Reconcile:fullName] ${nameDecision.auditReason}');
    if (nameDecision.source == 'userApprovedCorrection') userProtected++;
    if (nameDecision.source == 'geminiExtraction') {
      if (localCardData.fullName == null || localCardData.fullName!.trim().isEmpty) {
        fieldsDiscovered++;
      } else if (nameDecision.chosenValue != localCardData.fullName) {
        fieldsCorrected++;
      }
    }

    // 2. RECONCILE COMPANY
    final companyDecision = _reconcileScalarField(
      fieldName: 'company',
      localValue: localCardData.company,
      geminiField: geminiResult?.company,
      rawOcrText: rawAllOcr,
      frontOcr: frontOcr,
      backOcr: backOcr,
      geminiAvailable: geminiAvailable,
      learnedCorrections: learnedCorrections,
      currentFingerprint: cardFingerprint,
    );
    decisions['company'] = companyDecision;
    auditTrail.add('[Reconcile:company] ${companyDecision.auditReason}');
    if (companyDecision.source == 'userApprovedCorrection') userProtected++;
    if (companyDecision.source == 'geminiExtraction') {
      if (localCardData.company == null || localCardData.company!.trim().isEmpty) {
        fieldsDiscovered++;
      } else if (companyDecision.chosenValue != localCardData.company) {
        fieldsCorrected++;
      }
    }

    // 3. RECONCILE JOB TITLE
    final titleDecision = _reconcileScalarField(
      fieldName: 'jobTitle',
      localValue: localCardData.jobTitle,
      geminiField: geminiResult?.jobTitle,
      rawOcrText: rawAllOcr,
      frontOcr: frontOcr,
      backOcr: backOcr,
      geminiAvailable: geminiAvailable,
      learnedCorrections: learnedCorrections,
      currentFingerprint: cardFingerprint,
    );
    decisions['jobTitle'] = titleDecision;
    auditTrail.add('[Reconcile:jobTitle] ${titleDecision.auditReason}');
    if (titleDecision.source == 'userApprovedCorrection') userProtected++;
    if (titleDecision.source == 'geminiExtraction') {
      if (localCardData.jobTitle == null || localCardData.jobTitle!.trim().isEmpty) {
        fieldsDiscovered++;
      } else if (titleDecision.chosenValue != localCardData.jobTitle) {
        fieldsCorrected++;
      }
    }

    // 4. RECONCILE ADDRESS
    final addressDecision = _reconcileAddress(
      localValue: localCardData.address,
      geminiAddress: geminiResult?.address,
      rawOcrText: rawAllOcr,
      frontOcr: frontOcr,
      backOcr: backOcr,
      geminiAvailable: geminiAvailable,
      learnedCorrections: learnedCorrections,
      currentFingerprint: cardFingerprint,
    );
    decisions['address'] = addressDecision;
    auditTrail.add('[Reconcile:address] ${addressDecision.auditReason}');
    if (addressDecision.source == 'userApprovedCorrection') userProtected++;
    if (addressDecision.source == 'geminiExtraction') {
      if (localCardData.address == null || localCardData.address!.trim().isEmpty) {
        fieldsDiscovered++;
      } else if (addressDecision.chosenValue != localCardData.address) {
        fieldsCorrected++;
      }
    }

    // 5. RECONCILE WEBSITE
    final websiteDecision = _reconcileWebsite(
      localValue: localCardData.website,
      geminiWebsites: geminiResult?.websites,
      rawOcrText: rawAllOcr,
      frontOcr: frontOcr,
      backOcr: backOcr,
      geminiAvailable: geminiAvailable,
      learnedCorrections: learnedCorrections,
      currentFingerprint: cardFingerprint,
    );
    decisions['website'] = websiteDecision;
    auditTrail.add('[Reconcile:website] ${websiteDecision.auditReason}');
    if (websiteDecision.source == 'userApprovedCorrection') userProtected++;
    if (websiteDecision.source == 'geminiExtraction') {
      if (localCardData.website == null || localCardData.website!.trim().isEmpty) {
        fieldsDiscovered++;
      } else if (websiteDecision.chosenValue != localCardData.website) {
        fieldsCorrected++;
      }
    }

    // 6. RECONCILE PHONE NUMBERS
    final phonesResult = _reconcilePhones(
      localPhones: localCardData.phoneNumbers,
      geminiPhones: geminiResult?.phoneNumbers,
      rawOcrText: rawAllOcr,
      learnedCorrections: learnedCorrections,
      geminiAvailable: geminiAvailable,
    );
    auditTrail.add('[Reconcile:phones] ${phonesResult.auditReason}');
    if (phonesResult.geminiContributed) fieldsCorrected++;

    // 7. RECONCILE EMAIL ADDRESSES
    final emailsResult = _reconcileEmails(
      localEmails: localCardData.emailAddresses,
      geminiEmails: geminiResult?.emailAddresses,
      rawOcrText: rawAllOcr,
      learnedCorrections: learnedCorrections,
      geminiAvailable: geminiAvailable,
    );
    auditTrail.add('[Reconcile:emails] ${emailsResult.auditReason}');
    if (emailsResult.geminiContributed) fieldsCorrected++;

    // Update field evidence and confidence states based on decisions
    for (final entry in decisions.entries) {
      final fName = entry.key;
      final d = entry.value;

      final existingEv = updatedEvidence[fName];
      updatedEvidence[fName] = FieldEvidence(
        fieldName: fName,
        originalOcrText: existingEv?.originalOcrText ?? (d.chosenValue ?? ''),
        normalizedValue: d.chosenValue ?? '',
        sourceEngine: d.source == 'geminiExtraction'
            ? 'Google Gemini Multimodal'
            : (existingEv?.sourceEngine ?? 'Hybrid OCR'),
        sourceObservationIds: d.sourceObservationIds.isNotEmpty
            ? d.sourceObservationIds
            : (existingEv?.sourceObservationIds ?? const []),
        boundingBoxes: existingEv?.boundingBoxes ?? const [],
        ocrConfidence: existingEv?.ocrConfidence ?? 1.0,
        parserConfidence: d.confidence,
        verificationStatus: d.verificationStatus,
        userApprovedValue: d.source == 'userApprovedCorrection'
            ? d.chosenValue
            : existingEv?.userApprovedValue,
        verificationSource: d.source,
        uncertaintyReason: d.reviewRequired ? d.auditReason : null,
        side: existingEv?.side ?? CardSide.front,
      );

      updatedConfidenceStates[fName] = d.verificationStatus == FieldVerificationStatus.verified
          ? 'high'
          : (d.verificationStatus == FieldVerificationStatus.probable
              ? 'medium'
              : (d.verificationStatus == FieldVerificationStatus.notFound ? 'notDetected' : 'uncertain'));

      if (d.alternatives.isNotEmpty) {
        updatedAlternatives[fName] = d.alternatives;
      }
    }

    final bool overallReviewRequired = decisions.values.any((d) => d.reviewRequired) ||
        (geminiResult != null && geminiResult.requiresManualReview);

    final reconciledCard = BusinessCardData(
      fullName: nameDecision.chosenValue,
      company: companyDecision.chosenValue,
      jobTitle: titleDecision.chosenValue,
      website: websiteDecision.chosenValue,
      address: addressDecision.chosenValue,
      phoneNumbers: phonesResult.phones,
      emailAddresses: emailsResult.emails,
      unclassifiedLines: localCardData.unclassifiedLines,
      parsingNotes: [
        ...localCardData.parsingNotes,
        if (geminiResult?.department != null) '[Gemini Dept] ${geminiResult!.department}',
        if (geminiResult?.credentials != null) '[Gemini Cred] ${geminiResult!.credentials}',
        '[Reconciliation Summary] GeminiAssisted: $geminiAvailable | Discovered: $fieldsDiscovered | Corrected: $fieldsCorrected | UserProtected: $userProtected',
      ],
      fieldEvidence: updatedEvidence,
      fieldConfidenceStates: updatedConfidenceStates,
      alternativeCandidates: updatedAlternatives,
    );

    return GeminiOcrReconciliationResult(
      reconciledData: reconciledCard,
      fieldDecisions: decisions,
      auditTrail: auditTrail,
      requiresReview: overallReviewRequired,
      geminiAssisted: geminiAvailable,
      fieldsCorrectedByGemini: fieldsCorrected,
      fieldsDiscoveredByGemini: fieldsDiscovered,
      userCorrectionsProtected: userProtected,
    );
  }

  ReconciliationFieldDecision _reconcileScalarField({
    required String fieldName,
    required String? localValue,
    required ExtractedField? geminiField,
    required String rawOcrText,
    required OcrSideResult frontOcr,
    OcrSideResult? backOcr,
    required bool geminiAvailable,
    required List<LearnedCorrectionRecord> learnedCorrections,
    String? currentFingerprint,
    bool isCorporateDisqualified = false,
  }) {
    // 1. Check User-Approved Corrections (Rule: Highest Precedence)
    final userCorr = _findActiveUserCorrection(
      fieldName: fieldName,
      corrections: learnedCorrections,
      localValue: localValue,
      rawOcrText: rawOcrText,
      currentFingerprint: currentFingerprint,
    );
    if (userCorr != null && userCorr.approvedValue.trim().isNotEmpty) {
      return ReconciliationFieldDecision(
        fieldName: fieldName,
        chosenValue: userCorr.approvedValue.trim(),
        source: 'userApprovedCorrection',
        verificationStatus: FieldVerificationStatus.verified,
        confidence: 1.0,
        reviewRequired: false,
        auditReason: 'Protected user-approved correction (${userCorr.approvedValue})',
        sourceObservationIds: userCorr.relevantObservationIds,
      );
    }

    final hasLocal = localValue != null && localValue.trim().isNotEmpty;
    final geminiVal = geminiField?.value?.trim();
    final hasGemini = geminiVal != null && geminiVal.isNotEmpty;
    final geminiStatus = geminiField != null ? geminiField.verificationStatus.toLowerCase() : 'probable';

    // Special: Disqualified local person name (e.g. Corporate Entity at top of card)
    if (fieldName == 'fullName' && isCorporateDisqualified) {
      if (geminiAvailable && hasGemini && geminiStatus != 'rejected' && geminiStatus != 'notfound') {
        return ReconciliationFieldDecision(
          fieldName: fieldName,
          chosenValue: geminiVal,
          source: 'geminiExtraction',
          verificationStatus: FieldVerificationStatus.fromString(geminiStatus),
          confidence: geminiField!.confidence,
          reviewRequired: geminiField.reviewRequired,
          auditReason: 'Gemini visual extraction adopted: local candidate "$localValue" was corporate entity.',
          sourceObservationIds: geminiField.sourceObservationIds,
        );
      }
      return ReconciliationFieldDecision(
        fieldName: fieldName,
        chosenValue: null,
        source: 'localConsensus',
        verificationStatus: FieldVerificationStatus.notFound,
        confidence: 0.10,
        reviewRequired: false,
        auditReason: 'Local candidate "$localValue" disqualified as corporate entity.',
      );
    }

    // 2. Gemini Available & Multimodal
    if (geminiAvailable && geminiField != null) {
      // Case A: Gemini confirms field is absent / notFound
      if (geminiStatus == 'notfound' || geminiStatus == 'rejected' || !hasGemini) {
        if (!hasLocal) {
          return ReconciliationFieldDecision(
            fieldName: fieldName,
            chosenValue: null,
            source: 'geminiExtraction',
            verificationStatus: FieldVerificationStatus.notFound,
            confidence: 0.95,
            reviewRequired: false,
            auditReason: 'Gemini multimodal verification confirmed field is absent from card.',
          );
        } else {
          // Conflict: Local parser thought it had a value, but Gemini inspected pixels and found nothing
          return ReconciliationFieldDecision(
            fieldName: fieldName,
            chosenValue: null,
            source: 'geminiExtraction',
            verificationStatus: FieldVerificationStatus.notFound,
            confidence: 0.85,
            reviewRequired: false,
            auditReason: 'Gemini corrected local false-positive "$localValue" to null (not present on card).',
            alternatives: [localValue],
          );
        }
      }

      // Case B: Gemini extracted a non-empty value
      if (hasGemini) {
        // Validate against raw OCR or image evidence (Negative constraint: no hallucination)
        final bool groundedInOcr = _hasTokenOverlap(geminiVal, rawOcrText);
        final bool groundedInVisual = geminiField.isVisuallyVerified &&
            (geminiField.visualEvidenceDescription != null && geminiField.visualEvidenceDescription!.isNotEmpty);

        if (!groundedInOcr && !groundedInVisual && (geminiField.confidence < 0.65)) {
          // Gemini hallucination safeguard: proposed value has NO support in OCR and NO visual verification
          if (hasLocal) {
            return ReconciliationFieldDecision(
              fieldName: fieldName,
              chosenValue: localValue,
              source: 'localParserBaseline',
              verificationStatus: FieldVerificationStatus.reviewRequired,
              confidence: 0.50,
              reviewRequired: true,
              auditReason: 'Gemini proposed "$geminiVal" without OCR or visual evidence; retained local "$localValue".',
              alternatives: [geminiVal],
            );
          }
        }

        // Gemini correction or independent discovery accepted
        final bool isCorrection = hasLocal && !_cleanEquals(localValue, geminiVal);
        return ReconciliationFieldDecision(
          fieldName: fieldName,
          chosenValue: geminiVal,
          source: 'geminiExtraction',
          verificationStatus: FieldVerificationStatus.fromString(geminiStatus),
          confidence: geminiField.confidence,
          reviewRequired: geminiField.reviewRequired,
          auditReason: isCorrection
              ? 'Gemini corrected local "$localValue" to "$geminiVal" (${geminiField.correctionReason ?? "visual evidence"}).'
              : 'Gemini verified value "$geminiVal".',
          sourceObservationIds: geminiField.sourceObservationIds,
          alternatives: hasLocal && isCorrection ? [localValue] : const [],
        );
      }
    }

    // 3. Fallback to Local OCR / Parser
    if (hasLocal) {
      return ReconciliationFieldDecision(
        fieldName: fieldName,
        chosenValue: localValue,
        source: 'localParserBaseline',
        verificationStatus: FieldVerificationStatus.probable,
        confidence: 0.80,
        reviewRequired: false,
        auditReason: 'Local parser extracted value without Gemini intervention.',
      );
    }

    return ReconciliationFieldDecision(
      fieldName: fieldName,
      chosenValue: null,
      source: 'notFound',
      verificationStatus: FieldVerificationStatus.notFound,
      confidence: 1.0,
      reviewRequired: false,
      auditReason: 'Field not detected on card.',
    );
  }

  ReconciliationFieldDecision _reconcileAddress({
    required String? localValue,
    required ExtractedAddress? geminiAddress,
    required String rawOcrText,
    required OcrSideResult frontOcr,
    OcrSideResult? backOcr,
    required bool geminiAvailable,
    required List<LearnedCorrectionRecord> learnedCorrections,
    String? currentFingerprint,
  }) {
    final userCorr = _findActiveUserCorrection(
      fieldName: 'address',
      corrections: learnedCorrections,
      localValue: localValue,
      rawOcrText: rawOcrText,
      currentFingerprint: currentFingerprint,
    );
    if (userCorr != null && userCorr.approvedValue.trim().isNotEmpty) {
      return ReconciliationFieldDecision(
        fieldName: 'address',
        chosenValue: userCorr.approvedValue.trim(),
        source: 'userApprovedCorrection',
        verificationStatus: FieldVerificationStatus.verified,
        confidence: 1.0,
        reviewRequired: false,
        auditReason: 'Protected user-approved address.',
      );
    }

    if (geminiAvailable && geminiAddress != null) {
      final geminiVal = geminiAddress.fullAddress?.trim();
      final geminiStatus = geminiAddress.verificationStatus.toLowerCase();
      if (geminiVal != null && geminiVal.isNotEmpty && geminiStatus != 'notfound' && geminiStatus != 'rejected') {
        return ReconciliationFieldDecision(
          fieldName: 'address',
          chosenValue: geminiVal,
          source: 'geminiExtraction',
          verificationStatus: FieldVerificationStatus.fromString(geminiAddress.verificationStatus),
          confidence: geminiAddress.confidence,
          reviewRequired: geminiAddress.reviewRequired,
          auditReason: 'Gemini multimodal extraction assembled address: "$geminiVal".',
          sourceObservationIds: geminiAddress.sourceObservationIds,
        );
      }
    }

    if (localValue != null && localValue.trim().isNotEmpty) {
      return ReconciliationFieldDecision(
        fieldName: 'address',
        chosenValue: localValue.trim(),
        source: 'localParserBaseline',
        verificationStatus: FieldVerificationStatus.probable,
        confidence: 0.75,
        reviewRequired: false,
        auditReason: 'Local parser address.',
      );
    }

    return const ReconciliationFieldDecision(
      fieldName: 'address',
      chosenValue: null,
      source: 'notFound',
      verificationStatus: FieldVerificationStatus.notFound,
      confidence: 1.0,
      reviewRequired: false,
      auditReason: 'No address detected.',
    );
  }

  ReconciliationFieldDecision _reconcileWebsite({
    required String? localValue,
    required List<ExtractedWebsite>? geminiWebsites,
    required String rawOcrText,
    required OcrSideResult frontOcr,
    OcrSideResult? backOcr,
    required bool geminiAvailable,
    required List<LearnedCorrectionRecord> learnedCorrections,
    String? currentFingerprint,
  }) {
    final userCorr = _findActiveUserCorrection(
      fieldName: 'website',
      corrections: learnedCorrections,
      localValue: localValue,
      rawOcrText: rawOcrText,
      currentFingerprint: currentFingerprint,
    );
    if (userCorr != null && userCorr.approvedValue.trim().isNotEmpty) {
      return ReconciliationFieldDecision(
        fieldName: 'website',
        chosenValue: userCorr.approvedValue.trim(),
        source: 'userApprovedCorrection',
        verificationStatus: FieldVerificationStatus.verified,
        confidence: 1.0,
        reviewRequired: false,
        auditReason: 'Protected user-approved website.',
      );
    }

    if (geminiAvailable && geminiWebsites != null && geminiWebsites.isNotEmpty) {
      final validWeb = geminiWebsites.firstWhere(
        (w) => w.url.trim().isNotEmpty,
        orElse: () => geminiWebsites.first,
      );
      if (validWeb.url.trim().isNotEmpty) {
        return ReconciliationFieldDecision(
          fieldName: 'website',
          chosenValue: validWeb.url.trim(),
          source: 'geminiExtraction',
          verificationStatus: FieldVerificationStatus.probable,
          confidence: validWeb.confidence,
          reviewRequired: false,
          auditReason: 'Gemini extraction confirmed website: "${validWeb.url}".',
          sourceObservationIds: validWeb.sourceObservationIds,
        );
      }
    }

    if (localValue != null && localValue.trim().isNotEmpty) {
      return ReconciliationFieldDecision(
        fieldName: 'website',
        chosenValue: localValue.trim(),
        source: 'localParserBaseline',
        verificationStatus: FieldVerificationStatus.probable,
        confidence: 0.85,
        reviewRequired: false,
        auditReason: 'Local parser website.',
      );
    }

    return const ReconciliationFieldDecision(
      fieldName: 'website',
      chosenValue: null,
      source: 'notFound',
      verificationStatus: FieldVerificationStatus.notFound,
      confidence: 1.0,
      reviewRequired: false,
      auditReason: 'No website detected.',
    );
  }

  ({List<BusinessCardPhone> phones, String auditReason, bool geminiContributed}) _reconcilePhones({
    required List<BusinessCardPhone> localPhones,
    required List<ExtractedPhone>? geminiPhones,
    required String rawOcrText,
    required List<LearnedCorrectionRecord> learnedCorrections,
    required bool geminiAvailable,
  }) {
    final results = <BusinessCardPhone>[];
    final seen = <String>{};
    bool geminiContributed = false;

    // A. Add Gemini phones when available and verified
    if (geminiAvailable && geminiPhones != null && geminiPhones.isNotEmpty) {
      for (final gp in geminiPhones) {
        final numClean = _canonicalDigits(gp.number);
        if (numClean.length >= 7 && !seen.contains(numClean)) {
          seen.add(numClean);
          results.add(BusinessCardPhone(
            number: gp.number.trim(),
            label: gp.label.isNotEmpty ? gp.label : 'Mobile',
          ));
          geminiContributed = true;
        }
      }
    }

    // B. Reconcile remaining unique local phones
    for (final lp in localPhones) {
      final numClean = _canonicalDigits(lp.number);
      if (numClean.length >= 7 && !seen.contains(numClean)) {
        seen.add(numClean);
        results.add(lp);
      }
    }

    return (
      phones: results,
      auditReason: 'Reconciled ${results.length} phone(s) (Gemini contributed: $geminiContributed).',
      geminiContributed: geminiContributed,
    );
  }

  ({List<BusinessCardEmail> emails, String auditReason, bool geminiContributed}) _reconcileEmails({
    required List<BusinessCardEmail> localEmails,
    required List<ExtractedEmail>? geminiEmails,
    required String rawOcrText,
    required List<LearnedCorrectionRecord> learnedCorrections,
    required bool geminiAvailable,
  }) {
    final results = <BusinessCardEmail>[];
    final seen = <String>{};
    bool geminiContributed = false;

    // A. Add Gemini emails
    if (geminiAvailable && geminiEmails != null && geminiEmails.isNotEmpty) {
      for (final ge in geminiEmails) {
        final emailClean = ge.email.trim().toLowerCase();
        if (emailClean.contains('@') && !seen.contains(emailClean)) {
          seen.add(emailClean);
          results.add(BusinessCardEmail(
            email: emailClean,
            label: ge.label.isNotEmpty ? ge.label : 'Work',
          ));
          geminiContributed = true;
        }
      }
    }

    // B. Reconcile remaining unique local emails
    for (final le in localEmails) {
      final emailClean = le.email.trim().toLowerCase();
      if (emailClean.contains('@') && !seen.contains(emailClean)) {
        seen.add(emailClean);
        results.add(le);
      }
    }

    return (
      emails: results,
      auditReason: 'Reconciled ${results.length} email(s) (Gemini contributed: $geminiContributed).',
      geminiContributed: geminiContributed,
    );
  }

  LearnedCorrectionRecord? _findActiveUserCorrection({
    required String fieldName,
    required List<LearnedCorrectionRecord> corrections,
    String? localValue,
    required String rawOcrText,
    String? currentFingerprint,
  }) {
    for (final c in corrections) {
      if (!c.isActive || !c.isApproved || c.fieldName != fieldName) continue;

      // 1. If fingerprint is known for both, they must match
      if (currentFingerprint != null && c.imageFingerprint.isNotEmpty) {
        if (c.imageFingerprint != currentFingerprint) {
          continue; // Belongs to a different card image
        }
      }

      // 2. Personal identity fields (strict employee isolation):
      // A learned correction for a personal field (e.g. fullName) must NEVER overwrite
      // a different person's name!
      final bool isPersonalField = fieldName == 'fullName' || fieldName == 'personalEmail';
      if (isPersonalField) {
        if (localValue != null && localValue.trim().isNotEmpty) {
          final cleanLocal = _cleanEquals(c.originalExtractedValue, localValue);
          final overlap = _hasTokenOverlap(c.originalExtractedValue, localValue);
          if (!cleanLocal && !overlap) {
            continue; // Belongs to a different employee/person
          }
        } else {
          if (!_hasTokenOverlap(c.originalExtractedValue, rawOcrText) &&
              !_hasTokenOverlap(c.approvedValue, rawOcrText)) {
            continue; // No evidence of this person on the card
          }
        }
      }

      // 3. Exact image reuse tier requires matching fingerprint or evidence in OCR/localValue
      if (c.tier == CorrectionTier.exactImageReuse) {
        if (currentFingerprint == null) {
          final hasLocalMatch = localValue != null && _cleanEquals(c.originalExtractedValue, localValue);
          final hasOcrMatch = _hasTokenOverlap(c.originalExtractedValue, rawOcrText);
          if (!hasLocalMatch && !hasOcrMatch) {
            continue;
          }
        }
      }

      return c;
    }
    return null;
  }

  bool _isCorporateDisqualified(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    final corporateSuffixes = RegExp(
      r'\b(technolog(?:y|ies)|tech|solutions?|services?|enterprises?|industr(?:y|ies)|'
      r'systems?|laborator(?:y|ies)|labs?|holdings?|group|consulting|consultanc(?:y|ies)|'
      r'associates?|partners?|hospitals?|clinics?|healthcare|health\s+care|studios?|'
      r'agenc(?:y|ies)|ventures?|dynamics?|interactive|innovations?|designs?|software|'
      r'pvt|private|ltd|limited|inc|incorporated|corp|corporation|llc|llp|gmbh)\b',
      caseSensitive: false,
    );
    return corporateSuffixes.hasMatch(text);
  }

  bool _hasTokenOverlap(String needle, String haystack) {
    final tokens = needle
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3);
    for (final token in tokens) {
      if (haystack.contains(token)) return true;
    }
    return false;
  }

  bool _cleanEquals(String a, String b) {
    final cleanA = a.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final cleanB = b.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return cleanA == cleanB;
  }

  String _canonicalDigits(String input) {
    return input.replaceAll(RegExp(r'\D'), '');
  }
}
