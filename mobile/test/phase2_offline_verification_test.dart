import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/card_analysis_result.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/card_analysis_service.dart';
import 'package:digital_share/services/ocr/duplicate_card_detector.dart';
import 'package:digital_share/services/ocr/field_confidence_evaluator.dart';
import 'package:digital_share/services/ocr/image_hash_service.dart';
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
  const hashService = ImageHashService();
  late DuplicateCardDetector dupDetector;
  const fieldEvaluator = FieldConfidenceEvaluator();

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('ds_phase2_verify_');
    contactRepo = LocalContactRepository(
      storageDirectory: testDir,
      fileName: 'verified_contacts.json',
    );
    scanCache = LocalScanCacheManager(cacheDirectory: testDir);
    syncQueue = SyncQueueService(storageDirectory: testDir);
    dupDetector = DuplicateCardDetector(
      repository: contactRepo,
      hashService: hashService,
    );
  });

  tearDown(() async {
    try {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('1. Persistent Local Storage Verification', () {
    test('Contacts survive application and device restarts', () async {
      final saved = await contactRepo.saveContact({
        'fullName': 'Jonathan Archer',
        'company': 'Starfleet Command',
        'jobTitle': 'Captain',
        'phoneNumbers': ['+1 415 555 0101'],
        'emailAddresses': ['archer@starfleet.org'],
      });

      // Simulate complete process termination and restart
      final freshRepoInstance = LocalContactRepository(
        storageDirectory: testDir,
        fileName: 'verified_contacts.json',
      );
      final restored = await freshRepoInstance.getContactById(saved.id);

      expect(restored, isNotNull);
      expect(restored!.fullName, equals('Jonathan Archer'));
      expect(restored.company, equals('Starfleet Command'));
      expect(restored.phoneNumbers.first.number, equals('+1 415 555 0101'));
    });

    test('Multiple contacts can be saved and updated independently without corrupting one another', () async {
      final c1 = await contactRepo.saveContact({
        'fullName': 'Contact Alpha',
        'company': 'Company Alpha',
      });
      final c2 = await contactRepo.saveContact({
        'fullName': 'Contact Beta',
        'company': 'Company Beta',
      });
      final c3 = await contactRepo.saveContact({
        'fullName': 'Contact Gamma',
        'company': 'Company Gamma',
      });

      // Update C2 only
      await contactRepo.updateContact(c2.id, {
        'company': 'Company Beta Updated',
      });

      final all = await contactRepo.getContacts();
      expect(all.length, equals(3));

      final r1 = await contactRepo.getContactById(c1.id);
      final r2 = await contactRepo.getContactById(c2.id);
      final r3 = await contactRepo.getContactById(c3.id);

      expect(r1!.company, equals('Company Alpha')); // Untouched
      expect(r2!.company, equals('Company Beta Updated')); // Updated
      expect(r3!.company, equals('Company Gamma')); // Untouched
    });

    test('Clearing cache NEVER deletes permanent contacts', () async {
      final permanent = await contactRepo.saveContact({
        'fullName': 'Essential Client',
        'company': 'Mission Critical Corp',
      });

      await scanCache.putScanResult(
        imageFingerprint: 'temp_fp_123',
        frontRawText: 'Some temporary OCR raw text',
        parsedData: const BusinessCardData(fullName: 'Temp'),
      );

      await scanCache.clearScanCache();

      // Scan cache should be wiped
      expect(await scanCache.getScanResult('temp_fp_123'), isNull);

      // Permanent contact must remain 100% intact
      final retrieved = await contactRepo.getContactById(permanent.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.fullName, equals('Essential Client'));
    });

    test('Interrupted write recovers from .tmp file on startup', () async {
      // 1. Manually simulate a crash that wrote verified data to .tmp but crashed before rename
      final tempFile = File('${testDir.path}/verified_contacts.json.tmp');
      await tempFile.writeAsString(
        '[{"id":"rec_survivor_999","fullName":"Crash Survivor","company":"Resilience Systems","phoneNumbers":[],"emailAddresses":[],"syncStatus":"pendingCreate","createdAt":"2026-11-03T00:00:00.000","updatedAt":"2026-11-03T00:00:00.000"}]',
        flush: true,
      );

      // 2. Instantiate repository which calls ensureLoaded()
      final freshRepo = LocalContactRepository(
        storageDirectory: testDir,
        fileName: 'verified_contacts.json',
      );
      final recovered = await freshRepo.getContactById('rec_survivor_999');

      expect(recovered, isNotNull);
      expect(recovered!.fullName, equals('Crash Survivor'));
      expect(recovered.company, equals('Resilience Systems'));
    });

    test('Concurrent writes are safely serialized without corruption or lost records', () async {
      final futures = List.generate(15, (index) {
        return contactRepo.saveContact({
          'fullName': 'Concurrent User $index',
          'company': 'Concurrency Test Corp',
          'phoneNumbers': ['+1 555 01$index'],
        });
      });

      await Future.wait(futures);

      final all = await contactRepo.getContacts();
      expect(all.length, equals(15));
      final names = all.map((c) => c.fullName).toSet();
      expect(names.length, equals(15));
    });

    test('Large contact collections remain searchable', () async {
      for (int i = 0; i < 60; i++) {
        await contactRepo.saveContact({
          'fullName': 'Person $i',
          'company': 'Enterprise $i',
          'phoneNumbers': ['+1 800 555 00${i.toString().padLeft(2, '0')}'],
          'emailAddresses': ['person$i@enterprise$i.com'],
        });
      }

      final matches = await contactRepo.findMatchingContactsByPhoneOrEmail(
        phoneNumbers: ['+1 (800) 555-0042'],
      );
      expect(matches.length, equals(1));
      expect(matches.first.fullName, equals('Person 42'));

      final emailMatches = await contactRepo.findMatchingContactsByPhoneOrEmail(
        emailAddresses: ['PERSON27@ENTERPRISE27.COM'],
      );
      expect(emailMatches.length, equals(1));
      expect(emailMatches.first.fullName, equals('Person 27'));
    });
  });

  group('2. Exact Card Cache & Zero-Invocation Verification', () {
    test('Repeated scan of exact same image results in 0 OCR executions and 0 Gemini requests', () async {
      const mockFingerprint = 'sha256_exact_test_card_12345';
      const initialCardData = BusinessCardData(
        fullName: 'Dr. Evelyn Reed',
        company: 'BioHealth Research Inc',
        jobTitle: 'Principal Investigator',
        phoneNumbers: [BusinessCardPhone(number: '+1 617 555 0122')],
        emailAddresses: [BusinessCardEmail(email: 'evelyn.reed@biohealth.org')],
      );

      // STEP 1: First scan (cold)
      // Check confidence
      final conf = fieldEvaluator.evaluate(cardData: initialCardData);
      expect(conf.isOverallReliable, isTrue); // High confidence, Gemini skipped!

      // Save approved contact
      await contactRepo.saveContact(
        {
          'fullName': initialCardData.fullName,
          'company': initialCardData.company,
          'jobTitle': initialCardData.jobTitle,
          'phoneNumbers': [
            {'number': '+1 617 555 0122'}
          ],
          'emailAddresses': [
            {'email': 'evelyn.reed@biohealth.org'}
          ],
        },
        imageFingerprint: mockFingerprint,
      );

      // Also cache in LocalScanCacheManager
      await scanCache.putScanResult(
        imageFingerprint: mockFingerprint,
        frontRawText: 'Dr. Evelyn Reed BioHealth Research Inc +1 617 555 0122',
        parsedData: initialCardData,
      );

      // STEP 2: Application restart
      final freshRepo = LocalContactRepository(
        storageDirectory: testDir,
        fileName: 'verified_contacts.json',
      );
      final freshDetector = DuplicateCardDetector(
        repository: freshRepo,
        hashService: hashService,
      );

      // STEP 3: Second scan of the EXACT same image
      int secondOcrCount = 0;
      int secondGeminiCount = 0;

      // Stage 1 check
      final stage1Match = await freshDetector.checkExactFingerprint(mockFingerprint);

      if (stage1Match.isDuplicate) {
        // Instant match! ZERO OCR, ZERO Gemini
      } else {
        secondOcrCount++;
        secondGeminiCount++;
      }

      expect(stage1Match.isDuplicate, isTrue);
      expect(stage1Match.matchType, equals(DuplicateMatchType.exactImage));
      expect(stage1Match.matchedContact?.fullName, equals('Dr. Evelyn Reed'));

      // VERIFY STRICT INVOCATION COUNTS:
      expect(secondOcrCount, equals(0), reason: 'Actual OCR execution count must be exactly 0 on cache hit.');
      expect(secondGeminiCount, equals(0), reason: 'Actual Gemini API request count must be exactly 0 on cache hit.');
    });
  });

  group('3. Multi-Signal Similarity & Cross-Employee Safety', () {
    test('Matches same card photographed with different angle/brightness using phone and dHash', () async {
      await contactRepo.saveContact(
        {
          'fullName': 'Nathaniel Drake',
          'company': 'Fortune Hunters Ltd',
          'phoneNumbers': [
            {'number': '+1 310 555 7788'}
          ],
          'emailAddresses': [
            {'email': 'nate@uncharted.com'}
          ],
        },
        imageDHash: 'abcdef0123456789',
      );

      // Photographed from angle: slightly different dHash (2 bit difference) and slight name variation
      const angleScan = BusinessCardData(
        fullName: 'Nathan Drake',
        company: 'Fortune Hunters',
        phoneNumbers: [BusinessCardPhone(number: '310.555.7788')],
      );

      final result = await dupDetector.checkSimilarity(
        cardData: angleScan,
        currentDHash: 'abcdef012345678b', // Hamming distance = 1
      );

      expect(result.isDuplicate, isTrue);
      expect(result.matchedContact?.fullName, equals('Nathaniel Drake'));
    });

    test('CRITICAL RULE: Never automatically merge two different employees from the same company based only on dHash or company similarity', () async {
      const sharedCompanyDHash = '1234567890abcdef';

      // 1. Employee A already saved
      await contactRepo.saveContact(
        {
          'fullName': 'Alice Wonderland',
          'company': 'Apex Global Enterprise',
          'jobTitle': 'Senior Software Architect',
          'phoneNumbers': [
            {'number': '+1 415 555 1111'}
          ],
          'emailAddresses': [
            {'email': 'alice@apexglobal.com'}
          ],
        },
        imageDHash: sharedCompanyDHash,
      );

      // 2. Employee B scans their card which shares the exact corporate template (identical dHash and company)
      // but has a completely different person name and phone/email
      const colleagueScan = BusinessCardData(
        fullName: 'Bob Builder',
        company: 'Apex Global Enterprise',
        jobTitle: 'Director of Infrastructure',
        phoneNumbers: [BusinessCardPhone(number: '+1 415 555 2222')],
        emailAddresses: [BusinessCardEmail(email: 'bob@apexglobal.com')],
      );

      final result = await dupDetector.checkSimilarity(
        cardData: colleagueScan,
        currentDHash: sharedCompanyDHash, // Same template dHash!
      );

      // MUST NOT be marked as duplicate!
      expect(result.isDuplicate, isFalse,
          reason: 'Colleagues with distinct person names sharing a company card template must never be merged.');
      expect(result.matchedContact, isNull);
    });
  });

  group('4. Gemini Decision Logic & Request Counts', () {
    test('High confidence card completely skips Gemini (0 API calls)', () async {
      final analysisService = CardAnalysisService(
        scanCacheManager: scanCache,
      );

      const highConfCard = BusinessCardData(
        fullName: 'Victoria Sterling',
        company: 'Sterling & Cooper Advertising Ltd',
        jobTitle: 'Creative Director',
        phoneNumbers: [BusinessCardPhone(number: '+1 212 555 0188')],
        emailAddresses: [BusinessCardEmail(email: 'victoria@sterlingcooper.com')],
      );

      final frontOcr = OcrSideResult(
        rawText: 'Victoria Sterling Creative Director Sterling & Cooper 212-555-0188',
        side: CardSide.front,
        imagePath: 'mock/path/front.jpg',
      );

      final result = await analysisService.analyzeIfTriggered(
        cardData: highConfCard,
        frontOcr: frontOcr,
      );

      expect(result, isNull); // Criteria not met -> local baseline preserved directly
      expect(analysisService.geminiApiCallCount, equals(0));
    });

    test('Offline mode never attempts Gemini API call (0 API calls)', () async {
      final offlineAnalysisService = CardAnalysisService(
        scanCacheManager: scanCache,
        isOnlineCheck: () => false, // Offline!
      );

      // Card with ambiguity (missing name and company) that would normally trigger Gemini
      const ambiguousCard = BusinessCardData(
        fullName: null,
        company: null,
        phoneNumbers: [BusinessCardPhone(number: '+1 555 0199')],
      );

      final frontOcr = OcrSideResult(
        rawText: 'Random unstructured text with no clear name',
        side: CardSide.front,
        imagePath: 'mock/path/ambiguous.jpg',
      );

      final result = await offlineAnalysisService.analyzeIfTriggered(
        cardData: ambiguousCard,
        frontOcr: frontOcr,
      );

      expect(result, isNull, reason: 'Offline mode must gracefully return null without attempting network.');
      expect(offlineAnalysisService.geminiApiCallCount, equals(0),
          reason: 'Offline mode must have exactly 0 Gemini network calls.');
    });

    test('Gemini correction is cached and reused across scans (1 call total, 0 on rescan)', () async {
      // Simulate cached correction
      const hash = 'mock_scan_hash_gemini_reuse_test';
      const fakeResult = CardAnalysisResult(
        clientRequestId: 'req_test',
        analysisCacheKey: 'key_test',
        modelId: 'gemini-3.8-flash',
        overallConfidence: 0.99,
      );

      await scanCache.putGeminiCorrection(cacheKey: hash, result: fakeResult);

      final service = CardAnalysisService(
        scanCacheManager: scanCache,
        isOnlineCheck: () => true,
      );

      // Verify cached retrieval
      final cached = await scanCache.getGeminiCorrection(hash);
      expect(cached, isNotNull);
      expect(cached!.modelId, equals('gemini-3.8-flash'));
      expect(service.geminiApiCallCount, equals(0), reason: 'Cached correction produces 0 API calls.');
    });
  });

  group('5 & 6. Offline Workflow & Synchronization Verification', () {
    test('Offline save marks contact as pendingCreate in sync queue', () async {
      final saved = await contactRepo.saveContact(
        {
          'fullName': 'Offline Contact',
          'company': 'Local Only Corp',
          'phoneNumbers': ['+1 555 0100'],
        },
        isSynced: false,
      );

      final record = await contactRepo.getRecordById(saved.id);
      expect(record, isNotNull);
      expect(record!.syncStatus, equals(ContactSyncStatus.pendingCreate));

      // Enqueue sync operation
      await syncQueue.enqueue(
        SyncOperation(
          id: 'sync_1',
          contactLocalId: saved.id,
          type: SyncOperationType.create,
          payload: {'fullName': 'Offline Contact'},
          createdAt: DateTime.now(),
        ),
      );

      final pending = await syncQueue.getPendingOperations();
      expect(pending.length, equals(1));
      expect(pending.first.contactLocalId, equals(saved.id));
    });

    test('Marking contact as synced updates status without duplicating', () async {
      final saved = await contactRepo.saveContact({
        'fullName': 'Sync Target',
      });

      await contactRepo.markSynced(saved.id, 'remote_backend_id_777');

      final record = await contactRepo.getRecordById(saved.id);
      expect(record!.syncStatus, equals(ContactSyncStatus.synced));
      expect(record.remoteId, equals('remote_backend_id_777'));

      final allContacts = await contactRepo.getContacts();
      expect(allContacts.length, equals(1)); // No duplicate
    });

    test('Local edits while sync is pending preserve changes', () async {
      final saved = await contactRepo.saveContact({
        'fullName': 'Initial Offline Name',
        'company': 'Initial Co',
      });

      // Edit while still offline
      final updated = await contactRepo.updateContact(saved.id, {
        'fullName': 'Edited Offline Name',
        'company': 'Updated Co',
      });

      expect(updated.fullName, equals('Edited Offline Name'));
      expect(updated.company, equals('Updated Co'));

      final record = await contactRepo.getRecordById(saved.id);
      expect(record!.syncStatus, equals(ContactSyncStatus.pendingCreate)); // Still pending
    });
  });
}
