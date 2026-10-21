import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/services/ocr/ocr_engine.dart';
import 'package:digital_share/services/ocr/ocr_quality_assessment.dart';

void main() {
  group('OCR Quality Assessment Tests (Prompt Section 24)', () {
    // -------------------------------------------------------------------------
    // Case A: Strong normal card -> ML Kit considered sufficient
    // -------------------------------------------------------------------------
    test('Case A: Strong normal card is evaluated as sufficient (score >= 65)', () {
      const normalCard = '''
Rahul Kumar
Senior Developer
ABC Technologies
Mobile: +91 98765 43210
Email: rahul@abctech.com
''';

      final assessment = OcrQualityEvaluator.assessText(normalCard);

      expect(assessment.isSufficient, isTrue);
      expect(assessment.score, greaterThanOrEqualTo(OcrQualityThresholds.sufficiencyScoreThreshold));
      expect(assessment.detectedSignals, contains(OcrSignalNames.validEmail));
      expect(assessment.detectedSignals, contains(OcrSignalNames.validPhone));
      expect(assessment.detectedSignals, contains(OcrSignalNames.plausiblePersonName));
      expect(assessment.detectedSignals, contains(OcrSignalNames.plausibleJobTitle));
      expect(assessment.detectedSignals, contains(OcrSignalNames.plausibleCompany));
    });

    // -------------------------------------------------------------------------
    // Case B: Antony-Lobo-style corrupted ML Kit result -> considered weak
    // -------------------------------------------------------------------------
    test('Case B: Antony Lobo corrupted ML Kit result is considered insufficient and triggers fallback', () {
      const corruptedMlKitText = '''
Sntony Doto
Kon ConsulfGpain
spainconsulate.chennai@gmail.com
''';

      final assessment = OcrQualityEvaluator.assessText(corruptedMlKitText);

      // Corrupted word "ConsulfGpain" and missing phone anchor should degrade score
      expect(assessment.isSufficient, isFalse);
      expect(assessment.score, lessThan(OcrQualityThresholds.sufficiencyScoreThreshold));
      expect(assessment.reasons.any((r) => r.contains('corrupted') || r.contains('Corrupted')), isTrue);
      expect(assessment.missingSignals, contains(OcrSignalNames.validPhone));
    });

    test('Case B2: Antony Lobo PaddleOCR result is evaluated as strong and sufficient', () {
      const paddleOcrText = '''
Antony Lobo
Hon. Consul of Spain.
Consulate of Spain
6, Nimmo Road, Santhome
Tel:+91-44-42107657
Chennai-600 004
spainconsulate.chennai@gmail.com
''';

      final assessment = OcrQualityEvaluator.assessText(paddleOcrText);

      expect(assessment.isSufficient, isTrue);
      expect(assessment.score, greaterThanOrEqualTo(80.0));
      expect(assessment.detectedSignals, contains(OcrSignalNames.validEmail));
      expect(assessment.detectedSignals, contains(OcrSignalNames.validPhone));
      expect(assessment.detectedSignals, contains(OcrSignalNames.plausiblePersonName));
      expect(assessment.detectedSignals, contains(OcrSignalNames.plausibleJobTitle));
      expect(assessment.detectedSignals, contains(OcrSignalNames.plausibleCompany));
      expect(assessment.detectedSignals, contains(OcrSignalNames.addressIndicator));
    });

    // -------------------------------------------------------------------------
    // Case C: Valid email + phone + plausible name -> positive quality signals
    // -------------------------------------------------------------------------
    test('Case C: Valid email, phone, and plausible name produce strong positive signals', () {
      const card = '''
Dr. Jane Doe
Director of Research
Global Health Institute
Phone: +1 415 555 0199
Email: jane.doe@globalhealth.org
''';

      final assessment = OcrQualityEvaluator.assessText(card);

      expect(assessment.isSufficient, isTrue);
      expect(assessment.detectedSignals, contains(OcrSignalNames.validEmail));
      expect(assessment.detectedSignals, contains(OcrSignalNames.validPhone));
      expect(assessment.detectedSignals, contains(OcrSignalNames.plausiblePersonName));
      expect(assessment.score, greaterThanOrEqualTo(70.0));
    });

    // -------------------------------------------------------------------------
    // Case D: Large amount of garbage text -> character count alone does not produce high quality
    // -------------------------------------------------------------------------
    test('Case D: Large amount of garbage text fails sufficiency despite high character count', () {
      // 200+ characters of non-alphanumeric noise
      final garbageText = StringBuffer();
      for (int i = 0; i < 15; i++) {
        garbageText.writeln('|||| %%%% ^^^^ #### @@@@ **** ~~~~ ????');
      }

      final text = garbageText.toString();
      expect(text.length, greaterThan(200));

      final assessment = OcrQualityEvaluator.assessText(text);

      expect(assessment.isSufficient, isFalse);
      expect(assessment.score, lessThan(40.0));
      expect(assessment.reasons.any((r) => r.contains('noise') || r.contains('Noise')), isTrue);
      expect(assessment.missingSignals, contains(OcrSignalNames.validEmail));
      expect(assessment.missingSignals, contains(OcrSignalNames.validPhone));
      expect(assessment.missingSignals, contains(OcrSignalNames.plausiblePersonName));
    });

    // -------------------------------------------------------------------------
    // Case E: Many one-character lines -> negative quality signal
    // -------------------------------------------------------------------------
    test('Case E: Excessive single-character lines triggers penalty and fails sufficiency', () {
      const fragmentedText = '''
A
b
C
d
E
f
g
Rahul Kumar
rahul@example.com
''';

      final assessment = OcrQualityEvaluator.assessText(fragmentedText);

      expect(assessment.isSufficient, isFalse);
      expect(assessment.reasons.any((r) => r.contains('single-character') || r.contains('Single')), isTrue);
      expect(assessment.metrics['singleCharLineCount'], greaterThanOrEqualTo(5));
    });

    // -------------------------------------------------------------------------
    // Case F: Missing name but valid contact details -> reasonable fallback behavior
    // -------------------------------------------------------------------------
    test('Case F: Card with contact details but missing person name triggers fallback to recover name', () {
      const companyOnlyCard = '''
Acme Corporation
HQ: 100 Main Street
Tel: +1 800 555 0100
info@acmecorp.com
www.acmecorp.com
''';

      final assessment = OcrQualityEvaluator.assessText(companyOnlyCard);

      // Has phone, email, website, but missing person's name
      expect(assessment.detectedSignals, contains(OcrSignalNames.validEmail));
      expect(assessment.detectedSignals, contains(OcrSignalNames.validPhone));
      expect(assessment.detectedSignals, contains(OcrSignalNames.validWebsite));
      expect(assessment.missingSignals, contains(OcrSignalNames.plausiblePersonName));

      // Quality assessment considers it insufficient without identity so PaddleOCR can attempt
      // to recover the cardholder's name
      expect(assessment.isSufficient, isFalse);
      expect(assessment.reasons.any((r) => r.contains('name') || r.contains('Name')), isTrue);
    });

    // -------------------------------------------------------------------------
    // Case G: Multiple valid phone/email fields preserved
    // -------------------------------------------------------------------------
    test('Case G: Multiple phones and emails are all detected as valid signals', () {
      const multiContactCard = '''
Elena Rostova
Managing Partner
Vanguard Legal
Direct: +1 212 555 0140
Mobile: +1 917 555 0199
Work: elena@vanguardlaw.com
Personal: elena.rostova@gmail.com
''';

      final assessment = OcrQualityEvaluator.assessText(multiContactCard);

      expect(assessment.isSufficient, isTrue);
      expect(assessment.detectedSignals, contains(OcrSignalNames.validEmail));
      expect(assessment.detectedSignals, contains(OcrSignalNames.validPhone));
      expect(assessment.detectedSignals, contains(OcrSignalNames.plausiblePersonName));
      expect(assessment.score, greaterThanOrEqualTo(75.0));
    });

    // -------------------------------------------------------------------------
    // Empty & Failure Handling
    // -------------------------------------------------------------------------
    test('Empty text returns 0 score and isSufficient=false', () {
      final assessment = OcrQualityEvaluator.assessText('   \n  \n');
      expect(assessment.score, 0.0);
      expect(assessment.isSufficient, isFalse);
    });

    test('Engine failure result returns 0 score and isSufficient=false', () {
      final failureResult = OcrEngineResult.failure(
        engineName: 'Test Engine',
        error: 'Simulated engine failure',
      );
      final assessment = OcrQualityEvaluator.assessEngineResult(failureResult);
      expect(assessment.score, 0.0);
      expect(assessment.isSufficient, isFalse);
      expect(assessment.reasons.first, contains('failed'));
    });
  });
}
