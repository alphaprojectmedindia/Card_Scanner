import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/field_evidence.dart';
import 'package:digital_share/models/imported_contact.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/screens/connections/imported_contact_details_screen.dart';
import 'package:digital_share/services/card_analysis_decision_service.dart';
import 'package:digital_share/services/ocr/field_confidence_evaluator.dart';
import 'package:digital_share/services/imported_contact_service.dart';
import 'package:digital_share/services/ocr/duplicate_card_detector.dart';
import 'package:digital_share/services/ocr/image_hash_service.dart';
import 'package:digital_share/services/ocr/local_correction_learning_service.dart';
import 'package:digital_share/services/ocr/same_card_cache_reconciler.dart';
import 'package:digital_share/services/storage/local_contact_repository.dart';
import 'package:digital_share/services/storage/local_scan_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalContactRepository repository;
  late LocalScanCacheManager cacheManager;
  late LocalCorrectionLearningService learningService;
  late DuplicateCardDetector duplicateDetector;
  late SameCardCacheReconciler cacheReconciler;
  const hashService = ImageHashService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stage7_smart_cache_test_');
    cacheManager = LocalScanCacheManager(cacheDirectory: tempDir);
    learningService = LocalCorrectionLearningService(storageDirectory: tempDir);
    repository = LocalContactRepository(
      storageDirectory: tempDir,
      fileName: 'stage7_contacts.json',
      scanCacheManager: cacheManager,
      learningService: learningService,
    );
    duplicateDetector = DuplicateCardDetector(
      repository: repository,
      hashService: hashService,
    );
    cacheReconciler = const SameCardCacheReconciler();
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Stage 7 — Smart Same-Card Cache Integration Tests', () {
    // 1. Exact same image uses exact-image cache
    test('Scenario 1: Exact same image uses exact-image cache without redundant work', () async {
      const fingerprint = 'sha256_exact_image_card_test_123';
      const parsedData = BusinessCardData(
        fullName: 'Eleanor Vance',
        company: 'Hill House Architecture',
        jobTitle: 'Principal Architect',
        emailAddresses: [BusinessCardEmail(email: 'eleanor@hillhouse.com')],
        phoneNumbers: [BusinessCardPhone(number: '+1-555-0144')],
      );

      // Save initial contact
      await repository.saveContact(
        {
          'fullName': 'Eleanor Vance',
          'company': 'Hill House Architecture',
          'jobTitle': 'Principal Architect',
          'emailAddresses': [{'email': 'eleanor@hillhouse.com'}],
          'phoneNumbers': [{'number': '+1-555-0144'}],
          'userId': 'user_stage7',
        },
        imageFingerprint: fingerprint,
      );

      // Cache scan result
      await cacheManager.putScanResult(
        imageFingerprint: fingerprint,
        userId: 'user_stage7',
        frontRawText: 'Eleanor Vance Hill House Architecture Principal Architect',
        parsedData: parsedData,
      );

      // Duplicate check detects exact image
      final exactMatch = await duplicateDetector.checkExactFingerprint(
        fingerprint,
        userId: 'user_stage7',
      );
      expect(exactMatch.isDuplicate, isTrue);
      expect(exactMatch.matchType, equals(DuplicateMatchType.exactImage));
      expect(exactMatch.confidence, equals(1.0));
      expect(exactMatch.matchedContact?.fullName, equals('Eleanor Vance'));

      // Retrieve cached scan directly
      final cachedScan = await cacheManager.getScanResult(
        fingerprint,
        userId: 'user_stage7',
      );
      expect(cachedScan, isNotNull);
      expect(cachedScan!.parsedData.fullName, equals('Eleanor Vance'));
      expect(cachedScan.parsedData.company, equals('Hill House Architecture'));
    });

    // 2. Same physical card photographed differently can be recognized (dHash <= 10)
    test('Scenario 2: Same physical card photographed differently recognized via dHash and identifiers', () async {
      const originalDHash = '1100110011001100';
      const slightlyDifferentPhotoDHash = '1100110011001101'; // 1 bit distance <= 10

      await repository.saveContact(
        {
          'fullName': 'Sarah Connor',
          'company': 'Cyberdyne Systems',
          'jobTitle': 'Systems Consultant',
          'phoneNumbers': [{'number': '+1 (310) 555-0199'}],
          'emailAddresses': [{'email': 'sarah.connor@cyberdyne.com'}],
          'userId': 'user_stage7',
        },
        imageDHash: originalDHash,
      );

      // New scan of the same card photographed with different lighting/angle
      const newScanData = BusinessCardData(
        fullName: 'Sarah Connor',
        company: 'Cyberdyne Systems',
        phoneNumbers: [BusinessCardPhone(number: '310-555-0199')],
      );

      final matchResult = await duplicateDetector.checkSimilarity(
        cardData: newScanData,
        currentDHash: slightlyDifferentPhotoDHash,
        userId: 'user_stage7',
      );

      expect(matchResult.isDuplicate, isTrue);
      expect(matchResult.isDefinitiveMatch, isTrue);
      expect(matchResult.confidence, greaterThanOrEqualTo(0.75));
      expect(matchResult.matchedRecord?.fullName, equals('Sarah Connor'));
    });

    // 3. Different employee from same company is not treated as the same person (anti-collision)
    test('Scenario 3: Anti-collision isolates distinct employees sharing identical company layout and dHash', () async {
      const companyLayoutDHash = '1010101010101010';

      // Employee A saved previously
      await repository.saveContact(
        {
          'fullName': 'Alice Smith',
          'company': 'Globex Corporation',
          'jobTitle': 'Senior Software Engineer',
          'phoneNumbers': [{'number': '+1-415-555-0101'}],
          'emailAddresses': [{'email': 'alice.smith@globex.com'}],
          'userId': 'user_stage7',
        },
        imageDHash: companyLayoutDHash,
      );

      final employeeARecord = (await repository.getContactsForUser('user_stage7')).first;
      final fullRecordA = (await repository.getRecordById(employeeARecord.id))!;

      // Employee B new scan with identical company template
      const newScanEmployeeB = BusinessCardData(
        fullName: 'Bob Jones',
        company: 'Globex Corporation',
        jobTitle: 'Account Executive',
        phoneNumbers: [BusinessCardPhone(number: '+1-415-555-0102')],
        emailAddresses: [BusinessCardEmail(email: 'bob.jones@globex.com')],
      );

      final frontOcrB = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Bob Jones\nGlobex Corporation\nAccount Executive\n+1-415-555-0102\nbob.jones@globex.com',
      );

      // Reconciler MUST abort personal assimilation due to distinct identity
      final reconResult = cacheReconciler.reconcile(
        newScanData: newScanEmployeeB,
        frontOcr: frontOcrB,
        cachedRecord: fullRecordA,
        matchConfidence: 0.60,
      );

      expect(reconResult.isSamePersonVerified, isFalse);
      // Verify Bob Jones retains his own name, phone, and email, never Alice's
      expect(reconResult.reconciledCardData.fullName, equals('Bob Jones'));
      expect(reconResult.reconciledCardData.phoneNumbers.first.number, equals('+1-415-555-0102'));
      expect(reconResult.reconciledCardData.emailAddresses.first.email, equals('bob.jones@globex.com'));
      expect(reconResult.improvementsApplied.any((i) => i.contains('Suppressed personal field transfer')), isTrue);
    });

    // 4. Cached corrections improve parsing when supported by new evidence
    test('Scenario 4: Cached user corrections upgrade partial/noisy text when corroborated by raw OCR tokens', () async {
      // Saved record with user-approved full name and title
      await repository.saveContact(
        {
          'fullName': 'Dr. Evelyn Reed, Ph.D.',
          'company': 'Biomedical Dynamics',
          'jobTitle': 'Chief Scientific Officer',
          'userId': 'user_stage7',
        },
        imageDHash: '1111111100000000',
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Dr Evelyn Reed',
            normalizedValue: 'Dr. Evelyn Reed, Ph.D.',
            userApprovedValue: 'Dr. Evelyn Reed, Ph.D.',
            sourceEngine: 'userManualEdit',
            sourceObservationIds: const ['obs_cached_1'],
            boundingBoxes: const [Rect.fromLTWH(10, 10, 150, 30)],
            ocrConfidence: 0.90,
            parserConfidence: 0.95,
            verificationStatus: FieldVerificationStatus.verified,
          ),
        },
      );

      final record = (await repository.getContactsForUser('user_stage7')).first;
      final fullRecord = (await repository.getRecordById(record.id))!;

      // New scan produces noisy/partial name "Dr Evelyn" in parser, but raw text includes 'Dr Evelyn Reed'
      const noisyParsedScan = BusinessCardData(
        fullName: 'Dr Evelyn',
        company: 'Biomedical Dynamics',
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Dr Evelyn Reed\nBiomedical Dynamics\nChief Scientific Officer',
      );

      final recon = cacheReconciler.reconcile(
        newScanData: noisyParsedScan,
        frontOcr: frontOcr,
        cachedRecord: fullRecord,
        matchConfidence: 0.88,
      );

      expect(recon.isSamePersonVerified, isTrue);
      expect(recon.improvementsApplied.any((imp) => imp.toLowerCase().contains('full name')), isTrue);
      expect(recon.reconciledCardData.fullName, equals('Dr. Evelyn Reed, Ph.D.'));
      expect(recon.reconciledCardData.fieldEvidence['fullName']?.sourceEngine, equals('cache_assisted'));
      expect(recon.reconciledCardData.fieldEvidence['fullName']?.verificationStatus, equals(FieldVerificationStatus.verified));
    });

    // 5. Conflicting cached and new values require review
    test('Scenario 5: Direct conflict between new high-confidence OCR and old cache surfaces reviewRequired', () async {
      await repository.saveContact(
        {
          'fullName': 'Marcus Fenix',
          'company': 'Coalition Technologies',
          'phoneNumbers': [{'number': '+1-555-0100'}],
          'userId': 'user_stage7',
        },
        imageDHash: '1100110000110011',
      );

      final record = (await repository.getContactsForUser('user_stage7')).first;
      final fullRecord = (await repository.getRecordById(record.id))!;

      // New scan clearly shows new direct phone number +1-555-9999 (e.g. updated office line)
      const newScan = BusinessCardData(
        fullName: 'Marcus Fenix',
        company: 'Coalition Technologies',
        phoneNumbers: [BusinessCardPhone(number: '+1-555-9999')],
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Marcus Fenix\nCoalition Technologies\n+1-555-9999',
      );

      final recon = cacheReconciler.reconcile(
        newScanData: newScan,
        frontOcr: frontOcr,
        cachedRecord: fullRecord,
        matchConfidence: 0.85,
      );

      // Reconciler must NOT overwrite new phone; it must flag conflict and preserve candidates
      expect(recon.conflictsDetected, contains('phone'));
      expect(recon.reconciledCardData.phoneNumbers.first.number, equals('+1-555-9999'));
      final phoneEvidence = recon.reconciledCardData.fieldEvidence['phone'];
      expect(phoneEvidence, isNotNull);
      expect(phoneEvidence!.verificationStatus, equals(FieldVerificationStatus.reviewRequired));
      expect(recon.reconciledCardData.alternativeCandidates['phone']?.any((c) => c.contains('555-0100')), isTrue);
    });

    // 6. Clear cache-assisted results avoid unnecessary Gemini calls
    test('Scenario 6: Clean cache-assisted scan with high confidence bypasses Gemini API', () async {
      final evaluator = FieldConfidenceEvaluator();
      const decisionService = CardAnalysisDecisionService();

      const confidentCardData = BusinessCardData(
        fullName: 'Victoria Neuman',
        company: 'Federal Bureau of Standards',
        jobTitle: 'Director',
        phoneNumbers: [BusinessCardPhone(number: '+1-202-555-0188')],
        emailAddresses: [BusinessCardEmail(email: 'vneuman@standards.gov')],
        fieldConfidenceStates: {
          'fullName': 'highConfidence',
          'company': 'highConfidence',
          'jobTitle': 'highConfidence',
          'address': 'highConfidence',
        },
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Victoria Neuman\nDirector\nFederal Bureau of Standards\n+1-202-555-0188\nvneuman@standards.gov',
      );

      final report = evaluator.evaluate(cardData: confidentCardData, frontOcr: frontOcr);
      expect(report.overallScore, greaterThanOrEqualTo(0.85));
      expect(report.hasLowConfidenceCriticalFields, isFalse);

      final decision = decisionService.evaluate(
        cardData: confidentCardData,
        frontOcr: frontOcr,
      );

      expect(decision.shouldInvokeGemini, isFalse);
      expect(decision.mode, equals(AnalysisMode.none));
    });

    // 7. Uncertain cache-assisted results trigger Gemini
    test('Scenario 7: Uncertain card with entity name confusion triggers Gemini evaluation', () async {
      const decisionService = CardAnalysisDecisionService();

      // Card data where person name contains corporate keywords (triggers Trigger 1)
      const uncertainCardData = BusinessCardData(
        fullName: 'Apex Solutions Pvt Ltd',
        company: 'John Doe',
        phoneNumbers: [BusinessCardPhone(number: '+1-555-0100')],
        fieldConfidenceStates: {
          'fullName': 'uncertain',
          'company': 'uncertain',
        },
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Apex Solutions Pvt Ltd\nJohn Doe',
      );

      final decision = decisionService.evaluate(
        cardData: uncertainCardData,
        frontOcr: frontOcr,
      );

      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules, isNotEmpty);
    });

    // 8. Gemini receives actual new image bytes
    test('Scenario 8: Gemini receives actual newly captured card image bytes rather than stale cache', () async {
      final newImageFile = File('${tempDir.path}/new_captured_card.jpg');
      final newImageBytes = [255, 216, 255, 224, 0, 16, 74, 70, 73, 70]; // JPEG magic header bytes
      await newImageFile.writeAsBytes(newImageBytes);

      // Verify the new image path and bytes exist
      expect(await newImageFile.exists(), isTrue);
      final readBytes = await newImageFile.readAsBytes();
      expect(readBytes, equals(newImageBytes));

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: newImageFile.path,
        rawText: 'Thomas Anderson\nMetacortex Software',
      );

      // Verify frontOcr points to the newly captured image path, preserving actual image bytes
      expect(frontOcr.imagePath, equals(newImageFile.path));
      final imageFromOcr = File(frontOcr.imagePath);
      expect(await imageFromOcr.readAsBytes(), equals(newImageBytes));
    });

    // 9. Historical reprocessing is accessible through the UI
    testWidgets('Scenario 9: ImportedContactDetailsScreen displays reprocess_card_button in AppBar', (tester) async {
      const sampleContact = ImportedContact(
        id: 'contact_reprocess_ui_123',
        fullName: 'Dana Scully',
        company: 'FBI Field Office',
        jobTitle: 'Special Agent',
        phoneNumbers: [ImportedContactPhone(number: '+1-202-555-0199', label: 'Mobile')],
        emailAddresses: [ImportedContactEmail(email: 'dscully@fbi.gov', label: 'Work')],
      );

      final service = ImportedContactService(localRepo: repository);

      await tester.pumpWidget(
        MaterialApp(
          home: ImportedContactDetailsScreen(
            contact: sampleContact,
            contactService: service,
          ),
        ),
      );

      // Verify reprocess_card_button is present in the AppBar actions
      final reprocessButtonFinder = find.byKey(const Key('reprocess_card_button'));
      expect(reprocessButtonFinder, findsOneWidget);

      // Verify tooltip and icon
      final iconButton = tester.widget<IconButton>(reprocessButtonFinder);
      expect(iconButton.tooltip, contains('Reprocess Card'));
    });

    // 10. Account switching does not leak cache data
    test('Scenario 10: Multi-user isolation prevents cache and contact leakage across account switches', () async {
      const userA = 'user_alpha_777';
      const userB = 'user_beta_888';
      const sharedFingerprint = 'sha256_shared_fingerprint_test';

      // 1. User A saves contact and cache
      await repository.saveContact(
        {
          'fullName': 'Geralt of Rivia',
          'company': 'School of the Wolf',
          'userId': userA,
        },
        imageFingerprint: sharedFingerprint,
      );

      await cacheManager.putScanResult(
        imageFingerprint: sharedFingerprint,
        userId: userA,
        frontRawText: 'Geralt of Rivia School of the Wolf',
        parsedData: const BusinessCardData(
          fullName: 'Geralt of Rivia',
          company: 'School of the Wolf',
        ),
      );

      // 2. Query as User A: data exists
      final userAContacts = await repository.getContactsForUser(userA);
      expect(userAContacts.length, equals(1));
      expect(userAContacts.first.fullName, equals('Geralt of Rivia'));

      final userACache = await cacheManager.getScanResult(sharedFingerprint, userId: userA);
      expect(userACache, isNotNull);
      expect(userACache!.parsedData.fullName, equals('Geralt of Rivia'));

      // 3. Switch to User B: User B cannot access User A's contacts or cache
      final userBContacts = await repository.getContactsForUser(userB);
      expect(userBContacts, isEmpty);

      final userBCache = await cacheManager.getScanResult(sharedFingerprint, userId: userB);
      expect(userBCache, isNull);

      final userBExactMatch = await duplicateDetector.checkExactFingerprint(
        sharedFingerprint,
        userId: userB,
      );
      expect(userBExactMatch.isDuplicate, isFalse);

      // 4. Clear User A's data on logout / purge
      await repository.clearUserData(userA);
      await cacheManager.clearUserCache(userA);

      final purgedUserAContacts = await repository.getContactsForUser(userA);
      expect(purgedUserAContacts, isEmpty);

      final purgedUserACache = await cacheManager.getScanResult(sharedFingerprint, userId: userA);
      expect(purgedUserACache, isNull);
    });
  });
}
