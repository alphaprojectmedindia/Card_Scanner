import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/ocr/field_semantic_evaluator.dart';
import 'package:digital_share/services/ocr/hybrid_ocr_pipeline.dart';
import 'package:digital_share/services/ocr/ocr_engine.dart';

/// Test double simulating an OCR engine with configurable output and latency.
class MockTestOcrEngine implements OcrEngine {
  @override
  final String name;
  final OcrEngineResult resultToReturn;
  int invocationCount = 0;

  MockTestOcrEngine({
    required this.name,
    required this.resultToReturn,
  });

  Future<bool> initialize() async => true;

  @override
  Future<OcrEngineResult> recognize(String imagePath) async {
    invocationCount++;
    return resultToReturn;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // SECTION 1: MANDATORY BENCHMARK TESTS (A, B, C, D, E, F, G)
  // ===========================================================================
  group('Mandatory Hybrid OCR & Field-Level Resolution Benchmark Tests', () {
    // -------------------------------------------------------------------------
    // TEST A: MANDATORY GLOBAL-SCORE TEST (92 vs 74)
    // -------------------------------------------------------------------------
    test('TEST A: ML Kit 92 (Name=Location) vs Paddle 74 (Name=Arun Kumar) -> Paddle Name wins, 92 DOES NOT win', () async {
      // ML Kit has high overall score (92) with valid contact info, but misidentified Name as "Chennai"
      final mockMlKit = MockTestOcrEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Chennai\nSoftware Solutions Pvt Ltd\nPhone: +91 98765 43210\nEmail: arun@softwaresolutions.com\nwww.softwaresolutions.com\n6, Mount Road, Chennai - 600002',
          lineCount: 6,
          characterCount: 155,
          processingTime: Duration(milliseconds: 280),
          isSuccess: true,
          detectedLines: [
            'Chennai',
            'Software Solutions Pvt Ltd',
            'Phone: +91 98765 43210',
            'Email: arun@softwaresolutions.com',
            'www.softwaresolutions.com',
            '6, Mount Road, Chennai - 600002',
          ],
        ),
      );

      // PaddleOCR has lower overall score (74) but accurately extracted "Arun Kumar"
      final mockPaddle = MockTestOcrEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Arun Kumar\nSoftware Solutions Pvt Ltd\nPhone: +91 98765 43210\nEmail: arun@softwaresolutions.com\n6, Mount Road, Chennai - 600002',
          lineCount: 5,
          characterCount: 145,
          processingTime: Duration(milliseconds: 3800),
          isSuccess: true,
          detectedLines: [
            'Arun Kumar',
            'Software Solutions Pvt Ltd',
            'Phone: +91 98765 43210',
            'Email: arun@softwaresolutions.com',
            '6, Mount Road, Chennai - 600002',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final sideResult = await pipeline.processCardSide(
        imagePath: '/test/card_a.jpg',
        side: CardSide.front,
      );

      // Verify Paddle was invoked despite ML Kit's high score because Name was location-like
      expect(mockMlKit.invocationCount, 1);
      expect(mockPaddle.invocationCount, 1);
      expect(sideResult.metadata['fallbackInvoked'], isTrue);

      const parser = BusinessCardParser();
      final parsed = parser.parseSide(sideResult);

      // MANDATORY ASSERTION: Arun Kumar wins Name; Chennai is NEVER selected as Name!
      expect(parsed.fullName, 'Arun Kumar');
      expect(parsed.fullName, isNot(contains('Chennai')));

      // Phone and email are preserved and verified
      expect(parsed.phoneNumbers.any((p) => p.number.contains('98765')), isTrue);
      expect(parsed.emailAddresses.any((e) => e.email.contains('arun@softwaresolutions.com')), isTrue);

      // Field sources prove field-level resolution: Name from Paddle, others from ML Kit or Both
      final fieldSources = sideResult.metadata['fieldSources'] as Map<String, dynamic>?;
      expect(fieldSources, isNotNull);
      expect(fieldSources!['name'], contains('PaddleOCR'));
    });

    // -------------------------------------------------------------------------
    // TEST B: MANDATORY INVERSE TEST (ML Kit 72 vs Paddle 90)
    // -------------------------------------------------------------------------
    test('TEST B: ML Kit 72 (Name=John Mathew) vs Paddle 90 (Name=Company) -> ML Kit Name wins, global score does not win', () async {
      // ML Kit has lower overall score (72) but clean Name "John Mathew"
      final mockMlKit = MockTestOcrEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'John Mathew\nSenior Architect\nGlobal Tech Industries Ltd\n+1-555-019-2834\njohn@globaltech.com',
          lineCount: 5,
          characterCount: 95,
          processingTime: Duration(milliseconds: 310),
          isSuccess: true,
          detectedLines: [
            'John Mathew',
            'Senior Architect',
            'Global Tech Industries Ltd',
            '+1-555-019-2834',
            'john@globaltech.com',
          ],
        ),
      );

      // PaddleOCR has high overall score (90) but put company as top candidate
      final mockPaddle = MockTestOcrEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Global Tech Industries Ltd\nSenior Architect\n100 Tech Park, Suite 400\n+1-555-019-2834\njohn@globaltech.com\nwww.globaltech.com',
          lineCount: 6,
          characterCount: 130,
          processingTime: Duration(milliseconds: 3900),
          isSuccess: true,
          detectedLines: [
            'Global Tech Industries Ltd',
            'Senior Architect',
            '100 Tech Park, Suite 400',
            '+1-555-019-2834',
            'john@globaltech.com',
            'www.globaltech.com',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final sideResult = await pipeline.processCardSide(
        imagePath: '/test/card_b.jpg',
        side: CardSide.front,
      );

      const parser = BusinessCardParser();
      final parsed = parser.parseSide(sideResult);

      // MANDATORY ASSERTION: John Mathew wins Name; company is NEVER selected as Name!
      expect(parsed.fullName, 'John Mathew');
      expect(parsed.fullName, isNot(contains('Global Tech Industries Ltd')));
    });

    // -------------------------------------------------------------------------
    // TEST C: MANDATORY EMPTY-NAME TEST (Zero-Hallucination)
    // -------------------------------------------------------------------------
    test('TEST C: No trustworthy human name in either engine -> Name is empty (null), no substitution', () async {
      final mockMlKit = MockTestOcrEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Apex Logistics & Freight Solutions Ltd\n24/7 Dispatch Services\nTel: +1-800-555-0199\nsupport@apexlogistics.com\n12 Harbor Boulevard, Bay Area',
          lineCount: 5,
          characterCount: 140,
          processingTime: Duration(milliseconds: 290),
          isSuccess: true,
          detectedLines: [
            'Apex Logistics & Freight Solutions Ltd',
            '24/7 Dispatch Services',
            'Tel: +1-800-555-0199',
            'support@apexlogistics.com',
            '12 Harbor Boulevard, Bay Area',
          ],
        ),
      );

      final mockPaddle = MockTestOcrEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Apex Logistics & Freight Solutions Ltd\n24/7 Dispatch Services\nTel: +1-800-555-0199\nsupport@apexlogistics.com\n12 Harbor Boulevard, Bay Area',
          lineCount: 5,
          characterCount: 140,
          processingTime: Duration(milliseconds: 3600),
          isSuccess: true,
          detectedLines: [
            'Apex Logistics & Freight Solutions Ltd',
            '24/7 Dispatch Services',
            'Tel: +1-800-555-0199',
            'support@apexlogistics.com',
            '12 Harbor Boulevard, Bay Area',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final sideResult = await pipeline.processCardSide(
        imagePath: '/test/card_c.jpg',
        side: CardSide.front,
      );

      const parser = BusinessCardParser();
      final parsed = parser.parseSide(sideResult);

      // MANDATORY ASSERTION: Zero-hallucination rule: Name MUST be null!
      expect(parsed.fullName, isNull);
      expect(parsed.company, contains('Apex Logistics'));
      expect(parsed.phoneNumbers.isNotEmpty, isTrue);
      expect(parsed.emailAddresses.isNotEmpty, isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST D: THRESHOLD TEST 59 -> PADDLE MUST RUN
    // -------------------------------------------------------------------------
    test('TEST D: ML Kit score = 59 (< 60) -> Paddle MUST run', () async {
      // Missing phone and email, borderline text -> score 55 (< 60)
      final mockMlKit = MockTestOcrEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Acme Studio\nCreative Design Agency\nwww.acmestudio.design',
          lineCount: 3,
          characterCount: 56,
          processingTime: Duration(milliseconds: 250),
          isSuccess: true,
          detectedLines: [
            'Acme Studio',
            'Creative Design Agency',
            'www.acmestudio.design',
          ],
        ),
      );

      final mockPaddle = MockTestOcrEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Acme Studio\nCreative Design Agency\nTel: +1 415 555 9012\nwww.acmestudio.design',
          lineCount: 4,
          characterCount: 77,
          processingTime: Duration(milliseconds: 3800),
          isSuccess: true,
          detectedLines: [
            'Acme Studio',
            'Creative Design Agency',
            'Tel: +1 415 555 9012',
            'www.acmestudio.design',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final sideResult = await pipeline.processCardSide(
        imagePath: '/test/card_d.jpg',
        side: CardSide.front,
      );

      expect(mockMlKit.invocationCount, 1);
      expect(mockPaddle.invocationCount, 1); // Paddle MUST run
      expect(sideResult.metadata['fallbackInvoked'], isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST E: BOTH ENGINES RUN FOR PHYSICAL CARDS (FAST PATH REMOVED)
    // -------------------------------------------------------------------------
    test('TEST E: ML Kit and Paddle both run for physical cards and arbitrate field-by-field', () async {
      final mockMlKit = MockTestOcrEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Antony Lobo\nHon. Consul of Spain\nConsulate of Spain\nTel: +91 44 4210 7657\nspainconsulate.chennai@gmail.com',
          lineCount: 5,
          characterCount: 115,
          processingTime: Duration(milliseconds: 290),
          isSuccess: true,
          detectedLines: [
            'Antony Lobo',
            'Hon. Consul of Spain',
            'Consulate of Spain',
            'Tel: +91 44 4210 7657',
            'spainconsulate.chennai@gmail.com',
          ],
        ),
      );

      final mockPaddle = MockTestOcrEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Antony Lobo\nHon. Consul of Spain\nConsulate of Spain\nTel: +91 44 4210 7657\nspainconsulate.chennai@gmail.com',
          lineCount: 5,
          characterCount: 115,
          processingTime: Duration(milliseconds: 3800),
          isSuccess: true,
          detectedLines: [
            'Antony Lobo',
            'Hon. Consul of Spain',
            'Consulate of Spain',
            'Tel: +91 44 4210 7657',
            'spainconsulate.chennai@gmail.com',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final sideResult = await pipeline.processCardSide(
        imagePath: '/test/card_e.jpg',
        side: CardSide.front,
      );

      expect(mockMlKit.invocationCount, 1);
      expect(mockPaddle.invocationCount, 1); // Both engines run
      expect(sideResult.metadata['fallbackInvoked'], isTrue);
      expect(sideResult.metadata['timings'], isNotNull);
    });

    // -------------------------------------------------------------------------
    // TEST F: ML KIT 85 BUT WEAK/CORRUPTED NAME -> PADDLE MUST RUN
    // -------------------------------------------------------------------------
    test('TEST F: ML Kit score = 85 with low name confidence -> Paddle MUST run despite high score', () async {
      final mockMlKit = MockTestOcrEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Snt0ny Doto\nGlobal Consulting\nTel: +91 98400 12345\ninfo@globalconsulting.com\nwww.globalconsulting.com\n15 Gandhi Road, Chennai',
          lineCount: 6,
          characterCount: 135,
          processingTime: Duration(milliseconds: 310),
          isSuccess: true,
          detectedLines: [
            'Snt0ny Doto',
            'Global Consulting',
            'Tel: +91 98400 12345',
            'info@globalconsulting.com',
            'www.globalconsulting.com',
            '15 Gandhi Road, Chennai',
          ],
        ),
      );

      final mockPaddle = MockTestOcrEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Antony Lobo\nGlobal Consulting\nTel: +91 98400 12345\ninfo@globalconsulting.com\n15 Gandhi Road, Chennai',
          lineCount: 5,
          characterCount: 120,
          processingTime: Duration(milliseconds: 3900),
          isSuccess: true,
          detectedLines: [
            'Antony Lobo',
            'Global Consulting',
            'Tel: +91 98400 12345',
            'info@globalconsulting.com',
            '15 Gandhi Road, Chennai',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final sideResult = await pipeline.processCardSide(
        imagePath: '/test/card_f.jpg',
        side: CardSide.front,
      );

      expect(mockMlKit.invocationCount, 1);
      expect(mockPaddle.invocationCount, 1); // Paddle MUST run
      expect(sideResult.metadata['fallbackInvoked'], isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST G: ML KIT 95 BUT NAME LOOKS LIKE LOCATION -> PADDLE MUST RUN
    // -------------------------------------------------------------------------
    test('TEST G: ML Kit score = 95 with location name -> Paddle MUST run despite high score', () async {
      final mockMlKit = MockTestOcrEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Chennai - 600004\nNexus Enterprises Ltd\nTel: +91 44 2498 7654\ncontact@nexus.in\nwww.nexus.in\n100 Santhome High Road',
          lineCount: 6,
          characterCount: 140,
          processingTime: Duration(milliseconds: 320),
          isSuccess: true,
          detectedLines: [
            'Chennai - 600004',
            'Nexus Enterprises Ltd',
            'Tel: +91 44 2498 7654',
            'contact@nexus.in',
            'www.nexus.in',
            '100 Santhome High Road',
          ],
        ),
      );

      final mockPaddle = MockTestOcrEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Vikram Sundaram\nManaging Director\nNexus Enterprises Ltd\nTel: +91 44 2498 7654\ncontact@nexus.in\n100 Santhome High Road, Chennai - 600004',
          lineCount: 6,
          characterCount: 165,
          processingTime: Duration(milliseconds: 3850),
          isSuccess: true,
          detectedLines: [
            'Vikram Sundaram',
            'Managing Director',
            'Nexus Enterprises Ltd',
            'Tel: +91 44 2498 7654',
            'contact@nexus.in',
            '100 Santhome High Road, Chennai - 600004',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final sideResult = await pipeline.processCardSide(
        imagePath: '/test/card_g.jpg',
        side: CardSide.front,
      );

      expect(mockMlKit.invocationCount, 1);
      expect(mockPaddle.invocationCount, 1); // Paddle MUST run!
      expect(sideResult.metadata['fallbackInvoked'], isTrue);

      const parser = BusinessCardParser();
      final parsed = parser.parseSide(sideResult);
      expect(parsed.fullName, 'Vikram Sundaram');
      expect(parsed.fullName, isNot(contains('Chennai')));
    });
  });

  // ===========================================================================
  // SECTION 2: 27 COMPREHENSIVE STRUCTURAL REGRESSION TEST CATEGORIES
  // ===========================================================================
  group('27 Comprehensive Business Card Structural Regression Cases', () {
    // 1. Standard corporate card
    test('1. Standard corporate card: person, title, company, address, phones, email', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          'Sarah Jenkins',
          'Vice President of Engineering',
          'Acme Technologies Corp',
          '+1-415-555-0199',
          'sjenkins@acmetech.com',
          'www.acmetech.com',
          '500 Howard Street, San Francisco, CA 94105',
        ],
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 95.0,
        secondaryLines: [],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 0.0,
      );
      expect(res.name?.value, 'Sarah Jenkins');
      expect(res.jobTitle?.value, contains('Vice President'));
      expect(res.company?.value, contains('Acme Technologies'));
    });

    // 2. Government officer
    test('2. Government officer: Name with I.A.S. credential, multi-line senior title', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          'Kumar Jayant, I.A.S.',
          'Additional Chief Secretary to Government',
          'Department of Revenue Administration',
          'Government Secretariat, Fort St. George',
          'Chennai - 600009',
          'Phone: 044-25670123',
        ],
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 88.0,
        secondaryLines: [],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 0.0,
      );
      expect(res.name?.value, contains('Kumar Jayant'));
      expect(res.jobTitle?.value, contains('Additional Chief Secretary'));
      expect(res.name?.value, isNot(contains('Secretary')));
    });

    // 3. Doctor card
    test('3. Doctor card: Dr. prefix, medical degrees, hospital', () {
      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'Dr. A. R. Swaminathan, M.D., D.M.',
        sourceEngine: 'Google ML Kit',
      );
      expect(cand.isTrustworthy, isTrue);
      expect(cand.semanticConfidence, greaterThanOrEqualTo(0.80));
      expect(cand.positiveEvidence.any((e) => e.contains('honorific')), isTrue);
    });

    // 4. Lawyer card
    test('4. Lawyer card: Adv. prefix, Bar Council credentials', () {
      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'Adv. Meenakshi Sundaram, B.A., B.L.',
        sourceEngine: 'Google ML Kit',
      );
      expect(cand.isTrustworthy, isTrue);
      expect(cand.positiveEvidence.any((e) => e.contains('honorific')), isTrue);
    });

    // 5. Professor card
    test('5. Professor card: Prof. prefix and department', () {
      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'Prof. K. Narayanan, Ph.D.',
        sourceEngine: 'Google ML Kit',
      );
      expect(cand.isTrustworthy, isTrue);
      expect(cand.positiveEvidence.any((e) => e.contains('initial')), isTrue);
    });

    // 6. Consultant card
    test('6. Consultant card: Name and Management Consultant title', () {
      final titleCand = FieldSemanticEvaluator.evaluateJobTitleCandidate(
        rawLine: 'Senior Strategy Consultant',
        sourceEngine: 'Google ML Kit',
      );
      expect(titleCand.semanticConfidence, greaterThanOrEqualTo(0.70));
    });

    // 7. Freelancer card
    test('7. Freelancer card: Independent designer with portfolio', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          'Elena Rostova',
          'Independent UI/UX Designer',
          'hello@elenarostova.design',
          '+44 7700 900123',
          'www.elenarostova.design',
        ],
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 85.0,
        secondaryLines: [],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 0.0,
      );
      expect(res.name?.value, 'Elena Rostova');
      expect(res.jobTitle?.value, contains('Designer'));
    });

    // 8. Shop owner card
    test('8. Shop owner card: Store name top, Prop. person name', () {
      final nameCand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'Prop. S. Murugesan',
        sourceEngine: 'Google ML Kit',
      );
      expect(nameCand.isTrustworthy, isTrue);
      expect(nameCand.value, contains('Murugesan'));
    });

    // 9. Event company card
    test('9. Event company card: Brand name, event suffix, person name', () {
      final compCand = FieldSemanticEvaluator.evaluateCompanyCandidate(
        rawLine: 'Grand Occasions Events & Celebrations Pvt Ltd',
        sourceEngine: 'Google ML Kit',
      );
      expect(compCand.semanticConfidence, greaterThanOrEqualTo(0.80));
    });

    // 10. Large brand + small person name
    test('10. Large brand + small person name: Brand is NOT person name', () {
      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'SAMSUNG ELECTRONICS GLOBAL',
        sourceEngine: 'Google ML Kit',
      );
      expect(cand.rejectionReasons.any((r) => r.contains('corporate')), isTrue);
      expect(cand.semanticConfidence, lessThan(0.40));
    });

    // 11. Large location + small person name
    test('11. Large location + small person name: "CHENNAI" is NOT person name', () {
      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'CHENNAI',
        sourceEngine: 'Google ML Kit',
      );
      expect(cand.isTrustworthy, isFalse);
      expect(cand.semanticConfidence, lessThan(0.15));
    });

    // 12. Address above person name
    test('12. Address above person name: Address line is NOT name', () {
      final isAddr = FieldSemanticEvaluator.isLocationOrAddressLine('12/4, Gandhi Road, Adyar');
      expect(isAddr, isTrue);
    });

    // 13. Initial-based name
    test('13. Initial-based name: "A. K. Raman" recognized accurately', () {
      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'A. K. Raman',
        sourceEngine: 'Google ML Kit',
      );
      expect(cand.isTrustworthy, isTrue);
      expect(cand.positiveEvidence.any((e) => e.contains('initial')), isTrue);
    });

    // 14. Credential suffix
    test('14. Credential suffix: "Robert C. Martin, Retd." preserves name and credential', () {
      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'Robert C. Martin, Retd.',
        sourceEngine: 'Google ML Kit',
      );
      expect(cand.isTrustworthy, isTrue);
    });

    // 15. ALL CAPS name
    test('15. ALL CAPS name: "RAJESH KHANNA" recognized accurately', () {
      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'RAJESH KHANNA',
        sourceEngine: 'Google ML Kit',
      );
      expect(cand.isTrustworthy, isTrue);
      expect(cand.positiveEvidence.any((e) => e.contains('ALL CAPS')), isTrue);
    });

    // 16. Stylized/corrupted ML Kit name
    test('16. Stylized/corrupted ML Kit name: Corruption detected and penalized', () {
      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'Sntony Doto ConsulfGpain',
        sourceEngine: 'Google ML Kit',
      );
      expect(cand.rejectionReasons.any((r) => r.contains('corrupted')), isTrue);
    });

    // 17. Paddle corrects difficult name
    test('17. Paddle corrects difficult name: Field resolver selects Paddle candidate', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: ['Sntony Doto', '+1-800-555-0199'],
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 60.0,
        secondaryLines: ['Antony Lobo', 'Managing Director', '+1-800-555-0199'],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 80.0,
      );
      expect(res.name?.value, 'Antony Lobo');
      expect(res.name?.sourceEngine, 'PaddleOCR');
    });

    // 18. ML Kit and Paddle disagree
    test('18. ML Kit and Paddle disagree: Stronger semantic candidate wins', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: ['Vikram Seth', 'Novels & Literature'],
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 70.0,
        secondaryLines: ['New Delhi - 110001', 'Novels & Literature'],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 90.0,
      );
      expect(res.name?.value, 'Vikram Seth');
    });

    // 19. No person name
    test('19. No person name: Clean null output', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: ['Metro Cash & Carry Ltd', '+91 44 1234 5678'],
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 70.0,
        secondaryLines: ['Metro Cash & Carry Ltd', '+91 44 1234 5678'],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 75.0,
      );
      expect(res.name, isNull);
    });

    // 20. Company-only card
    test('20. Company-only card: Company resolved, name empty', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: ['Apex Logistics Inc', 'Worldwide Shipping', '+1-800-555-0199'],
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 80.0,
        secondaryLines: ['Apex Logistics Inc', 'Worldwide Shipping', '+1-800-555-0199'],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 85.0,
      );
      expect(res.name, isNull);
      expect(res.company?.value, contains('Apex Logistics'));
    });

    // 21. Address-heavy card
    test('21. Address-heavy card: Clustered address lines never become Name', () {
      final isAddr1 = FieldSemanticEvaluator.isLocationOrAddressLine('6, Nimmo Road, Santhome');
      final isAddr2 = FieldSemanticEvaluator.isLocationOrAddressLine('Chennai - 600004, Tamil Nadu');
      expect(isAddr1, isTrue);
      expect(isAddr2, isTrue);
    });

    // 22. Multiple phones
    test('22. Multiple phones: Deduplicated and merged across engines', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: ['+91 98400 11111', '+91 44 2222 3333'],
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 70.0,
        secondaryLines: ['+91 98400 11111', '+91 98400 44444'],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 70.0,
      );
      expect(res.phones.length, 3);
    });

    // 23. Multiple emails
    test('23. Multiple emails: Deduplicated and preserved', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: ['john@company.com', 'sales@company.com'],
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 70.0,
        secondaryLines: ['john@company.com', 'support@company.com'],
        secondaryEngineName: 'PaddleOCR',
        secondaryOcrQualityScore: 70.0,
      );
      expect(res.emails.length, 3);
    });

    // 24. Front/back card
    test('24. Front/back card: Independent side parsing and conservative merge', () {
      const parser = BusinessCardParser();
      final frontData = BusinessCardData(
        fullName: 'Arun Kumar',
        jobTitle: 'Technical Director',
        company: 'Medindia Health Network',
        phoneNumbers: [BusinessCardPhone(number: '+91 98765 43210', normalizedNumber: '+919876543210')],
      );
      final backData = BusinessCardData(
        address: '100 Mount Road, Chennai - 600002',
        phoneNumbers: [
          BusinessCardPhone(number: '+91 44 2855 1234', normalizedNumber: '+914428551234'),
        ],
        emailAddresses: [BusinessCardEmail(email: 'info@medindia.net', normalizedEmail: 'info@medindia.net')],
      );

      final merged = parser.mergeDualSidedData(
        frontData: frontData,
        backData: backData,
        frontRawText: 'Arun Kumar\nTechnical Director\nMedindia Health Network',
        backRawText: '100 Mount Road, Chennai - 600002\nPhone: +91 44 2855 1234\ninfo@medindia.net',
      );
      expect(merged.fullName, 'Arun Kumar');
      expect(merged.company, contains('Medindia'));
      expect(merged.address, contains('Mount Road'));
      expect(merged.phoneNumbers.length, 2);
      expect(merged.emailAddresses.length, 1);
    });

    // 25. Rotated text
    test('25. Rotated text: Handles empty or unusual lines safely', () {
      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: '   ',
        sourceEngine: 'Google ML Kit',
      );
      expect(cand.isTrustworthy, isFalse);
    });

    // 26. Slogan-heavy card
    test('26. Slogan-heavy card: Slogan rejected from being Name', () {
      final isSlog = FieldSemanticEvaluator.isSlogan('We bring performances alive');
      expect(isSlog, isTrue);

      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'We bring performances alive',
        sourceEngine: 'Google ML Kit',
      );
      expect(cand.isTrustworthy, isFalse);
      expect(cand.rejectionReasons.any((r) => r.contains('slogan')), isTrue);
    });

    // 27. Low-contrast text
    test('27. Low-contrast text: Valid candidate scored on semantic evidence', () {
      final cand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'Dev Anand',
        sourceEngine: 'PaddleOCR',
        ocrConfidence: 0.65, // Lower OCR confidence due to contrast
      );
      expect(cand.isTrustworthy, isTrue);
      expect(cand.semanticConfidence, greaterThanOrEqualTo(0.70));
    });
  });
}
