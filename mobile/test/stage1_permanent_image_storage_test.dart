import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/storage/card_image_storage_service.dart';
import 'package:digital_share/services/storage/local_contact_record.dart';
import 'package:digital_share/services/storage/local_contact_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testBaseDir;
  late CardImageStorageService imageService;
  late LocalContactRepository contactRepo;

  setUp(() async {
    testBaseDir = await Directory.systemTemp.createTemp('ds_stage1_test_');
    imageService = CardImageStorageService(baseDirectory: testBaseDir);
    contactRepo = LocalContactRepository(
      storageDirectory: Directory('${testBaseDir.path}/storage'),
      fileName: 'test_stage1_contacts.json',
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

  group('Stage 1 — CardImageStorageService Core Requirements', () {
    test('Stores original front and back card images in persistent storage with stable filenames', () async {
      // 1. Create simulated camera/temp files
      final tempDir = await Directory.systemTemp.createTemp('temp_camera_');
      final tempFront = File('${tempDir.path}/cam_front_123.jpg');
      final tempBack = File('${tempDir.path}/cam_back_123.png');

      final frontBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03, 0x04]);
      final backBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x05, 0x06, 0x07, 0x08]);

      await tempFront.writeAsBytes(frontBytes, flush: true);
      await tempBack.writeAsBytes(backBytes, flush: true);

      // 2. Store card images for contact
      const contactId = 'contact_abc_789';
      final result = await imageService.storeCardImages(
        contactId: contactId,
        tempFrontPath: tempFront.path,
        tempBackPath: tempBack.path,
        cleanupTempOnSuccess: true,
      );

      expect(result.frontStoredSuccessfully, isTrue);
      expect(result.backStoredSuccessfully, isTrue);
      expect(result.permanentFrontPath, isNotNull);
      expect(result.permanentBackPath, isNotNull);

      // 3. Verify permanent paths and stable filenames
      expect(result.permanentFrontPath, endsWith('contact_abc_789_front.jpg'));
      expect(result.permanentBackPath, endsWith('contact_abc_789_back.png'));

      final permFrontFile = File(result.permanentFrontPath!);
      final permBackFile = File(result.permanentBackPath!);

      expect(await permFrontFile.exists(), isTrue);
      expect(await permBackFile.exists(), isTrue);
      expect(await permFrontFile.readAsBytes(), equals(frontBytes));
      expect(await permBackFile.readAsBytes(), equals(backBytes));

      // 4. Verify temp files were cleaned up after verified copy
      expect(await tempFront.exists(), isFalse);
      expect(await tempBack.exists(), isFalse);

      await tempDir.delete(recursive: true);
    });

    test('Preserves original image bytes and stores derived enhanced images separately', () async {
      final tempDir = await Directory.systemTemp.createTemp('temp_cam_');
      final tempFront = File('${tempDir.path}/raw_scan.jpg');
      final originalBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      await tempFront.writeAsBytes(originalBytes, flush: true);

      const contactId = 'contact_enhanced_001';
      final storeResult = await imageService.storeCardImages(
        contactId: contactId,
        tempFrontPath: tempFront.path,
      );

      expect(storeResult.frontStoredSuccessfully, isTrue);

      // Derived enhanced bytes (e.g. contrast enhanced / binarized)
      final enhancedBytes = Uint8List.fromList([99, 98, 97, 96, 95]);
      final enhancedPath = await imageService.storeEnhancedImage(
        contactId: contactId,
        side: CardSide.front,
        enhancedBytes: enhancedBytes,
      );

      expect(enhancedPath, isNotNull);
      expect(enhancedPath, contains('enhanced'));
      expect(enhancedPath, isNot(equals(storeResult.permanentFrontPath)));

      // Original file MUST NOT be altered
      final originalFile = File(storeResult.permanentFrontPath!);
      expect(await originalFile.readAsBytes(), equals(originalBytes));

      // Enhanced file stored in separate directory
      final enhancedFile = File(enhancedPath!);
      expect(await enhancedFile.readAsBytes(), equals(enhancedBytes));

      await tempDir.delete(recursive: true);
    });

    test('Handles corrupt, zero-byte, or missing temporary files safely without crashing', () async {
      final tempDir = await Directory.systemTemp.createTemp('temp_corrupt_');
      final zeroByteFile = File('${tempDir.path}/zero_byte.jpg');
      await zeroByteFile.writeAsBytes([], flush: true);

      final result = await imageService.storeCardImages(
        contactId: 'contact_corrupt_test',
        tempFrontPath: zeroByteFile.path,
        tempBackPath: '${tempDir.path}/non_existent.jpg',
      );

      expect(result.frontStoredSuccessfully, isFalse);
      expect(result.backStoredSuccessfully, isFalse);
      expect(result.warnings.length, equals(2));
      expect(result.permanentFrontPath, isNull);

      // Source zero-byte file must NOT be deleted so user/system can inspect or retry
      expect(await zeroByteFile.exists(), isTrue);

      await tempDir.delete(recursive: true);
    });

    test('Deletes permanent images when contact is removed', () async {
      final tempDir = await Directory.systemTemp.createTemp('temp_del_');
      final tempFront = File('${tempDir.path}/del_front.jpg');
      await tempFront.writeAsBytes([1, 2, 3, 4], flush: true);

      const contactId = 'contact_to_delete_999';
      final res = await imageService.storeCardImages(
        contactId: contactId,
        tempFrontPath: tempFront.path,
      );

      final permFile = File(res.permanentFrontPath!);
      expect(await permFile.exists(), isTrue);

      await imageService.deleteContactImages(contactId);
      expect(await permFile.exists(), isFalse);

      await tempDir.delete(recursive: true);
    });
  });

  group('Stage 1 — LocalContactRepository Integration with Permanent Images', () {
    test('saveContact atomically moves images to permanent storage and updates LocalContactRecord', () async {
      final tempDir = await Directory.systemTemp.createTemp('temp_repo_save_');
      final tempFront = File('${tempDir.path}/front_stage.jpg');
      final tempBack = File('${tempDir.path}/back_stage.jpg');
      await tempFront.writeAsBytes([0xAA, 0xBB, 0xCC], flush: true);
      await tempBack.writeAsBytes([0x11, 0x22, 0x33], flush: true);

      final contact = await contactRepo.saveContact(
        {
          'fullName': 'Dr. Marcus Thorne',
          'company': 'Vanguard BioTech',
        },
        imageFingerprint: 'fp_ Thorne_99',
        frontImagePath: tempFront.path,
        backImagePath: tempBack.path,
      );

      // Verify returned contact
      expect(contact.fullName, equals('Dr. Marcus Thorne'));

      // Verify underlying LocalContactRecord has verified permanent paths
      final record = await contactRepo.getRecordById(contact.id);
      expect(record, isNotNull);
      expect(record!.frontImagePath, isNotNull);
      expect(record.backImagePath, isNotNull);
      expect(record.frontImagePath, contains('cards/images'));
      expect(record.frontImagePath, endsWith('${record.id}_front.jpg'));
      expect(record.backImagePath, endsWith('${record.id}_back.jpg'));

      // Verify files actually exist on disk with correct bytes
      final storedFront = File(record.frontImagePath!);
      final storedBack = File(record.backImagePath!);
      expect(await storedFront.exists(), isTrue);
      expect(await storedBack.exists(), isTrue);
      expect(await storedFront.readAsBytes(), equals([0xAA, 0xBB, 0xCC]));
      expect(await storedBack.readAsBytes(), equals([0x11, 0x22, 0x33]));

      // Verify temp files are gone
      expect(await tempFront.exists(), isFalse);
      expect(await tempBack.exists(), isFalse);

      await tempDir.delete(recursive: true);
    });
  });

  group('Stage 1 — Honest Migration of Existing Records', () {
    test('Migrates existing records whose temp images still exist; honestly flags already deleted images', () async {
      final tempDir = await Directory.systemTemp.createTemp('temp_migration_');

      // Record 1: Temp files still exist
      final survivingFront = File('${tempDir.path}/surviving_front.jpg');
      await survivingFront.writeAsBytes([10, 20, 30], flush: true);

      final record1 = LocalContactRecord(
        id: 'rec_surviving_01',
        fullName: 'Alive Images Person',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        frontImagePath: survivingFront.path,
      );
      await contactRepo.updateLocalRecord(record1);

      // Record 2: Temp file was already deleted by OS temp cleaner
      final record2 = LocalContactRecord(
        id: 'rec_missing_02',
        fullName: 'Dead Images Person',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        frontImagePath: '${tempDir.path}/already_deleted_by_os.jpg',
      );
      await contactRepo.updateLocalRecord(record2);

      // Execute migration
      final report = await imageService.migrateExistingRecords(contactRepo);

      expect(report.totalRecordsChecked, equals(2));
      expect(report.frontImagesMigrated, equals(1));
      expect(report.missingImagesCount, equals(1));
      expect(report.unrecoverableRecordIds, contains('rec_missing_02'));

      // Record 1 must now have a verified permanent path
      final updated1 = await contactRepo.getRecordById('rec_surviving_01');
      expect(updated1!.frontImagePath, contains('cards/images'));
      expect(await File(updated1.frontImagePath!).exists(), isTrue);

      // Record 2 must NOT claim to be recovered
      final updated2 = await contactRepo.getRecordById('rec_missing_02');
      expect(updated2!.frontImagePath, equals('${tempDir.path}/already_deleted_by_os.jpg'));

      await tempDir.delete(recursive: true);
    });
  });
}

