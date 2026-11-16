import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/field_evidence.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/models/recovered_ocr_observation.dart';
import 'package:digital_share/services/ocr/contact_reprocessing_service.dart';
import 'package:digital_share/services/ocr/multi_engine_reconciler.dart';
import 'package:digital_share/services/ocr/ocr_engine.dart';
import 'package:digital_share/services/ocr/ocr_observation.dart';
import 'package:digital_share/services/ocr/targeted_high_res_reocr_service.dart';
import 'package:digital_share/services/ocr/targeted_reocr_cache.dart';
import 'package:digital_share/services/ocr/targeted_reocr_uncertainty_detector.dart';
import 'package:digital_share/services/storage/card_image_storage_service.dart';
import 'package:digital_share/services/storage/local_contact_repository.dart';

/// Test double implementing [OcrEngine] for deterministic targeted re-OCR testing.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late CardImageStorageService imageService;
  late LocalContactRepository repository;
  late TargetedReOcrCache cache;
  late File sampleFrontImageFile;
  late File sampleBackImageFile;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('ds_stage3_reocr_test_');
    imageService = CardImageStorageService(baseDirectory: testDir);
    await imageService.ensureDirectoriesExist();

    repository = LocalContactRepository(
      storageDirectory: Directory('${testDir.path}/storage'),
      fileName: 'test_contacts_stage3.json',
      imageStorageService: imageService,
    );
    await repository.ensureLoaded();

    cache = TargetedReOcrCache(
      cacheDirectory: Directory('${testDir.path}/cache'),
    );

    // Create synthetic bitmap card images (800x500 pixels)
    final frontImg = img.Image(width: 800, height: 500);
    img.fill(frontImg, color: img.ColorRgb8(255, 255, 255));
    final frontBytes = Uint8List.fromList(img.encodeJpg(frontImg));
    sampleFrontImageFile = File('${testDir.path}/sample_front.jpg');
    await sampleFrontImageFile.writeAsBytes(frontBytes, flush: true);

    final backImg = img.Image(width: 800, height: 500);
    img.fill(backImg, color: img.ColorRgb8(240, 240, 240));
    final backBytes = Uint8List.fromList(img.encodeJpg(backImg));
    sampleBackImageFile = File('${testDir.path}/sample_back.jpg');
    await sampleBackImageFile.writeAsBytes(backBytes, flush: true);
  });

  tearDown(() async {
    try {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Stage 3 — Field-Level Uncertainty Detection', () {
    const detector = TargetedReOcrUncertaintyDetector();

    test('Triggers re-OCR on low-confidence field (< 0.70)', () {
      final evidence = <String, FieldEvidence>{
        'fullName': FieldEvidence(
          fieldName: 'fullName',
          originalOcrText: 'John Doe',
          normalizedValue: 'John Doe',
          sourceEngine: 'PaddleOCR',
          sourceObservationIds: const ['front_0'],
          boundingBoxes: const [Rect.fromLTWH(50, 40, 200, 30)],
          ocrConfidence: 0.55, // LOW CONFIDENCE
          parserConfidence: 0.80,
          verificationStatus: FieldVerificationStatus.reviewRequired,
          side: CardSide.front,
        ),
      };

      final requests = detector.detectUncertainFields(fieldEvidence: evidence);
      expect(requests.length, equals(1));
      expect(requests.first.fieldName, equals('fullName'));
      expect(requests.first.triggerReason, contains('Low OCR confidence'));
    });

    test('Excludes high-confidence verified fields and absent fields (Negative Rule)', () {
      final evidence = <String, FieldEvidence>{
        'company': FieldEvidence(
          fieldName: 'company',
          originalOcrText: 'Acme Global Ltd',
          normalizedValue: 'Acme Global Ltd',
          sourceEngine: 'PaddleOCR',
          sourceObservationIds: const ['front_0'],
          boundingBoxes: const [Rect.fromLTWH(50, 10, 300, 35)],
          ocrConfidence: 0.98,
          parserConfidence: 0.95,
          verificationStatus: FieldVerificationStatus.verified,
          side: CardSide.front,
        ),
        'website': FieldEvidence.notFound('website', side: CardSide.front), // ABSENT
      };

      final requests = detector.detectUncertainFields(fieldEvidence: evidence);
      expect(requests, isEmpty, reason: 'High-confidence and absent fields must not trigger re-OCR');
    });

    test('Triggers re-OCR on PaddleOCR and ML Kit disagreement with competing alternatives', () {
      final evidence = <String, FieldEvidence>{
        'phoneNumbers': FieldEvidence(
          fieldName: 'phoneNumbers',
          originalOcrText: '9840512345',
          normalizedValue: '9840512345',
          sourceEngine: 'PaddleOCR',
          sourceObservationIds: const ['front_2'],
          boundingBoxes: const [Rect.fromLTWH(50, 120, 200, 25)],
          ocrConfidence: 0.88,
          parserConfidence: 0.85,
          verificationStatus: FieldVerificationStatus.probable,
          side: CardSide.front,
        ),
      };

      final cardData = const BusinessCardData(
        alternativeCandidates: {
          'phoneNumbers': ['+91 98405 12345', '98405 12340'], // Competing candidates
        },
      );

      final requests = detector.detectUncertainFields(
        fieldEvidence: evidence,
        cardData: cardData,
      );
      expect(requests.length, equals(1));
      expect(requests.first.triggerReason, contains('disagreement'));
    });

    test('Triggers re-OCR on ambiguous glyphs in phone number (0 vs O, 1 vs l/I)', () {
      final evidence = <String, FieldEvidence>{
        'phoneNumbers': FieldEvidence(
          fieldName: 'phoneNumbers',
          originalOcrText: '+91 984O5 12345', // 'O' instead of '0'
          normalizedValue: '+91 984O5 12345',
          sourceEngine: 'PaddleOCR',
          sourceObservationIds: const ['front_2'],
          boundingBoxes: const [Rect.fromLTWH(50, 120, 200, 25)],
          ocrConfidence: 0.75,
          parserConfidence: 0.70,
          verificationStatus: FieldVerificationStatus.probable,
          side: CardSide.front,
        ),
      };

      final requests = detector.detectUncertainFields(fieldEvidence: evidence);
      expect(requests.length, equals(1));
      expect(requests.first.triggerReason, contains('ambiguous alpha-numeric glyphs'));
    });
  });

  group('Stage 3 — Targeted High-Res Crop and Coordinate Restoration', () {
    test('Calculates crop bounding box with padding and restores coordinates', () {
      const transform = CropTransformationMetadata(
        cropLeft: 100,
        cropTop: 150,
        cropWidth: 200,
        cropHeight: 30, // < 36px so scaled
        padX: 10,
        padY: 10,
        scale: 1.2,
        originalWidth: 800,
        originalHeight: 500,
      );

      // Observation detected in upscaled crop image
      const cropDetectedBox = Rect.fromLTWH(12, 6, 120, 24);
      final restoredBox = transform.mapCropRectToOriginal(cropDetectedBox);

      // origLeft = 100 + (12 / 1.2) = 110.0
      // origTop = 150 + (6 / 1.2) = 155.0
      // origWidth = 120 / 1.2 = 100.0
      // origHeight = 24 / 1.2 = 20.0
      expect(restoredBox.left, closeTo(110.0, 0.01));
      expect(restoredBox.top, closeTo(155.0, 0.01));
      expect(restoredBox.width, closeTo(100.0, 0.01));
      expect(restoredBox.height, closeTo(20.0, 0.01));
    });

    test('Marks spatial mapping as uncertain if coordinate transformation is degenerate', () {
      const degenerateTransform = CropTransformationMetadata(
        cropLeft: 0,
        cropTop: 0,
        cropWidth: 0,
        cropHeight: 0,
        scale: 0.0,
        originalWidth: 800,
        originalHeight: 500,
      );

      final mapped = degenerateTransform.mapCropRectToOriginal(const Rect.fromLTWH(10, 10, 50, 20));
      expect(mapped, equals(Rect.zero));
    });

    test('Executes targeted re-OCR on physical crop with front/back image isolation', () async {
      final paddle = MockOcrEngine('PaddleOCR', onRecognize: (path) async {
        return const OcrEngineResult(
          engineName: 'PaddleOCR',
          rawText: '+91 98405 12345',
          processingTime: Duration(milliseconds: 15),
          detectedLines: ['+91 98405 12345'],
          observations: [
            OcrObservation(
              id: 'paddle_rec_0',
              text: '+91 98405 12345',
              boundingBox: Rect.fromLTWH(10, 5, 180, 25),
              normalizedBoundingBox: Rect.fromLTWH(0.05, 0.1, 0.9, 0.8),
              engine: 'PaddleOCR',
              confidence: 0.98,
            ),
          ],
        );
      });

      const reOcrService = TargetedHighResReOcrService();
      final request = TargetedReOcrRequest(
        fieldName: 'phoneNumbers',
        side: CardSide.front,
        targetBoundingBox: const Rect.fromLTWH(50, 100, 220, 30),
        candidateText: '+91 984O5 12345',
        triggerReason: 'Ambiguous glyph',
      );

      final result = await reOcrService.reprocessTargetedRegion(
        originalImagePath: sampleFrontImageFile.path,
        request: request,
        primaryEngine: paddle,
        cache: cache,
      );

      expect(result.isSuccess, isTrue);
      expect(result.recoveredObservations.length, equals(1));
      final rec = result.recoveredObservations.first;
      expect(rec.text, equals('+91 98405 12345'));
      expect(rec.side, equals(CardSide.front));
      expect(rec.sourceEngine, contains('PaddleOCR'));
      expect(rec.originalCoordinates.left, greaterThanOrEqualTo(0));
      expect(rec.originalCoordinates.right, lessThanOrEqualTo(800));
    });
  });

  group('Stage 3 — Multi-Engine Reconciliation', () {
    const reconciler = MultiEngineReconciler();

    test('Reconciles phone number: disambiguates glyphs and prefers complete digit sequence', () {
      final baseline = <String, FieldEvidence>{
        'phoneNumbers': FieldEvidence(
          fieldName: 'phoneNumbers',
          originalOcrText: '98405 123', // 8 digits (incomplete)
          normalizedValue: '98405123',
          sourceEngine: 'PaddleOCR',
          sourceObservationIds: const ['front_1'],
          boundingBoxes: const [Rect.fromLTWH(50, 80, 150, 25)],
          ocrConfidence: 0.90,
          parserConfidence: 0.65,
          verificationStatus: FieldVerificationStatus.reviewRequired,
          side: CardSide.front,
        ),
      };

      final recovery = TargetedRegionRecoveryResult(
        request: const TargetedReOcrRequest(
          fieldName: 'phoneNumbers',
          side: CardSide.front,
          targetBoundingBox: Rect.fromLTWH(50, 80, 150, 25),
          candidateText: '98405 123',
          triggerReason: 'Incomplete digits',
        ),
        recoveredObservations: [
          RecoveredOcrObservation(
            id: 'rec_front_paddle_0',
            text: '+91 98405 12345', // 10 digits + country code
            sourceEngine: 'PaddleOCR (Targeted)',
            side: CardSide.front,
            originalCoordinates: const Rect.fromLTWH(48, 78, 160, 28),
            cropCoordinates: const Rect.fromLTWH(10, 5, 150, 24),
            transformationMetadata: const CropTransformationMetadata(
              cropLeft: 40,
              cropTop: 70,
              cropWidth: 170,
              cropHeight: 35,
              originalWidth: 800,
              originalHeight: 500,
            ),
            ocrConfidence: 0.96,
            reprocessingReason: 'Incomplete digits',
            createdAt: DateTime.now(),
          ),
        ],
        transformationMetadata: const CropTransformationMetadata(
          cropLeft: 40,
          cropTop: 70,
          cropWidth: 170,
          cropHeight: 35,
          originalWidth: 800,
          originalHeight: 500,
        ),
      );

      final outcome = reconciler.reconcile(
        baselineEvidence: baseline,
        recoveryResults: [recovery],
      );

      final updatedPhone = outcome.updatedFieldEvidence['phoneNumbers']!;
      expect(updatedPhone.effectiveValue, equals('+91 98405 12345'));
      expect(updatedPhone.verificationStatus, equals(FieldVerificationStatus.probable));
      expect(outcome.improvementsApplied.length, equals(1));
    });

    test('Reconciles email address: validates RFC structure and fixes (at) notation', () {
      final baseline = <String, FieldEvidence>{
        'emailAddresses': FieldEvidence(
          fieldName: 'emailAddresses',
          originalOcrText: 'sarah.connor(at)cyberdyne',
          normalizedValue: 'sarah.connor(at)cyberdyne',
          sourceEngine: 'PaddleOCR',
          sourceObservationIds: const ['front_3'],
          boundingBoxes: const [Rect.fromLTWH(50, 140, 200, 25)],
          ocrConfidence: 0.85,
          parserConfidence: 0.50,
          verificationStatus: FieldVerificationStatus.reviewRequired,
          side: CardSide.front,
        ),
      };

      final recovery = TargetedRegionRecoveryResult(
        request: const TargetedReOcrRequest(
          fieldName: 'emailAddresses',
          side: CardSide.front,
          targetBoundingBox: Rect.fromLTWH(50, 140, 200, 25),
          candidateText: 'sarah.connor(at)cyberdyne',
          triggerReason: 'Malformed email',
        ),
        recoveredObservations: [
          RecoveredOcrObservation(
            id: 'rec_front_mlkit_0',
            text: 'sarah.connor@cyberdyne.com',
            sourceEngine: 'Google ML Kit (Targeted)',
            side: CardSide.front,
            originalCoordinates: const Rect.fromLTWH(50, 140, 210, 25),
            cropCoordinates: const Rect.fromLTWH(5, 5, 200, 20),
            transformationMetadata: const CropTransformationMetadata(
              cropLeft: 45,
              cropTop: 135,
              cropWidth: 220,
              cropHeight: 35,
              originalWidth: 800,
              originalHeight: 500,
            ),
            ocrConfidence: 0.94,
            reprocessingReason: 'Malformed email',
            createdAt: DateTime.now(),
          ),
        ],
        transformationMetadata: const CropTransformationMetadata(
          cropLeft: 45,
          cropTop: 135,
          cropWidth: 220,
          cropHeight: 35,
          originalWidth: 800,
          originalHeight: 500,
        ),
      );

      final outcome = reconciler.reconcile(
        baselineEvidence: baseline,
        recoveryResults: [recovery],
      );

      final updatedEmail = outcome.updatedFieldEvidence['emailAddresses']!;
      expect(updatedEmail.effectiveValue, equals('sarah.connor@cyberdyne.com'));
      expect(updatedEmail.sourceEngine, contains('Google ML Kit'));
    });

    test('Reconciles person name vs company: rejects corporate tokens in person name', () {
      final baseline = <String, FieldEvidence>{
        'fullName': FieldEvidence(
          fieldName: 'fullName',
          originalOcrText: 'Apex Solutions Ltd', // Wrongly classified as name
          normalizedValue: 'Apex Solutions Ltd',
          sourceEngine: 'PaddleOCR',
          sourceObservationIds: const ['front_0'],
          boundingBoxes: const [Rect.fromLTWH(50, 30, 220, 30)],
          ocrConfidence: 0.92,
          parserConfidence: 0.60,
          verificationStatus: FieldVerificationStatus.reviewRequired,
          side: CardSide.front,
        ),
      };

      final recovery = TargetedRegionRecoveryResult(
        request: const TargetedReOcrRequest(
          fieldName: 'fullName',
          side: CardSide.front,
          targetBoundingBox: Rect.fromLTWH(50, 30, 220, 30),
          candidateText: 'Apex Solutions Ltd',
          triggerReason: 'Corporate tokens in name',
        ),
        recoveredObservations: [
          RecoveredOcrObservation(
            id: 'rec_front_paddle_1',
            text: 'Dr. Jane M. Foster', // True person name nearby
            sourceEngine: 'PaddleOCR (Targeted)',
            side: CardSide.front,
            originalCoordinates: const Rect.fromLTWH(50, 30, 190, 28),
            cropCoordinates: const Rect.fromLTWH(8, 5, 180, 25),
            transformationMetadata: const CropTransformationMetadata(
              cropLeft: 40,
              cropTop: 25,
              cropWidth: 210,
              cropHeight: 38,
              originalWidth: 800,
              originalHeight: 500,
            ),
            ocrConfidence: 0.95,
            reprocessingReason: 'Corporate tokens in name',
            createdAt: DateTime.now(),
          ),
        ],
        transformationMetadata: const CropTransformationMetadata(
          cropLeft: 40,
          cropTop: 25,
          cropWidth: 210,
          cropHeight: 38,
          originalWidth: 800,
          originalHeight: 500,
        ),
      );

      final outcome = reconciler.reconcile(
        baselineEvidence: baseline,
        recoveryResults: [recovery],
      );

      final updatedName = outcome.updatedFieldEvidence['fullName']!;
      expect(updatedName.effectiveValue, equals('Dr. Jane M. Foster'));
    });

    test('Reconciles multi-line address preserving vertical line sequence', () {
      final baseline = <String, FieldEvidence>{
        'address': FieldEvidence(
          fieldName: 'address',
          originalOcrText: 'Suite 400',
          normalizedValue: 'Suite 400',
          sourceEngine: 'PaddleOCR',
          sourceObservationIds: const ['front_4'],
          boundingBoxes: const [Rect.fromLTWH(50, 300, 120, 20)],
          ocrConfidence: 0.85,
          parserConfidence: 0.50,
          verificationStatus: FieldVerificationStatus.reviewRequired,
          side: CardSide.front,
        ),
      };

      final recovery = TargetedRegionRecoveryResult(
        request: const TargetedReOcrRequest(
          fieldName: 'address',
          side: CardSide.front,
          targetBoundingBox: Rect.fromLTWH(50, 300, 120, 20),
          candidateText: 'Suite 400',
          triggerReason: 'Short address',
        ),
        recoveredObservations: [
          RecoveredOcrObservation(
            id: 'rec_front_paddle_addr_1',
            text: '100 Silicon Way, Suite 400',
            sourceEngine: 'PaddleOCR (Targeted)',
            side: CardSide.front,
            originalCoordinates: const Rect.fromLTWH(50, 295, 250, 25),
            cropCoordinates: const Rect.fromLTWH(5, 5, 240, 20),
            transformationMetadata: const CropTransformationMetadata(
              cropLeft: 40,
              cropTop: 280,
              cropWidth: 300,
              cropHeight: 80,
              originalWidth: 800,
              originalHeight: 500,
            ),
            ocrConfidence: 0.95,
            reprocessingReason: 'Short address',
            createdAt: DateTime.now(),
          ),
          RecoveredOcrObservation(
            id: 'rec_front_paddle_addr_2',
            text: 'San Jose, CA 95134',
            sourceEngine: 'PaddleOCR (Targeted)',
            side: CardSide.front,
            originalCoordinates: const Rect.fromLTWH(50, 325, 180, 25),
            cropCoordinates: const Rect.fromLTWH(5, 35, 170, 20),
            transformationMetadata: const CropTransformationMetadata(
              cropLeft: 40,
              cropTop: 280,
              cropWidth: 300,
              cropHeight: 80,
              originalWidth: 800,
              originalHeight: 500,
            ),
            ocrConfidence: 0.94,
            reprocessingReason: 'Short address',
            createdAt: DateTime.now(),
          ),
        ],
        transformationMetadata: const CropTransformationMetadata(
          cropLeft: 40,
          cropTop: 280,
          cropWidth: 300,
          cropHeight: 80,
          originalWidth: 800,
          originalHeight: 500,
        ),
      );

      final outcome = reconciler.reconcile(
        baselineEvidence: baseline,
        recoveryResults: [recovery],
      );

      final updatedAddr = outcome.updatedFieldEvidence['address']!;
      expect(updatedAddr.effectiveValue, contains('100 Silicon Way, Suite 400'));
      expect(updatedAddr.effectiveValue, contains('San Jose, CA 95134'));
      expect(updatedAddr.sourceObservationIds.length, equals(2));
    });

    test('Never overwrites user manual edit during reconciliation', () {
      final userEditedBaseline = {
        'fullName': FieldEvidence(
          fieldName: 'fullName',
          originalOcrText: 'Dr. Sarah Connrr',
          normalizedValue: 'Dr. Sarah Connrr',
          userApprovedValue: 'Dr. Sarah Connor', // User corrected
          sourceEngine: 'PaddleOCR',
          sourceObservationIds: const ['front_0'],
          boundingBoxes: const [Rect.fromLTWH(50, 40, 200, 30)],
          ocrConfidence: 0.85,
          parserConfidence: 0.85,
          verificationStatus: FieldVerificationStatus.verified,
          verificationSource: 'userManualEdit',
          side: CardSide.front,
        ),
      };

      final recovery = TargetedRegionRecoveryResult(
        request: const TargetedReOcrRequest(
          fieldName: 'fullName',
          side: CardSide.front,
          targetBoundingBox: Rect.fromLTWH(50, 40, 200, 30),
          candidateText: 'Dr. Sarah Connrr',
          triggerReason: 'Testing preservation',
        ),
        recoveredObservations: [
          RecoveredOcrObservation(
            id: 'rec_front_0',
            text: 'Sarah Connors', // Disagreeing recovered text
            sourceEngine: 'PaddleOCR (Targeted)',
            side: CardSide.front,
            originalCoordinates: const Rect.fromLTWH(50, 40, 200, 30),
            cropCoordinates: const Rect.fromLTWH(5, 5, 190, 25),
            transformationMetadata: const CropTransformationMetadata(
              cropLeft: 45,
              cropTop: 35,
              cropWidth: 210,
              cropHeight: 40,
              originalWidth: 800,
              originalHeight: 500,
            ),
            ocrConfidence: 0.99,
            reprocessingReason: 'Testing preservation',
            createdAt: DateTime.now(),
          ),
        ],
        transformationMetadata: const CropTransformationMetadata(
          cropLeft: 45,
          cropTop: 35,
          cropWidth: 210,
          cropHeight: 40,
          originalWidth: 800,
          originalHeight: 500,
        ),
      );

      final outcome = reconciler.reconcile(
        baselineEvidence: userEditedBaseline,
        recoveryResults: [recovery],
      );

      final ev = outcome.updatedFieldEvidence['fullName']!;
      expect(ev.effectiveValue, equals('Dr. Sarah Connor'), reason: 'User manual edit must be strictly preserved');
      expect(ev.isUserEdited, isTrue);
    });
  });

  group('Stage 3 — Cache Correctness, Invalidation, and Card Isolation', () {
    test('Stores and retrieves cached targeted observations with exact key match', () async {
      final obs = [
        RecoveredOcrObservation(
          id: 'rec_front_1',
          text: '+91 98405 12345',
          sourceEngine: 'PaddleOCR (Targeted)',
          side: CardSide.front,
          originalCoordinates: const Rect.fromLTWH(50, 100, 200, 30),
          cropCoordinates: const Rect.fromLTWH(10, 5, 180, 25),
          transformationMetadata: const CropTransformationMetadata(
            cropLeft: 40,
            cropTop: 90,
            cropWidth: 220,
            cropHeight: 40,
            originalWidth: 800,
            originalHeight: 500,
          ),
          ocrConfidence: 0.97,
          reprocessingReason: 'Cache test',
          createdAt: DateTime.now(),
        ),
      ];

      const cropBox = Rect.fromLTWH(50, 100, 200, 30);
      await cache.put(
        imageHash: 'hash_abc123',
        side: CardSide.front,
        cropRect: cropBox,
        engine: 'PaddleOCR',
        observations: obs,
      );

      // Hit: same hash, side, and crop box
      final cachedHit = await cache.get(
        imageHash: 'hash_abc123',
        side: CardSide.front,
        cropRect: cropBox,
        engine: 'PaddleOCR',
      );
      expect(cachedHit, isNotNull);
      expect(cachedHit!.length, equals(1));
      expect(cachedHit.first.text, equals('+91 98405 12345'));

      // Miss: different side
      final missSide = await cache.get(
        imageHash: 'hash_abc123',
        side: CardSide.back,
        cropRect: cropBox,
        engine: 'PaddleOCR',
      );
      expect(missSide, isNull);

      // Miss: different image hash (CARD ISOLATION GUARANTEE)
      final missHash = await cache.get(
        imageHash: 'hash_coworker456',
        side: CardSide.front,
        cropRect: cropBox,
        engine: 'PaddleOCR',
      );
      expect(missHash, isNull, reason: 'Must NEVER reuse OCR results across different images/coworkers');
    });

    test('Invalidates cached entries when image hash is cleared', () async {
      const cropBox = Rect.fromLTWH(10, 10, 100, 20);
      await cache.put(
        imageHash: 'hash_to_invalidate',
        side: CardSide.front,
        cropRect: cropBox,
        engine: 'PaddleOCR',
        observations: [],
      );

      await cache.invalidateImage('hash_to_invalidate');
      final hit = await cache.get(
        imageHash: 'hash_to_invalidate',
        side: CardSide.front,
        cropRect: cropBox,
        engine: 'PaddleOCR',
      );
      expect(hit, isNull);
    });
  });

  group('Stage 3 — End-to-End Contact Reprocessing (Historical & Offline)', () {
    test('Reprocesses historical contact record with permanent image and updates evidence', () async {
      final savedContact = await repository.saveContact(
        {
          'fullName': 'Dr. Sarah Connrr', // OCR typo in baseline
          'phoneNumbers': ['98405 12'], // incomplete digits
        },
        frontImagePath: sampleFrontImageFile.path,
        frontObservations: [
          {
            'id': 'front_0',
            'text': 'Dr. Sarah Connrr',
            'boundingBox': {'left': 50.0, 'top': 40.0, 'width': 200.0, 'height': 30.0},
            'confidence': 0.60, // Low conf
            'engine': 'PaddleOCR',
          },
          {
            'id': 'front_1',
            'text': '98405 12',
            'boundingBox': {'left': 50.0, 'top': 90.0, 'width': 150.0, 'height': 25.0},
            'confidence': 0.70, // Incomplete
            'engine': 'PaddleOCR',
          },
        ],
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Dr. Sarah Connrr',
            normalizedValue: 'Dr. Sarah Connrr',
            sourceEngine: 'PaddleOCR',
            sourceObservationIds: const ['front_0'],
            boundingBoxes: const [Rect.fromLTWH(50, 40, 200, 30)],
            ocrConfidence: 0.60,
            parserConfidence: 0.60,
            verificationStatus: FieldVerificationStatus.reviewRequired,
            side: CardSide.front,
          ),
          'phoneNumbers': FieldEvidence(
            fieldName: 'phoneNumbers',
            originalOcrText: '98405 12',
            normalizedValue: '9840512',
            sourceEngine: 'PaddleOCR',
            sourceObservationIds: const ['front_1'],
            boundingBoxes: const [Rect.fromLTWH(50, 90, 150, 25)],
            ocrConfidence: 0.70,
            parserConfidence: 0.60,
            verificationStatus: FieldVerificationStatus.reviewRequired,
            side: CardSide.front,
          ),
        },
      );

      final initialRecord = await repository.getRecordById(savedContact.id);
      expect(initialRecord, isNotNull);
      expect(initialRecord!.hasCompleteEvidence, isTrue);

      final primaryEngine = MockOcrEngine('PaddleOCR', onRecognize: (path) async {
        return const OcrEngineResult(
          engineName: 'PaddleOCR',
          rawText: 'Dr. Sarah Connor\n+91 98405 12345',
          processingTime: Duration(milliseconds: 20),
          detectedLines: ['Dr. Sarah Connor', '+91 98405 12345'],
          observations: [
            OcrObservation(
              id: 'paddle_0',
              text: 'Dr. Sarah Connor',
              boundingBox: Rect.fromLTWH(10, 5, 190, 25),
              normalizedBoundingBox: Rect.fromLTWH(0, 0, 1, 1),
              engine: 'PaddleOCR',
              confidence: 0.98,
            ),
            OcrObservation(
              id: 'paddle_1',
              text: '+91 98405 12345',
              boundingBox: Rect.fromLTWH(10, 35, 180, 25),
              normalizedBoundingBox: Rect.fromLTWH(0, 0, 1, 1),
              engine: 'PaddleOCR',
              confidence: 0.97,
            ),
          ],
        );
      });

      final reprocessService = ContactReprocessingService(
        imageStorageService: imageService,
        cache: cache,
      );

      final reprocessResult = await reprocessService.reprocessRecord(
        record: initialRecord,
        primaryEngine: primaryEngine,
      );

      expect(reprocessResult.wasReprocessed, isTrue);
      expect(reprocessResult.improvementsApplied.length, greaterThanOrEqualTo(1));

      final updatedRecord = reprocessResult.updatedRecord;
      expect(updatedRecord.fullName, equals('Dr. Sarah Connor'));
      expect(updatedRecord.recoveredObservations.length, greaterThanOrEqualTo(1));

      // Verify original observations are PRESERVED
      expect(updatedRecord.frontObservations.length, equals(2));
      expect(updatedRecord.frontObservations[0]['text'], equals('Dr. Sarah Connrr'));

      // Save updated record
      await repository.updateLocalRecord(updatedRecord);
      final reloaded = await repository.getRecordById(savedContact.id);
      expect(reloaded!.fullName, equals('Dr. Sarah Connor'));
      expect(reloaded.recoveredObservations.isNotEmpty, isTrue);
    });

    test('Honestly handles missing or deleted permanent image without claiming recovery', () async {
      final savedContact = await repository.saveContact(
        {'fullName': 'John Doe'},
        frontImagePath: '/non_existent/deleted_card.jpg',
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'John D',
            normalizedValue: 'John D',
            sourceEngine: 'PaddleOCR',
            sourceObservationIds: const ['front_0'],
            boundingBoxes: const [Rect.fromLTWH(50, 40, 100, 30)],
            ocrConfidence: 0.50,
            parserConfidence: 0.50,
            verificationStatus: FieldVerificationStatus.reviewRequired,
            side: CardSide.front,
          ),
        },
      );

      final record = (await repository.getRecordById(savedContact.id))!;
      final reprocessService = ContactReprocessingService(imageStorageService: imageService);

      final result = await reprocessService.reprocessRecord(
        record: record,
        primaryEngine: MockOcrEngine('PaddleOCR'),
      );

      expect(result.wasReprocessed, isFalse);
      expect(result.diagnosticMessage, contains('missing or have been deleted'));
      expect(result.updatedRecord.fullName, equals('John Doe'), reason: 'Record must not be mutated if image is missing');
    });
  });
}
