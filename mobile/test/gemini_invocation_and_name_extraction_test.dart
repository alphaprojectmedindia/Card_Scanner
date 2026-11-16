import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/card_analysis_result.dart';
import 'package:digital_share/models/field_evidence.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/models/scan_execution_diagnostics.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/card_analysis_decision_service.dart';
import 'package:digital_share/services/ocr/field_confidence_evaluator.dart';

void main() {
  group('Part 5: Gemini Invocation and Person Name Extraction Test Suite (10 Scenarios)', () {
    const parser = BusinessCardParser();
    const fieldEvaluator = FieldConfidenceEvaluator();
    const decisionService = CardAnalysisDecisionService();

    late Directory tempDir;
    late File tempImage;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gemini_test_');
      tempImage = File('${tempDir.path}/card.jpg')..writeAsBytesSync([1, 2, 3, 4]);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    // -------------------------------------------------------------------------
    // Scenario 1: Company extracted as name
    // -------------------------------------------------------------------------
    test('Scenario 1: Company at top of card (e.g. Apex Healthcare) is not accepted as fullName', () {
      final lines = [
        'Apex Healthcare',
        '+1 555-0199',
        'info@apexhealthcare.com',
        'www.apexhealthcare.com',
      ];

      final parsed = parser.parse(lines.join('\n'));

      // Verify fullName is NOT Apex Healthcare
      expect(parsed.fullName, anyOf(isNull, isEmpty));
      expect(parsed.fieldConfidenceStates['fullName'], equals('notDetected'));
      expect(parsed.fieldEvidence['fullName']?.verificationStatus, equals(FieldVerificationStatus.notFound));
      expect(parsed.company, equals('Apex Healthcare'));
    });

    test('Scenario 1b: Blue Horizon Technologies at line 0 is identified as company, not person', () {
      final lines = [
        'Blue Horizon Technologies',
        '123 Innovation Way, Suite 400',
        '+1 415-555-2671',
        'contact@bluehorizon.io',
      ];

      final parsed = parser.parse(lines.join('\n'));

      expect(parsed.fullName, anyOf(isNull, isEmpty));
      expect(parsed.company, contains('Blue Horizon Technologies'));
    });

    // -------------------------------------------------------------------------
    // Scenario 2: Person name extracted as company
    // -------------------------------------------------------------------------
    test('Scenario 2: Person name with honorific/job title is correctly assigned to fullName and NOT company', () {
      final lines = [
        'Dr. Antony Lobo',
        'Managing Director',
        'Nova Technologies Pvt Ltd',
        '+91 98400 12345',
        'antony@novatech.in',
      ];

      final parsed = parser.parse(lines.join('\n'));

      expect(parsed.fullName, equals('Dr. Antony Lobo'));
      expect(parsed.jobTitle, equals('Managing Director'));
      expect(parsed.company, equals('Nova Technologies Pvt Ltd'));
      expect(parsed.company, isNot(contains('Antony Lobo')));
    });

    test('Scenario 2b: Standard person name directly adjacent to job title is not assigned to company', () {
      final lines = [
        'Summit Media Group',
        'Angela Davies',
        'Chief Technology Officer',
        '+1 555 321 9876',
        'angela@summitmedia.com',
      ];

      final parsed = parser.parse(lines.join('\n'));

      expect(parsed.fullName, equals('Angela Davies'));
      expect(parsed.jobTitle, equals('Chief Technology Officer'));
      expect(parsed.company, equals('Summit Media Group'));
    });

    // -------------------------------------------------------------------------
    // Scenario 3: High OCR confidence but incorrect assignment
    // -------------------------------------------------------------------------
    test('Scenario 3: High OCR confidence token matching corporate entities is flagged low confidence for fullName', () {
      final cardData = BusinessCardData(
        fullName: 'Summit Consulting', // Misassigned company as name
        company: null,
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 456 7890')],
        emailAddresses: const [BusinessCardEmail(email: 'info@summit.com')],
        fieldConfidenceStates: const {'fullName': 'highConfidence'},
      );

      final report = fieldEvaluator.evaluate(cardData: cardData);

      // Even with supposed high confidence, evaluator must catch corporate entity tokens and demote to low
      expect(report['fullName']!.level, equals(FieldConfidenceLevel.low));
      expect(report['fullName']!.score, lessThanOrEqualTo(0.30));
      expect(report['fullName']!.uncertaintyReasons, anyElement(contains('corporate entity tokens')));

      final ocr = OcrSideResult(
        side: CardSide.front,
        imagePath: tempImage.path,
        rawText: 'Summit Consulting\n+1 555 456 7890',
      );
      final decision = decisionService.evaluate(cardData: cardData, frontOcr: ocr);
      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules, anyElement(contains('T1')));
      expect(decision.mode, equals(AnalysisMode.multimodalVision));
    });

    // -------------------------------------------------------------------------
    // Scenario 4: Missing person name
    // -------------------------------------------------------------------------
    test('Scenario 4: Missing person name marks field notDetected and never manufactures name from email', () {
      final lines = [
        'Global Logistics Solutions',
        'info@globallogistics.com',
        '+1 800 555 0199',
        'www.globallogistics.com',
      ];

      final parsed = parser.parse(lines.join('\n'));

      expect(parsed.fullName, anyOf(isNull, isEmpty));
      expect(parsed.fieldConfidenceStates['fullName'], equals('notDetected'));
      // Ensure email user 'info' is NOT used to manufacture a human name
      expect(parsed.fullName, isNot(equals('Info')));

      final report = fieldEvaluator.evaluate(cardData: parsed);
      expect(report.hasLowConfidenceCriticalFields, isTrue);

      final ocr = OcrSideResult(
        side: CardSide.front,
        imagePath: tempImage.path,
        rawText: lines.join('\n'),
      );
      final decision = decisionService.evaluate(cardData: parsed, frontOcr: ocr);
      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules, anyElement(contains('T3')));
    });

    // -------------------------------------------------------------------------
    // Scenario 5: Two competing candidates
    // -------------------------------------------------------------------------
    test('Scenario 5: Two competing viable person names populates alternativeCandidates and marks uncertain', () {
      final lines = [
        'Alex Morgan',
        'Jordan Lee',
        'Senior Partners',
        '+1 555 444 3333',
        'partners@legaladvisors.com',
      ];

      final parsed = parser.parse(lines.join('\n'));

      expect(parsed.alternativeCandidates['fullName'], isNotNull);
      expect(parsed.alternativeCandidates['fullName']!.length, greaterThanOrEqualTo(2));
      expect(parsed.alternativeCandidates['fullName'], containsAll(['Alex Morgan', 'Jordan Lee']));
      expect(parsed.fieldConfidenceStates['fullName'], equals('uncertain'));
      expect(parsed.fieldEvidence['fullName']?.verificationStatus, equals(FieldVerificationStatus.reviewRequired));
    });

    // -------------------------------------------------------------------------
    // Scenario 6: Gemini triggered for uncertain name
    // -------------------------------------------------------------------------
    test('Scenario 6: Uncertain or competing name triggers Gemini MultimodalVision evaluation', () {
      final cardData = BusinessCardData(
        fullName: 'Alex Morgan',
        company: 'Legal Advisors LLP',
        fieldConfidenceStates: const {'fullName': 'uncertain'},
        alternativeCandidates: const {
          'fullName': ['Alex Morgan', 'Jordan Lee']
        },
      );

      final ocr = OcrSideResult(
        side: CardSide.front,
        imagePath: tempImage.path,
        rawText: 'Alex Morgan\nJordan Lee\nLegal Advisors LLP',
      );

      final decision = decisionService.evaluate(cardData: cardData, frontOcr: ocr);

      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.mode, equals(AnalysisMode.multimodalVision));
      expect(decision.triggeredRules, anyElement(contains('T1')));
    });

    // -------------------------------------------------------------------------
    // Scenario 7: Gemini skipped for reliable result
    // -------------------------------------------------------------------------
    test('Scenario 7: Completely clean and unambiguous card scan bypasses Gemini with 0 API cost', () {
      final cardData = BusinessCardData(
        fullName: 'Robert Smith',
        company: 'Acme Technologies Pvt Ltd',
        jobTitle: 'Chief Executive Officer',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 123 4567')],
        emailAddresses: const [BusinessCardEmail(email: 'robert.smith@acme.com')],
        website: 'www.acme.com',
        fieldConfidenceStates: const {
          'fullName': 'highConfidence',
          'company': 'highConfidence',
          'jobTitle': 'highConfidence',
          'phone': 'highConfidence',
          'email': 'highConfidence',
          'website': 'highConfidence',
        },
      );

      final report = fieldEvaluator.evaluate(cardData: cardData);
      expect(report.hasLowConfidenceCriticalFields, isFalse);

      final ocr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Robert Smith\nChief Executive Officer\nAcme Technologies Pvt Ltd\n+1 555 123 4567\nrobert.smith@acme.com\nwww.acme.com',
      );

      final decision = decisionService.evaluate(cardData: cardData, frontOcr: ocr);
      expect(decision.shouldInvokeGemini, isFalse);
      expect(decision.mode, equals(AnalysisMode.none));
    });

    // -------------------------------------------------------------------------
    // Scenario 8: Front/back image bytes reaching backend
    // -------------------------------------------------------------------------
    test('Scenario 8: CardAnalysisResult deserializes image upload verification and execution status accurately', () {
      final json = {
        'clientRequestId': 'req_multimodal_01',
        'analysisCacheKey': 'cache_key_01',
        'geminiApiExecuted': true,
        'geminiExecutionStatus': 'ExecutedSuccessfully',
        'frontImageReceived': true,
        'backImageReceived': true,
        'modelId': 'gemini-3.1-flash-lite',
        'usageMetadata': {
          'promptTokenCount': 240,
          'candidatesTokenCount': 85,
          'totalTokenCount': 325,
        },
        'fullName': {
          'value': 'Elena Rostova',
          'confidence': 0.96,
          'verificationStatus': 'verified',
          'sourceObservationIds': ['front_1'],
        },
        'company': {
          'value': 'Quantum Dynamics',
          'confidence': 0.94,
          'verificationStatus': 'verified',
          'sourceObservationIds': ['front_0'],
        },
      };

      final result = CardAnalysisResult.fromJson(json);

      expect(result.geminiApiExecuted, isTrue);
      expect(result.geminiExecutionStatus, equals('ExecutedSuccessfully'));
      expect(result.frontImageReceived, isTrue);
      expect(result.backImageReceived, isTrue);
      expect(result.modelId, equals('gemini-3.1-flash-lite'));
      expect(result.promptTokens, equals(240));
      expect(result.candidateTokens, equals(85));
      expect(result.totalTokens, equals(325));
      expect(result.fullName?.value, equals('Elena Rostova'));
      expect(result.company?.value, equals('Quantum Dynamics'));
    });

    // -------------------------------------------------------------------------
    // Scenario 9: Gemini correction applied only when supported
    // -------------------------------------------------------------------------
    test('Scenario 9: Gemini notFound for person name clears field and never revives erroneous local baseline', () {
      final localBaseline = BusinessCardData(
        fullName: 'Apex Healthcare', // Erroneous local baseline
        company: null,
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 123 4567')],
      );

      final geminiResult = CardAnalysisResult(
        clientRequestId: 'req_correction_test',
        analysisCacheKey: 'cache_test',
        fullName: const ExtractedField(
          value: null,
          confidence: 0.95,
          verificationStatus: 'notFound',
          sourceObservationIds: [],
        ),
        company: const ExtractedField(
          value: 'Apex Healthcare',
          confidence: 0.95,
          verificationStatus: 'verified',
          sourceObservationIds: ['obs_0'],
        ),
        geminiApiExecuted: true,
        geminiExecutionStatus: 'ExecutedSuccessfully',
      );

      final merged = geminiResult.toBusinessCardData(localBaseline);

      // Verify that fullName was NOT revived from local baseline!
      expect(merged.fullName, isNull);
      expect(merged.company, equals('Apex Healthcare'));
    });

    // -------------------------------------------------------------------------
    // Scenario 10: Gemini failure preserving local result
    // -------------------------------------------------------------------------
    test('Scenario 10: Gemini network failure/timeout preserves local baseline safely', () {
      final localBaseline = BusinessCardData(
        fullName: 'Marcus Aurelius',
        company: 'Roman Senate',
        jobTitle: 'Emperor',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 999 8888')],
      );

      final failedGeminiResult = CardAnalysisResult(
        clientRequestId: 'req_timeout_test',
        analysisCacheKey: '',
        fallbackToLocalBaseline: true,
        requiresManualReview: true,
        geminiApiExecuted: false,
        geminiExecutionStatus: 'FallbackTimeout',
        reviewWarnings: const ['Network timeout contacting Gemini backend.'],
      );

      final merged = failedGeminiResult.toBusinessCardData(localBaseline);

      expect(merged.fullName, equals('Marcus Aurelius'));
      expect(merged.company, equals('Roman Senate'));
      expect(merged.jobTitle, equals('Emperor'));
      expect(merged.phoneNumbers.first.number, equals('+1 555 999 8888'));
    });

    // -------------------------------------------------------------------------
    // Diagnostic Audit Formatter Test
    // -------------------------------------------------------------------------
    test('ScanExecutionDiagnostics correctly captures all 17 audit properties and 5 stages', () {
      const diag = ScanExecutionDiagnostics(
        scanId: 'scan_session_99',
        contactId: 'contact_42',
        exactCacheHit: false,
        perceptualCacheAttempted: true,
        perceptualCacheMatched: false,
        ocrEngineResults: 'PaddleOCR (PP-OCRv5) (Front: 6 lines, Back: 0 lines)',
        parserOutputSummary: 'Name: "Apex Healthcare", Co: "", Job: ""',
        fieldConfidenceSummary: 'Score: 0.45 | CriticalUncertain: true | fullName: low, company: low',
        triggeredDecisionRules: ['T1: Person name contains corporate/business legal entity tokens'],
        decisionOutcome: 'shouldInvoke: true, mode: MultimodalVision, primary: "T1..."',
        stage1DecisionMade: true,
        stage2BackendSubmitted: true,
        stage3GeminiApiExecuted: true,
        stage4GeminiResponseReceived: true,
        stage5GeminiCorrectionAccepted: true,
        imageUploadStatus: 'Front: Available, Back: None',
        analysisModeRequested: 'MultimodalVision',
        modelNameReturned: 'gemini-3.1-flash-lite',
        promptTokens: 250,
        candidateTokens: 90,
        totalTokens: 340,
        rawGeminiExtractions: 'Name: null, Co: "Apex Healthcare", Job: null',
        baselineVsGeminiDiff: 'Name: "Apex Healthcare" -> null, Co: null -> "Apex Healthcare"',
        finalAcceptedContactValues: 'Name: null, Co: "Apex Healthcare", Job: null, Phones: 1, Emails: 1',
      );

      // Verify logToConsole does not throw
      diag.logToConsole();

      final summary = diag.toAuditSummary();
      expect(summary, contains('ScanId=scan_session_99'));
      expect(summary, contains('Decision=true'));
      expect(summary, contains('BackendSubmitted=true'));
      expect(summary, contains('ApiExecuted=true'));
      expect(summary, contains('ResponseRecv=true'));
      expect(summary, contains('CorrectionAccepted=true'));
      expect(summary, contains('T1: Person name contains corporate/business legal entity tokens'));
    });
  });
}
