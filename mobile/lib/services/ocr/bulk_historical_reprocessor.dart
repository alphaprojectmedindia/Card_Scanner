import 'dart:async';
import '../../models/field_evidence.dart';
import '../../models/historical_reprocess_diff.dart';
import '../card_analysis_service.dart';
import '../storage/card_image_storage_service.dart';
import '../storage/local_contact_record.dart';
import '../storage/local_contact_repository.dart';
import 'contact_reprocessing_service.dart';
import 'local_correction_learning_service.dart';
import 'ocr_engine.dart';

/// Progress state emitted during bulk historical contact reprocessing.
class BulkReprocessProgress {
  final int totalCount;
  final int processedCount;
  final int improvedCount;
  final int skippedMissingImagesCount;
  final int geminiCallsMade;
  final bool isCancelled;
  final String? currentContactId;
  final String? currentContactName;

  const BulkReprocessProgress({
    required this.totalCount,
    required this.processedCount,
    required this.improvedCount,
    required this.skippedMissingImagesCount,
    required this.geminiCallsMade,
    this.isCancelled = false,
    this.currentContactId,
    this.currentContactName,
  });

  double get percentComplete =>
      totalCount == 0 ? 1.0 : (processedCount / totalCount).clamp(0.0, 1.0);
}

/// Token used to cooperatively cancel an in-flight bulk reprocessing batch.
class ReprocessCancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

/// Summary result of a bulk historical reprocessing operation.
class BulkReprocessResult {
  final int totalExamined;
  final int processedCount;
  final int skippedMissingImages;
  final int improvedCount;
  final int geminiCallsCount;
  final bool wasCancelled;
  final List<HistoricalReprocessDiff> diffs;

  const BulkReprocessResult({
    required this.totalExamined,
    required this.processedCount,
    required this.skippedMissingImages,
    required this.improvedCount,
    required this.geminiCallsCount,
    required this.wasCancelled,
    required this.diffs,
  });
}

/// Coordinator for safe, throttled, incremental bulk historical contact reprocessing (Stage 5).
///
/// **Safety & Resilience Principles**:
/// 1. Incremental processing one record at a time to prevent memory spikes.
/// 2. Prioritizes contacts with missing or uncertain fields (`reviewRequired`).
/// 3. Skips contacts without recoverable images and reports them honestly.
/// 4. Hard cap on Gemini visual verification calls (`geminiMaxBatchCalls`).
/// 5. 100% offline capable: if offline or Gemini cap reached, executes local OCR and learning only.
/// 6. Immediate cancellation support without corrupting stored contacts.
/// 7. Never auto-overwrites: outputs staged [HistoricalReprocessDiff]s for user review.
class BulkHistoricalReprocessor {
  final ContactReprocessingService reprocessingService;
  final CardImageStorageService imageStorageService;
  final LocalContactRepository? repository;

  BulkHistoricalReprocessor({
    ContactReprocessingService? reprocessingService,
    CardImageStorageService? imageStorageService,
    this.repository,
  })  : reprocessingService = reprocessingService ?? ContactReprocessingService(),
        imageStorageService = imageStorageService ?? CardImageStorageService();

  /// Executes bulk reprocessing on the provided records.
  Future<BulkReprocessResult> reprocessBulk({
    required List<LocalContactRecord> records,
    required OcrEngine primaryEngine,
    OcrEngine? secondaryEngine,
    CardAnalysisService? geminiService,
    LocalCorrectionLearningService? learningService,
    String userId = 'default_user',
    bool allowGemini = false,
    int geminiMaxBatchCalls = 5,
    void Function(BulkReprocessProgress progress)? onProgress,
    ReprocessCancellationToken? cancellationToken,
  }) async {
    // 1. Sort records: prioritize contacts with uncertain or missing fields
    final sortedRecords = List<LocalContactRecord>.from(records)..sort((a, b) {
      final aUncertain = _countUncertainFields(a);
      final bUncertain = _countUncertainFields(b);
      return bUncertain.compareTo(aUncertain); // Higher uncertain count first
    });

    final diffs = <HistoricalReprocessDiff>[];
    int processedCount = 0;
    int improvedCount = 0;
    int skippedMissingImagesCount = 0;
    int geminiCallsMade = 0;

    for (final record in sortedRecords) {
      // Cancellation check
      if (cancellationToken != null && cancellationToken.isCancelled) {
        onProgress?.call(BulkReprocessProgress(
          totalCount: sortedRecords.length,
          processedCount: processedCount,
          improvedCount: improvedCount,
          skippedMissingImagesCount: skippedMissingImagesCount,
          geminiCallsMade: geminiCallsMade,
          isCancelled: true,
          currentContactId: record.id,
          currentContactName: record.fullName,
        ));
        break;
      }

      // Check image availability
      final hasFront = await imageStorageService.verifyImageFile(record.frontImagePath);
      final hasBack = await imageStorageService.verifyImageFile(record.backImagePath);

      if (!hasFront && !hasBack) {
        skippedMissingImagesCount++;
        processedCount++;
        diffs.add(HistoricalReprocessDiff(
          contactId: record.id,
          imageFingerprint: record.imageFingerprint,
          wasReprocessed: false,
          missingImages: true,
          diagnosticMessage: 'Original card images missing. Cannot reprocess.',
        ));

        onProgress?.call(BulkReprocessProgress(
          totalCount: sortedRecords.length,
          processedCount: processedCount,
          improvedCount: improvedCount,
          skippedMissingImagesCount: skippedMissingImagesCount,
          geminiCallsMade: geminiCallsMade,
          currentContactId: record.id,
          currentContactName: record.fullName,
        ));
        continue;
      }

      // Determine if Gemini can be called for this contact
      final bool canInvokeGemini = allowGemini &&
          geminiService != null &&
          geminiCallsMade < geminiMaxBatchCalls &&
          _hasImportantUncertainFields(record);

      final diff = await reprocessingService.reprocessHistoricalContact(
        record: record,
        primaryEngine: primaryEngine,
        secondaryEngine: secondaryEngine,
        geminiService: canInvokeGemini ? geminiService : null,
        learningService: learningService,
        userId: userId,
        invokeGeminiIfUncertain: canInvokeGemini,
      );

      if (canInvokeGemini && diff.proposedRecord != null) {
        // If proposed record utilized Gemini, track call
        final usedGemini = diff.fieldDiffs.values.any((d) =>
            d.source.contains('gemini') ||
            d.source.contains('Gemini') ||
            d.source.contains('visualVerification'));
        if (usedGemini) {
          geminiCallsMade++;
        }
      }

      diffs.add(diff);
      processedCount++;
      if (diff.hasChanges) {
        improvedCount++;
      }

      onProgress?.call(BulkReprocessProgress(
        totalCount: sortedRecords.length,
        processedCount: processedCount,
        improvedCount: improvedCount,
        skippedMissingImagesCount: skippedMissingImagesCount,
        geminiCallsMade: geminiCallsMade,
        currentContactId: record.id,
        currentContactName: record.fullName,
      ));
    }

    return BulkReprocessResult(
      totalExamined: sortedRecords.length,
      processedCount: processedCount,
      skippedMissingImages: skippedMissingImagesCount,
      improvedCount: improvedCount,
      geminiCallsCount: geminiCallsMade,
      wasCancelled: cancellationToken?.isCancelled ?? false,
      diffs: diffs,
    );
  }

  static int _countUncertainFields(LocalContactRecord r) {
    int count = 0;
    for (final ev in r.fieldEvidence.values) {
      if (ev.verificationStatus == FieldVerificationStatus.reviewRequired ||
          ev.effectiveValue.isEmpty) {
        count++;
      }
    }
    return count;
  }

  static bool _hasImportantUncertainFields(LocalContactRecord r) {
    final important = ['fullName', 'company', 'phone', 'email'];
    for (final key in important) {
      final ev = r.fieldEvidence[key];
      if (ev == null ||
          ev.verificationStatus == FieldVerificationStatus.reviewRequired ||
          ev.effectiveValue.isEmpty) {
        return true;
      }
    }
    return false;
  }
}

