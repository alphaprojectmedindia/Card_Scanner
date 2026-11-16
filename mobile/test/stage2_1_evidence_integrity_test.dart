import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/field_evidence.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/storage/card_image_storage_service.dart';
import 'package:digital_share/services/storage/local_contact_record.dart';
import 'package:digital_share/services/storage/local_contact_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late CardImageStorageService imageService;
  late LocalContactRepository repository;
  const parser = BusinessCardParser();

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('ds_stage2_1_integrity_test_');
    imageService = CardImageStorageService(baseDirectory: testDir);
    await imageService.ensureDirectoriesExist();

    repository = LocalContactRepository(
      storageDirectory: Directory('${testDir.path}/storage'),
      fileName: 'test_contacts_integrity.json',
      imageStorageService: imageService,
    );
    await repository.ensureLoaded();
  });

  tearDown(() async {
    try {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Stage 2.1 — Observation Reference Integrity', () {
    test('OcrSideResult generates unique, stable observation IDs matching line index', () {
      final lines = [
        const OcrLineMetadata(
          text: 'Acme Corporation',
          side: CardSide.front,
          lineIndex: 0,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(10, 10, 200, 30),
          confidence: 0.98,
        ),
        const OcrLineMetadata(
          text: 'Dr. Jane Doe',
          side: CardSide.front,
          lineIndex: 1,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(10, 50, 150, 30),
          confidence: 0.99,
        ),
      ];

      final sideResult = OcrSideResult(
        side: CardSide.front,
        imagePath: '/tmp/card.jpg',
        rawText: 'Acme Corporation\nDr. Jane Doe',
        lines: lines,
      );

      final obs = sideResult.observations;
      expect(obs.length, equals(2));
      expect(obs[0]['id'], equals('front_0'));
      expect(obs[1]['id'], equals('front_1'));
      expect(obs[0]['text'], equals('Acme Corporation'));
      expect(obs[1]['text'], equals('Dr. Jane Doe'));
    });

    test('Record evidence integrity validation detects cross-side contamination, missing, and duplicate IDs', () {
      final validRecord = LocalContactRecord(
        id: 'rec_valid_01',
        fullName: 'Valid Person',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        frontObservations: [
          {
            'id': 'front_0',
            'text': 'Valid Person',
            'side': 'front',
            'boundingBox': {'left': 10.0, 'top': 20.0, 'width': 100.0, 'height': 25.0},
          }
        ],
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Valid Person',
            normalizedValue: 'Valid Person',
            sourceEngine: 'PaddleOCR',
            sourceObservationIds: const ['front_0'],
            boundingBoxes: const [Rect.fromLTWH(10, 20, 100, 25)],
            side: CardSide.front,
          ),
        },
      );

      expect(validRecord.validateEvidenceIntegrity(), isEmpty);

      // Record with cross-side reference violation (front field references back observation)
      final crossSideRecord = validRecord.copyWith(
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Valid Person',
            normalizedValue: 'Valid Person',
            sourceEngine: 'PaddleOCR',
            sourceObservationIds: const ['back_0'], // VIOLATION
            boundingBoxes: const [Rect.fromLTWH(10, 20, 100, 25)],
            side: CardSide.front,
          ),
        },
      );
      final crossViolations = crossSideRecord.validateEvidenceIntegrity();
      expect(crossViolations, isNotEmpty);
      expect(crossViolations.any((v) => v.contains('references BACK observation')), isTrue);

      // Record with non-existent observation ID
      final missingObsRecord = validRecord.copyWith(
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Valid Person',
            normalizedValue: 'Valid Person',
            sourceEngine: 'PaddleOCR',
            sourceObservationIds: const ['front_999'], // MISSING
            side: CardSide.front,
          ),
        },
      );
      final missingViolations = missingObsRecord.validateEvidenceIntegrity();
      expect(missingViolations.any((v) => v.contains('non-existent observation')), isTrue);

      // Record with duplicate observation reference
      final duplicateObsRecord = validRecord.copyWith(
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Valid Person',
            normalizedValue: 'Valid Person',
            sourceEngine: 'PaddleOCR',
            sourceObservationIds: const ['front_0', 'front_0'], // DUPLICATE
            side: CardSide.front,
          ),
        },
      );
      final dupViolations = duplicateObsRecord.validateEvidenceIntegrity();
      expect(dupViolations.any((v) => v.contains('duplicate observation reference')), isTrue);
    });

    test('Multi-line address retains all contributing observation IDs and bounding boxes', () {
      final backLines = [
        const OcrLineMetadata(
          text: 'Building 4, Sector 7',
          side: CardSide.back,
          lineIndex: 0,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(20, 30, 200, 25),
          confidence: 0.95,
        ),
        const OcrLineMetadata(
          text: 'Connaught Place, New Delhi',
          side: CardSide.back,
          lineIndex: 1,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(20, 60, 250, 25),
          confidence: 0.96,
        ),
      ];

      final backResult = OcrSideResult(
        side: CardSide.back,
        imagePath: '/tmp/back.jpg',
        rawText: 'Building 4, Sector 7\nConnaught Place, New Delhi',
        lines: backLines,
      );

      final parsed = parser.parseSide(backResult);
      expect(parsed.fieldEvidence.containsKey('address'), isTrue);

      final addrEv = parsed.fieldEvidence['address']!;
      expect(addrEv.sourceObservationIds, containsAll(['back_0', 'back_1']));
      expect(addrEv.boundingBoxes.length, equals(2));
      expect(addrEv.side, equals(CardSide.back));
      expect(addrEv.sourceEngine, isNotEmpty);
    });
  });

  group('Stage 2.1 — User Correction Integrity', () {
    test('Editing a contact preserves original OCR evidence and records correction separately', () async {
      // 1. Initial save with raw OCR evidence
      final saved = await repository.saveContact(
        {
          'fullName': 'Dr. Sarah Connrr', // Typo in OCR
          'company': 'Nova Health',
        },
        rawRecognizedText: 'Dr. Sarah Connrr\nNova Health',
        frontRawText: 'Dr. Sarah Connrr\nNova Health',
        frontObservations: [
          {
            'id': 'front_0',
            'text': 'Dr. Sarah Connrr',
            'side': 'front',
            'confidence': 0.88,
            'boundingBox': {'left': 50.0, 'top': 50.0, 'width': 200.0, 'height': 30.0},
          },
          {
            'id': 'front_1',
            'text': 'Nova Health',
            'side': 'front',
            'confidence': 0.95,
            'boundingBox': {'left': 50.0, 'top': 90.0, 'width': 180.0, 'height': 30.0},
          },
        ],
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Dr. Sarah Connrr',
            normalizedValue: 'Dr. Sarah Connrr',
            sourceEngine: 'PaddleOCR',
            sourceObservationIds: const ['front_0'],
            boundingBoxes: const [Rect.fromLTWH(50, 50, 200, 30)],
            ocrConfidence: 0.88,
            parserConfidence: 0.70,
            verificationStatus: FieldVerificationStatus.reviewRequired,
            side: CardSide.front,
          ),
          'company': FieldEvidence(
            fieldName: 'company',
            originalOcrText: 'Nova Health',
            normalizedValue: 'Nova Health',
            sourceEngine: 'PaddleOCR',
            sourceObservationIds: const ['front_1'],
            boundingBoxes: const [Rect.fromLTWH(50, 90, 180, 30)],
            ocrConfidence: 0.95,
            parserConfidence: 0.85,
            verificationStatus: FieldVerificationStatus.probable,
            side: CardSide.front,
          ),
        },
      );

      final initialRecord = await repository.getRecordById(saved.id);
      expect(initialRecord, isNotNull);
      expect(initialRecord!.fieldEvidence['fullName']!.verificationStatus, equals(FieldVerificationStatus.reviewRequired));
      expect(initialRecord.fieldEvidence['fullName']!.isUserEdited, isFalse);

      // 2. User edits fullName in contact review/edit screen
      await repository.updateContact(saved.id, {
        'fullName': 'Dr. Sarah Connor', // Corrected name
      });

      final updatedRecord = await repository.getRecordById(saved.id);
      expect(updatedRecord, isNotNull);
      expect(updatedRecord!.fullName, equals('Dr. Sarah Connor'));

      // Check evidence preservation
      final nameEv = updatedRecord.fieldEvidence['fullName']!;
      expect(nameEv.originalOcrText, equals('Dr. Sarah Connrr')); // PRESERVED
      expect(nameEv.normalizedValue, equals('Dr. Sarah Connrr')); // PRESERVED
      expect(nameEv.userApprovedValue, equals('Dr. Sarah Connor')); // USER CORRECTION
      expect(nameEv.effectiveValue, equals('Dr. Sarah Connor'));
      expect(nameEv.isUserEdited, isTrue);
      expect(nameEv.verificationStatus, equals(FieldVerificationStatus.verified)); // VERIFIED VIA USER
      expect(nameEv.verificationSource, equals('userManualEdit'));
      expect(nameEv.verifiedAt, isNotNull);
      expect(nameEv.sourceObservationIds, equals(['front_0'])); // PRESERVED
      expect(nameEv.boundingBoxes.length, equals(1)); // PRESERVED

      // Unedited field (company) must NOT be marked verified falsely
      final companyEv = updatedRecord.fieldEvidence['company']!;
      expect(companyEv.isUserEdited, isFalse);
      expect(companyEv.verificationStatus, equals(FieldVerificationStatus.probable)); // NOT falsely verified
      expect(companyEv.verificationSource, equals('ocrBaseline'));
    });
  });

  group('Stage 2.1 — Dual-Sided Conflict Handling', () {
    test('Aligns primary evidence key with chosen candidate and preserves non-chosen side under prefix', () {
      final frontLines = [
        const OcrLineMetadata(
          text: 'Suite 400',
          side: CardSide.front,
          lineIndex: 0,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(50, 50, 150, 25),
        ),
      ];

      final backLines = [
        const OcrLineMetadata(
          text: '123 Innovation Way, Suite 400',
          side: CardSide.back,
          lineIndex: 0,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(40, 40, 280, 25),
        ),
        const OcrLineMetadata(
          text: 'Austin, TX 78701',
          side: CardSide.back,
          lineIndex: 1,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(40, 70, 180, 25),
        ),
      ];

      final frontResult = OcrSideResult(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: 'Suite 400',
        lines: frontLines,
      );

      final backResult = OcrSideResult(
        side: CardSide.back,
        imagePath: '/tmp/b.jpg',
        rawText: '123 Innovation Way, Suite 400\nAustin, TX 78701',
        lines: backLines,
      );

      final dual = parser.parseDualSided(front: frontResult, back: backResult);

      // Back address is richer/more complete than front
      expect(dual.address, contains('123 Innovation Way'));

      // Primary evidence for 'address' must be from the back side where the value originated
      expect(dual.fieldEvidence.containsKey('address'), isTrue);
      final primaryAddrEv = dual.fieldEvidence['address']!;
      expect(primaryAddrEv.sourceObservationIds, contains('back_0'));
      expect(primaryAddrEv.side, equals(CardSide.back));

      // Front address evidence must be non-destructively preserved under front_address
      expect(dual.fieldEvidence.containsKey('front_address'), isTrue);
      final frontAddrEv = dual.fieldEvidence['front_address']!;
      expect(frontAddrEv.sourceObservationIds, contains('front_0'));
      expect(frontAddrEv.side, equals(CardSide.front));
    });

    test('Complementary front and back address lines merge into CardSide.both with combined observations', () {
      final frontLines = [
        const OcrLineMetadata(
          text: 'Floor 3, Tech Hub',
          side: CardSide.front,
          lineIndex: 0,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(50, 50, 150, 25),
        ),
      ];

      final backLines = [
        const OcrLineMetadata(
          text: '123 Innovation Way',
          side: CardSide.back,
          lineIndex: 0,
          blockIndex: 0,
          boundingBox: Rect.fromLTWH(40, 40, 280, 25),
        ),
      ];

      final frontResult = OcrSideResult(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: 'Floor 3, Tech Hub',
        lines: frontLines,
      );

      final backResult = OcrSideResult(
        side: CardSide.back,
        imagePath: '/tmp/b.jpg',
        rawText: '123 Innovation Way',
        lines: backLines,
      );

      final dual = parser.parseDualSided(front: frontResult, back: backResult);
      expect(dual.address, equals('Floor 3, Tech Hub, 123 Innovation Way'));

      final addrEv = dual.fieldEvidence['address']!;
      expect(addrEv.side, equals(CardSide.both));
      expect(addrEv.sourceObservationIds, containsAll(['front_0', 'back_0']));
      expect(addrEv.boundingBoxes.length, equals(2));
    });
  });

  group('Stage 2.1 — Persistence and Safe Failure Recovery', () {
    test('Interrupted write recovery safely restores from backup (.bak) or temp (.tmp) file', () async {
      final record = LocalContactRecord(
        id: 'rec_crash_01',
        fullName: 'Crash Resilient Contact',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        frontObservations: [
          {'id': 'front_0', 'text': 'Crash Resilient Contact'}
        ],
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Crash Resilient Contact',
            normalizedValue: 'Crash Resilient Contact',
            sourceEngine: 'PaddleOCR',
            sourceObservationIds: const ['front_0'],
          ),
        },
      );

      await repository.updateLocalRecord(record);

      final storeFile = File('${testDir.path}/storage/test_contacts_integrity.json');
      expect(await storeFile.exists(), isTrue);

      // Simulate a sudden crash that created a valid backup but corrupted storeFile to 0 bytes
      final backupFile = File('${storeFile.path}.bak');
      await storeFile.copy(backupFile.path);
      await storeFile.writeAsString('', flush: true); // Truncated/corrupted file
      expect(await storeFile.length(), equals(0));

      // Instantiate a new repository representing app restart after crash
      final recoveredRepo = LocalContactRepository(
        storageDirectory: Directory('${testDir.path}/storage'),
        fileName: 'test_contacts_integrity.json',
        imageStorageService: imageService,
      );
      await recoveredRepo.ensureLoaded();

      final recoveredRecord = await recoveredRepo.getRecordById('rec_crash_01');
      expect(recoveredRecord, isNotNull);
      expect(recoveredRecord!.fullName, equals('Crash Resilient Contact'));
      expect(recoveredRecord.fieldEvidence.containsKey('fullName'), isTrue);
    });

    test('Front-only and dual-sided contact save, reload, and permanent image cleanup', () async {
      final tempDir = await Directory.systemTemp.createTemp('temp_imgs_');
      final fImg = File('${tempDir.path}/front.jpg');
      final bImg = File('${tempDir.path}/back.jpg');
      await fImg.writeAsBytes([1, 2, 3, 4], flush: true);
      await bImg.writeAsBytes([5, 6, 7, 8], flush: true);

      final saved = await repository.saveContact(
        {
          'fullName': 'Dual Sided Person',
          'company': 'Dual Corp',
        },
        frontImagePath: fImg.path,
        backImagePath: bImg.path,
        frontRawText: 'Dual Sided Person',
        backRawText: 'Dual Corp',
        frontObservations: [
          {'id': 'front_0', 'text': 'Dual Sided Person'}
        ],
        backObservations: [
          {'id': 'back_0', 'text': 'Dual Corp'}
        ],
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Dual Sided Person',
            normalizedValue: 'Dual Sided Person',
            sourceEngine: 'PaddleOCR',
            sourceObservationIds: const ['front_0'],
          ),
          'company': FieldEvidence(
            fieldName: 'company',
            originalOcrText: 'Dual Corp',
            normalizedValue: 'Dual Corp',
            sourceEngine: 'PaddleOCR',
            sourceObservationIds: const ['back_0'],
            side: CardSide.back,
          ),
        },
      );

      final loadedRecord = await repository.getRecordById(saved.id);
      expect(loadedRecord, isNotNull);
      expect(loadedRecord!.hasCompleteEvidence, isTrue);
      expect(await File(loadedRecord.frontImagePath!).exists(), isTrue);
      expect(await File(loadedRecord.backImagePath!).exists(), isTrue);

      final frontPath = loadedRecord.frontImagePath!;
      final backPath = loadedRecord.backImagePath!;

      // Deleting contact cleans up permanent images
      await repository.deleteContact(saved.id, markPendingSync: false);
      expect(await repository.getRecordById(saved.id), isNull);
      expect(await File(frontPath).exists(), isFalse);
      expect(await File(backPath).exists(), isFalse);
    });
  });
}
