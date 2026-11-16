import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/card_analysis_result.dart';
import 'package:digital_share/services/storage/local_contact_record.dart';
import 'package:digital_share/services/storage/local_contact_repository.dart';
import 'package:digital_share/services/storage/local_scan_cache_manager.dart';
import 'package:digital_share/services/storage/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late LocalContactRepository contactRepo;
  late LocalScanCacheManager scanCache;
  late SyncQueueService syncQueue;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('ds_offline_test_');
    contactRepo = LocalContactRepository(
      storageDirectory: testDir,
      fileName: 'test_contacts.json',
    );
    scanCache = LocalScanCacheManager(cacheDirectory: testDir);
    syncQueue = SyncQueueService(storageDirectory: testDir);
  });

  tearDown(() async {
    try {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('LocalContactRepository Tests', () {
    test('Saves contact locally and persists atomically across instances', () async {
      final contactData = {
        'fullName': 'Elena Rostova',
        'company': 'Quantum Dynamics Ltd',
        'jobTitle': 'Chief Technology Officer',
        'phoneNumbers': [
          {'number': '+1-555-0199', 'label': 'Work'}
        ],
        'emailAddresses': [
          {'email': 'elena@quantumdynamics.io', 'label': 'Work'}
        ],
        'website': 'https://quantumdynamics.io',
        'address': '100 Innovation Way, Boston, MA 02110',
      };

      final saved = await contactRepo.saveContact(
        contactData,
        imageFingerprint: 'sha256_mock_fingerprint_123',
        imageDHash: 'a1b2c3d4e5f60718',
        rawRecognizedText: 'Elena Rostova CTO Quantum Dynamics',
      );

      expect(saved.id, isNotEmpty);
      expect(saved.fullName, equals('Elena Rostova'));
      expect(saved.company, equals('Quantum Dynamics Ltd'));

      // Verify persistent disk recovery via completely new repository instance
      final newRepo = LocalContactRepository(
        storageDirectory: testDir,
        fileName: 'test_contacts.json',
      );
      final retrieved = await newRepo.getContactById(saved.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.fullName, equals('Elena Rostova'));
      expect(retrieved.phoneNumbers.length, equals(1));
      expect(retrieved.phoneNumbers.first.number, equals('+1-555-0199'));

      // Verify internal record metadata
      final record = await newRepo.getRecordById(saved.id);
      expect(record, isNotNull);
      expect(record!.imageFingerprint, equals('sha256_mock_fingerprint_123'));
      expect(record.imageDHash, equals('a1b2c3d4e5f60718'));
      expect(record.syncStatus, equals(ContactSyncStatus.pendingCreate));
    });

    test('Finds exact match by image fingerprint and matching phone/email', () async {
      await contactRepo.saveContact(
        {
          'fullName': 'Marcus Vance',
          'company': 'Apex Capital',
          'phoneNumbers': ['+1 415 555 2671'],
          'emailAddresses': ['marcus@apexcapital.com'],
        },
        imageFingerprint: 'exact_front_fingerprint_abc',
      );

      final byFingerprint = await contactRepo.findByImageFingerprint('exact_front_fingerprint_abc');
      expect(byFingerprint, isNotNull);
      expect(byFingerprint!.fullName, equals('Marcus Vance'));

      final byPhone = await contactRepo.findMatchingContactsByPhoneOrEmail(
        phoneNumbers: ['(415) 555-2671'],
      );
      expect(byPhone.length, equals(1));
      expect(byPhone.first.fullName, equals('Marcus Vance'));

      final byEmail = await contactRepo.findMatchingContactsByPhoneOrEmail(
        emailAddresses: ['MARCUS@apexcapital.com'],
      );
      expect(byEmail.length, equals(1));
      expect(byEmail.first.fullName, equals('Marcus Vance'));
    });

    test('Updates and deletes contact locally', () async {
      final saved = await contactRepo.saveContact({
        'fullName': 'Sarah Connor',
        'company': 'Cyberdyne Resistance',
      });

      final updated = await contactRepo.updateContact(saved.id, {
        'company': 'Tech Resistance Global',
      });
      expect(updated.company, equals('Tech Resistance Global'));

      await contactRepo.deleteContact(saved.id);
      final afterDelete = await contactRepo.getContactById(saved.id);
      expect(afterDelete, isNull);
    });
  });

  group('LocalScanCacheManager & Isolation Tests', () {
    test('Caches and retrieves OCR scan result by image fingerprint', () async {
      const cardData = BusinessCardData(
        fullName: 'Devin Thorne',
        company: 'Vanguard Systems',
        phoneNumbers: [BusinessCardPhone(number: '+1 212 555 0144')],
        emailAddresses: [BusinessCardEmail(email: 'devin@vanguard.com')],
      );

      await scanCache.putScanResult(
        imageFingerprint: 'front_sha256_devin',
        frontRawText: 'Devin Thorne Vanguard Systems 212-555-0144',
        parsedData: cardData,
      );

      final cached = await scanCache.getScanResult('front_sha256_devin');
      expect(cached, isNotNull);
      expect(cached!.parsedData.fullName, equals('Devin Thorne'));
      expect(cached.parsedData.company, equals('Vanguard Systems'));
    });

    test('Caches and retrieves Gemini correction across restarts', () async {
      const result = CardAnalysisResult(
        clientRequestId: 'req_12345',
        analysisCacheKey: 'cache_12345',
        modelId: 'gemini-3.8-flash',
        overallConfidence: 0.98,
      );

      await scanCache.putGeminiCorrection(
        cacheKey: 'canonical_hash_gemini_test',
        result: result,
      );

      // Re-instantiate scan cache to verify disk persistence
      final newCache = LocalScanCacheManager(cacheDirectory: testDir);
      final retrieved = await newCache.getGeminiCorrection('canonical_hash_gemini_test');
      expect(retrieved, isNotNull);
      expect(retrieved!.clientRequestId, equals('req_12345'));
      expect(retrieved.modelId, equals('gemini-3.8-flash'));
    });

    test('CRITICAL RULE: Clearing temporary scan cache NEVER deletes permanent contacts', () async {
      // 1. Save permanent contact
      final savedContact = await contactRepo.saveContact({
        'fullName': 'Permanent Contact',
        'company': 'Forever Safe Inc',
      });

      // 2. Put entries in transient scan cache
      await scanCache.putScanResult(
        imageFingerprint: 'transient_fingerprint_999',
        frontRawText: 'some random text',
        parsedData: const BusinessCardData(fullName: 'Temporary Scan'),
      );

      // 3. Clear transient scan cache
      await scanCache.clearScanCache();

      // 4. Verify scan cache is empty
      final cached = await scanCache.getScanResult('transient_fingerprint_999');
      expect(cached, isNull);

      // 5. Verify permanent contact is completely intact
      final permanent = await contactRepo.getContactById(savedContact.id);
      expect(permanent, isNotNull);
      expect(permanent!.fullName, equals('Permanent Contact'));
      expect(permanent.company, equals('Forever Safe Inc'));
    });
  });

  group('SyncQueueService Tests', () {
    test('Enqueues operations and persists them to disk', () async {
      final op = SyncOperation(
        id: 'op_1',
        contactLocalId: 'loc_123',
        type: SyncOperationType.create,
        payload: {'fullName': 'Offline User'},
        createdAt: DateTime.now(),
      );

      await syncQueue.enqueue(op);

      final newQueue = SyncQueueService(storageDirectory: testDir);
      final pending = await newQueue.getPendingOperations();
      expect(pending.length, equals(1));
      expect(pending.first.contactLocalId, equals('loc_123'));
      expect(pending.first.type, equals(SyncOperationType.create));
    });
  });
}

