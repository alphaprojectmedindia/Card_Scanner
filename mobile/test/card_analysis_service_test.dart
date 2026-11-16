import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/card_analysis_result.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/card_analysis_service.dart';

void main() {
  group('CardAnalysisService and Model Tests', () {
    final service = CardAnalysisService();

    test('computeScanContentHash is deterministic for identical card inputs', () {
      final cardData = BusinessCardData(
        fullName: 'Jane Doe',
        company: 'Acme Corp',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 123 4567')],
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '',
        rawText: 'Jane Doe\nAcme Corp\n+1 555 123 4567',
      );

      final hash1 = service.computeScanContentHash(
        cardData: cardData,
        frontOcr: frontOcr,
      );

      final hash2 = service.computeScanContentHash(
        cardData: cardData,
        frontOcr: frontOcr,
      );

      expect(hash1, isNotEmpty);
      expect(hash1, equals(hash2));
    });

    test('CardAnalysisResult.toBusinessCardData non-destructively merges AI output', () {
      final baseline = BusinessCardData(
        fullName: 'Apex Solutions Pvt Ltd', // Inverted
        company: 'John Doe',
        jobTitle: 'Founder',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 123 4567')],
        emailAddresses: const [BusinessCardEmail(email: 'john@apex.com')],
        website: 'www.apex.com',
        address: 'Old Address',
        fieldConfidenceStates: const {
          'fullName': 'uncertain',
          'company': 'uncertain',
        },
      );

      const aiResult = CardAnalysisResult(
        clientRequestId: 'req_123',
        analysisCacheKey: 'cache_123',
        fullName: ExtractedField(
          value: 'John Doe',
          confidence: 0.95,
          wasCorrected: true,
          reviewRequired: false,
        ),
        company: ExtractedField(
          value: 'Apex Solutions Pvt Ltd',
          confidence: 0.98,
          wasCorrected: true,
          reviewRequired: false,
        ),
        jobTitle: ExtractedField(
          value: 'Chief Executive Officer & Founder',
          confidence: 0.92,
        ),
        address: ExtractedAddress(
          fullAddress: '100 Innovation Way, Tech City, CA 94016',
          confidence: 0.88,
          reviewRequired: true, // Flagged for review
        ),
        phoneNumbers: [
          ExtractedPhone(
            number: '+1 555 123 4567',
            confidence: 0.99,
          ),
        ],
        modelId: 'gemini-3.8-flash',
        reviewWarnings: ['Address missing suite number on visual inspection.'],
      );

      final merged = aiResult.toBusinessCardData(baseline);

      // Verify AI corrections applied
      expect(merged.fullName, equals('John Doe'));
      expect(merged.company, equals('Apex Solutions Pvt Ltd'));
      expect(merged.jobTitle, equals('Chief Executive Officer & Founder'));
      expect(merged.address, equals('100 Innovation Way, Tech City, CA 94016'));

      // Verify field confidence and review badges
      expect(merged.fieldConfidenceStates['fullName'], equals('highConfidence'));
      expect(merged.fieldConfidenceStates['company'], equals('highConfidence'));
      expect(merged.fieldConfidenceStates['address'], equals('uncertain')); // flagged reviewRequired

      // Verify diagnostic audit trail
      expect(merged.parsingNotes.any((n) => n.contains('gemini-3.8-flash')), isTrue);
      expect(merged.parsingNotes.any((n) => n.contains('Address missing suite number')), isTrue);
    });

    test('toBusinessCardData respects fallbackToLocalBaseline flag on error', () {
      final baseline = BusinessCardData(
        fullName: 'Local User',
        company: 'Local Corp',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 000 0000')],
      );

      const fallbackResult = CardAnalysisResult(
        clientRequestId: 'req_err',
        analysisCacheKey: '',
        fallbackToLocalBaseline: true,
        reviewWarnings: ['Service temporarily unavailable'],
      );

      final merged = fallbackResult.toBusinessCardData(baseline);
      expect(merged.fullName, equals('Local User'));
      expect(merged.company, equals('Local Corp'));
    });
  });
}

