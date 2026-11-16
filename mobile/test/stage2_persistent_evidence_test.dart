import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/field_evidence.dart';
import 'package:digital_share/models/imported_contact.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/ocr/ocr_observation.dart';
import 'package:digital_share/services/storage/card_image_storage_service.dart';
import 'package:digital_share/services/storage/local_contact_record.dart';
import 'package:digital_share/services/storage/local_contact_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testBaseDir;
  late CardImageStorageService imageService;
  late LocalContactRepository contactRepo;

  setUp(() async {
    testBaseDir = await Directory.systemTemp.createTemp('ds_stage2_test_');
    imageService = CardImageStorageService(baseDirectory: testBaseDir);
    contactRepo = LocalContactRepository(
      storageDirectory: Directory('${testBaseDir.path}/storage'),
      fileName: 'test_evidence_contacts.json',
      imageStorageService: imageService,
    );
    await imageService.ensureDirectoriesExist();
    await contactRepo.ensureLoaded();
  });

  tearDown(() async {
    try {
      if (await testBaseDir.exists()) {
        await testBaseDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Stage 2 — FieldEvidence Model & Verification States', () {
    test('FieldEvidence preserves complete metadata and does not mark verified on high OCR confidence alone', () {
      final evidence = FieldEvidence(
        fieldName: 'fullName',
        originalOcrText: 'DR. ELEANOR VANCE',
        normalizedValue: 'Dr. Eleanor Vance',
        sourceEngine: 'PaddleOCR (PP-OCRv5 Mobile)',
        sourceObservationIds: const ['front_obs_01', 'front_obs_02'],
        boundingBoxes: const [
          Rect.fromLTWH(50.0, 100.0, 300.0, 45.0),
          Rect.fromLTWH(360.0, 102.0, 80.0, 40.0),
        ],
        ocrConfidence: 0.985, // High OCR confidence
        parserConfidence: 0.950, // High semantic confidence
        verificationStatus: FieldVerificationStatus.probable, // MUST remain Probable until human/vision verified
        side: CardSide.front,
        processingVersion: '3.2.0',
      );

      // Verify that high confidence does NOT automatically become Verified
      expect(evidence.verificationStatus, equals(FieldVerificationStatus.probable));
      expect(evidence.isVerified, isFalse);
      expect(evidence.hasSupportingEvidence, isTrue);

      // Verify JSON serialization round-trip
      final json = evidence.toJson();
      expect(json['fieldName'], equals('fullName'));
      expect(json['verificationStatus'], equals('Probable'));
      expect(json['sourceObservationIds'], equals(['front_obs_01', 'front_obs_02']));
      expect((json['boundingBoxes'] as List).length, equals(2));

      final restored = FieldEvidence.fromJson(json);
      expect(restored.fieldName, equals(evidence.fieldName));
      expect(restored.normalizedValue, equals(evidence.normalizedValue));
      expect(restored.ocrConfidence, closeTo(0.985, 0.001));
      expect(restored.parserConfidence, closeTo(0.950, 0.001));
      expect(restored.verificationStatus, equals(FieldVerificationStatus.probable));
      expect(restored.boundingBoxes.length, equals(2));
      expect(restored.boundingBoxes[0], equals(const Rect.fromLTWH(50.0, 100.0, 300.0, 45.0)));
    });

    test('FieldEvidence.notFound creates non-manufactured empty reference', () {
      final notFound = FieldEvidence.notFound('website', side: CardSide.front);
      expect(notFound.fieldName, equals('website'));
      expect(notFound.normalizedValue, isEmpty);
      expect(notFound.sourceObservationIds, isEmpty);
      expect(notFound.boundingBoxes, isEmpty);
      expect(notFound.verificationStatus, equals(FieldVerificationStatus.notFound));
      expect(notFound.hasSupportingEvidence, isFalse);
    });
  });

  group('Stage 2 — LocalContactRecord Persistence & Round-Trip Serialization', () {
    test('Persists complete front and back OCR observations, bounding boxes, and field evidence', () async {
      final frontObs = [
        const OcrObservation(
          id: 'front_line_0',
          text: 'Acme Robotics Ltd.',
          boundingBox: Rect.fromLTWH(40, 60, 280, 50),
          normalizedBoundingBox: Rect.fromLTWH(0.04, 0.06, 0.28, 0.05),
          confidence: 0.99,
          engine: 'PaddleOCR (PP-OCRv5 Mobile)',
          lineIndex: 0,
        ).toJson(),
        const OcrObservation(
          id: 'front_line_1',
          text: 'Dr. Evelyn Reed',
          boundingBox: Rect.fromLTWH(40, 120, 220, 40),
          normalizedBoundingBox: Rect.fromLTWH(0.04, 0.12, 0.22, 0.04),
          confidence: 0.98,
          engine: 'PaddleOCR (PP-OCRv5 Mobile)',
          lineIndex: 1,
        ).toJson(),
      ];

      final backObs = [
        const OcrObservation(
          id: 'back_line_0',
          text: '100 Technology Square, Suite 400',
          boundingBox: Rect.fromLTWH(50, 80, 400, 35),
          normalizedBoundingBox: Rect.fromLTWH(0.05, 0.08, 0.40, 0.035),
          confidence: 0.95,
          engine: 'PaddleOCR (PP-OCRv5 Mobile)',
          lineIndex: 0,
        ).toJson(),
        const OcrObservation(
          id: 'back_line_1',
          text: 'Cambridge, MA 02139',
          boundingBox: Rect.fromLTWH(50, 120, 250, 35),
          normalizedBoundingBox: Rect.fromLTWH(0.05, 0.12, 0.25, 0.035),
          confidence: 0.96,
          engine: 'PaddleOCR (PP-OCRv5 Mobile)',
          lineIndex: 1,
        ).toJson(),
      ];

      final fieldEvidenceMap = <String, FieldEvidence>{
        'fullName': FieldEvidence(
          fieldName: 'fullName',
          originalOcrText: 'Dr. Evelyn Reed',
          normalizedValue: 'Dr. Evelyn Reed',
          sourceEngine: 'PaddleOCR (PP-OCRv5 Mobile)',
          sourceObservationIds: const ['front_line_1'],
          boundingBoxes: const [Rect.fromLTWH(40, 120, 220, 40)],
          ocrConfidence: 0.98,
          parserConfidence: 0.95,
          verificationStatus: FieldVerificationStatus.probable,
          side: CardSide.front,
        ),
        'company': FieldEvidence(
          fieldName: 'company',
          originalOcrText: 'Acme Robotics Ltd.',
          normalizedValue: 'Acme Robotics Ltd.',
          sourceEngine: 'PaddleOCR (PP-OCRv5 Mobile)',
          sourceObservationIds: const ['front_line_0'],
          boundingBoxes: const [Rect.fromLTWH(40, 60, 280, 50)],
          ocrConfidence: 0.99,
          parserConfidence: 0.96,
          verificationStatus: FieldVerificationStatus.probable,
          side: CardSide.front,
        ),
        // Multiline Address on Back Side
        'address': FieldEvidence(
          fieldName: 'address',
          originalOcrText: '100 Technology Square, Suite 400, Cambridge, MA 02139',
          normalizedValue: '100 Technology Square, Suite 400, Cambridge, MA 02139',
          sourceEngine: 'PaddleOCR (PP-OCRv5 Mobile)',
          sourceObservationIds: const ['back_line_0', 'back_line_1'],
          boundingBoxes: const [
            Rect.fromLTWH(50, 80, 400, 35),
            Rect.fromLTWH(50, 120, 250, 35),
          ],
          ocrConfidence: 0.955,
          parserConfidence: 0.92,
          verificationStatus: FieldVerificationStatus.probable,
          side: CardSide.back,
        ),
      };

      final record = LocalContactRecord(
        id: 'contact_evidence_001',
        fullName: 'Dr. Evelyn Reed',
        company: 'Acme Robotics Ltd.',
        address: '100 Technology Square, Suite 400, Cambridge, MA 02139',
        phoneNumbers: const [ImportedContactPhone(number: '+1 617-555-0199')],
        emailAddresses: const [ImportedContactEmail(email: 'evelyn@acmerobotics.com')],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        frontRawText: 'Acme Robotics Ltd.\nDr. Evelyn Reed',
        backRawText: '100 Technology Square, Suite 400\nCambridge, MA 02139',
        frontObservations: frontObs,
        backObservations: backObs,
        ocrEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        ocrModelVersion: 'PP-OCRv5_mobile',
        overallOcrConfidence: 0.97,
        fieldEvidence: fieldEvidenceMap,
        parserVersion: '3.2.0',
        preprocessingVersion: '1.0.0',
      );

      // 1. Verify helper properties
      expect(record.hasCompleteEvidence, isTrue);
      expect(record.hasRawOcrOnly, isFalse);

      // 2. Persist to repository
      await contactRepo.updateLocalRecord(record);

      // 3. Load from disk and verify
      final restored = await contactRepo.getRecordById('contact_evidence_001');
      expect(restored, isNotNull);
      expect(restored!.fullName, equals('Dr. Evelyn Reed'));
      expect(restored.frontObservations.length, equals(2));
      expect(restored.backObservations.length, equals(2));
      expect(restored.ocrEngineName, equals('PaddleOCR (PP-OCRv5 Mobile)'));
      expect(restored.fieldEvidence.containsKey('address'), isTrue);

      final addressEv = restored.fieldEvidence['address']!;
      expect(addressEv.sourceObservationIds, equals(['back_line_0', 'back_line_1']));
      expect(addressEv.boundingBoxes.length, equals(2));
      expect(addressEv.side, equals(CardSide.back));
      expect(addressEv.boundingBoxes[0], equals(const Rect.fromLTWH(50, 80, 400, 35)));
      expect(addressEv.boundingBoxes[1], equals(const Rect.fromLTWH(50, 120, 250, 35)));
    });

    test('Front and back observations remain strictly independent without cross-side contamination', () async {
      final frontObs = [
        const OcrObservation(
          id: 'front_0',
          text: 'Front Only Text',
          boundingBox: Rect.fromLTWH(10, 10, 100, 20),
          normalizedBoundingBox: Rect.fromLTWH(0.1, 0.1, 0.5, 0.1),
          engine: 'MLKit',
        ).toJson(),
      ];
      final backObs = [
        const OcrObservation(
          id: 'back_0',
          text: 'Back Only Details',
          boundingBox: Rect.fromLTWH(20, 20, 150, 30),
          normalizedBoundingBox: Rect.fromLTWH(0.2, 0.2, 0.6, 0.15),
          engine: 'PaddleOCR',
        ).toJson(),
      ];

      final record = LocalContactRecord(
        id: 'independent_sides_01',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        frontObservations: frontObs,
        backObservations: backObs,
      );

      final json = record.toJson();
      expect(json['frontObservations'][0]['id'], equals('front_0'));
      expect(json['backObservations'][0]['id'], equals('back_0'));

      final loaded = LocalContactRecord.fromJson(json);
      expect(loaded.frontObservations.single['text'], equals('Front Only Text'));
      expect(loaded.backObservations.single['text'], equals('Back Only Details'));
    });
  });

  group('Stage 2 — Backward-Compatible Legacy Migration', () {
    test('Correctly deserializes legacy JSON missing evidence without fabricating observations', () {
      final legacyJson = {
        'id': 'legacy_rec_1990',
        'fullName': 'Arthur Dent',
        'company': 'Megadodo Publications',
        'jobTitle': 'Field Researcher',
        'phoneNumbers': [
          {'number': '+44 20 7946 0991'}
        ],
        'emailAddresses': [
          {'email': 'arthur@hitchhiker.guide'}
        ],
        'address': 'Cottington, UK',
        'rawRecognizedText': 'Arthur Dent\nMegadodo Publications\nField Researcher\n+44 20 7946 0991',
        'syncStatus': 'synced',
        'createdAt': '2025-05-10T12:00:00.000Z',
        'updatedAt': '2025-05-10T12:00:00.000Z',
      };

      final record = LocalContactRecord.fromJson(legacyJson);

      // Safe defaults must be provided
      expect(record.id, equals('legacy_rec_1990'));
      expect(record.fullName, equals('Arthur Dent'));
      expect(record.company, equals('Megadodo Publications'));
      expect(record.phoneNumbers.first.number, equals('+44 20 7946 0991'));
      expect(record.emailAddresses.first.email, equals('arthur@hitchhiker.guide'));

      // Evidence flags must clearly reflect legacy status
      expect(record.hasCompleteEvidence, isFalse);
      expect(record.hasRawOcrOnly, isTrue);

      // NO observations must be fabricated
      expect(record.frontObservations, isEmpty);
      expect(record.backObservations, isEmpty);
      expect(record.fieldEvidence, isEmpty);
      expect(record.ocrEngineName, isNull);

      // Raw text must be preserved
      expect(record.frontRawText, equals(record.rawRecognizedText));
    });

    test('Loads legacy contacts from disk and updates fields without evidence loss', () async {
      // Write legacy raw JSON file to disk
      final storeFile = File('${testBaseDir.path}/storage/test_evidence_contacts.json');
      await storeFile.parent.create(recursive: true);
      await storeFile.writeAsString(jsonEncode([
        {
          'id': 'legacy_disk_rec_42',
          'fullName': 'Ford Prefect',
          'company': 'Sub-Etha Corporation',
          'phoneNumbers': [],
          'emailAddresses': [],
          'syncStatus': 'synced',
          'createdAt': '2025-06-01T10:00:00.000Z',
          'updatedAt': '2025-06-01T10:00:00.000Z',
          'rawRecognizedText': 'Ford Prefect Sub-Etha',
        }
      ]));

      // Instantiate fresh repository
      final repo = LocalContactRepository(
        storageDirectory: Directory('${testBaseDir.path}/storage'),
        fileName: 'test_evidence_contacts.json',
        imageStorageService: imageService,
      );
      await repo.ensureLoaded();

      final record = await repo.getRecordById('legacy_disk_rec_42');
      expect(record, isNotNull);
      expect(record!.fullName, equals('Ford Prefect'));
      expect(record.hasCompleteEvidence, isFalse);
      expect(record.hasRawOcrOnly, isTrue);

      // Update contact name
      final updated = await repo.updateContact('legacy_disk_rec_42', {
        'fullName': 'Ford Prefect (Betelgeuse)',
      });
      expect(updated.fullName, equals('Ford Prefect (Betelgeuse)'));

      final updatedRecord = await repo.getRecordById('legacy_disk_rec_42');
      expect(updatedRecord!.fullName, equals('Ford Prefect (Betelgeuse)'));
      expect(updatedRecord.rawRecognizedText, equals('Ford Prefect Sub-Etha'));
    });
  });

  group('Stage 2 — Corrupt and Incomplete Evidence Handling', () {
    test('Safely parses corrupt or malformed field evidence entries without crashing', () {
      final corruptJson = {
        'id': 'corrupt_ev_rec',
        'fullName': 'Corrupt Data Person',
        'createdAt': '2026-11-04T00:00:00.000Z',
        'updatedAt': '2026-11-04T00:00:00.000Z',
        'fieldEvidence': {
          'fullName': {
            'fieldName': 'fullName',
            'verificationStatus': 'NonExistentStatusXYZ',
            'boundingBoxes': 'NotAList', // malformed
            'ocrConfidence': 'NotANumber', // malformed
          },
          'invalidField': {
            'fieldName': 'invalidField',
          }
        },
      };

      final record = LocalContactRecord.fromJson(corruptJson);
      expect(record.fullName, equals('Corrupt Data Person'));
      expect(record.fieldEvidence.containsKey('fullName'), isTrue);

      final nameEv = record.fieldEvidence['fullName']!;
      expect(nameEv.verificationStatus, equals(FieldVerificationStatus.notFound));
      expect(nameEv.boundingBoxes, isEmpty);
      expect(nameEv.ocrConfidence, equals(1.0));
    });
  });

  group('Stage 2 — Parser Integration with Contributing Evidence', () {
    const parser = BusinessCardParser();

    test('parseSide creates granular FieldEvidence referencing line indices and bounding boxes', () {
      final lines = [
        const OcrLineMetadata(
          text: 'Nova Health Solutions',
          side: CardSide.front,
          lineIndex: 0,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(50, 40, 300, 35),
          confidence: 0.98,
        ),
        const OcrLineMetadata(
          text: 'Dr. Sarah Connor',
          side: CardSide.front,
          lineIndex: 1,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(50, 90, 240, 35),
          confidence: 0.99,
        ),
        const OcrLineMetadata(
          text: 'Chief Medical Officer',
          side: CardSide.front,
          lineIndex: 2,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(50, 135, 220, 28),
          confidence: 0.95,
        ),
        const OcrLineMetadata(
          text: '+1 (555) 789-0123',
          side: CardSide.front,
          lineIndex: 3,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(50, 180, 180, 25),
          confidence: 0.97,
        ),
        const OcrLineMetadata(
          text: 'sarah.connor@novahealth.org',
          side: CardSide.front,
          lineIndex: 4,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(50, 215, 260, 25),
          confidence: 0.96,
        ),
      ];

      final sideResult = OcrSideResult(
        side: CardSide.front,
        imagePath: '/tmp/card_front.jpg',
        rawText: 'Nova Health Solutions\nDr. Sarah Connor\nChief Medical Officer\n+1 (555) 789-0123\nsarah.connor@novahealth.org',
        lines: lines,
      );

      final parsed = parser.parseSide(sideResult);

      expect(parsed.fullName, equals('Dr. Sarah Connor'));
      expect(parsed.company, equals('Nova Health Solutions'));
      expect(parsed.jobTitle, equals('Chief Medical Officer'));

      // Check FieldEvidence
      expect(parsed.fieldEvidence.containsKey('fullName'), isTrue);
      final nameEv = parsed.fieldEvidence['fullName']!;
      expect(nameEv.normalizedValue, equals('Dr. Sarah Connor'));
      expect(nameEv.sourceObservationIds, equals(['front_1']));
      expect(nameEv.boundingBoxes, equals([const Rect.fromLTWH(50, 90, 240, 35)]));
      expect(nameEv.side, equals(CardSide.front));

      expect(parsed.fieldEvidence.containsKey('company'), isTrue);
      final compEv = parsed.fieldEvidence['company']!;
      expect(compEv.normalizedValue, equals('Nova Health Solutions'));
      expect(compEv.sourceObservationIds, equals(['front_0']));

      expect(parsed.fieldEvidence.containsKey('jobTitle'), isTrue);
      final titleEv = parsed.fieldEvidence['jobTitle']!;
      expect(titleEv.normalizedValue, equals('Chief Medical Officer'));
      expect(titleEv.sourceObservationIds, equals(['front_2']));

      expect(parsed.fieldEvidence.containsKey('phone'), isTrue);
      final phoneEv = parsed.fieldEvidence['phone']!;
      expect(phoneEv.sourceObservationIds, equals(['front_3']));

      expect(parsed.fieldEvidence.containsKey('email'), isTrue);
      final emailEv = parsed.fieldEvidence['email']!;
      expect(emailEv.sourceObservationIds, equals(['front_4']));

      // Website was absent: no fabricated observation reference
      expect(parsed.fieldEvidence.containsKey('website'), isFalse);
    });

    test('parseDualSided retains back-side evidence when front contains name and company', () {
      final frontLines = [
        const OcrLineMetadata(
          text: 'Dr. Sarah Connor',
          side: CardSide.front,
          lineIndex: 0,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(50, 50, 200, 30),
        ),
        const OcrLineMetadata(
          text: 'Nova Health',
          side: CardSide.front,
          lineIndex: 1,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(50, 90, 180, 30),
        ),
      ];

      final backLines = [
        const OcrLineMetadata(
          text: 'Suite 500, Medical Tower',
          side: CardSide.back,
          lineIndex: 0,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(40, 40, 300, 30),
        ),
        const OcrLineMetadata(
          text: 'Boston, MA 02115',
          side: CardSide.back,
          lineIndex: 1,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(40, 80, 200, 30),
        ),
      ];

      final frontResult = OcrSideResult(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: 'Dr. Sarah Connor\nNova Health',
        lines: frontLines,
      );

      final backResult = OcrSideResult(
        side: CardSide.back,
        imagePath: '/tmp/b.jpg',
        rawText: 'Suite 500, Medical Tower\nBoston, MA 02115',
        lines: backLines,
      );

      final dual = parser.parseDualSided(front: frontResult, back: backResult);
      expect(dual.fullName, equals('Dr. Sarah Connor'));
      expect(dual.company, equals('Nova Health'));
      expect(dual.address, contains('Medical Tower'));

      // Verify that back side evidence is completely preserved
      expect(dual.fieldEvidence.containsKey('address'), isTrue);
      final addrEv = dual.fieldEvidence['address']!;
      expect(addrEv.sourceObservationIds, contains('back_0'));
      expect(addrEv.side, equals(CardSide.back));
    });
  });

  group('Stage 2 — Contact Updates and Deletion Lifecycle', () {
    test('Updating contact fields does not erase existing observations or evidence', () async {
      final record = LocalContactRecord(
        id: 'update_test_rec_01',
        fullName: 'Initial Name',
        company: 'Initial Co',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        frontObservations: [
          {'id': 'front_0', 'text': 'Initial Name'}
        ],
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Initial Name',
            normalizedValue: 'Initial Name',
            sourceEngine: 'PaddleOCR',
            sourceObservationIds: const ['front_0'],
          ),
        },
      );

      await contactRepo.updateLocalRecord(record);

      // Update company
      await contactRepo.updateContact('update_test_rec_01', {
        'company': 'Updated Co Worldwide',
      });

      final retrieved = await contactRepo.getRecordById('update_test_rec_01');
      expect(retrieved, isNotNull);
      expect(retrieved!.company, equals('Updated Co Worldwide'));
      expect(retrieved.fullName, equals('Initial Name'));
      expect(retrieved.frontObservations.length, equals(1));
      expect(retrieved.fieldEvidence.containsKey('fullName'), isTrue);
    });

    test('Deleting contact deletes record and cleans up associated permanent image files', () async {
      // 1. Create permanent image files
      final frontFile = File('${testBaseDir.path}/cards/images/delete_test_rec_front.jpg');
      await frontFile.parent.create(recursive: true);
      await frontFile.writeAsBytes([1, 2, 3], flush: true);

      final record = LocalContactRecord(
        id: 'delete_test_rec',
        fullName: 'To Be Deleted',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        frontImagePath: frontFile.path,
        frontObservations: [{'id': 'front_0', 'text': 'To Be Deleted'}],
      );

      await contactRepo.updateLocalRecord(record);
      expect(await frontFile.exists(), isTrue);

      // 2. Delete contact
      await contactRepo.deleteContact('delete_test_rec', markPendingSync: false);

      // 3. Verify record and image files are gone
      final retrieved = await contactRepo.getRecordById('delete_test_rec');
      expect(retrieved, isNull);
      expect(await frontFile.exists(), isFalse);
    });
  });
}
