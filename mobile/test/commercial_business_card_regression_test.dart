import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/ocr/phone_ocr_recovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const parser = BusinessCardParser();

  group('PART 5: COMMERCIAL OCR & PARSING REGRESSION TESTS', () {
    test('TEST CASE A: PELICAN NEST card extracts all details accurately', () {
      final rawLines = [
        'PELICAN NEST LLP',
        'Karthik Surendran',
        'Partner',
        'SAYEE, #31, Rajamannar Street, T. Nagar, Chennai - 600 017, India',
        'Telephone: +91 44 4202 3412/13',
        'Mobile: 98400 19790',
        'Email: karthiks@pelicangroup.in',
      ];

      final ocrResult = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: 'card.jpg',
        rawText: rawLines.join('\n'),
      );

      final cardData = parser.parseSide(ocrResult);

      // 1. Person Name must be Karthik Surendran, NEVER PELICAN NEST
      expect(cardData.fullName, equals('Karthik Surendran'));

      // 2. Job Title
      expect(cardData.jobTitle, equals('Partner'));

      // 3. Company Name
      expect(cardData.company, equals('PELICAN NEST LLP'));

      // 4. Phone Numbers: Must include both slash-extension numbers and mobile
      final phoneNumbers = cardData.phoneNumbers.map((p) => p.number).toList();
      expect(phoneNumbers.any((p) => p.contains('4202 3412')), isTrue,
          reason: 'Must contain office line 1');
      expect(phoneNumbers.any((p) => p.contains('4202 3413')), isTrue,
          reason: 'Must contain office line 2 (expanded from /13)');
      expect(phoneNumbers.any((p) => p.contains('98400 19790')), isTrue,
          reason: 'Must contain mobile number');

      // 5. Email
      expect(cardData.emailAddresses.length, equals(1));
      expect(cardData.emailAddresses.first.email, equals('karthiks@pelicangroup.in'));

      // 6. Address
      expect(cardData.address, contains('Rajamannar Street'));
      expect(cardData.address, contains('600 017'));
    });

    test('TEST CASE A (Variant): Truncated ELICAN NEST does not steal person name', () {
      final rawLines = [
        'ELICAN NEST',
        'Karthik Surendran',
        'Partner',
        'Telephone: +91 44 4202 3412/13',
        'karthiks@pelicangroup.in',
      ];

      final ocrResult = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: 'card.jpg',
        rawText: rawLines.join('\n'),
      );

      final cardData = parser.parseSide(ocrResult);

      // Person name MUST be Karthik Surendran
      expect(cardData.fullName, equals('Karthik Surendran'));
    });

    test('TEST CASE B: ROTARY card extracts honorific and prevents decorative text as name', () {
      final rawLines = [
        'Rotary',
        'Rtn. V.P. Ghanesh, F.C.A.',
        'Chairperson, Public Image 2024-25',
      ];

      final ocrResult = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: 'card.jpg',
        rawText: rawLines.join('\n'),
      );

      final cardData = parser.parseSide(ocrResult);

      // Rotary must be Organization / Company, NOT Person Name
      expect(cardData.fullName, isNot(equals('Rotary')));
      expect(cardData.fullName, contains('Ghanesh'));

      // Designation
      expect(cardData.jobTitle, contains('Chairperson'));
      expect(cardData.jobTitle, contains('Public Image'));

      // Organization
      expect(cardData.company, equals('Rotary'));
    });

    test('TEST CASE C: MEDINDIA / MRMED card extracts all visible fields cleanly', () {
      final rawLines = [
        'SAURAB JAIN',
        'Co-founder & CBO',
        'Eazymed Technologies Pvt Ltd',
        '+91 91767 17777',
        'saurab@mrmed.in',
        'www.mrmed.in',
        'Ground Floor, No.5 Raja Street, T Nagar, Chennai - 600017',
      ];

      final ocrResult = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: 'card.jpg',
        rawText: rawLines.join('\n'),
      );

      final cardData = parser.parseSide(ocrResult);

      // Person
      expect(cardData.fullName, equals('SAURAB JAIN'));

      // Designation
      expect(cardData.jobTitle, equals('Co-founder & CBO'));

      // Company
      expect(cardData.company, equals('Eazymed Technologies Pvt Ltd'));

      // Phone
      expect(cardData.phoneNumbers.any((p) => p.number.contains('91767 17777')), isTrue);

      // Email
      expect(cardData.emailAddresses.length, equals(1));
      expect(cardData.emailAddresses.first.email, equals('saurab@mrmed.in'));

      // Website
      expect(cardData.website, equals('www.mrmed.in'));

      // Address
      expect(cardData.address, contains('Raja Street'));
      expect(cardData.address, contains('600017'));
    });

    test('Slash phone extension expansion utility handles multiple formats', () {
      // 1. Standard Indian dual landline
      final res1 = PhoneOcrRecovery.expandSlashPhoneExtensions('+91 44 4202 3412/13');
      expect(res1, equals('+91 44 4202 3412, +91 44 4202 3413'));

      // 2. Landline with hyphen and space
      final res2 = PhoneOcrRecovery.expandSlashPhoneExtensions('044-42023412 / 13');
      expect(res2, equals('044-42023412, 044-42023413'));

      // 3. Triple extension
      final res3 = PhoneOcrRecovery.expandSlashPhoneExtensions('42023412/13/14');
      expect(res3, equals('42023412, 42023413, 42023414'));
    });
  });
}
