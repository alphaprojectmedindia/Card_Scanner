import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/services/ocr/field_confidence_evaluator.dart';

void main() {
  const evaluator = FieldConfidenceEvaluator();

  group('FieldConfidenceEvaluator Tests', () {
    test('Grades clean, high-confidence card with HIGH grades and bypasses Gemini', () {
      const cleanCard = BusinessCardData(
        fullName: 'Alexander Wright',
        company: 'Vanguard Global Technologies Ltd',
        jobTitle: 'Senior Vice President of Engineering',
        phoneNumbers: [
          BusinessCardPhone(number: '+1-415-555-0199', label: 'Work'),
        ],
        emailAddresses: [
          BusinessCardEmail(email: 'alex.wright@vanguard-tech.com', label: 'Work'),
        ],
        website: 'www.vanguard-tech.com',
        address: '500 Howard Street, Suite 400, San Francisco, CA 94105',
      );

      final report = evaluator.evaluate(cardData: cleanCard);

      expect(report.overallScore, greaterThanOrEqualTo(0.80));
      expect(report.isOverallReliable, isTrue);
      expect(report.hasLowConfidenceCriticalFields, isFalse);

      expect(report['fullName']?.level, equals(FieldConfidenceLevel.high));
      expect(report['company']?.level, equals(FieldConfidenceLevel.high));
      expect(report['jobTitle']?.level, equals(FieldConfidenceLevel.high));
      expect(report['phoneNumbers']?.level, equals(FieldConfidenceLevel.high));
      expect(report['emailAddresses']?.level, equals(FieldConfidenceLevel.high));
    });

    test('Grades card with name/company inversion confusion with LOW confidence and flags critical', () {
      const confusingCard = BusinessCardData(
        fullName: 'Apex Solutions Pvt Ltd', // Corporate entity in name!
        company: 'Dr. John Watson', // Personal honorific in company!
        fieldConfidenceStates: {
          'fullName': 'uncertain',
          'company': 'uncertain',
        },
        phoneNumbers: [
          BusinessCardPhone(number: '12345'), // Bad phone length
        ],
        emailAddresses: [], // Missing email
      );

      final report = evaluator.evaluate(cardData: confusingCard);

      expect(report.hasLowConfidenceCriticalFields, isTrue);
      expect(report['fullName']?.isLow, isTrue);
      expect(report['company']?.isLow, isTrue);
      expect(report['fullName']?.uncertaintyReasons, isNotEmpty);
      expect(report['company']?.uncertaintyReasons, isNotEmpty);
    });

    test('Grades missing core identity as low confidence', () {
      const missingIdentityCard = BusinessCardData(
        fullName: null,
        company: null,
        phoneNumbers: [
          BusinessCardPhone(number: '+1-555-0100'),
        ],
        emailAddresses: [
          BusinessCardEmail(email: 'contact@domain.com'),
        ],
      );

      final report = evaluator.evaluate(cardData: missingIdentityCard);

      expect(report.hasLowConfidenceCriticalFields, isTrue);
      expect(report['fullName']?.level, equals(FieldConfidenceLevel.low));
      expect(report['company']?.level, equals(FieldConfidenceLevel.low));
    });
  });
}

