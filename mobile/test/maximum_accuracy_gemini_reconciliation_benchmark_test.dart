import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/card_analysis_result.dart';
import 'package:digital_share/models/field_evidence.dart';
import 'package:digital_share/models/learned_correction.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/ocr/gemini_ocr_reconciliation_engine.dart';
import 'package:digital_share/services/storage/offline_scan_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GeminiOcrReconciliationEngine engine;
  late String tempDir;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    engine = const GeminiOcrReconciliationEngine();
    tempDir = Directory.systemTemp.createTempSync('digital_share_benchmark_').path;
  });

  tearDown(() {
    try {
      Directory(tempDir).deleteSync(recursive: true);
    } catch (_) {}
  });

  group('DIGITAL SHARE — MAXIMUM ACCURACY BENCHMARK & RECONCILIATION SUITE (10 CATEGORIES)', () {
    // 1. Company-first cards
    test('Category 1: Company-first card correctly isolates company and extracts person name', () {
      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '$tempDir/front.jpg',
        rawText: 'Apex Healthcare Solutions Pvt Ltd\nDr. Antony Lobo\nSenior Consultant - Cardiology\nPhone: +91 98765 43210',
      );

      final localParsed = BusinessCardData(
        fullName: 'Apex Healthcare Solutions Pvt Ltd', // Local parser mistake
        company: null,
        jobTitle: 'Senior Consultant - Cardiology',
        phoneNumbers: const [BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile')],
      );

      final geminiResult = CardAnalysisResult(
        clientRequestId: 'bench_c1',
        analysisCacheKey: 'cache_c1',
        visualVerificationPerformed: true,
        frontImageVerified: true,
        geminiApiExecuted: true,
        fullName: const ExtractedField(
          value: 'Dr. Antony Lobo',
          confidence: 0.98,
          isVisuallyVerified: true,
          verificationStatus: 'verified',
        ),
        company: const ExtractedField(
          value: 'Apex Healthcare Solutions Pvt Ltd',
          confidence: 0.99,
          isVisuallyVerified: true,
          verificationStatus: 'verified',
        ),
        jobTitle: const ExtractedField(
          value: 'Senior Consultant - Cardiology',
          confidence: 0.95,
          isVisuallyVerified: true,
          verificationStatus: 'verified',
        ),
        promptTokens: 245,
        candidateTokens: 82,
        totalTokens: 327,
      );

      final result = engine.reconcile(
        localCardData: localParsed,
        frontOcr: frontOcr,
        geminiResult: geminiResult,
      );

      expect(result.reconciledData.fullName, equals('Dr. Antony Lobo'));
      expect(result.reconciledData.company, equals('Apex Healthcare Solutions Pvt Ltd'));
      expect(result.reconciledData.jobTitle, equals('Senior Consultant - Cardiology'));
      expect(result.fieldsCorrectedByGemini, greaterThanOrEqualTo(1));
      expect(result.fieldDecisions['fullName']?.source, equals('geminiExtraction'));
    });

    // 2. Person names below company
    test('Category 2: Person name located below company name is extracted without confusion', () {
      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '$tempDir/front.jpg',
        rawText: 'Blue Horizon Technologies\nMeera Nambiar\nVP Engineering\nmeera@bluehorizon.io',
      );

      final localParsed = BusinessCardData(
        fullName: null,
        company: 'Blue Horizon Technologies',
        jobTitle: 'VP Engineering',
        emailAddresses: const [BusinessCardEmail(email: 'meera@bluehorizon.io', label: 'Work')],
      );

      final geminiResult = CardAnalysisResult(
        clientRequestId: 'bench_c2',
        analysisCacheKey: 'cache_c2',
        visualVerificationPerformed: true,
        geminiApiExecuted: true,
        fullName: const ExtractedField(
          value: 'Meera Nambiar',
          confidence: 0.96,
          isVisuallyVerified: true,
          verificationStatus: 'verified',
        ),
        company: const ExtractedField(
          value: 'Blue Horizon Technologies',
          confidence: 0.99,
          isVisuallyVerified: true,
          verificationStatus: 'verified',
        ),
      );

      final result = engine.reconcile(
        localCardData: localParsed,
        frontOcr: frontOcr,
        geminiResult: geminiResult,
      );

      expect(result.reconciledData.fullName, equals('Meera Nambiar'));
      expect(result.reconciledData.company, equals('Blue Horizon Technologies'));
      expect(result.fieldsDiscoveredByGemini, equals(1));
    });

    // 3. Job titles near names
    test('Category 3: Job title immediately adjacent to name guides correct field placement', () {
      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '$tempDir/front.jpg',
        rawText: 'Vikram Sethi\nChief Technical Architect\nOmniCloud Systems\nvikram.sethi@omnicloud.com',
      );

      final localParsed = BusinessCardData(
        fullName: 'Vikram Sethi',
        jobTitle: 'Chief Technical Architect',
        company: 'OmniCloud Systems',
      );

      final geminiResult = CardAnalysisResult(
        clientRequestId: 'bench_c3',
        analysisCacheKey: 'cache_c3',
        visualVerificationPerformed: true,
        geminiApiExecuted: true,
        fullName: const ExtractedField(value: 'Vikram Sethi', confidence: 0.99, verificationStatus: 'verified'),
        jobTitle: const ExtractedField(value: 'Chief Technical Architect', confidence: 0.98, verificationStatus: 'verified'),
        company: const ExtractedField(value: 'OmniCloud Systems', confidence: 0.97, verificationStatus: 'verified'),
      );

      final result = engine.reconcile(
        localCardData: localParsed,
        frontOcr: frontOcr,
        geminiResult: geminiResult,
      );

      expect(result.reconciledData.fullName, equals('Vikram Sethi'));
      expect(result.reconciledData.jobTitle, equals('Chief Technical Architect'));
      expect(result.reconciledData.company, equals('OmniCloud Systems'));
    });

    // 4. Multiple employees from one company (Strict Employee Isolation)
    test('Category 4: Multiple employees from same company never transfer personal identity data', () {
      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '$tempDir/front.jpg',
        rawText: 'Global Logistics Solutions\nSiddharth Rao\nOperations Director\n+91 99887 76655\nsiddharth@globallogistics.com',
      );

      final localParsed = BusinessCardData(
        fullName: 'Siddharth Rao',
        company: 'Global Logistics Solutions',
        jobTitle: 'Operations Director',
        phoneNumbers: const [BusinessCardPhone(number: '+91 99887 76655', label: 'Mobile')],
        emailAddresses: const [BusinessCardEmail(email: 'siddharth@globallogistics.com', label: 'Work')],
      );

      // Learned correction from a colleague (Anita Sharma) at the SAME company
      final colleagueCorrection = LearnedCorrectionRecord(
        id: 'corr_colleague_1',
        imageFingerprint: 'different_hash_colleague',
        fieldName: 'fullName',
        originalExtractedValue: 'Anita S',
        approvedValue: 'Anita Sharma',
        createdAt: DateTime.now(),
        tier: CorrectionTier.exactImageReuse,
        isActive: true,
      );

      final result = engine.reconcile(
        localCardData: localParsed,
        frontOcr: frontOcr,
        learnedCorrections: [colleagueCorrection], // Different image hash!
      );

      // Verify strict isolation: Colleague's name Anita Sharma MUST NOT be transferred!
      expect(result.reconciledData.fullName, equals('Siddharth Rao'));
      expect(result.reconciledData.fullName, isNot(equals('Anita Sharma')));
    });

    // 5. Multiple phone numbers and emails
    test('Category 5: Multiple phone numbers (mobile, direct, toll-free) and emails merged losslessly', () {
      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '$tempDir/front.jpg',
        rawText: 'Summit Enterprises\nTel: +1-800-555-0199\nDirect: +1-415-555-0142\ninfo@summit.com\nsupport@summit.com',
      );

      final localParsed = BusinessCardData(
        company: 'Summit Enterprises',
        phoneNumbers: const [
          BusinessCardPhone(number: '+1-800-555-0199', label: 'Toll-Free'),
        ],
        emailAddresses: const [
          BusinessCardEmail(email: 'info@summit.com', label: 'General'),
        ],
      );

      final geminiResult = CardAnalysisResult(
        clientRequestId: 'bench_c5',
        analysisCacheKey: 'cache_c5',
        visualVerificationPerformed: true,
        geminiApiExecuted: true,
        phoneNumbers: const [
          ExtractedPhone(number: '+1-800-555-0199', label: 'Toll-Free', confidence: 0.99),
          ExtractedPhone(number: '+1-415-555-0142', label: 'Direct', confidence: 0.97),
        ],
        emailAddresses: const [
          ExtractedEmail(email: 'info@summit.com', label: 'General', confidence: 0.99),
          ExtractedEmail(email: 'support@summit.com', label: 'Support', confidence: 0.98),
        ],
      );

      final result = engine.reconcile(
        localCardData: localParsed,
        frontOcr: frontOcr,
        geminiResult: geminiResult,
      );

      expect(result.reconciledData.phoneNumbers.length, equals(2));
      expect(result.reconciledData.emailAddresses.length, equals(2));
      expect(result.reconciledData.phoneNumbers.any((p) => p.number.contains('0142')), isTrue);
      expect(result.reconciledData.emailAddresses.any((e) => e.email.contains('support')), isTrue);
    });

    // 6. Two-sided cards
    test('Category 6: Dual-sided card combines front identity and back physical address', () {
      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '$tempDir/front.jpg',
        rawText: 'Priya Sundaram\nCreative Director\nStudio Lotus Designs',
      );
      final backOcr = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: '$tempDir/back.jpg',
        rawText: 'Lotus Tower, 4th Floor\nIndiranagar 100 Feet Road\nBengaluru 560038, India\nwww.studiolotus.in',
      );

      final localParsed = BusinessCardData(
        fullName: 'Priya Sundaram',
        jobTitle: 'Creative Director',
        company: 'Studio Lotus Designs',
        isDualSided: true,
        address: 'Lotus Tower, 4th Floor, Indiranagar',
      );

      final geminiResult = CardAnalysisResult(
        clientRequestId: 'bench_c6',
        analysisCacheKey: 'cache_c6',
        visualVerificationPerformed: true,
        frontImageVerified: true,
        backImageVerified: true,
        geminiApiExecuted: true,
        fullName: const ExtractedField(value: 'Priya Sundaram', confidence: 0.99, verificationStatus: 'verified'),
        company: const ExtractedField(value: 'Studio Lotus Designs', confidence: 0.99, verificationStatus: 'verified'),
        jobTitle: const ExtractedField(value: 'Creative Director', confidence: 0.97, verificationStatus: 'verified'),
        address: const ExtractedAddress(
          fullAddress: 'Lotus Tower, 4th Floor, Indiranagar 100 Feet Road, Bengaluru 560038, India',
          confidence: 0.98,
          verificationStatus: 'verified',
        ),
        websites: const [ExtractedWebsite(url: 'https://www.studiolotus.in', confidence: 0.99)],
      );

      final result = engine.reconcile(
        localCardData: localParsed,
        frontOcr: frontOcr,
        backOcr: backOcr,
        geminiResult: geminiResult,
      );

      expect(result.reconciledData.fullName, equals('Priya Sundaram'));
      expect(result.reconciledData.address, contains('Bengaluru 560038'));
      expect(result.reconciledData.website, equals('https://www.studiolotus.in'));
    });

    // 7. Indian and international formats
    test('Category 7: Indian PIN codes (+91 phone prefixes) and international formats parsed accurately', () {
      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '$tempDir/front.jpg',
        rawText: 'Rajesh K. Verma, FCA\nChartered Accountant\nVerma & Associates\n+91 94440 12345\nNew Delhi 110001',
      );

      final localParsed = BusinessCardData(
        fullName: 'Rajesh K. Verma, FCA',
        jobTitle: 'Chartered Accountant',
        company: 'Verma & Associates',
        address: 'New Delhi 110001',
        phoneNumbers: const [BusinessCardPhone(number: '+91 94440 12345', label: 'Mobile')],
      );

      final geminiResult = CardAnalysisResult(
        clientRequestId: 'bench_c7',
        analysisCacheKey: 'cache_c7',
        visualVerificationPerformed: true,
        geminiApiExecuted: true,
        fullName: const ExtractedField(value: 'Rajesh K. Verma, FCA', confidence: 0.99, verificationStatus: 'verified'),
        jobTitle: const ExtractedField(value: 'Chartered Accountant', confidence: 0.98, verificationStatus: 'verified'),
        company: const ExtractedField(value: 'Verma & Associates', confidence: 0.99, verificationStatus: 'verified'),
        address: const ExtractedAddress(fullAddress: 'New Delhi 110001, India', confidence: 0.95),
      );

      final result = engine.reconcile(
        localCardData: localParsed,
        frontOcr: frontOcr,
        geminiResult: geminiResult,
      );

      expect(result.reconciledData.fullName, equals('Rajesh K. Verma, FCA'));
      expect(result.reconciledData.company, equals('Verma & Associates'));
      expect(result.reconciledData.address, contains('110001'));
    });

    // 8. Multilingual cards (Latin + Devanagari / Regional script)
    test('Category 8: Multilingual business card preserves Latin text while acknowledging regional script', () {
      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '$tempDir/front.jpg',
        rawText: 'भारत इलेक्ट्रॉनिक्स | Bharat Electronics\nAnand Joshi\nGeneral Manager\nBangalore, India',
      );

      final localParsed = BusinessCardData(
        fullName: 'Anand Joshi',
        company: 'Bharat Electronics',
        jobTitle: 'General Manager',
      );

      final geminiResult = CardAnalysisResult(
        clientRequestId: 'bench_c8',
        analysisCacheKey: 'cache_c8',
        visualVerificationPerformed: true,
        geminiApiExecuted: true,
        fullName: const ExtractedField(value: 'Anand Joshi', confidence: 0.98, verificationStatus: 'verified'),
        company: const ExtractedField(value: 'Bharat Electronics', confidence: 0.98, verificationStatus: 'verified'),
      );

      final result = engine.reconcile(
        localCardData: localParsed,
        frontOcr: frontOcr,
        geminiResult: geminiResult,
      );

      expect(result.reconciledData.fullName, equals('Anand Joshi'));
      expect(result.reconciledData.company, equals('Bharat Electronics'));
    });

    // 9. Blurry and rotated cards (Safe Review Flagging)
    test('Category 9: Low readability and visual distortion flags reviewRequired and avoids false confidence', () {
      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '$tempDir/blurry.jpg',
        rawText: 'Jn D0e\nSftwre Eng\nAcme C0rp',
      );

      final localParsed = BusinessCardData(
        fullName: 'Jn D0e',
        jobTitle: 'Sftwre Eng',
        company: 'Acme C0rp',
      );

      final geminiResult = CardAnalysisResult(
        clientRequestId: 'bench_c9',
        analysisCacheKey: 'cache_c9',
        visualVerificationPerformed: true,
        geminiApiExecuted: true,
        requiresManualReview: true,
        reviewWarnings: const ['Image is blurry; text recognition uncertainty'],
        fullName: const ExtractedField(
          value: 'John Doe',
          confidence: 0.60,
          isVisuallyVerified: false,
          reviewRequired: true,
          verificationStatus: 'reviewRequired',
          correctionReason: 'Inferred John Doe from distorted Jn D0e',
        ),
      );

      final result = engine.reconcile(
        localCardData: localParsed,
        frontOcr: frontOcr,
        geminiResult: geminiResult,
      );

      expect(result.requiresReview, isTrue);
      expect(result.fieldDecisions['fullName']?.reviewRequired, isTrue);
    });

    // 10. Cards without person names (Honest Absence & Zero Hallucination)
    test('Category 10: Company-only card returns fullName as null and never hallucinates person name', () {
      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '$tempDir/front.jpg',
        rawText: 'City Central Diagnostic Laboratory\nOpen 24 Hours\nHelpline: 080-23456789\ninfo@citycentrallabs.com\nwww.citycentrallabs.com',
      );

      final localParsed = BusinessCardData(
        fullName: 'City Central Diagnostic Laboratory', // Erroneously mapped locally
        company: null,
        phoneNumbers: const [BusinessCardPhone(number: '080-23456789', label: 'Helpline')],
        emailAddresses: const [BusinessCardEmail(email: 'info@citycentrallabs.com', label: 'Work')],
        website: 'www.citycentrallabs.com',
      );

      final geminiResult = CardAnalysisResult(
        clientRequestId: 'bench_c10',
        analysisCacheKey: 'cache_c10',
        visualVerificationPerformed: true,
        geminiApiExecuted: true,
        fullName: const ExtractedField(
          value: null,
          confidence: 0.99,
          verificationStatus: 'notFound',
          correctionReason: 'Card represents a medical diagnostic facility; no individual person name is visible.',
        ),
        company: const ExtractedField(
          value: 'City Central Diagnostic Laboratory',
          confidence: 0.99,
          verificationStatus: 'verified',
        ),
      );

      final result = engine.reconcile(
        localCardData: localParsed,
        frontOcr: frontOcr,
        geminiResult: geminiResult,
      );

      // Strict requirement: fullName MUST be null, not manufactured!
      expect(result.reconciledData.fullName, isNull);
      expect(result.reconciledData.company, equals('City Central Diagnostic Laboratory'));
      expect(result.fieldDecisions['fullName']?.verificationStatus, equals(FieldVerificationStatus.notFound));
    });

    // 11. Protected User-Approved Corrections (Highest Precedence)
    test('User-approved manual corrections take precedence over Gemini and local OCR', () {
      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '$tempDir/front.jpg',
        rawText: 'Rob Smith\nCEO\nAcme Corp',
      );

      final localParsed = BusinessCardData(
        fullName: 'Rob Smith',
        company: 'Acme Corp',
        jobTitle: 'CEO',
      );

      final approvedCorrection = LearnedCorrectionRecord(
        id: 'user_corr_1',
        imageFingerprint: 'fingerprint_test_1',
        fieldName: 'fullName',
        originalExtractedValue: 'Rob Smith',
        approvedValue: 'Robert J. Smith',
        createdAt: DateTime.now(),
        tier: CorrectionTier.exactImageReuse,
        isActive: true,
      );

      final geminiResult = CardAnalysisResult(
        clientRequestId: 'bench_user',
        analysisCacheKey: 'cache_user',
        visualVerificationPerformed: true,
        geminiApiExecuted: true,
        fullName: const ExtractedField(value: 'Rob Smith', confidence: 0.95), // Gemini saw "Rob"
      );

      final result = engine.reconcile(
        localCardData: localParsed,
        frontOcr: frontOcr,
        geminiResult: geminiResult,
        learnedCorrections: [approvedCorrection],
      );

      // User's approved correction "Robert J. Smith" MUST win!
      expect(result.reconciledData.fullName, equals('Robert J. Smith'));
      expect(result.userCorrectionsProtected, equals(1));
      expect(result.fieldDecisions['fullName']?.source, equals('userApprovedCorrection'));
    });

    // 12. Offline Scan Queue Service
    test('Offline Scan Queue enqueues scans when offline and retrieves pending items', () async {
      final queueService = OfflineScanQueueService();
      await queueService.clearQueue();

      await queueService.enqueueScan(
        scanId: 'offline_scan_101',
        userId: 'user_test_99',
        frontImagePath: '$tempDir/front.jpg',
        frontSha256: 'sha256_mock_123',
        cardData: const BusinessCardData(
          fullName: 'Offline User',
          company: 'Offline Corp',
        ),
      );

      final pending = await queueService.getPendingScans(userId: 'user_test_99');
      expect(pending.length, equals(1));
      expect(pending.first.id, equals('offline_scan_101'));
      expect(pending.first.status, equals('pending'));

      await queueService.markCompleted('offline_scan_101');
      final remaining = await queueService.getPendingScans(userId: 'user_test_99');
      expect(remaining.isEmpty, isTrue);
    });
  });
}

