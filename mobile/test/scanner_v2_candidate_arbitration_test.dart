import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/screens/scan/business_card_review_screen.dart';
import 'package:digital_share/services/ocr/field_candidate.dart';
import 'package:digital_share/services/ocr/field_semantic_evaluator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Scanner V2 Candidate Arbitration & UI Correction Regression Tests', () {
    // -------------------------------------------------------------------------
    // TEST A: Inferior garbled name cannot beat a strong human-name candidate
    // -------------------------------------------------------------------------
    test('Test A: Inferior garbled name cannot beat a strong human-name candidate', () {
      final primaryLines = [
        '6Ninn Boad Sanikoms', // Corrupted OCR line with numbers inside letters
        'Satony',
      ];
      final secondaryLines = [
        'Dr. Sunil Shroff', // Clean human name candidate
        'Transplant Surgeon',
        'MGM Healthcare',
      ];

      final result = FieldSemanticEvaluator.resolveFields(
        primaryLines: primaryLines,
        primaryEngineName: 'PaddleOCR',
        primaryOcrQualityScore: 0.70,
        secondaryLines: secondaryLines,
        secondaryEngineName: 'ML Kit',
        secondaryOcrQualityScore: 0.90,
      );

      expect(result.name, isNotNull);
      expect(result.name!.value, 'Dr. Sunil Shroff');
      expect(result.name!.value, isNot(contains('6Ninn')));
      // The garbled text should be penalized and not chosen
      final garbledScore = FieldSemanticEvaluator.computeTextQualityScore('6Ninn Boad Sanikoms');
      expect(garbledScore, lessThan(0.60));
    });

    // -------------------------------------------------------------------------
    // TEST B: "Transplantsurgeon" and "Transplant Surgeon" reconcile to better form
    // -------------------------------------------------------------------------
    test('Test B: Near-equivalent job titles reconcile and the cleanly spaced form wins', () {
      final primaryLines = [
        'Dr. Rajesh Kumar',
        'Transplantsurgeon', // Fused word from engine 1
        'Apollo Hospitals',
      ];
      final secondaryLines = [
        'Dr. Rajesh Kumar',
        'Transplant Surgeon', // Clean Title Case with spaces from engine 2
        'Apollo Hospitals',
      ];

      final result = FieldSemanticEvaluator.resolveFields(
        primaryLines: primaryLines,
        primaryEngineName: 'PaddleOCR',
        primaryOcrQualityScore: 0.85,
        secondaryLines: secondaryLines,
        secondaryEngineName: 'ML Kit',
        secondaryOcrQualityScore: 0.90,
      );

      expect(result.jobTitle, isNotNull);
      expect(result.jobTitle!.value, 'Transplant Surgeon');
      expect(result.agreedSignals, contains('jobTitle'));
      // Consensus boost should elevate semantic confidence
      expect(result.jobTitle!.semanticConfidence, greaterThanOrEqualTo(0.80));
    });

    // -------------------------------------------------------------------------
    // TEST C: "MGMHealthcare" and "MGM Healthcare" reconcile without duplicate companies
    // -------------------------------------------------------------------------
    test('Test C: Near-equivalent companies reconcile to spaced form without duplicates', () {
      final primaryLines = [
        'MGMHealthcare', // Fused
        'Dr. S. Sharma',
        'Senior Consultant',
      ];
      final secondaryLines = [
        'MGM Healthcare', // Cleanly spaced
        'Dr. S. Sharma',
        'Senior Consultant',
      ];

      final result = FieldSemanticEvaluator.resolveFields(
        primaryLines: primaryLines,
        primaryEngineName: 'PaddleOCR',
        primaryOcrQualityScore: 0.85,
        secondaryLines: secondaryLines,
        secondaryEngineName: 'ML Kit',
        secondaryOcrQualityScore: 0.90,
      );

      expect(result.company, isNotNull);
      expect(result.company!.value, 'MGM Healthcare');
      expect(result.agreedSignals, contains('company'));
      // Does not treat MGMHealthcare as an unrelated second company
      expect(result.company!.value, isNot('MGMHealthcare'));
    });

    // -------------------------------------------------------------------------
    // TEST D: Weak arbitrary string such as "Satony" cannot beat strong designation
    // -------------------------------------------------------------------------
    test('Test D: Weak arbitrary string cannot beat a strong occupational designation', () {
      final primaryLines = [
        'Satony', // Garbage single word
        'Madras Medical Mission',
      ];
      final secondaryLines = [
        'Transplant Surgeon', // Strong occupational phrase
        'Madras Medical Mission',
      ];

      final result = FieldSemanticEvaluator.resolveFields(
        primaryLines: primaryLines,
        primaryEngineName: 'PaddleOCR',
        primaryOcrQualityScore: 0.75,
        secondaryLines: secondaryLines,
        secondaryEngineName: 'ML Kit',
        secondaryOcrQualityScore: 0.90,
      );

      expect(result.jobTitle, isNotNull);
      expect(result.jobTitle!.value, 'Transplant Surgeon');
      expect(result.jobTitle!.value, isNot('Satony'));

      // In fact, "Satony" has 0 occupational evidence
      final satonyCandidate = FieldSemanticEvaluator.evaluateJobTitleCandidate(
        rawLine: 'Satony',
        sourceEngine: 'PaddleOCR',
        lineIndex: 0,
      );
      expect(satonyCandidate.semanticConfidence, equals(0.0));
    });

    // -------------------------------------------------------------------------
    // TEST E: Weak arbitrary string cannot become company when organization exists
    // -------------------------------------------------------------------------
    test('Test E: Weak arbitrary string cannot become company when stronger organization exists', () {
      final primaryLines = [
        'Satony', // Arbitrary single word on line 0
        'Dr. Ananya Roy',
        'Cardiologist',
      ];
      final secondaryLines = [
        'Madras Medical Mission Hospital', // Clear organization candidate
        'Dr. Ananya Roy',
        'Cardiologist',
      ];

      final result = FieldSemanticEvaluator.resolveFields(
        primaryLines: primaryLines,
        primaryEngineName: 'PaddleOCR',
        primaryOcrQualityScore: 0.75,
        secondaryLines: secondaryLines,
        secondaryEngineName: 'ML Kit',
        secondaryOcrQualityScore: 0.90,
      );

      expect(result.company, isNotNull);
      expect(result.company!.value, 'Madras Medical Mission Hospital');
      expect(result.company!.value, isNot('Satony'));

      // Single word without corporate suffix/domain gets 0 score
      final satonyCompCandidate = FieldSemanticEvaluator.evaluateCompanyCandidate(
        rawLine: 'Satony',
        sourceEngine: 'PaddleOCR',
        lineIndex: 0,
      );
      expect(satonyCompCandidate.semanticConfidence, equals(0.0));
    });

    // -------------------------------------------------------------------------
    // TEST F: Obviously weak field cannot receive highConfidence solely because OCR returned text
    // -------------------------------------------------------------------------
    test('Test F: Obviously weak/garbled field cannot receive highConfidence', () {
      // 1. Weak candidate with poor text quality
      final weakGarbledCandidate = FieldCandidate(
        field: 'fullName',
        value: '6Ninn Boad Sanikoms',
        sourceEngine: 'PaddleOCR',
        ocrConfidence: 0.85,
        semanticConfidence: 0.50,
        textQualityScore: 0.40, // Low text quality
      );
      expect(weakGarbledCandidate.confidenceState, equals(FieldConfidenceState.uncertain));
      expect(weakGarbledCandidate.confidenceState, isNot(equals(FieldConfidenceState.highConfidence)));

      // 2. Weak candidate with rejection reasons
      final rejectedCandidate = FieldCandidate(
        field: 'company',
        value: 'Satony',
        sourceEngine: 'PaddleOCR',
        ocrConfidence: 0.90,
        semanticConfidence: 0.20,
        textQualityScore: 1.0,
        rejectionReasons: const ['Single isolated word without corporate suffix or domain match'],
      );
      expect(rejectedCandidate.confidenceState, equals(FieldConfidenceState.uncertain));

      // 3. Strong clean candidate receives highConfidence
      final strongCandidate = FieldCandidate(
        field: 'fullName',
        value: 'Dr. Sunil Shroff',
        sourceEngine: 'ML Kit',
        ocrConfidence: 0.92,
        semanticConfidence: 0.85,
        textQualityScore: 1.0,
      );
      expect(strongCandidate.confidenceState, equals(FieldConfidenceState.highConfidence));
    });

    // -------------------------------------------------------------------------
    // TEST G: Alternative candidate UI is absent from normal review UI
    // -------------------------------------------------------------------------
    testWidgets('Test G: Alternative candidate UI chips are completely absent from review screen', (tester) async {
      final cardWithAlternatives = BusinessCardData(
        fullName: 'Dr. Sunil Shroff',
        jobTitle: 'Transplant Surgeon',
        company: 'MGM Healthcare',
        phoneNumbers: const [
          BusinessCardPhone(number: '+91 98400 12345', label: 'Mobile'),
        ],
        emailAddresses: const [
          BusinessCardEmail(email: 'sunil@mgm.com', label: 'Work'),
        ],
        rawRecognizedText: 'Dr. Sunil Shroff\nTransplant Surgeon\nMGM Healthcare',
        alternativeCandidates: const {
          'fullName': ['D. Sunil Shro...'],
          'jobTitle': ['Satony'],
          'company': ['Madras Medical Mission Hospital'],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: cardWithAlternatives),
        ),
      );
      await tester.pump();

      // Ensure "Alternative detected:" text is NEVER shown to normal users
      expect(find.textContaining('Alternative detected'), findsNothing);
      expect(find.text('Use'), findsNothing);
      expect(find.text('D. Sunil Shro...'), findsNothing);
      expect(find.text('Satony'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // TEST H: Additional Card Text section is absent from normal review UI
    // -------------------------------------------------------------------------
    testWidgets('Test H: Additional Card Text section is completely absent from review screen', (tester) async {
      final cardWithUnclassified = BusinessCardData(
        fullName: 'Dr. Sunil Shroff',
        jobTitle: 'Transplant Surgeon',
        company: 'MGM Healthcare',
        phoneNumbers: const [
          BusinessCardPhone(number: '+91 98400 12345', label: 'Mobile'),
        ],
        emailAddresses: const [
          BusinessCardEmail(email: 'sunil@mgm.com', label: 'Work'),
        ],
        rawRecognizedText: 'Raw OCR',
        unclassifiedLines: const [
          'SCAN ME',
          'Madras MedicalMission',
          'Transplantsurgeon',
          'MGMHealthcare',
          'D. Sunil Shro...',
          'Madras Medical Mission Hospital',
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: cardWithUnclassified),
        ),
      );
      await tester.pump();

      // Ensure "ADDITIONAL CARD TEXT" header and its items are NOT rendered
      expect(find.text('ADDITIONAL CARD TEXT'), findsNothing);
      expect(find.text('SCAN ME'), findsNothing);
      expect(find.text('Transplantsurgeon'), findsNothing);
      expect(find.text('MGMHealthcare'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // TEST I: unclassifiedLines remain internally preserved for testing & diagnostics
    // -------------------------------------------------------------------------
    test('Test I: unclassifiedLines and alternativeCandidates remain internally preserved', () {
      final primaryLines = [
        'Dr. Sunil Shroff',
        'Transplant Surgeon',
        'MGM Healthcare',
        'SCAN ME', // Unclaimed logo/QR label
        'NABH Accredited', // Unclaimed accreditation
      ];
      final secondaryLines = [
        'Dr. Sunil Shroff',
        'Transplant Surgeon',
        'MGM Healthcare',
      ];

      final resolution = FieldSemanticEvaluator.resolveFields(
        primaryLines: primaryLines,
        primaryEngineName: 'PaddleOCR',
        primaryOcrQualityScore: 0.90,
        secondaryLines: secondaryLines,
        secondaryEngineName: 'ML Kit',
        secondaryOcrQualityScore: 0.90,
      );

      // Verify unclassifiedLines is preserved internally
      expect(resolution.unclassifiedLines, isNotEmpty);
      expect(resolution.unclassifiedLines, contains('SCAN ME'));
      expect(resolution.unclassifiedLines, contains('NABH Accredited'));

      // Check serialization preserves unclassified lines
      final json = resolution.toJson();
      expect(json['unclassifiedLines'], isNotNull);
      expect((json['unclassifiedLines'] as List), contains('SCAN ME'));
    });

    // -------------------------------------------------------------------------
    // TEST J: No card-specific hardcoding exists in parser/evaluator code
    // -------------------------------------------------------------------------
    test('Test J: Codebase contains NO card-specific hardcoding', () {
      final evaluatorFile = File('lib/services/ocr/field_semantic_evaluator.dart');
      final parserFile = File('lib/services/business_card_parser.dart');

      expect(evaluatorFile.existsSync(), isTrue);
      expect(parserFile.existsSync(), isTrue);

      final evaluatorContent = evaluatorFile.readAsStringSync().toLowerCase();
      final parserContent = parserFile.readAsStringSync().toLowerCase();

      // Ensure no hardcoded specific people, clinics, or bespoke test card names
      expect(evaluatorContent, isNot(contains('sunil shroff')));
      expect(parserContent, isNot(contains('sunil shroff')));

      expect(evaluatorContent, isNot(contains('madras medical mission')));
      expect(parserContent, isNot(contains('madras medical mission')));

      expect(evaluatorContent, isNot(contains('mgm healthcare')));
      expect(parserContent, isNot(contains('mgm healthcare')));

      expect(evaluatorContent, isNot(contains('6ninn')));
      expect(parserContent, isNot(contains('6ninn')));

      expect(evaluatorContent, isNot(contains('satony')));
      expect(parserContent, isNot(contains('satony')));
    });
  });
}
