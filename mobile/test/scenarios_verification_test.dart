import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/card_analysis_result.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/card_analysis_decision_service.dart';
import 'package:digital_share/services/ocr/ocr_observation.dart';

void main() {
  const parser = BusinessCardParser();
  const decisionService = CardAnalysisDecisionService();

  group('End-to-End Scenarios Verification', () {
    // -------------------------------------------------------------------------
    // Scenario 1: Clear single-column business card
    // -------------------------------------------------------------------------
    test('Scenario 1: Clear single-column business card', () {
      const rawText = '''
Alexander Wright
Principal Architect
CloudScale Technologies Inc
+1 (555) 742-8910
alex.wright@cloudscale.io
www.cloudscale.io
742 Evergreen Terrace, Springfield, OR 97477
''';

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: rawText,
      );

      final localData = parser.parseDualSided(front: frontOcr);

      // Verify Ground Truth extracted locally
      expect(localData.fullName, equals('Alexander Wright'));
      expect(localData.company, equals('CloudScale Technologies Inc'));
      expect(localData.jobTitle, equals('Principal Architect'));
      expect(localData.phoneNumbers.any((p) => p.number.contains('742')), isTrue);
      expect(localData.emailAddresses.any((e) => e.email == 'alex.wright@cloudscale.io'), isTrue);

      final decision = decisionService.evaluate(cardData: localData, frontOcr: frontOcr);

      // Clean card without ambiguity does NOT require AI (saves cost)
      // Ground truth matches perfectly locally.
      expect(decision.shouldInvokeGemini, isFalse);
    });

    // -------------------------------------------------------------------------
    // Scenario 2: Company name that resembles a person's name
    // -------------------------------------------------------------------------
    test('Scenario 2: Company name resembling a person name ("Marshall & Sterling")', () {
      const rawText = '''
David Miller
Account Executive
Marshall & Sterling
Ph: +1 845 454 0800
dmiller@marshallsterling.com
110 Main Street, Poughkeepsie, NY 12601
''';

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: rawText,
      );

      final localData = parser.parseDualSided(front: frontOcr);
      final decision = decisionService.evaluate(cardData: localData, frontOcr: frontOcr);
      expect(decision, isNotNull);

      // Ground truth: Name: David Miller, Company: Marshall & Sterling
      // If local parser assigns correctly or needs verification:
      expect(localData.fullName, equals('David Miller'));

      // Simulate Gemini assistance when ambiguity is flagged
      const geminiCorrection = CardAnalysisResult(
        clientRequestId: 'scen2',
        analysisCacheKey: 'k2',
        fullName: ExtractedField(value: 'David Miller', confidence: 0.98),
        company: ExtractedField(value: 'Marshall & Sterling', confidence: 0.95),
        jobTitle: ExtractedField(value: 'Account Executive', confidence: 0.95),
        modelId: 'gemini-3.8-flash',
      );

      final merged = geminiCorrection.toBusinessCardData(localData);
      expect(merged.fullName, equals('David Miller'));
      expect(merged.company, equals('Marshall & Sterling'));
      expect(merged.jobTitle, equals('Account Executive'));
    });

    // -------------------------------------------------------------------------
    // Scenario 3: Person name and company name on adjacent lines
    // -------------------------------------------------------------------------
    test('Scenario 3: Person name and company name on adjacent lines', () {
      const rawText = '''
Nexus BioLabs LLC
Dr. Arthur Pendelton
Director of Research
Tel: +1 617 555 0192
arthur.p@nexusbiolabs.com
''';

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: rawText,
      );

      final localData = parser.parseDualSided(front: frontOcr);
      final decision = decisionService.evaluate(cardData: localData, frontOcr: frontOcr);
      expect(decision, isNotNull);

      // If company was on line 1 and name on line 2 with Dr., verify resolution:
      expect(localData.fullName, contains('Arthur Pendelton'));
      expect(localData.company, contains('Nexus BioLabs'));
    });

    // -------------------------------------------------------------------------
    // Scenario 4: Two-column business card
    // -------------------------------------------------------------------------
    test('Scenario 4: Two-column business card layout', () {
      final obs = [
        const OcrObservation(
          id: 'col1_name',
          text: 'Sarah Jenkins',
          boundingBox: Rect.fromLTWH(50, 100, 200, 30),
          normalizedBoundingBox: Rect.fromLTWH(0.05, 0.20, 0.35, 0.10),
          confidence: 0.95,
          engine: 'PaddleOCR',
        ),
        const OcrObservation(
          id: 'col1_title',
          text: 'Managing Director',
          boundingBox: Rect.fromLTWH(50, 140, 200, 30),
          normalizedBoundingBox: Rect.fromLTWH(0.05, 0.32, 0.35, 0.10),
          confidence: 0.95,
          engine: 'PaddleOCR',
        ),
        const OcrObservation(
          id: 'col2_phone',
          text: '+44 20 7946 0912',
          boundingBox: Rect.fromLTWH(550, 100, 200, 30),
          normalizedBoundingBox: Rect.fromLTWH(0.55, 0.20, 0.40, 0.10),
          confidence: 0.95,
          engine: 'PaddleOCR',
        ),
        const OcrObservation(
          id: 'col2_email',
          text: 's.jenkins@vanguard.co.uk',
          boundingBox: Rect.fromLTWH(550, 140, 200, 30),
          normalizedBoundingBox: Rect.fromLTWH(0.55, 0.32, 0.40, 0.10),
          confidence: 0.95,
          engine: 'PaddleOCR',
        ),
      ];

      final frontOcr = OcrSideResult(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Sarah Jenkins\nManaging Director\n+44 20 7946 0912\ns.jenkins@vanguard.co.uk',
        metadata: {'observations': obs},
      );

      final localData = parser.parseDualSided(front: frontOcr);
      final decision = decisionService.evaluate(cardData: localData, frontOcr: frontOcr);

      // Decision engine detects multi-column layout (T6)
      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules.any((r) => r.startsWith('T6')), isTrue);
    });

    // -------------------------------------------------------------------------
    // Scenario 5: Address mixed with designation and company information
    // -------------------------------------------------------------------------
    test('Scenario 5: Address mixed with company information (T2)', () {
      final cardData = BusinessCardData(
        fullName: 'Rajesh Sharma',
        company: 'Vardhaman & Co',
        jobTitle: 'Partner',
        address: 'Vardhaman & Co, 3rd Floor, Express Towers, Nariman Point, Mumbai 400021',
        fieldConfidenceStates: const {'address': 'uncertain'},
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Rajesh Sharma\nPartner\nVardhaman & Co\nVardhaman & Co, 3rd Floor, Express Towers, Nariman Point, Mumbai 400021',
      );

      final decision = decisionService.evaluate(cardData: cardData, frontOcr: frontOcr);

      // Trigger 2 fires because address contains company name
      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules.any((r) => r.startsWith('T2')), isTrue);

      // AI disentangles company from address cleanly
      const aiResponse = CardAnalysisResult(
        clientRequestId: 'scen5',
        analysisCacheKey: 'k5',
        company: ExtractedField(value: 'Vardhaman & Co', confidence: 0.98),
        address: ExtractedAddress(
          fullAddress: '3rd Floor, Express Towers, Nariman Point, Mumbai 400021',
          city: 'Mumbai',
          postalCode: '400021',
          confidence: 0.94,
        ),
      );

      final merged = aiResponse.toBusinessCardData(cardData);
      expect(merged.address, equals('3rd Floor, Express Towers, Nariman Point, Mumbai 400021'));
      expect(merged.company, equals('Vardhaman & Co'));
    });

    // -------------------------------------------------------------------------
    // Scenario 6: Multiple phone numbers and email addresses
    // -------------------------------------------------------------------------
    test('Scenario 6: Multiple phone numbers and email addresses', () {
      const rawText = '''
Elena Rostova
Head of Operations
Volga Logistics
Mobile: +7 916 123 4567
Office: +7 495 987 6543
Direct: +7 495 987 6544
elena@volga-logistics.ru
operations@volga-logistics.ru
www.volga-logistics.ru
''';

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: rawText,
      );

      final localData = parser.parseDualSided(front: frontOcr);

      expect(localData.phoneNumbers.length, greaterThanOrEqualTo(2));
      expect(localData.emailAddresses.length, equals(2));
      expect(localData.emailAddresses.any((e) => e.email.contains('elena@')), isTrue);
      expect(localData.emailAddresses.any((e) => e.email.contains('operations@')), isTrue);
    });

    // -------------------------------------------------------------------------
    // Scenario 7: Card with OCR spelling errors
    // -------------------------------------------------------------------------
    test('Scenario 7: Card with OCR spelling errors (Trigger 8 & AI recovery)', () {
      final cardData = BusinessCardData(
        fullName: 'J0hn Sm1th',
        company: 'Gl0bal Tech S0luti0ns',
        unclassifiedLines: const ['~|~ err_line_1', '^_{} err_line_2', '??? err_line_3'],
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'J0hn Sm1th\nGl0bal Tech S0luti0ns\n~|~ err_line_1\n^_{} err_line_2\n??? err_line_3',
      );

      final decision = decisionService.evaluate(cardData: cardData, frontOcr: frontOcr);

      // Triggers T8 for high unclassified line count and OCR noise
      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules.any((r) => r.startsWith('T8')), isTrue);

      // AI corrects OCR character confusions (0 -> o, 1 -> i)
      const aiResponse = CardAnalysisResult(
        clientRequestId: 'scen7',
        analysisCacheKey: 'k7',
        fullName: ExtractedField(value: 'John Smith', confidence: 0.95, wasCorrected: true),
        company: ExtractedField(value: 'Global Tech Solutions', confidence: 0.96, wasCorrected: true),
      );

      final merged = aiResponse.toBusinessCardData(cardData);
      expect(merged.fullName, equals('John Smith'));
      expect(merged.company, equals('Global Tech Solutions'));
    });

    // -------------------------------------------------------------------------
    // Scenario 8: Card with missing or unreadable fields
    // -------------------------------------------------------------------------
    test('Scenario 8: Card with missing core identity fields (Trigger 3)', () {
      final cardData = BusinessCardData(
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 456 7890')],
        emailAddresses: const [BusinessCardEmail(email: 'info@sample.org')],
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: '+1 555 456 7890\ninfo@sample.org',
      );

      final decision = decisionService.evaluate(cardData: cardData, frontOcr: frontOcr);

      // Missing core identity triggers T3
      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules.any((r) => r.startsWith('T3')), isTrue);

      // If Gemini cannot find a name either, it safely preserves existing fields without crashing
      const aiResponse = CardAnalysisResult(
        clientRequestId: 'scen8',
        analysisCacheKey: 'k8',
        requiresManualReview: true,
        reviewWarnings: ['Could not reliably detect person name from card text.'],
      );

      final merged = aiResponse.toBusinessCardData(cardData);
      expect(merged.phoneNumbers, isNotEmpty);
      expect(merged.emailAddresses, isNotEmpty);
      expect(merged.parsingNotes.any((n) => n.contains('Could not reliably detect person name')), isTrue);
    });
  });
}
