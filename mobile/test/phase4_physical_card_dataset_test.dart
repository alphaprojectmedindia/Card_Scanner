import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/ocr/email_ocr_recovery.dart';
import 'package:digital_share/services/ocr/field_semantic_evaluator.dart';
import 'package:digital_share/services/ocr/phone_ocr_recovery.dart';

void main() {
  final parser = BusinessCardParser();

  group('Phase 4: Physical-Card Regression Dataset & Field Validation', () {
    test('Target Card 1: Lions Clubs International (Bangladesh)', () {
      final lines = [
        'Lions Clubs International',
        'Nazmul Haque',
        'International Director 2025-2027',
        'House - 113, Road - 3, Block # F',
        'Banani, Dhaka-1213, Bangladesh',
        '+88 01713 032845',
        'lnazmul.haque1951@gmail.com',
        // Simulated OCR fragments from multi-pass / secondary OCR:
        '1951@gmail.com',
        '951@gmail.com',
        '2025-2027',
      ];
      final rawText = lines.join('\n');

      final result = parser.parse(rawText);

      // 1. Person Name
      expect(result.fullName, isNotNull);
      expect(result.fullName, equals('Nazmul Haque'));

      // 2. Job Title
      expect(result.jobTitle, isNotNull);
      expect(result.jobTitle, equals('International Director 2025-2027'));

      // 3. Organization / Company
      expect(result.company, isNotNull);
      expect(result.company, equals('Lions Clubs International'));

      // 4. Phone extraction: Bangladesh mobile format + tenure year exclusion
      final phones = result.phoneNumbers;
      expect(phones, isNotEmpty);
      expect(
        phones.any((p) => p.number.contains('01713') && p.number.contains('032845')),
        isTrue,
        reason: 'Should extract Bangladesh mobile number (+88 01713 032845)',
      );
      expect(
        phones.any((p) => p.number.contains('2025') || p.number.contains('2027')),
        isFalse,
        reason: 'Tenure year range 2025-2027 must NEVER be extracted as a phone number',
      );

      // 5. Email deduplication & fragment subsumption
      final emails = result.emailAddresses;
      expect(emails.length, equals(1),
          reason: 'Subsumed fragments (1951@gmail.com, 951@gmail.com) must be suppressed');
      expect(emails.first.email, equals('lnazmul.haque1951@gmail.com'));

      // 6. Address isolation (no entity bleed)
      expect(result.address, isNotNull);
      expect(result.address, contains('Banani'));
      expect(result.address, contains('Dhaka-1213'));
      expect(result.address, contains('Bangladesh'));
      expect(result.address!.contains('Nazmul Haque'), isFalse,
          reason: 'Person name must not bleed into address');
      expect(result.address!.contains('Lions Clubs'), isFalse,
          reason: 'Company name must not bleed into address');
      expect(result.address!.contains('International Director'), isFalse,
          reason: 'Job title must not bleed into address');

      // 7. Cross-engine Field Semantic Evaluator validation
      final fieldRes = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 0.95,
        secondaryLines: [
          'Lions Clubs International',
          'Nazmul Haque',
          'International Director 2025-2027',
          'House - 113, Road - 3, Block # F',
          'Banani, Dhaka-1213, Bangladesh',
          '+8801713032845',
          'lnazmul.haque1951@gmail.com',
          '1951@gmail.com',
        ],
        secondaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        secondaryOcrQualityScore: 0.90,
      );

      expect(fieldRes.name?.value, equals('Nazmul Haque'));
      expect(fieldRes.jobTitle?.value, equals('International Director 2025-2027'));
      expect(fieldRes.company?.value, equals('Lions Clubs International'));
      expect(fieldRes.emails.length, equals(1));
      expect(fieldRes.emails.first.value, equals('lnazmul.haque1951@gmail.com'));
    });

    test('Target Card 2: Vardhaman & Co (Chennai, Landline STD Deduplication & Email Subsumption)', () {
      final lines = [
        'Vardhaman & Co',
        'V. Baskaran',
        '044-24344627',
        '044-24342596',
        '24342596', // Un-prefixed landline duplicate
        '9840136801',
        'vardhaman_1973@hotmail.com',
        'i1973@hotmail.com', // OCR character corruption fragment
        'abhabj@gmail.com',
        'New No. 12 (Old No. 31-A), Krishna Street',
        'T. Nagar, Chennai - 600 017',
      ];
      final rawText = lines.join('\n');

      final result = parser.parse(rawText);

      // 1. Person & Company
      expect(result.fullName, equals('V. Baskaran'));
      expect(result.company, equals('Vardhaman & Co'));

      // 2. Phone numbers (Landline deduplication: 24342596 merged into 044-24342596)
      final phoneNumbers = result.phoneNumbers.map((p) => p.number).toList();
      expect(phoneNumbers.any((p) => p.contains('24344627')), isTrue);
      expect(phoneNumbers.any((p) => p.contains('044') && p.contains('24342596')), isTrue);
      expect(phoneNumbers.any((p) => p.contains('9840136801')), isTrue);
      // Confirm no duplicate 8-digit without STD code
      final duplicate8Digit = phoneNumbers.where((p) => p.replaceAll(RegExp(r'\D'), '') == '24342596');
      expect(duplicate8Digit, isEmpty,
          reason: 'Standalone 24342596 must be deduplicated into STD-prefixed 044-24342596');

      // 3. Email recovery & corruption suppression
      final emailList = result.emailAddresses.map((e) => e.email).toList();
      expect(emailList.contains('vardhaman_1973@hotmail.com'), isTrue);
      expect(emailList.contains('abhabj@gmail.com'), isTrue);
      expect(emailList.contains('i1973@hotmail.com'), isFalse,
          reason: 'i1973@hotmail.com must be suppressed as a fragment of vardhaman_1973@hotmail.com');

      // 4. Address extraction
      expect(result.address, isNotNull);
      expect(result.address, contains('Krishna Street'));
      expect(result.address, contains('T. Nagar'));
      expect(result.address, contains('Chennai - 600 017'));
      expect(result.address!.contains('Baskaran'), isFalse);
      expect(result.address!.contains('Vardhaman'), isFalse);
    });

    test('Target Card 3: Consulate of Spain (Company vs Job Title Separation)', () {
      final lines = [
        'Consulate of Spain',
        'Antony Lobo',
        'Hon. Consul of Spain',
        'spainconsulate.chennai@gmail.com',
        '+91-44-42107657',
      ];
      final rawText = lines.join('\n');

      final result = parser.parse(rawText);

      // 1. Person Name
      expect(result.fullName, equals('Antony Lobo'));

      // 2. Job Title
      expect(result.jobTitle, equals('Hon. Consul of Spain'));

      // 3. Organization / Company (Must NOT be classified as Hon. Consul of Spain)
      expect(result.company, equals('Consulate of Spain'));

      // 4. Contact details
      expect(result.emailAddresses.length, equals(1));
      expect(result.emailAddresses.first.email, equals('spainconsulate.chennai@gmail.com'));
      expect(result.phoneNumbers.length, equals(1));
      expect(result.phoneNumbers.first.number, contains('42107657'));

      // 5. Cross-engine field resolution
      final fieldRes = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'Google ML Kit',
        primaryOcrQualityScore: 0.95,
        secondaryLines: [
          'Consulate of Spain',
          'Antony Lobo',
          'Hon. Consul of Spain',
          '+91-44-42107657',
          'spainconsulate.chennai@gmail.com',
        ],
        secondaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        secondaryOcrQualityScore: 0.90,
      );

      expect(fieldRes.name?.value, equals('Antony Lobo'));
      expect(fieldRes.jobTitle?.value, equals('Hon. Consul of Spain'));
      expect(fieldRes.company?.value, equals('Consulate of Spain'));
    });

    test('Target Card 4: US Card (US Phone Pattern & Single-Digit Email Subsumption)', () {
      final lines = [
        'tanakagawa86@gmail.com',
        '6@gmail.com', // OCR sub-bounding box fragment
        '(336) 414-6830',
        '123 27th Ave N',
        'St Petersburg, FL 33704',
      ];
      final rawText = lines.join('\n');

      final result = parser.parse(rawText);

      // 1. Email extraction with single-digit fragment suppressed
      expect(result.emailAddresses.length, equals(1));
      expect(result.emailAddresses.first.email, equals('tanakagawa86@gmail.com'));

      // 2. US Phone parenthesized area code
      expect(result.phoneNumbers.length, equals(1));
      expect(result.phoneNumbers.first.number, equals('(336) 414-6830'));

      // 3. Address extraction
      expect(result.address, isNotNull);
      expect(result.address, contains('123 27th Ave N'));
      expect(result.address, contains('St Petersburg, FL 33704'));
    });

    test('Controlled Email Subsumption Unit Tests', () {
      final candidates = [
        const EmailCandidate(
          raw: 'lnazmul.haque1951@gmail.com',
          email: 'lnazmul.haque1951@gmail.com',
          normalized: 'lnazmul.haque1951@gmail.com',
        ),
        const EmailCandidate(
          raw: '1951@gmail.com',
          email: '1951@gmail.com',
          normalized: '1951@gmail.com',
        ),
        const EmailCandidate(
          raw: '951@gmail.com',
          email: '951@gmail.com',
          normalized: '951@gmail.com',
        ),
        const EmailCandidate(
          raw: 'vardhaman_1973@hotmail.com',
          email: 'vardhaman_1973@hotmail.com',
          normalized: 'vardhaman_1973@hotmail.com',
        ),
        const EmailCandidate(
          raw: 'i1973@hotmail.com',
          email: 'i1973@hotmail.com',
          normalized: 'i1973@hotmail.com',
        ),
        const EmailCandidate(
          raw: 'tanakagawa86@gmail.com',
          email: 'tanakagawa86@gmail.com',
          normalized: 'tanakagawa86@gmail.com',
        ),
        const EmailCandidate(
          raw: '6@gmail.com',
          email: '6@gmail.com',
          normalized: '6@gmail.com',
        ),
        const EmailCandidate(
          raw: 'support@apple.com',
          email: 'support@apple.com',
          normalized: 'support@apple.com',
        ),
        const EmailCandidate(
          raw: 'sales@apple.com',
          email: 'sales@apple.com',
          normalized: 'sales@apple.com',
        ),
      ];

      final suppressed = EmailOcrRecovery.suppressEmailFragments(candidates);
      final suppressedEmails = suppressed.map((e) => e.email).toList();

      expect(suppressedEmails, contains('lnazmul.haque1951@gmail.com'));
      expect(suppressedEmails.contains('1951@gmail.com'), isFalse);
      expect(suppressedEmails.contains('951@gmail.com'), isFalse);

      expect(suppressedEmails, contains('vardhaman_1973@hotmail.com'));
      expect(suppressedEmails.contains('i1973@hotmail.com'), isFalse);

      expect(suppressedEmails, contains('tanakagawa86@gmail.com'));
      expect(suppressedEmails.contains('6@gmail.com'), isFalse);

      // Distinct emails with different prefixes on the same domain must both be preserved
      expect(suppressedEmails, contains('support@apple.com'));
      expect(suppressedEmails, contains('sales@apple.com'));
    });

    test('Tenure Year Range Disqualification from Phone Engine', () {
      final lines = [
        'International Director 2025-2027',
        'Term: 2024 - 2026',
        '2023/2025',
      ];
      final phones = PhoneOcrRecovery.extractPhoneCandidates(lines);
      expect(phones, isEmpty, reason: 'Year ranges must not be parsed as phones');
    });

    test('Cards with one email must never produce two or three emails from OCR fragments', () {
      final multiFragmentCard = [
        'Dr. Rajesh Sharma',
        'Senior Consultant',
        'Apollo Hospitals',
        'rajesh.sharma2020@apollo.org',
        '2020@apollo.org', // Fragment 1
        'sharma2020@apollo.org', // Fragment 2
        '0@apollo.org', // Fragment 3
        '+91 98400 12345',
      ].join('\n');

      final result = parser.parse(multiFragmentCard);
      expect(result.emailAddresses.length, equals(1));
      expect(result.emailAddresses.first.email, equals('rajesh.sharma2020@apollo.org'));
    });

    test('Profession-specific designations are recognized as Job Titles without forcing Company', () {
      final caCard = [
        'K. R. Ramanathan & Associates',
        'Chartered Accountants',
        'K. R. Ramanathan, B.Com, FCA',
        'Chartered Accountant',
        '+91 44 2827 1234',
        'ramanathan@cakrr.com',
      ].join('\n');

      final result = parser.parse(caCard);
      expect(result.jobTitle, equals('Chartered Accountant'));
      expect(result.jobTitle != result.company, isTrue);
      expect(result.company, contains('Ramanathan & Associates'));
    });

    test('Verification Status correctly distinguishes Detected, Please verify, and Not detected', () {
      // 1. High confidence card
      final fullCard = [
        'Apex Medical Systems',
        'Dr. John Mathew',
        'Chief Medical Officer',
        '+91 98765 43210',
        'john@apexsystems.com',
        'www.apexsystems.com',
        '100 Anna Salai, Guindy, Chennai - 600032',
      ].join('\n');

      final fullResult = parser.parse(fullCard);
      expect(fullResult.fieldConfidenceStates['fullName'], equals('highConfidence'));
      expect(fullResult.fieldConfidenceStates['phone'], equals('highConfidence'));
      expect(fullResult.fieldConfidenceStates['email'], equals('highConfidence'));
      expect(fullResult.fieldConfidenceStates['website'], equals('highConfidence'));
      expect(fullResult.fieldConfidenceStates['company'], equals('highConfidence'));

      // 2. Incomplete card with missing fields
      final minimalCard = [
        'John', // 1-word name (uncertain)
        '+91 98765 43210',
      ].join('\n');

      final minResult = parser.parse(minimalCard);
      expect(minResult.fieldConfidenceStates['email'], equals('notDetected'));
      expect(minResult.fieldConfidenceStates['website'], equals('notDetected'));
      expect(minResult.fieldConfidenceStates['address'], equals('notDetected'));
    });
  });
}
