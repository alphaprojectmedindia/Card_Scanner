import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/card_analysis_decision_service.dart';
import 'package:digital_share/services/ocr/ocr_observation.dart';

void main() {
  group('CardAnalysisDecisionService Tests', () {
    const decisionService = CardAnalysisDecisionService();

    test('Clean valid business card does not invoke Gemini (zero API cost)', () {
      final cardData = BusinessCardData(
        fullName: 'Jane Doe',
        company: 'Acme Global Technologies',
        jobTitle: 'Chief Technology Officer',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 123 4567')],
        emailAddresses: const [BusinessCardEmail(email: 'jane@acme.com')],
        website: 'www.acme.com',
        address: '123 Market St, San Francisco, CA 94105',
        fieldConfidenceStates: const {
          'fullName': 'highConfidence',
          'company': 'highConfidence',
          'jobTitle': 'highConfidence',
          'address': 'highConfidence',
        },
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Jane Doe\nChief Technology Officer\nAcme Global Technologies\n+1 555 123 4567\njane@acme.com\nwww.acme.com\n123 Market St, San Francisco, CA 94105',
      );

      final decision = decisionService.evaluate(
        cardData: cardData,
        frontOcr: frontOcr,
      );

      expect(decision.shouldInvokeGemini, isFalse);
      expect(decision.mode, equals(AnalysisMode.none));
    });

    test('Trigger 1: Inverted name containing corporate entity keyword invokes Gemini', () {
      final cardData = BusinessCardData(
        fullName: 'Apex Solutions Pvt Ltd',
        company: 'John Miller',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 987 6543')],
        emailAddresses: const [BusinessCardEmail(email: 'john@apex.com')],
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Apex Solutions Pvt Ltd\nJohn Miller',
      );

      final decision = decisionService.evaluate(
        cardData: cardData,
        frontOcr: frontOcr,
      );

      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.mode, equals(AnalysisMode.textOnly));
      expect(decision.triggeredRules.any((r) => r.startsWith('T1')), isTrue);
    });

    test('Trigger 1: Company beginning with honorific title invokes Gemini', () {
      final cardData = BusinessCardData(
        fullName: 'Clinic Staff',
        company: 'Dr. Gregory House',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 222 3333')],
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Clinic Staff\nDr. Gregory House',
      );

      final decision = decisionService.evaluate(
        cardData: cardData,
        frontOcr: frontOcr,
      );

      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules.any((r) => r.startsWith('T1')), isTrue);
    });

    test('Trigger 2: Address contaminated with corporate entity invokes Gemini', () {
      final cardData = BusinessCardData(
        fullName: 'Alice Walker',
        company: 'Tech Corp',
        address: 'Suite 400, Global Logistics Technologies Ltd, Tech Park, Austin TX',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 333 4444')],
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Alice Walker\nSuite 400, Global Logistics Technologies Ltd, Tech Park, Austin TX',
      );

      final decision = decisionService.evaluate(
        cardData: cardData,
        frontOcr: frontOcr,
      );

      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules.any((r) => r.startsWith('T2')), isTrue);
    });

    test('Trigger 3: Missing core identity invokes Gemini', () {
      final cardData = BusinessCardData(
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 999 8888')],
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Some unclassified text\n+1 555 999 8888',
      );

      final decision = decisionService.evaluate(
        cardData: cardData,
        frontOcr: frontOcr,
      );

      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules.any((r) => r.startsWith('T3')), isTrue);
    });

    test('Trigger 4: Hybrid OCR fallbackInvoked invokes Gemini', () {
      final cardData = BusinessCardData(
        fullName: 'Bob Vance',
        company: 'Vance Refrigeration',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 777 6666')],
      );

      final frontOcr = OcrSideResult(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Bob Vance\nVance Refrigeration',
        metadata: const {'fallbackInvoked': true},
      );

      final decision = decisionService.evaluate(
        cardData: cardData,
        frontOcr: frontOcr,
      );

      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules.any((r) => r.startsWith('T4')), isTrue);
    });

    test('Trigger 4: Low average observation confidence invokes Gemini', () {
      final obs = [
        const OcrObservation(
          id: 'test_1',
          text: 'Messy Line 1',
          boundingBox: Rect.fromLTWH(10, 10, 100, 20),
          normalizedBoundingBox: Rect.fromLTWH(0.1, 0.1, 0.5, 0.1),
          confidence: 0.55,
          engine: 'PaddleOCR',
        ),
        const OcrObservation(
          id: 'test_2',
          text: 'Messy Line 2',
          boundingBox: Rect.fromLTWH(10, 40, 100, 20),
          normalizedBoundingBox: Rect.fromLTWH(0.1, 0.2, 0.5, 0.1),
          confidence: 0.60,
          engine: 'PaddleOCR',
        ),
      ];

      final cardData = BusinessCardData(
        fullName: 'Messy Name',
        company: 'Messy Corp',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 111 2222')],
      );

      final frontOcr = OcrSideResult(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Messy Line 1\nMessy Line 2',
        metadata: {'observations': obs},
      );

      final decision = decisionService.evaluate(
        cardData: cardData,
        frontOcr: frontOcr,
      );

      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules.any((r) => r.startsWith('T4')), isTrue);
    });

    test('Trigger 5: Date range collision in parsing notes invokes Gemini', () {
      final cardData = BusinessCardData(
        fullName: 'Carlos Santana',
        company: 'Music Ltd',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 000 1111')],
        parsingNotes: const ['Detected possible date range tenure collision: 2025-2027'],
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Carlos Santana\n2025-2027\n+1 555 000 1111',
      );

      final decision = decisionService.evaluate(
        cardData: cardData,
        frontOcr: frontOcr,
      );

      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules.any((r) => r.startsWith('T5')), isTrue);
    });

    test('Trigger 6: Multi-column spatial layout detection invokes Gemini', () {
      final obs = [
        const OcrObservation(
          id: 'col1_line1',
          text: 'Dr. John Smith',
          boundingBox: Rect.fromLTWH(10, 100, 100, 30),
          normalizedBoundingBox: Rect.fromLTWH(0.05, 0.30, 0.35, 0.10),
          confidence: 0.95,
          engine: 'PaddleOCR',
        ),
        const OcrObservation(
          id: 'col1_line2',
          text: 'Senior Partner',
          boundingBox: Rect.fromLTWH(10, 140, 100, 30),
          normalizedBoundingBox: Rect.fromLTWH(0.05, 0.42, 0.35, 0.10),
          confidence: 0.95,
          engine: 'PaddleOCR',
        ),
        const OcrObservation(
          id: 'col2_line1',
          text: 'Ph: +1 555 444 3333',
          boundingBox: Rect.fromLTWH(600, 100, 100, 30),
          normalizedBoundingBox: Rect.fromLTWH(0.60, 0.30, 0.35, 0.10),
          confidence: 0.95,
          engine: 'PaddleOCR',
        ),
        const OcrObservation(
          id: 'col2_line2',
          text: 'john@partnerfirm.com',
          boundingBox: Rect.fromLTWH(600, 140, 100, 30),
          normalizedBoundingBox: Rect.fromLTWH(0.60, 0.42, 0.35, 0.10),
          confidence: 0.95,
          engine: 'PaddleOCR',
        ),
      ];

      final cardData = BusinessCardData(
        fullName: 'Dr. John Smith',
        company: 'Partner Firm',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 444 3333')],
        emailAddresses: const [BusinessCardEmail(email: 'john@partnerfirm.com')],
      );

      final frontOcr = OcrSideResult(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Dr. John Smith\nSenior Partner\nPh: +1 555 444 3333\njohn@partnerfirm.com',
        metadata: {'observations': obs},
      );

      final decision = decisionService.evaluate(
        cardData: cardData,
        frontOcr: frontOcr,
      );

      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules.any((r) => r.startsWith('T6')), isTrue);
    });

    test('Trigger 7: Email indicator in text but missing parsed email invokes Gemini', () {
      final cardData = BusinessCardData(
        fullName: 'David Lee',
        company: 'Innovate LLC',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 888 7777')],
        emailAddresses: const [], // missing
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'David Lee\nInnovate LLC\nContact: dlee [at] innovate.com',
      );

      final decision = decisionService.evaluate(
        cardData: cardData,
        frontOcr: frontOcr,
      );

      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules.any((r) => r.startsWith('T7')), isTrue);
    });

    test('Trigger 8: High unclassified line count invokes Gemini', () {
      final cardData = BusinessCardData(
        fullName: 'Elena Rostova',
        company: 'Global Export',
        unclassifiedLines: const [
          'Random Line Alpha',
          'Random Line Beta',
          'Random Line Gamma',
        ],
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Elena Rostova\nGlobal Export\nRandom Line Alpha\nRandom Line Beta\nRandom Line Gamma',
      );

      final decision = decisionService.evaluate(
        cardData: cardData,
        frontOcr: frontOcr,
      );

      expect(decision.shouldInvokeGemini, isTrue);
      expect(decision.triggeredRules.any((r) => r.startsWith('T8')), isTrue);
    });
  });
}

