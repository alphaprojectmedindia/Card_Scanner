import 'dart:io';
import '../../models/field_evidence.dart';
import '../../models/historical_reprocess_diff.dart';
import '../../models/imported_contact.dart';
import '../../models/ocr_side_result.dart';
import '../../models/recovered_ocr_observation.dart';
import '../card_analysis_decision_service.dart';
import '../card_analysis_service.dart';
import '../storage/card_image_storage_service.dart';
import '../storage/local_contact_record.dart';
import '../storage/local_scan_cache_manager.dart';
import 'local_correction_learning_service.dart';
import 'multi_engine_reconciler.dart';
import 'ocr_engine.dart';
import 'targeted_high_res_reocr_service.dart';
import 'targeted_reocr_cache.dart';
import 'targeted_reocr_uncertainty_detector.dart';

/// Result returned from contact reprocessing.
class ReprocessContactResult {
  final LocalContactRecord updatedRecord;
  final bool wasReprocessed;
  final List<String> improvementsApplied;
  final String? diagnosticMessage;

  const ReprocessContactResult({
    required this.updatedRecord,
    required this.wasReprocessed,
    this.improvementsApplied = const [],
    this.diagnosticMessage,
  });
}

/// Service that reprocesses new or historical business contacts using persistent images (Part 22 Stage 3).
///
/// Features:
/// 1. Verifies physical image existence before initiating OCR inference.
/// 2. Isolates front and back card images strictly (no cross-side bounding box contamination).
/// 3. Retains all original observations and user manual edits without overwrite.
/// 4. Utilizes on-device PaddleOCR and Google ML Kit without external network or Gemini dependencies.
/// 5. Integrates with TargetedReOcrCache for fast idempotent execution.
class ContactReprocessingService {
  final TargetedHighResReOcrService reOcrService;
  final TargetedReOcrUncertaintyDetector uncertaintyDetector;
  final MultiEngineReconciler reconciler;
  final CardImageStorageService imageStorageService;
  final TargetedReOcrCache? cache;

  ContactReprocessingService({
    this.reOcrService = const TargetedHighResReOcrService(),
    this.uncertaintyDetector = const TargetedReOcrUncertaintyDetector(),
    this.reconciler = const MultiEngineReconciler(),
    CardImageStorageService? imageStorageService,
    this.cache,
  }) : imageStorageService = imageStorageService ?? CardImageStorageService();

  /// Reprocesses a [LocalContactRecord] using its stored permanent images.
  Future<ReprocessContactResult> reprocessRecord({
    required LocalContactRecord record,
    required OcrEngine primaryEngine,
    OcrEngine? secondaryEngine,
  }) async {
    // 1. Verify permanent card images
    final hasFront = await imageStorageService.verifyImageFile(record.frontImagePath);
    final hasBack = await imageStorageService.verifyImageFile(record.backImagePath);

    if (!hasFront && !hasBack) {
      return ReprocessContactResult(
        updatedRecord: record,
        wasReprocessed: false,
        diagnosticMessage: 'Original card images are missing or have been deleted; cannot reprocess.',
      );
    }

    // 2. Identify uncertain fields
    final requests = uncertaintyDetector.detectUncertainFields(
      fieldEvidence: record.fieldEvidence,
    );

    if (requests.isEmpty) {
      return ReprocessContactResult(
        updatedRecord: record,
        wasReprocessed: false,
        diagnosticMessage: 'All fields are already verified or high-confidence; no targeted re-OCR needed.',
      );
    }

    final recoveryResults = <TargetedRegionRecoveryResult>[];

    // 3. Process each request with strict side isolation
    for (final req in requests) {
      final imagePath = req.side == CardSide.back ? record.backImagePath : record.frontImagePath;
      if (imagePath == null || !File(imagePath).existsSync()) {
        continue;
      }

      final result = await reOcrService.reprocessTargetedRegion(
        originalImagePath: imagePath,
        request: req,
        primaryEngine: primaryEngine,
        secondaryEngine: secondaryEngine,
        cache: cache,
        imageHash: req.side == CardSide.back ? null : record.imageFingerprint,
      );

      if (result.isSuccess && result.recoveredObservations.isNotEmpty) {
        recoveryResults.add(result);
      }
    }

    if (recoveryResults.isEmpty) {
      return ReprocessContactResult(
        updatedRecord: record,
        wasReprocessed: false,
        diagnosticMessage: 'Targeted re-OCR executed but no new or superior candidates were recognized.',
      );
    }

    // 4. Multi-engine contextual reconciliation
    final reconciliation = reconciler.reconcile(
      baselineEvidence: record.fieldEvidence,
      recoveryResults: recoveryResults,
      frontObservations: record.frontObservations,
      backObservations: record.backObservations,
    );

    // 5. Build updated contact record safely preserving user edits
    final newEvidence = reconciliation.updatedFieldEvidence;
    final allRecoveredObs = [
      ...record.recoveredObservations,
      ...reconciliation.recoveredObservations,
    ];

    // Deduplicate recovered observations by id
    final seenIds = <String>{};
    final uniqueRecoveredObs = <RecoveredOcrObservation>[];
    for (final obs in allRecoveredObs) {
      if (seenIds.add(obs.id)) {
        uniqueRecoveredObs.add(obs);
      }
    }

    // Derive top-level field updates from evidence, respecting userApprovedValue
    String? newFullName = record.fullName;
    String? newCompany = record.company;
    String? newJobTitle = record.jobTitle;
    String? newWebsite = record.website;
    String? newAddress = record.address;
    List<ImportedContactPhone> newPhones = List.from(record.phoneNumbers);
    List<ImportedContactEmail> newEmails = List.from(record.emailAddresses);

    if (newEvidence.containsKey('fullName')) {
      newFullName = newEvidence['fullName']!.effectiveValue;
    }
    if (newEvidence.containsKey('company')) {
      newCompany = newEvidence['company']!.effectiveValue;
    }
    if (newEvidence.containsKey('jobTitle')) {
      newJobTitle = newEvidence['jobTitle']!.effectiveValue;
    }
    if (newEvidence.containsKey('website')) {
      newWebsite = newEvidence['website']!.effectiveValue;
    }
    if (newEvidence.containsKey('address')) {
      newAddress = newEvidence['address']!.effectiveValue;
    }

    // If phone evidence was improved, sync into phoneNumbers list if unedited
    if (newEvidence.containsKey('phone') || newEvidence.containsKey('phoneNumbers')) {
      final phoneEv = newEvidence['phone'] ?? newEvidence['phoneNumbers']!;
      final phoneVal = phoneEv.effectiveValue;
      if (phoneVal.isNotEmpty && !newPhones.any((p) => p.number == phoneVal)) {
        if (!phoneEv.isUserEdited) {
          newPhones = [
            ImportedContactPhone(
              number: phoneVal,
              normalizedNumber: phoneVal.replaceAll(RegExp(r'\D'), ''),
              label: 'Mobile',
            ),
            ...newPhones.where((p) => p.number != phoneEv.originalOcrText),
          ];
        }
      }
    }

    // If email evidence was improved, sync into emailAddresses list if unedited
    if (newEvidence.containsKey('email') || newEvidence.containsKey('emailAddresses')) {
      final emailEv = newEvidence['email'] ?? newEvidence['emailAddresses']!;
      final emailVal = emailEv.effectiveValue;
      if (emailVal.isNotEmpty && !newEmails.any((e) => e.email.toLowerCase() == emailVal.toLowerCase())) {
        if (!emailEv.isUserEdited) {
          newEmails = [
            ImportedContactEmail(
              email: emailVal,
              normalizedEmail: emailVal.trim().toLowerCase(),
              label: 'Work',
            ),
            ...newEmails.where((e) => e.email != emailEv.originalOcrText),
          ];
        }
      }
    }

    final updatedRecord = record.copyWith(
      fullName: newFullName,
      company: newCompany,
      jobTitle: newJobTitle,
      website: newWebsite,
      address: newAddress,
      phoneNumbers: newPhones,
      emailAddresses: newEmails,
      fieldEvidence: newEvidence,
      recoveredObservations: uniqueRecoveredObs,
      updatedAt: DateTime.now(),
    );

    return ReprocessContactResult(
      updatedRecord: updatedRecord,
      wasReprocessed: true,
      improvementsApplied: reconciliation.improvementsApplied,
    );
  }

  /// Reprocesses a previously scanned historical contact safely according to Stage 5 specification.
  ///
  /// **Core Guarantees**:
  /// 1. Verifies physical image existence first. If missing, reports honestly (`missingImages: true`).
  /// 2. Performs targeted re-OCR, reconciliation, and applies learned rules.
  /// 3. Invokes Gemini only for unresolved important fields if allowed and online.
  /// 4. Generates a staged [HistoricalReprocessDiff] comparing previous saved values against proposed values.
  /// 5. **NEVER silently overwrites the contact record**; existing values are preserved until user approval.
  Future<HistoricalReprocessDiff> reprocessHistoricalContact({
    required LocalContactRecord record,
    required OcrEngine primaryEngine,
    OcrEngine? secondaryEngine,
    CardAnalysisService? geminiService,
    LocalCorrectionLearningService? learningService,
    String userId = 'default_user',
    bool invokeGeminiIfUncertain = false,
    LocalScanCacheManager? scanCacheManager,
  }) async {
    // 1. Verify permanent card images
    final hasFront = await imageStorageService.verifyImageFile(record.frontImagePath);
    final hasBack = await imageStorageService.verifyImageFile(record.backImagePath);

    if (!hasFront && !hasBack) {
      return HistoricalReprocessDiff(
        contactId: record.id,
        imageFingerprint: record.imageFingerprint,
        wasReprocessed: false,
        missingImages: true,
        diagnosticMessage: 'Original card images are missing or unreadable; cannot reprocess.',
      );
    }

    // 2. Perform targeted re-OCR and reconciliation
    final reprocessResult = await reprocessRecord(
      record: record,
      primaryEngine: primaryEngine,
      secondaryEngine: secondaryEngine,
    );

    var candidateRecord = reprocessResult.updatedRecord;

    // 3. Apply learned corrections (Tier 1 exact-image and Tier 3 general rules)
    if (learningService != null && record.imageFingerprint != null) {
      final parsedData = candidateRecord.toBusinessCardData();
      final improvedData = await learningService.applyLearnedCorrectionsToCardData(
        parsedData: parsedData,
        imageFingerprint: record.imageFingerprint,
        userId: userId,
      );
      candidateRecord = candidateRecord.copyWith(
        fullName: improvedData.fullName,
        company: improvedData.company,
        jobTitle: improvedData.jobTitle,
        website: improvedData.website,
        address: improvedData.address,
        fieldEvidence: improvedData.fieldEvidence,
      );
    }

    // 4. Invoke Gemini only for unresolved important fields if explicitly permitted
    final frontPath = record.frontImagePath;
    if (invokeGeminiIfUncertain && geminiService != null && hasFront && frontPath != null) {
      final stillUncertain = candidateRecord.fieldEvidence.values
          .where((e) =>
              e.verificationStatus == FieldVerificationStatus.reviewRequired ||
              e.effectiveValue.isEmpty)
          .map((e) => e.fieldName)
          .toList();

      if (stillUncertain.isNotEmpty) {
        try {
          final backPath = record.backImagePath;
          final frontSideResult = OcrSideResult(
            side: CardSide.front,
            imagePath: frontPath,
            rawText: record.frontRawText ?? '',
            metadata: {'selectedEngine': record.ocrEngineName ?? 'paddle_ocr'},
          );
          final backSideResult = hasBack && backPath != null
              ? OcrSideResult(
                  side: CardSide.back,
                  imagePath: backPath,
                  rawText: record.backRawText ?? '',
                  metadata: {'selectedEngine': record.ocrEngineName ?? 'paddle_ocr'},
                )
              : null;

          final geminiResult = await geminiService.analyzeIfTriggered(
            cardData: candidateRecord.toBusinessCardData(),
            frontOcr: frontSideResult,
            backOcr: backSideResult,
            precomputedDecision: const CardAnalysisDecision(
              shouldInvokeGemini: true,
              mode: AnalysisMode.multimodalVision,
              triggeredRules: ['historical_reprocessing'],
              primaryReason: 'Historical reprocessing for uncertain fields',
            ),
          );

          if (geminiResult != null && geminiResult.visualVerificationPerformed) {
            final geminiCardData = geminiResult.toBusinessCardData(
              candidateRecord.toBusinessCardData(),
            );
            candidateRecord = candidateRecord.copyWith(
              fullName: geminiCardData.fullName ?? candidateRecord.fullName,
              company: geminiCardData.company ?? candidateRecord.company,
              jobTitle: geminiCardData.jobTitle ?? candidateRecord.jobTitle,
              website: geminiCardData.website ?? candidateRecord.website,
              address: geminiCardData.address ?? candidateRecord.address,
              fieldEvidence: geminiCardData.fieldEvidence,
            );
          }
        } catch (_) {
          // Graceful offline fallback: keep local candidate record
        }
      }
    }

    // 5. Build structured field-level diffs
    final diffs = <String, HistoricalFieldDiff>{};

    void checkField(String fieldName, String? prev, String? prop, String defaultSource) {
      final ev = candidateRecord.fieldEvidence[fieldName];
      final isLearned = ev?.verificationSource == 'learnedExactImage' ||
          ev?.verificationSource == 'learnedParserRule';
      final src = ev?.verificationSource ?? defaultSource;
      final status = ev?.verificationStatus ?? FieldVerificationStatus.probable;

      diffs[fieldName] = HistoricalFieldDiff(
        fieldName: fieldName,
        previousValue: prev,
        proposedValue: prop,
        source: src,
        isLearnedFromEarlierApproval: isLearned,
        confidence: ev?.ocrConfidence ?? 1.0,
        reason: ev?.uncertaintyReason,
        status: status,
      );
    }

    checkField('fullName', record.fullName, candidateRecord.fullName, 'targetedReOcr');
    checkField('company', record.company, candidateRecord.company, 'targetedReOcr');
    checkField('jobTitle', record.jobTitle, candidateRecord.jobTitle, 'targetedReOcr');
    checkField('website', record.website, candidateRecord.website, 'targetedReOcr');
    checkField('address', record.address, candidateRecord.address, 'targetedReOcr');

    final prevPhone = record.phoneNumbers.map((p) => p.number).join(', ');
    final propPhone = candidateRecord.phoneNumbers.map((p) => p.number).join(', ');
    checkField('phone', prevPhone.isEmpty ? null : prevPhone, propPhone.isEmpty ? null : propPhone, 'targetedReOcr');

    final prevEmail = record.emailAddresses.map((e) => e.email).join(', ');
    final propEmail = candidateRecord.emailAddresses.map((e) => e.email).join(', ');
    checkField('email', prevEmail.isEmpty ? null : prevEmail, propEmail.isEmpty ? null : propEmail, 'targetedReOcr');

    return HistoricalReprocessDiff(
      contactId: record.id,
      imageFingerprint: record.imageFingerprint,
      fieldDiffs: diffs,
      wasReprocessed: reprocessResult.wasReprocessed || candidateRecord != record,
      missingImages: false,
      proposedRecord: candidateRecord,
    );
  }

  /// Commits approved field changes to a [LocalContactRecord] after explicit user approval.
  /// Also registers user confirmations with the [LocalCorrectionLearningService].
  Future<LocalContactRecord> applyApprovedHistoricalDiff({
    required LocalContactRecord record,
    required HistoricalReprocessDiff diff,
    Set<String>? acceptedFieldNames,
    LocalCorrectionLearningService? learningService,
    String userId = 'default_user',
  }) async {
    if (diff.proposedRecord == null) return record;

    final proposed = diff.proposedRecord!;
    final accepted = acceptedFieldNames ?? diff.fieldDiffs.keys.toSet();

    final updatedEvidence = Map<String, FieldEvidence>.from(record.fieldEvidence);
    for (final fieldName in accepted) {
      if (proposed.fieldEvidence.containsKey(fieldName)) {
        final propEv = proposed.fieldEvidence[fieldName]!;
        updatedEvidence[fieldName] = propEv.copyWith(
          userApprovedValue: propEv.effectiveValue,
          verificationStatus: FieldVerificationStatus.verified,
          verificationSource: 'userApprovedReprocess',
          verifiedAt: DateTime.now().toUtc(),
        );

        // Learn from user approval
        if (learningService != null && record.imageFingerprint != null) {
          final originalVal = record.fieldEvidence[fieldName]?.effectiveValue ?? '';
          if (originalVal != propEv.effectiveValue) {
            await learningService.recordUserCorrection(
              imageFingerprint: record.imageFingerprint!,
              fieldName: fieldName,
              originalExtractedValue: originalVal,
              approvedValue: propEv.effectiveValue,
              userId: userId,
              source: 'userApprovedReprocess',
            );
          }
        }
      }
    }

    return record.copyWith(
      fullName: accepted.contains('fullName') ? proposed.fullName : record.fullName,
      company: accepted.contains('company') ? proposed.company : record.company,
      jobTitle: accepted.contains('jobTitle') ? proposed.jobTitle : record.jobTitle,
      website: accepted.contains('website') ? proposed.website : record.website,
      address: accepted.contains('address') ? proposed.address : record.address,
      phoneNumbers: accepted.contains('phone') ? proposed.phoneNumbers : record.phoneNumbers,
      emailAddresses: accepted.contains('email') ? proposed.emailAddresses : record.emailAddresses,
      fieldEvidence: updatedEvidence,
      recoveredObservations: [
        ...record.recoveredObservations,
        ...proposed.recoveredObservations,
      ],
      updatedAt: DateTime.now(),
    );
  }
}
