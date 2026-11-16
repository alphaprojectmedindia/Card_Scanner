import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/card_analysis_result.dart';
import 'package:digital_share/models/field_evidence.dart';
import 'package:digital_share/models/historical_reprocess_diff.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/card_analysis_service.dart';
import 'package:digital_share/services/ocr/bulk_historical_reprocessor.dart';
import 'package:digital_share/services/ocr/contact_reprocessing_service.dart';
import 'package:digital_share/services/ocr/local_correction_learning_service.dart';
import 'package:digital_share/services/ocr/ocr_engine.dart';
import 'package:digital_share/services/ocr/ocr_observation.dart';
import 'package:digital_share/services/storage/card_image_storage_service.dart';
import 'package:digital_share/services/storage/local_contact_record.dart';
import 'package:digital_share/services/storage/local_contact_repository.dart';
import 'package:digital_share/services/storage/local_scan_cache_manager.dart';

/// Test double implementing [OcrEngine] for deterministic offline OCR.
class MockOcrEngine implements OcrEngine {
  @override
  final String name;
  final Future<OcrEngineResult> Function(String imagePath)? onRecognize;

  MockOcrEngine(this.name, {this.onRecognize});

  @override
  Future<OcrEngineResult> recognize(String imagePath) async {
    if (onRecognize != null) {
      return onRecognize!(imagePath);
    }
    return OcrEngineResult(
      engineName: name,
      rawText: 'Mock Recognized Text',
      lineCount: 1,
      characterCount: 20,
      processingTime: const Duration(milliseconds: 10),
      detectedLines: const ['Mock Recognized Text'],
      observations: [
        OcrObservation(
          id: '${name}_0',
          text: 'Mock Recognized Text',
          boundingBox: const Rect.fromLTWH(0, 0, 100, 20),
          normalizedBoundingBox: const Rect.fromLTWH(0, 0, 1, 1),
          engine: name,
          confidence: 0.95,
        ),
      ],
    );
  }

  @override
  Future<void> dispose() async {}
}

/// Test double implementing [CardAnalysisService] to mock Gemini without paid calls.
class MockCardAnalysisService extends CardAnalysisService {
  int callCount = 0;
  final Future<CardAnalysisResult?> Function({
    required BusinessCardData cardData,
    required OcrSideResult frontOcr,
    OcrSideResult? backOcr,
  })? onAnalyze;

  MockCardAnalysisService({this.onAnalyze});

  @override
  int get geminiApiCallCount => callCount;

  @override
  Future<CardAnalysisResult?> analyzeIfTriggered({
    required BusinessCardData cardData,
    required OcrSideResult frontOcr,
    OcrSideResult? backOcr,
    dynamic precomputedDecision,
  }) async {
    callCount++;
    if (onAnalyze != null) {
      return onAnalyze!(
        cardData: cardData,
        frontOcr: frontOcr,
        backOcr: backOcr,
      );
    }
    return CardAnalysisResult(
      clientRequestId: 'req_mock_1',
      analysisCacheKey: 'cache_mock_1',
      visualVerificationPerformed: true,
      frontImageVerified: true,
      backImageVerified: backOcr != null,
      fullName: const ExtractedField(
        value: 'Gemini Verified Name',
        confidence: 0.99,
        isVisuallyVerified: true,
        verificationStatus: 'verified',
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late CardImageStorageService imageStorageService;
  late LocalContactRepository contactRepo;
  late LocalScanCacheManager scanCacheManager;
  late LocalCorrectionLearningService learningService;
  late ContactReprocessingService reprocessingService;

  String createTestImage(String filename, {int width = 200, int height = 100}) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(240, 240, 240));
    final pngBytes = img.encodePng(image);
    final file = File('${testDir.path}/$filename');
    file.writeAsBytesSync(pngBytes, flush: true);
    return file.path;
  }

  setUp(() async {
    testDir = Directory.systemTemp.createTempSync('stage5_test_');
    imageStorageService = CardImageStorageService(
      baseDirectory: Directory('${testDir.path}/images'),
    );
    learningService = LocalCorrectionLearningService(
      storageDirectory: Directory('${testDir.path}/learning'),
    );
    scanCacheManager = LocalScanCacheManager(
      cacheDirectory: Directory('${testDir.path}/cache'),
    );
    contactRepo = LocalContactRepository(
      storageDirectory: Directory('${testDir.path}/contacts'),
      imageStorageService: imageStorageService,
      scanCacheManager: scanCacheManager,
      learningService: learningService,
    );
    reprocessingService = ContactReprocessingService(
      imageStorageService: imageStorageService,
    );
  });

  tearDown(() {
    try {
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Stage 5 — Local Learning & User-Approved Correction Reuse', () {
    test('1. Exact-image correction reuse applies approved value with verified status', () async {
      createTestImage('card_exact.png');
      const imageFingerprint = 'sha256_exact_card_hash_1111';

      // Record a user-approved edit
      await learningService.recordUserCorrection(
        imageFingerprint: imageFingerprint,
        fieldName: 'company',
        originalExtractedValue: 'Acme Corq',
        approvedValue: 'Acme Corp',
        source: 'userManualEdit',
        userId: 'user_alpha',
      );

      final baselineData = BusinessCardData(
        fullName: 'Jane Doe',
        company: 'Acme Corq',
        fieldEvidence: {
          'company': FieldEvidence(
            fieldName: 'company',
            originalOcrText: 'Acme Corq',
            normalizedValue: 'Acme Corq',
            sourceEngine: 'paddle_ocr',
            sourceObservationIds: const ['obs_1'],
            boundingBoxes: const [Rect.fromLTWH(10, 10, 80, 20)],
            ocrConfidence: 0.75,
            parserConfidence: 0.70,
            verificationStatus: FieldVerificationStatus.reviewRequired,
          ),
        },
      );

      final improved = await learningService.applyLearnedCorrectionsToCardData(
        parsedData: baselineData,
        imageFingerprint: imageFingerprint,
        userId: 'user_alpha',
      );

      expect(improved.company, equals('Acme Corp'));
      expect(improved.fieldEvidence['company']!.verificationStatus, equals(FieldVerificationStatus.verified));
      expect(improved.fieldEvidence['company']!.verificationSource, equals('learnedExactImage'));
    });

    test('2. Different contacts with similar templates never cross-contaminate personal identity', () async {
      const cardHashA = 'hash_card_template_user_a';
      const cardHashB = 'hash_card_template_user_b';

      // User corrected Card A's name
      await learningService.recordUserCorrection(
        imageFingerprint: cardHashA,
        fieldName: 'fullName',
        originalExtractedValue: 'Johnathan D',
        approvedValue: 'Johnathan Doe',
        source: 'userManualEdit',
        userId: 'user_alpha',
      );

      // Card B is a completely different person with different image hash
      final cardBData = BusinessCardData(
        fullName: 'Sarah Connor',
        company: 'Cyberdyne',
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Sarah Connor',
            normalizedValue: 'Sarah Connor',
            sourceEngine: 'paddle_ocr',
            sourceObservationIds: const ['obs_b1'],
            boundingBoxes: const [Rect.fromLTWH(10, 10, 80, 20)],
            ocrConfidence: 0.90,
            parserConfidence: 0.90,
            verificationStatus: FieldVerificationStatus.probable,
          ),
        },
      );

      final cardBImproved = await learningService.applyLearnedCorrectionsToCardData(
        parsedData: cardBData,
        imageFingerprint: cardHashB,
        userId: 'user_alpha',
      );

      // Sarah Connor MUST NOT become Johnathan Doe!
      expect(cardBImproved.fullName, equals('Sarah Connor'));
    });

    test('3. Front card correction does not affect or overwrite fields on the back side', () async {
      const imageFingerprint = 'hash_dual_sided_card';

      await learningService.recordUserCorrection(
        imageFingerprint: imageFingerprint,
        cardSide: CardSide.front,
        fieldName: 'website',
        originalExtractedValue: 'www.acme.co',
        approvedValue: 'www.acme.com',
        userId: 'user_alpha',
      );

      // Querying for back side
      final backMatches = await learningService.getExactImageCorrections(
        imageFingerprint: imageFingerprint,
        cardSide: CardSide.back,
        userId: 'user_alpha',
      );

      expect(backMatches.isEmpty, isTrue);
    });

    test('4. Different users/accounts are strictly isolated (no cross-user contamination)', () async {
      const imageFingerprint = 'hash_shared_device_card';

      // User A records correction
      await learningService.recordUserCorrection(
        imageFingerprint: imageFingerprint,
        fieldName: 'jobTitle',
        originalExtractedValue: 'Soft Dev',
        approvedValue: 'Software Developer',
        userId: 'user_alice',
      );

      // User B inspects the same card
      final userBMatches = await learningService.getExactImageCorrections(
        imageFingerprint: imageFingerprint,
        userId: 'user_bob',
      );

      expect(userBMatches.isEmpty, isTrue);
    });

    test('5. Changed image hash rejects exact-image correction reuse', () async {
      const originalHash = 'hash_original_crop';
      const modifiedHash = 'hash_modified_crop';

      await learningService.recordUserCorrection(
        imageFingerprint: originalHash,
        fieldName: 'fullName',
        originalExtractedValue: 'Rob Stark',
        approvedValue: 'Robb Stark',
        userId: 'user_alpha',
      );

      final matches = await learningService.getExactImageCorrections(
        imageFingerprint: modifiedHash,
        userId: 'user_alpha',
      );

      expect(matches.isEmpty, isTrue);
    });

    test('6. Stale learned corrections or cache entries are invalidated on parser version mismatch', () async {
      const imageHash = 'hash_version_check';

      await learningService.recordUserCorrection(
        imageFingerprint: imageHash,
        fieldName: 'company',
        originalExtractedValue: 'Old Co',
        approvedValue: 'New Co',
        processingVersion: '4.0.0', // Stale version
        userId: 'user_alpha',
      );

      // Looking up with newer pipeline version 5.0.0
      final matches = await learningService.getExactImageCorrections(
        imageFingerprint: imageHash,
        processingVersion: '5.0.0',
        userId: 'user_alpha',
      );

      expect(matches.isEmpty, isTrue);
    });

    test('7. User-approved correction is NEVER overwritten by learned rules or re-OCR', () async {
      const imageFingerprint = 'hash_user_protected';

      final userProtectedData = BusinessCardData(
        fullName: 'Custom Manually Approved Name',
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Raw Ocr Name',
            normalizedValue: 'Raw Ocr Name',
            userApprovedValue: 'Custom Manually Approved Name', // User manually edited!
            sourceEngine: 'paddle_ocr',
            sourceObservationIds: const ['obs_1'],
            boundingBoxes: const [Rect.fromLTWH(10, 10, 80, 20)],
            ocrConfidence: 0.6,
            parserConfidence: 0.6,
            verificationStatus: FieldVerificationStatus.verified,
            verificationSource: 'userManualEdit',
          ),
        },
      );

      // Attempt to apply a learned rule with a different value
      await learningService.recordUserCorrection(
        imageFingerprint: imageFingerprint,
        fieldName: 'fullName',
        originalExtractedValue: 'Raw Ocr Name',
        approvedValue: 'Automated Learned Name',
        userId: 'user_alpha',
      );

      final result = await learningService.applyLearnedCorrectionsToCardData(
        parsedData: userProtectedData,
        imageFingerprint: imageFingerprint,
        userId: 'user_alpha',
      );

      // User's manual edit MUST prevail
      expect(result.fullName, equals('Custom Manually Approved Name'));
      expect(result.fieldEvidence['fullName']!.userApprovedValue, equals('Custom Manually Approved Name'));
    });

    test('8. Rejected suggestions increment rejection count and deactivate unwanted rules', () async {
      final rec = await learningService.recordUserCorrection(
        imageFingerprint: 'hash_rejection_test',
        fieldName: 'website',
        originalExtractedValue: 'bad.site',
        approvedValue: 'good.site',
        userId: 'user_alpha',
      );

      expect(rec.isActive, isTrue);

      // User rejects once
      await learningService.recordUserRejection(correctionId: rec.id, userId: 'user_alpha');
      // User rejects twice
      await learningService.recordUserRejection(correctionId: rec.id, userId: 'user_alpha');

      final matches = await learningService.getExactImageCorrections(
        imageFingerprint: 'hash_rejection_test',
        userId: 'user_alpha',
      );

      expect(matches.isEmpty, isTrue); // Rule is now deactivated!
    });
  });

  group('Stage 5 — Historical Card Reprocessing & Diff Tracking', () {
    test('9. Reprocessing historical card generates structured diff without silent overwrite', () async {
      final permFront = createTestImage('hist_card_front.png');
      const imageFingerprint = 'hist_fingerprint_999';

      // 1. Save an initial contact
      final initialRecord = await contactRepo.saveContact(
        {
          'fullName': 'Alice Smith',
          'company': 'Initech Corp',
          'jobTitle': 'Senior Dev',
        },
        imageFingerprint: imageFingerprint,
        frontImagePath: permFront,
        rawRecognizedText: 'Alice Smith\nInitech Corp\nSenior Dev',
        fieldEvidence: {
          'jobTitle': FieldEvidence(
            fieldName: 'jobTitle',
            originalOcrText: 'Senior Dev',
            normalizedValue: 'Senior Dev',
            sourceEngine: 'paddle_ocr',
            sourceObservationIds: const ['obs_title'],
            boundingBoxes: const [Rect.fromLTWH(10, 40, 80, 15)],
            ocrConfidence: 0.60, // Low confidence -> triggers targeted re-OCR
            parserConfidence: 0.60,
            verificationStatus: FieldVerificationStatus.reviewRequired,
          ),
        },
      );

      final record = (await contactRepo.getRecordById(initialRecord.id))!;

      // 2. Mock targeted re-OCR engine that recognizes superior text
      final mockOcr = MockOcrEngine('paddle_ocr', onRecognize: (path) async {
        return OcrEngineResult(
          engineName: 'paddle_ocr',
          rawText: 'Senior Software Architect',
          lineCount: 1,
          characterCount: 25,
          processingTime: const Duration(milliseconds: 10),
          detectedLines: const ['Senior Software Architect'],
          observations: [
            OcrObservation(
              id: 'paddle_rec_1',
              text: 'Senior Software Architect',
              boundingBox: const Rect.fromLTWH(10, 40, 80, 15),
              normalizedBoundingBox: const Rect.fromLTWH(0.1, 0.4, 0.8, 0.15),
              engine: 'paddle_ocr',
              confidence: 0.98,
            ),
          ],
        );
      });

      // 3. Run historical reprocessing
      final diff = await reprocessingService.reprocessHistoricalContact(
        record: record,
        primaryEngine: mockOcr,
      );

      expect(diff.wasReprocessed, isTrue);
      expect(diff.hasChanges, isTrue);
      expect(diff.fieldDiffs.containsKey('jobTitle'), isTrue);

      final titleDiff = diff.fieldDiffs['jobTitle']!;
      expect(titleDiff.previousValue, equals('Senior Dev'));
      expect(titleDiff.proposedValue, equals('Senior Software Architect'));
      expect(titleDiff.isChanged, isTrue);

      // CRITICAL NEGATIVE CONSTRAINT CHECK:
      // The stored contact record in repository MUST NOT have been overwritten yet!
      final unmodifiedRecord = (await contactRepo.getRecordById(record.id))!;
      expect(unmodifiedRecord.jobTitle, equals('Senior Dev'));

      // 4. User explicitly approves the change
      final approvedRecord = await reprocessingService.applyApprovedHistoricalDiff(
        record: unmodifiedRecord,
        diff: diff,
        acceptedFieldNames: {'jobTitle'},
      );

      await contactRepo.updateLocalRecord(approvedRecord);

      final finalRecord = (await contactRepo.getRecordById(record.id))!;
      expect(finalRecord.jobTitle, equals('Senior Software Architect'));
    });

    test('10. Missing original images are reported honestly with zero manufactured evidence', () async {
      // Create a contact pointing to non-existent image paths
      final missingImageRecord = LocalContactRecord(
        id: 'contact_missing_images',
        fullName: 'Ghost Contact',
        frontImagePath: '${testDir.path}/deleted_front.jpg',
        backImagePath: '${testDir.path}/deleted_back.jpg',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final diff = await reprocessingService.reprocessHistoricalContact(
        record: missingImageRecord,
        primaryEngine: MockOcrEngine('paddle_ocr'),
      );

      expect(diff.missingImages, isTrue);
      expect(diff.wasReprocessed, isFalse);
      expect(diff.hasChanges, isFalse);
      expect(diff.diagnosticMessage, contains('Original card images are missing'));
    });
  });

  group('Stage 5 — Bulk Reprocessing & Offline Resilience', () {
    test('11. Interrupted processing cleanly halts via CancellationToken without corrupting progress', () async {
      final img1 = createTestImage('card_bulk_1.png');
      final img2 = createTestImage('card_bulk_2.png');

      final r1 = LocalContactRecord(
        id: 'c1',
        fullName: 'Contact 1',
        frontImagePath: img1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final r2 = LocalContactRecord(
        id: 'c2',
        fullName: 'Contact 2',
        frontImagePath: img2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final bulkReprocessor = BulkHistoricalReprocessor(
        reprocessingService: reprocessingService,
        imageStorageService: imageStorageService,
      );

      final cancellationToken = ReprocessCancellationToken();

      // Trigger cancellation immediately on first progress callback
      final result = await bulkReprocessor.reprocessBulk(
        records: [r1, r2],
        primaryEngine: MockOcrEngine('paddle_ocr'),
        cancellationToken: cancellationToken,
        onProgress: (progress) {
          cancellationToken.cancel();
        },
      );

      expect(result.wasCancelled, isTrue);
      expect(result.processedCount, lessThanOrEqualTo(2));
    });

    test('12. Contact deletion evicts scan cache and exact-image learned corrections', () async {
      final imgPath = createTestImage('delete_test_card.png');
      const fingerprint = 'delete_card_fingerprint_777';

      final contact = await contactRepo.saveContact(
        {'fullName': 'To Delete'},
        imageFingerprint: fingerprint,
        frontImagePath: imgPath,
      );

      // Populate scan cache
      await scanCacheManager.putScanResult(
        imageFingerprint: fingerprint,
        frontRawText: 'To Delete',
        parsedData: BusinessCardData(fullName: 'To Delete'),
        contactId: contact.id,
      );

      // Populate learned correction
      await learningService.recordUserCorrection(
        imageFingerprint: fingerprint,
        fieldName: 'fullName',
        originalExtractedValue: 'To Delet',
        approvedValue: 'To Delete',
      );

      expect(await scanCacheManager.getScanResult(fingerprint), isNotNull);
      expect((await learningService.getExactImageCorrections(imageFingerprint: fingerprint)).isNotEmpty, isTrue);

      // Delete contact
      await contactRepo.deleteContact(contact.id, markPendingSync: false);

      // Verify caches are cleaned
      expect(await scanCacheManager.getScanResult(fingerprint), isNull);
      expect((await learningService.getExactImageCorrections(imageFingerprint: fingerprint)).isEmpty, isTrue);
    });

    test('13. Offline processing operates 100% locally with zero network calls', () async {
      final imgPath = createTestImage('offline_card.png');
      const fingerprint = 'offline_fingerprint_888';

      final record = LocalContactRecord(
        id: 'offline_c1',
        fullName: 'Offline User',
        imageFingerprint: fingerprint,
        frontImagePath: imgPath,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Null Gemini service simulates 100% offline flight mode
      final diff = await reprocessingService.reprocessHistoricalContact(
        record: record,
        primaryEngine: MockOcrEngine('paddle_ocr'),
        geminiService: null,
        invokeGeminiIfUncertain: false,
      );

      expect(diff.wasReprocessed, isFalse); // No uncertain fields needing re-OCR
      expect(diff.missingImages, isFalse);
    });

    test('14. Bulk reprocessing strictly caps Gemini calls to geminiMaxBatchCalls', () async {
      final img1 = createTestImage('gem_bulk_1.png');
      final img2 = createTestImage('gem_bulk_2.png');
      final img3 = createTestImage('gem_bulk_3.png');

      LocalContactRecord makeUncertainRecord(String id, String img) {
        return LocalContactRecord(
          id: id,
          fullName: 'Uncertain Name $id',
          imageFingerprint: 'fp_$id',
          frontImagePath: img,
          fieldEvidence: {
            'fullName': FieldEvidence(
              fieldName: 'fullName',
              originalOcrText: 'Uncertain',
              normalizedValue: 'Uncertain',
              sourceEngine: 'paddle_ocr',
              sourceObservationIds: const ['o1'],
              boundingBoxes: const [Rect.fromLTWH(0, 0, 10, 10)],
              ocrConfidence: 0.4,
              parserConfidence: 0.4,
              verificationStatus: FieldVerificationStatus.reviewRequired,
            ),
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }

      final r1 = makeUncertainRecord('1', img1);
      final r2 = makeUncertainRecord('2', img2);
      final r3 = makeUncertainRecord('3', img3);

      final mockGemini = MockCardAnalysisService();
      final bulkReprocessor = BulkHistoricalReprocessor(
        reprocessingService: reprocessingService,
        imageStorageService: imageStorageService,
      );

      // Max calls allowed: 2
      final result = await bulkReprocessor.reprocessBulk(
        records: [r1, r2, r3],
        primaryEngine: MockOcrEngine('paddle_ocr'),
        geminiService: mockGemini,
        allowGemini: true,
        geminiMaxBatchCalls: 2,
      );

      // Gemini must have been invoked at most 2 times
      expect(mockGemini.callCount, lessThanOrEqualTo(2));
      expect(result.geminiCallsCount, lessThanOrEqualTo(2));
      expect(result.processedCount, equals(3));
    });

    test('15. Synchronization and learning update after user approval', () async {
      final imgPath = createTestImage('sync_card.png');
      const fingerprint = 'sync_card_fingerprint_555';

      final saved = await contactRepo.saveContact(
        {
          'fullName': 'David Warner',
          'company': 'Cricket Inc',
          'website': 'www.cric.co',
        },
        imageFingerprint: fingerprint,
        frontImagePath: imgPath,
      );

      final record = (await contactRepo.getRecordById(saved.id))!;

      final diff = HistoricalReprocessDiff(
        contactId: record.id,
        imageFingerprint: fingerprint,
        wasReprocessed: true,
        fieldDiffs: const {
          'website': HistoricalFieldDiff(
            fieldName: 'website',
            previousValue: 'www.cric.co',
            proposedValue: 'www.cricket.com',
            source: 'targetedReOcr',
            status: FieldVerificationStatus.verified,
          ),
        },
        proposedRecord: record.copyWith(
          website: 'www.cricket.com',
          fieldEvidence: {
            'website': FieldEvidence(
              fieldName: 'website',
              originalOcrText: 'www.cric.co',
              normalizedValue: 'www.cricket.com',
              sourceEngine: 'paddle_ocr',
              sourceObservationIds: const ['obs_w1'],
              boundingBoxes: const [Rect.fromLTWH(0, 0, 10, 10)],
              ocrConfidence: 0.99,
              parserConfidence: 0.99,
              verificationStatus: FieldVerificationStatus.verified,
            ),
          },
        ),
      );

      // User approves 'website' change
      final updated = await reprocessingService.applyApprovedHistoricalDiff(
        record: record,
        diff: diff,
        acceptedFieldNames: {'website'},
        learningService: learningService,
        userId: 'user_alpha',
      );

      await contactRepo.updateLocalRecord(updated);

      // Verify repository was updated
      final reloaded = (await contactRepo.getRecordById(saved.id))!;
      expect(reloaded.website, equals('www.cricket.com'));
      expect(reloaded.fieldEvidence['website']!.verificationSource, equals('userApprovedReprocess'));
      expect(reloaded.fieldEvidence['website']!.userApprovedValue, equals('www.cricket.com'));

      // Verify learning service captured this approved correction
      final learned = await learningService.getExactImageCorrections(
        imageFingerprint: fingerprint,
        userId: 'user_alpha',
      );
      expect(learned.any((c) => c.fieldName == 'website' && c.approvedValue == 'www.cricket.com'), isTrue);
    });
  });
}
