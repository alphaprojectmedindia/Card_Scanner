import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/ocr/ocr_engine.dart';
import 'package:digital_share/services/ocr/phone_ocr_recovery.dart';
import 'package:digital_share/services/ocr/hybrid_ocr_pipeline.dart';
import 'package:digital_share/services/ocr/field_semantic_evaluator.dart';
import 'package:digital_share/services/business_card_parser.dart';

class MockTestEngine implements OcrEngine {
  @override
  final String name;
  final OcrEngineResult resultToReturn;
  int callCount = 0;

  MockTestEngine({required this.name, required this.resultToReturn});

  @override
  Future<OcrEngineResult> recognize(String imagePath) async {
    callCount++;
    return resultToReturn;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('Section L: Phone OCR Recovery Comprehensive Test Suite (20 Scenarios)', () {
    // -------------------------------------------------------------------------
    // Scenario 1: +91 98765 43210
    // -------------------------------------------------------------------------
    test('1. +91 98765 43210 (International + with spaces)', () {
      final candidates = PhoneOcrRecovery.extractPhoneCandidates(['+91 98765 43210']);
      expect(candidates, isNotEmpty);
      expect(candidates.first.formatted, '+91 98765 43210');
      expect(candidates.first.normalized, '+919876543210');
      expect(candidates.first.confidence, greaterThanOrEqualTo(0.90));
    });

    // -------------------------------------------------------------------------
    // Scenario 2: 98765 43210
    // -------------------------------------------------------------------------
    test('2. 98765 43210 (Standard 10-digit mobile with space)', () {
      final candidates = PhoneOcrRecovery.extractPhoneCandidates(['98765 43210']);
      expect(candidates, isNotEmpty);
      expect(candidates.first.formatted, '98765 43210');
      expect(candidates.first.normalized, '9876543210');
      expect(candidates.first.label, 'Mobile');
    });

    // -------------------------------------------------------------------------
    // Scenario 3: 98765-43210
    // -------------------------------------------------------------------------
    test('3. 98765-43210 (Hyphenated 10-digit mobile)', () {
      final candidates = PhoneOcrRecovery.extractPhoneCandidates(['98765-43210']);
      expect(candidates, isNotEmpty);
      expect(candidates.first.formatted, '98765-43210');
      expect(candidates.first.normalized, '9876543210');
    });

    // -------------------------------------------------------------------------
    // Scenario 4: M: 9876543210
    // -------------------------------------------------------------------------
    test('4. M: 9876543210 (Abbreviated label M:)', () {
      final candidates = PhoneOcrRecovery.extractPhoneCandidates(['M: 9876543210']);
      expect(candidates, isNotEmpty);
      expect(candidates.first.formatted, contains('9876543210'));
      expect(candidates.first.label, 'Mobile');
    });

    // -------------------------------------------------------------------------
    // Scenario 5: Mobile: +91-98765-43210
    // -------------------------------------------------------------------------
    test('5. Mobile: +91-98765-43210 (Full label Mobile: with international format)', () {
      final candidates = PhoneOcrRecovery.extractPhoneCandidates(['Mobile: +91-98765-43210']);
      expect(candidates, isNotEmpty);
      expect(candidates.first.formatted, contains('+91-98765-43210'));
      expect(candidates.first.label, 'Mobile');
      expect(candidates.first.normalized, '+919876543210');
    });

    // -------------------------------------------------------------------------
    // Scenario 6: Tel: +44 20 7946 0958
    // -------------------------------------------------------------------------
    test('6. Tel: +44 20 7946 0958 (UK London telephone format)', () {
      final candidates = PhoneOcrRecovery.extractPhoneCandidates(['Tel: +44 20 7946 0958']);
      expect(candidates, isNotEmpty);
      expect(candidates.first.formatted, contains('+44 20 7946 0958'));
      expect(candidates.first.label, 'Phone');
      expect(candidates.first.normalized, '+442079460958');
    });

    // -------------------------------------------------------------------------
    // Scenario 7: +1 (415) 555-2671
    // -------------------------------------------------------------------------
    test('7. +1 (415) 555-2671 (US San Francisco format with parentheses)', () {
      final candidates = PhoneOcrRecovery.extractPhoneCandidates(['+1 (415) 555-2671']);
      expect(candidates, isNotEmpty);
      expect(candidates.first.formatted, contains('(415) 555-2671'));
      expect(candidates.first.normalized, '+14155552671');
    });

    // -------------------------------------------------------------------------
    // Scenario 8: OCR: 9876S 432I0 -> safely recover phone candidate
    // -------------------------------------------------------------------------
    test('8. OCR character confusion: 9876S 432I0 -> recovered as 98765 43210', () {
      final candidates = PhoneOcrRecovery.extractPhoneCandidates(['9876S 432I0']);
      expect(candidates, isNotEmpty);
      final phone = candidates.first;
      expect(phone.formatted, '98765 43210');
      expect(phone.normalized, '9876543210');
      expect(phone.hasCharacterCorrection, isTrue);
    });

    // -------------------------------------------------------------------------
    // Scenario 9: OCR: Sonia Mathew -> MUST NOT become 5onia Mathew
    // -------------------------------------------------------------------------
    test('9. Person name safety: "Sonia Mathew" MUST NOT be altered or converted to 5onia Mathew', () {
      // Direct candidate test
      final candidates = PhoneOcrRecovery.extractPhoneCandidates(['Sonia Mathew']);
      expect(candidates, isEmpty, reason: 'A person name must never produce a phone candidate');

      // Evaluator test
      final nameCand = FieldSemanticEvaluator.evaluateNameCandidate(
        rawLine: 'Sonia Mathew',
        sourceEngine: 'Google ML Kit',
      );
      expect(nameCand.value, 'Sonia Mathew');
      expect(nameCand.value.startsWith('5'), isFalse);
      expect(nameCand.isTrustworthy, isTrue);
    });

    // -------------------------------------------------------------------------
    // Scenario 10: Split OCR: +91 98765 \n 43210 -> recover joined candidate
    // -------------------------------------------------------------------------
    test('10. Split lines: "+91 98765" and "43210" joined into single phone', () {
      final lines = ['+91 98765', '43210'];
      final candidates = PhoneOcrRecovery.extractPhoneCandidates(lines);
      expect(candidates, isNotEmpty);
      final joined = candidates.firstWhere((c) => c.wasSplitJoined);
      expect(joined.formatted, contains('+91 98765 43210'));
      expect(joined.normalized, '+919876543210');
    });

    // -------------------------------------------------------------------------
    // Scenario 11: Two different mobile numbers -> both preserved
    // -------------------------------------------------------------------------
    test('11. Two different mobile numbers: both preserved without loss', () {
      final lines = [
        'Mobile: 98765 43210',
        'Office: 98765 43211',
      ];
      final candidates = PhoneOcrRecovery.extractPhoneCandidates(lines);
      expect(candidates.length, 2);
      expect(candidates.map((c) => c.normalized).toSet().length, 2);
      expect(candidates.any((c) => c.normalized == '9876543210'), isTrue);
      expect(candidates.any((c) => c.normalized == '9876543211'), isTrue);
    });

    // -------------------------------------------------------------------------
    // Scenario 12: Same number with different formatting -> deduplicated
    // -------------------------------------------------------------------------
    test('12. Same number with different formatting: correctly deduplicated', () {
      final lines = [
        '+91 98765 43210',
        '98765-43210',
      ];
      final candidates = PhoneOcrRecovery.extractPhoneCandidates(lines);
      // The two representations refer to the exact same 10-digit number and must deduplicate
      expect(candidates.length, 1);
      expect(candidates.first.normalized, contains('9876543210'));
    });

    // -------------------------------------------------------------------------
    // Scenario 13: High overall OCR confidence + phone blank -> fallback activates
    // -------------------------------------------------------------------------
    test('13. High overall OCR confidence (score >= 60) with phone blank -> PaddleOCR fallback activates', () async {
      final mockMlKit = MockTestEngine(
        name: 'Google ML Kit',
        resultToReturn: const OcrEngineResult(
          engineName: 'Google ML Kit',
          rawText: 'Dr. John Doe\nManaging Director\nAcme Health Solutions\njohn.doe@acmehealth.com\nwww.acmehealth.com',
          lineCount: 5,
          characterCount: 95,
          isSuccess: true,
          processingTime: Duration(milliseconds: 310),
          detectedLines: [
            'Dr. John Doe',
            'Managing Director',
            'Acme Health Solutions',
            'john.doe@acmehealth.com',
            'www.acmehealth.com',
          ],
        ),
      );

      final mockPaddle = MockTestEngine(
        name: 'PaddleOCR (PP-OCRv5 Mobile)',
        resultToReturn: const OcrEngineResult(
          engineName: 'PaddleOCR (PP-OCRv5 Mobile)',
          rawText: 'Dr. John Doe\nManaging Director\nAcme Health Solutions\njohn.doe@acmehealth.com\nTel: +91 98765 43210',
          lineCount: 5,
          characterCount: 110,
          isSuccess: true,
          processingTime: Duration(milliseconds: 4100),
          detectedLines: [
            'Dr. John Doe',
            'Managing Director',
            'Acme Health Solutions',
            'john.doe@acmehealth.com',
            'Tel: +91 98765 43210',
          ],
        ),
      );

      final pipeline = HybridOcrPipeline(
        primaryEngine: mockMlKit,
        secondaryEngine: mockPaddle,
      );

      final result = await pipeline.processCardSide(
        imagePath: '/test/card_without_phone_in_mlkit.jpg',
        side: CardSide.front,
      );

      // PaddleOCR MUST be invoked to assist phone recovery despite ML Kit high score!
      expect(mockPaddle.callCount, 1);
      expect(result.metadata['fallbackInvoked'], isTrue);
      expect(result.rawText, contains('98765 43210'));
    });

    // -------------------------------------------------------------------------
    // Scenario 14: ML Kit name + Paddle phone -> field-level hybrid resolution
    // -------------------------------------------------------------------------
    test('14. ML Kit correct name + Paddle correct phone -> field-level hybrid resolution combines both', () {
      final mlKitLines = [
        'Sonia Mathew',
        'Senior Software Architect',
        'Acme Technologies',
        'sonia@acmetech.com',
      ];

      final paddleLines = [
        'Sonia M.',
        'Senior Architect',
        'Acme Tech',
        '+91 98765 43210',
        'sonia@acmetech.com',
      ];

      final resolution = FieldSemanticEvaluator.resolveFields(
        primaryLines: mlKitLines,
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 85.0,
        secondaryLines: paddleLines,
        secondaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        secondaryOcrQualityScore: 82.0,
      );

      // Name should be from ML Kit (complete "Sonia Mathew")
      expect(resolution.name?.value, 'Sonia Mathew');
      expect(resolution.name?.sourceEngine, 'Google ML Kit');

      // Phone should be from PaddleOCR
      expect(resolution.phones, isNotEmpty);
      expect(resolution.phones.first.value, '+91 98765 43210');
      expect(resolution.phones.first.sourceEngine, 'PaddleOCR (PP-OCRv5 Mobile)');

      // Email should be agreed
      expect(resolution.emails.first.value, 'sonia@acmetech.com');
    });

    // -------------------------------------------------------------------------
    // Scenario 15: No trustworthy phone evidence -> remains blank (Zero Hallucination)
    // -------------------------------------------------------------------------
    test('15. Zero Hallucination: No trustworthy phone evidence -> phone numbers list remains empty', () {
      final lines = [
        'Dr. Alice Morgan',
        'Clinical Psychologist',
        'Mind Wellness Clinic',
        'alice@mindwellness.org',
        'www.mindwellness.org',
      ];

      final candidates = PhoneOcrRecovery.extractPhoneCandidates(lines);
      expect(candidates, isEmpty);

      const parser = BusinessCardParser();
      final parsed = parser.parseSide(
        OcrSideResult(
          side: CardSide.front,
          imagePath: '/test/no_phone.jpg',
          rawText: lines.join('\n'),
          processedAt: DateTime.now(),
          lines: [
            for (int i = 0; i < lines.length; i++)
              OcrLineMetadata(
                text: lines[i],
                side: CardSide.front,
                lineIndex: i,
                blockIndex: 0,
                boundingBox: Rect.zero,
              ),
          ],
        ),
      );

      expect(parsed.phoneNumbers, isEmpty, reason: 'Zero-hallucination requires phone to remain blank when no evidence exists');
    });

    // -------------------------------------------------------------------------
    // Scenario 16: Phone on back side of two-sided card -> preserved
    // -------------------------------------------------------------------------
    test('16. Phone on back side of two-sided card: correctly parsed and preserved', () {
      const parser = BusinessCardParser();

      final frontData = const BusinessCardData(
        fullName: 'Jane Doe',
        company: 'Design Studio',
        emailAddresses: [BusinessCardEmail(email: 'jane@design.com')],
      );

      final backData = const BusinessCardData(
        phoneNumbers: [
          BusinessCardPhone(
            number: '+91 98765 43210',
            normalizedNumber: '+919876543210',
            label: 'Mobile',
          ),
        ],
        website: 'www.design.com',
      );

      final merged = parser.mergeDualSidedData(
        frontData: frontData,
        backData: backData,
        frontRawText: 'Jane Doe\nDesign Studio\njane@design.com',
        backRawText: '+91 98765 43210\nwww.design.com',
      );

      expect(merged.fullName, 'Jane Doe');
      expect(merged.company, 'Design Studio');
      expect(merged.phoneNumbers, isNotEmpty);
      expect(merged.phoneNumbers.first.number, '+91 98765 43210');
      expect(merged.phoneNumbers.first.label, 'Mobile');
    });

    // -------------------------------------------------------------------------
    // Scenario 17: International numbers not rejected by India-specific rules
    // -------------------------------------------------------------------------
    test('17. International numbers (UK, US, Germany, Singapore) not rejected by Indian rules', () {
      final intlLines = [
        'Tel: +44 20 7946 0958', // UK
        'Direct: +1 (415) 555-2671', // US
        'Phone: +49 30 12345678', // Germany
        'WhatsApp: +65 6789 0123', // Singapore
        'Landline: 020 8765 4321', // UK national 0 distinct
      ];

      final candidates = PhoneOcrRecovery.extractPhoneCandidates(intlLines);
      expect(candidates.length, 5);
      expect(candidates.any((c) => c.normalized == '+442079460958'), isTrue);
      expect(candidates.any((c) => c.normalized == '+14155552671'), isTrue);
      expect(candidates.any((c) => c.normalized == '+493012345678'), isTrue);
      expect(candidates.any((c) => c.normalized == '+6567890123'), isTrue);
      expect(candidates.any((c) => c.normalized == '02087654321'), isTrue);
    });

    // -------------------------------------------------------------------------
    // Scenario 18: Gallery image phone extraction
    // -------------------------------------------------------------------------
    test('18. Gallery image phone extraction (clean high-res normalized scan)', () {
      final galleryLines = [
        'Rajesh Sharma',
        'Managing Director',
        'Sharma Global Logistics Pvt Ltd',
        'Mob: +91 98400 12345',
        'Off: 044 2456 7890',
        'rajesh@sharmalogistics.com',
      ];

      const parser = BusinessCardParser();
      final sideResult = OcrSideResult(
        side: CardSide.front,
        imagePath: '/gallery/card_gallery_scan.jpg',
        rawText: galleryLines.join('\n'),
        processedAt: DateTime.now(),
        lines: [
          for (int i = 0; i < galleryLines.length; i++)
            OcrLineMetadata(
              text: galleryLines[i],
              side: CardSide.front,
              lineIndex: i,
              blockIndex: 0,
              boundingBox: Rect.zero,
            ),
        ],
      );

      final parsed = parser.parseSide(sideResult);
      expect(parsed.phoneNumbers.length, 2);
      expect(parsed.phoneNumbers.any((p) => p.number.contains('98400 12345')), isTrue);
      expect(parsed.phoneNumbers.any((p) => p.number.contains('2456 7890')), isTrue);
    });

    // -------------------------------------------------------------------------
    // Scenario 19: Camera image phone extraction (with noise and character confusion)
    // -------------------------------------------------------------------------
    test('19. Camera image phone extraction with OCR confusion: recovers cleanly', () {
      final cameraLines = [
        'K. R. Varma',
        'Chief Consultant',
        'Varma Consultants',
        'M: 9876S 432I0', // OCR confused 5->S and 1->I
        'info@varmaconsulting.com',
      ];

      const parser = BusinessCardParser();
      final sideResult = OcrSideResult(
        side: CardSide.front,
        imagePath: '/camera/card_camera_photo.jpg',
        rawText: cameraLines.join('\n'),
        processedAt: DateTime.now(),
        lines: [
          for (int i = 0; i < cameraLines.length; i++)
            OcrLineMetadata(
              text: cameraLines[i],
              side: CardSide.front,
              lineIndex: i,
              blockIndex: 0,
              boundingBox: Rect.zero,
            ),
        ],
      );

      final parsed = parser.parseSide(sideResult);
      expect(parsed.phoneNumbers, isNotEmpty);
      expect(parsed.phoneNumbers.first.number, contains('98765 43210'));
      expect(parsed.phoneNumbers.first.label, 'Mobile');
    });

    // -------------------------------------------------------------------------
    // Scenario 20: Email/address numbers must not be incorrectly classified as phones
    // -------------------------------------------------------------------------
    test('20. Email/address numbers, GSTIN, dates must NOT be classified as phone numbers', () {
      final nonPhoneLines = [
        'john1234@company.com',
        'No. 45, 100 Feet Road, 4th Block, Koramangala',
        'PIN: 600028',
        'Postal Code: 90210',
        'GSTIN: 33AAAAA0000A1Z5',
        'CIN: L12345MH2020PLC123456',
        'Reg No: 12345678',
        'Date: 2024-10-15',
        'Invoice #98765432',
      ];

      final candidates = PhoneOcrRecovery.extractPhoneCandidates(nonPhoneLines);
      expect(candidates, isEmpty, reason: 'Addresses, PIN codes, GSTIN, and dates must not be classified as phones');
    });
  });
}
