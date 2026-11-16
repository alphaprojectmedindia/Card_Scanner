import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/card_analysis_result.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/ocr/gemini_ocr_reconciliation_engine.dart';
import 'package:digital_share/services/ocr/local_correction_learning_service.dart';
import 'package:digital_share/services/storage/card_image_storage_service.dart';
import 'package:digital_share/services/storage/local_contact_record.dart';
import 'package:digital_share/services/storage/local_contact_repository.dart';
import 'package:digital_share/services/storage/offline_scan_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CardImageStorageService imageStorage;
  late LocalContactRepository repository;
  late OfflineScanQueueService queueService;
  late LocalCorrectionLearningService learningService;
  const engine = GeminiOcrReconciliationEngine();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('digital_share_offline_recovery_');
    imageStorage = CardImageStorageService(baseDirectory: Directory('${tempDir.path}/images'));
    repository = LocalContactRepository(
      storageDirectory: Directory('${tempDir.path}/contacts'),
      imageStorageService: imageStorage,
    );
    queueService = OfflineScanQueueService();
    await queueService.clearQueue();
    learningService = LocalCorrectionLearningService(storageDirectory: Directory('${tempDir.path}/corrections'));
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('Complete Offline and Recovery Lifecycle Test', () async {
    const testUserId = 'auth_user_offline_007';

    // Step 1: User scans while offline
    final sampleFrontFile = File('${tempDir.path}/raw_front.jpg')..writeAsStringSync('dummy front image bytes');
    final sampleBackFile = File('${tempDir.path}/raw_back.jpg')..writeAsStringSync('dummy back image bytes');

    final localCardData = const BusinessCardData(
      fullName: 'Vikram Joshi',
      company: 'Apex Tech Solutions',
      jobTitle: 'Head of Engineering',
    );

    // Save contact locally
    final savedContact = await repository.saveContact(
      {
        'id': 'contact_offline_123',
        'fullName': localCardData.fullName,
        'company': localCardData.company,
        'jobTitle': localCardData.jobTitle,
        'userId': testUserId,
      },
      userId: testUserId,
      frontImagePath: sampleFrontFile.path,
      backImagePath: sampleBackFile.path,
      imageFingerprint: 'sha256_mock_offline_fingerprint',
    );

    expect(savedContact.id, equals('contact_offline_123'));
    final initialRecord = await repository.getRecordById('contact_offline_123', userId: testUserId);
    expect(initialRecord, isNotNull);
    expect(initialRecord!.syncStatus, equals(ContactSyncStatus.pendingCreate));

    // Enqueue in OfflineScanQueueService
    await queueService.enqueueScan(
      scanId: 'scan_queued_001',
      contactId: savedContact.id,
      userId: testUserId,
      frontImagePath: sampleFrontFile.path,
      backImagePath: sampleBackFile.path,
      frontSha256: 'sha256_mock_offline_fingerprint',
      cardData: localCardData,
    );

    // Record user manual edit on a field
    await learningService.recordUserCorrection(
      imageFingerprint: 'sha256_mock_offline_fingerprint',
      fieldName: 'fullName',
      originalExtractedValue: 'Vikram Joshi',
      approvedValue: 'Vikram K. Joshi',
      userId: testUserId,
      source: 'userManualEdit',
    );

    // Step 2: Simulate application process death and restart
    final restartedRepository = LocalContactRepository(
      storageDirectory: Directory('${tempDir.path}/contacts'),
      imageStorageService: CardImageStorageService(baseDirectory: Directory('${tempDir.path}/images')),
    );
    await restartedRepository.ensureLoaded();

    final userContacts = await restartedRepository.getContactsForUser(testUserId);
    expect(userContacts.length, equals(1));
    final reloadedContact = userContacts.first;
    expect(reloadedContact.fullName, equals('Vikram Joshi'));

    // Verify original image bytes remain intact and accessible
    final record = await restartedRepository.getRecordById(reloadedContact.id, userId: testUserId);
    expect(record, isNotNull);
    expect(record!.frontImagePath, isNotNull);
    expect(File(record.frontImagePath!).existsSync(), isTrue);
    expect(File(record.frontImagePath!).readAsStringSync(), equals('dummy front image bytes'));

    // Step 3: Network connectivity restored -> Process Offline Queue
    final pendingScans = await queueService.getPendingScans(userId: testUserId);
    expect(pendingScans.length, equals(1));
    final queueItem = pendingScans.first;
    expect(queueItem.id, equals('scan_queued_001'));
    expect(queueItem.contactId, equals('contact_offline_123'));

    // Simulate backend Gemini visual extraction returning
    final geminiResult = CardAnalysisResult(
      clientRequestId: queueItem.id,
      analysisCacheKey: 'cache_recovered_001',
      visualVerificationPerformed: true,
      geminiApiExecuted: true,
      fullName: const ExtractedField(value: 'Vikram Joshi', confidence: 0.95), // Gemini saw Vikram Joshi
      company: const ExtractedField(value: 'Apex Tech Solutions Ltd', confidence: 0.98), // Gemini improved company
    );

    // Load active learned corrections to protect manual edits
    final corrections = await learningService.getExactImageCorrections(
      imageFingerprint: 'sha256_mock_offline_fingerprint',
      userId: testUserId,
    );
    expect(corrections.length, equals(1));

    final frontOcr = OcrSideResult.fromText(
      side: CardSide.front,
      imagePath: record.frontImagePath!,
      rawText: 'Apex Tech Solutions\nVikram Joshi\nHead of Engineering',
    );

    // Reconcile Gemini with user corrections and local baseline
    final reconciled = engine.reconcile(
      localCardData: localCardData,
      frontOcr: frontOcr,
      geminiResult: geminiResult,
      learnedCorrections: corrections,
      currentCardFingerprint: 'sha256_mock_offline_fingerprint',
    );

    // User's manual edit "Vikram K. Joshi" MUST be protected!
    expect(reconciled.reconciledData.fullName, equals('Vikram K. Joshi'));
    // Gemini's company improvement accepted
    expect(reconciled.reconciledData.company, equals('Apex Tech Solutions Ltd'));

    // Update existing contact record (no duplicate contact created)
    await restartedRepository.updateContact(
      reloadedContact.id,
      {
        'fullName': reconciled.reconciledData.fullName,
        'company': reconciled.reconciledData.company,
      },
    );

    // Mark queued scan completed
    await queueService.markCompleted(queueItem.id);

    // Verify queue is empty (no duplicate API requests)
    final remainingQueue = await queueService.getPendingScans(userId: testUserId);
    expect(remainingQueue, isEmpty);

    // Verify contact count remains exactly 1 (no duplicate contacts)
    final finalContacts = await restartedRepository.getContactsForUser(testUserId);
    expect(finalContacts.length, equals(1));
    expect(finalContacts.first.fullName, equals('Vikram K. Joshi'));
    expect(finalContacts.first.company, equals('Apex Tech Solutions Ltd'));
  });
}
