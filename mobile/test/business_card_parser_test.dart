import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/services/business_card_parser.dart';

void main() {
  const parser = BusinessCardParser();

  group('BusinessCardParser Tests', () {
    test('TEST 1: One phone + one email', () {
      const text = '''
Rahul Kumar
Senior Developer
ABC Technologies
Mobile: +91 98765 43210
Email: rahul@abctech.com
''';
      final result = parser.parse(text);

      expect(result.phoneNumbers.length, 1);
      expect(result.phoneNumbers.first.number, '+91 98765 43210');
      expect(result.phoneNumbers.first.label, 'Mobile');

      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'rahul@abctech.com');
      expect(result.emailAddresses.first.normalizedEmail, 'rahul@abctech.com');
    });

    test('TEST 2: Two phone numbers', () {
      const text = '''
Rahul Kumar
Managing Director
Mobile: +91 98765 43210
Office: +91 44 2345 6789
rahul@company.com
''';
      final result = parser.parse(text);

      expect(result.phoneNumbers.length, 2);
      expect(result.phoneNumbers[0].number, '+91 98765 43210');
      expect(result.phoneNumbers[0].label, 'Mobile');
      expect(result.phoneNumbers[1].number, '+91 44 2345 6789');
      expect(result.phoneNumbers[1].label, 'Office');
    });

    test('TEST 3: Two email addresses', () {
      const text = '''
John Mathew
CEO
Global Tech
Work: john@globaltech.com
Personal: john.mathew@gmail.com
+1 415 555 0123
''';
      final result = parser.parse(text);

      expect(result.emailAddresses.length, 2);
      expect(result.emailAddresses[0].email, 'john@globaltech.com');
      expect(result.emailAddresses[0].label, 'Work');
      expect(result.emailAddresses[1].email, 'john.mathew@gmail.com');
      expect(result.emailAddresses[1].label, 'Personal');
    });

    test('TEST 4: Two phones + two emails', () {
      const text = '''
Priya Sharma
Sales Manager
Solutions Inc
Mobile: +91 98765 43210
Office: 044 2345 6789
Work: priya@solutions.com
Personal: priya.sharma@yahoo.com
''';
      final result = parser.parse(text);

      expect(result.phoneNumbers.length, 2);
      expect(result.phoneNumbers[0].number, '+91 98765 43210');
      expect(result.phoneNumbers[1].number, '044 2345 6789');

      expect(result.emailAddresses.length, 2);
      expect(result.emailAddresses[0].email, 'priya@solutions.com');
      expect(result.emailAddresses[1].email, 'priya.sharma@yahoo.com');
    });

    test('TEST 5: Indian phone format', () {
      const formats = '''
Card 1
+91 98765 43210
+91-98765-43210
+91 (98765) 43210
9876543210
''';
      final result = parser.parse(formats);

      // Duplicate representation check should deduplicate numbers pointing to the same Indian mobile subscriber
      expect(result.phoneNumbers.isNotEmpty, isTrue);
      expect(result.phoneNumbers.first.number, contains('98765'));
    });

    test('TEST 6: International phone format', () {
      const text = '''
Alex Smith
Doctor
Phone: +1 415 555 0123
Office: 044 2345 6789
alex@clinic.org
''';
      final result = parser.parse(text);

      expect(result.phoneNumbers.length, 2);
      expect(result.phoneNumbers[0].number, '+1 415 555 0123');
      expect(result.phoneNumbers[1].number, '044 2345 6789');
    });

    test('TEST 7: Duplicate phone representations', () {
      const text = '''
Rahul Kumar
Mobile: +91 98765 43210
Call: 9876543210
Alt: +91-98765-43210
''';
      final result = parser.parse(text);

      // Obvious duplicate representations of the same phone number should be consolidated
      expect(result.phoneNumbers.length, 1);
      expect(result.phoneNumbers.first.number, '+91 98765 43210');
    });

    test('TEST 8: Duplicate emails with different casing', () {
      const text = '''
Rahul Kumar
RAHUL@COMPANY.COM
rahul@company.com
Rahul@Company.com
''';
      final result = parser.parse(text);

      // Should normalize and deduplicate case-insensitively
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.normalizedEmail, 'rahul@company.com');
    });

    test('TEST 9: Website extraction', () {
      const text1 = '''
ABC Technologies
https://abc.com
''';
      final res1 = parser.parse(text1);
      expect(res1.website, 'https://abc.com');

      const text2 = '''
ABC Technologies
www.abc.com
''';
      final res2 = parser.parse(text2);
      expect(res2.website, 'www.abc.com');

      const text3 = '''
ABC Technologies
Website: abc.com
''';
      final res3 = parser.parse(text3);
      expect(res3.website, 'abc.com');
    });

    test('TEST 10: Email domain must not automatically become website', () {
      const text = '''
Rahul Kumar
Senior Developer
ABC Technologies
rahul@company.com
''';
      final result = parser.parse(text);

      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'rahul@company.com');
      // Must NOT extract company.com as website simply because it is an email domain
      expect(result.website, isNull);
    });

    test('TEST 11: No email', () {
      const text = '''
Rahul Kumar
Senior Developer
ABC Technologies
Mobile: +91 98765 43210
''';
      final result = parser.parse(text);

      expect(result.emailAddresses, isEmpty);
      expect(result.phoneNumbers.length, 1);
      expect(result.fullName, 'Rahul Kumar');
      expect(result.company, 'ABC Technologies');
    });

    test('TEST 12: No phone', () {
      const text = '''
Rahul Kumar
Senior Developer
ABC Technologies
rahul@company.com
''';
      final result = parser.parse(text);

      expect(result.phoneNumbers, isEmpty);
      expect(result.emailAddresses.length, 1);
      expect(result.fullName, 'Rahul Kumar');
      expect(result.company, 'ABC Technologies');
    });

    test('TEST 13: No phone or email but valid name/company text', () {
      const text = '''
Rahul Kumar
Senior Developer
ABC Technologies
''';
      final result = parser.parse(text);

      expect(result.phoneNumbers, isEmpty);
      expect(result.emailAddresses, isEmpty);
      expect(result.fullName, 'Rahul Kumar');
      expect(result.jobTitle, 'Senior Developer');
      expect(result.company, 'ABC Technologies');
    });

    test('TEST 14: Empty OCR result', () {
      final res1 = parser.parse('');
      expect(res1.fullName, isNull);
      expect(res1.company, isNull);
      expect(res1.jobTitle, isNull);
      expect(res1.phoneNumbers, isEmpty);
      expect(res1.emailAddresses, isEmpty);
      expect(res1.website, isNull);
      expect(res1.address, isNull);

      final res2 = parser.parse('   \n\n   ');
      expect(res2.fullName, isNull);
      expect(res2.phoneNumbers, isEmpty);
    });

    test('TEST 15: Noisy OCR text containing unrelated numbers', () {
      const text = '''
Acme Services
Building 42, Floor 4
PIN: 600001
Reg No: 123456
CIN: U12345MH2020PTC123456
GSTIN: 33AAAAA0000A1Z5
Invoice 98765
Phone: +91 98765 43210
''';
      final result = parser.parse(text);

      // Only the real phone number should be extracted, not the postal PIN or registration numbers
      expect(result.phoneNumbers.length, 1);
      expect(result.phoneNumbers.first.number, '+91 98765 43210');
    });

    test('TEST 16: Card containing name/company/job title', () {
      const text = '''
Rahul Kumar
Senior Developer
ABC Technologies
Mobile: +91 98765 43210
rahul@company.com
www.company.com
Chennai, Tamil Nadu
''';
      final result = parser.parse(text);

      expect(result.fullName, 'Rahul Kumar');
      expect(result.jobTitle, 'Senior Developer');
      expect(result.company, 'ABC Technologies');
      expect(result.phoneNumbers.length, 1);
      expect(result.emailAddresses.length, 1);
      expect(result.website, 'www.company.com');
      expect(result.address, contains('Chennai'));
    });
  });

  group('Physical Business Card Email OCR Bug Fix Tests (20 Cases)', () {
    test('1. denil@gmail.com', () {
      const text = '''
Denil Varghese Samuvel
Python Developer
NovaTechify
denil@gmail.com
Phone: 7975752452
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'denil@gmail.com');
      expect(result.emailAddresses.first.normalizedEmail, 'denil@gmail.com');
      expect(result.fullName, 'Denil Varghese Samuvel');
      expect(result.company, 'NovaTechify');
    });

    test('2. DENIL@GMAIL.COM (case-insensitive extraction and normalization)', () {
      const text = '''
DENIL VARGHESE
NovaTechify
DENIL@GMAIL.COM
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'DENIL@GMAIL.COM');
      expect(result.emailAddresses.first.normalizedEmail, 'denil@gmail.com');
    });

    test('3. denil.sam@gmail.com (dot in local-part)', () {
      const text = '''
Denil Sam
Software Engineer
denil.sam@gmail.com
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'denil.sam@gmail.com');
    });

    test('4. denil_sam@gmail.com (underscore in local-part)', () {
      const text = '''
Denil Sam
Python Developer
denil_sam@gmail.com
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'denil_sam@gmail.com');
    });

    test('5. denil-sam@company.com (hyphen in local-part)', () {
      const text = '''
Denil Sam
Consultant
denil-sam@company.com
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'denil-sam@company.com');
    });

    test('6. denil+work@example.com (plus in local-part)', () {
      const text = '''
Denil Sam
Solutions Inc
denil+work@example.com
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'denil+work@example.com');
    });

    test('7. contact@company.co.in (multi-segment ccTLD)', () {
      const text = '''
NovaTechify
contact@company.co.in
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'contact@company.co.in');
    });

    test('8. support@subdomain.company.com (subdomain email)', () {
      const text = '''
NovaTechify Support
support@subdomain.company.com
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'support@subdomain.company.com');
    });

    test('9. Email: denil@gmail.com (Email: label stripped from address)', () {
      const text = '''
Denil Samuvel
Email: denil@gmail.com
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'denil@gmail.com');
    });

    test('10. E-mail: denil@gmail.com (E-mail: label stripped from address)', () {
      const text = '''
Denil Samuvel
E-mail: denil@gmail.com
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'denil@gmail.com');
    });

    test('11. denil @ gmail.com (spaces around @)', () {
      const text = '''
Denil Varghese Samuvel
Python Developer
NovaTechify
denil @ gmail.com
Phone: 7975752452
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'denil@gmail.com');
    });

    test('12. denil@gmail .com (space before dot in domain)', () {
      const text = '''
Denil Samuvel
denil@gmail .com
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'denil@gmail.com');
    });

    test('13. denil @ gmail . com (spaces around @ and dot)', () {
      const text = '''
Denil Varghese Samuvel
Python Developer
NovaTechify
denil @ gmail . com
7975752452
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'denil@gmail.com');
    });

    test('14. email surrounded by punctuation (<email>, [email], quotes, trailing dot)', () {
      const text1 = '''
Denil Samuvel
<denil@gmail.com>
''';
      final res1 = parser.parse(text1);
      expect(res1.emailAddresses.length, 1);
      expect(res1.emailAddresses.first.email, 'denil@gmail.com');

      const text2 = '''
Denil Samuvel
(denil.sam@gmail.com)
''';
      final res2 = parser.parse(text2);
      expect(res2.emailAddresses.length, 1);
      expect(res2.emailAddresses.first.email, 'denil.sam@gmail.com');

      const text3 = '''
Contact us at "denil@gmail.com".
''';
      final res3 = parser.parse(text3);
      expect(res3.emailAddresses.length, 1);
      expect(res3.emailAddresses.first.email, 'denil@gmail.com');
    });

    test('15. two emails on one card (Personal and Work)', () {
      const text = '''
Denil Varghese Samuvel
NovaTechify
Personal: denil@gmail.com
Work: denil@novatechify.com
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 2);
      expect(result.emailAddresses.any((e) => e.email == 'denil@gmail.com' && e.label == 'Personal'), isTrue);
      expect(result.emailAddresses.any((e) => e.email == 'denil@novatechify.com' && e.label == 'Work'), isTrue);
    });

    test('16. duplicate email with different case (deduplicated)', () {
      const text = '''
Denil Samuvel
denil@gmail.com
DENIL@GMAIL.COM
Denil@Gmail.com
''';
      final result = parser.parse(text);
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.normalizedEmail, 'denil@gmail.com');
    });

    test('17. split email OCR elements where safely reconstructable', () {
      // Split element variant A: Line 1 = local-part, Line 2 = @, Line 3 = domain
      const text1 = '''
Denil Samuvel
Python Developer
denil.sam
@
gmail.com
Phone: 7975752452
''';
      final res1 = parser.parse(text1);
      expect(res1.emailAddresses.length, 1);
      expect(res1.emailAddresses.first.email, 'denil.sam@gmail.com');

      // Split element variant B: Line 1 = local-part@, Line 2 = domain
      const text2 = '''
Denil Samuvel
denil.sam@
gmail.com
''';
      final res2 = parser.parse(text2);
      expect(res2.emailAddresses.length, 1);
      expect(res2.emailAddresses.first.email, 'denil.sam@gmail.com');

      // Split element variant C: Line 1 = local-part, Line 2 = @domain
      const text3 = '''
Denil Samuvel
denilsam3394
@gmail.com
''';
      final res3 = parser.parse(text3);
      expect(res3.emailAddresses.length, 1);
      expect(res3.emailAddresses.first.email, 'denilsam3394@gmail.com');
    });

    test('18. text containing @ that is not a valid email', () {
      const text = '''
NovaTechify Technologies
Follow us @novatechify
Meeting @ 5pm
Buy 2 items @ \$10
''';
      final result = parser.parse(text);
      expect(result.emailAddresses, isEmpty);
    });

    test('19. website URL is not treated as email', () {
      const text = '''
Denil Samuvel
NovaTechify
https://novatechify.com
www.novatechify.com
''';
      final result = parser.parse(text);
      expect(result.emailAddresses, isEmpty);
      expect(result.website, isNotNull);
    });

    test('20. company/name do not generate an inferred email', () {
      const text = '''
Denil Varghese Samuvel
Python Developer
NovaTechify
novatechify.com
7975752452
''';
      final result = parser.parse(text);
      // Under no circumstances should denil@novatechify.com be inferred
      expect(result.emailAddresses, isEmpty);
      expect(result.fullName, 'Denil Varghese Samuvel');
      expect(result.company, 'NovaTechify');
      expect(result.jobTitle, 'Python Developer');
    });

    test('Real physical card test case: NovaTechify card with denilsam3394@gmail.com', () {
      const text = '''
NovaTechify
Denil Varghese Samuvel
Python Developer
7975752452
denilsam3394 @ gmail.com
''';
      final result = parser.parse(text);
      expect(result.fullName, 'Denil Varghese Samuvel');
      expect(result.jobTitle, 'Python Developer');
      expect(result.company, 'NovaTechify');
      expect(result.phoneNumbers.length, 1);
      expect(result.phoneNumbers.first.number, contains('7975752452'));
      expect(result.emailAddresses.length, 1);
      expect(result.emailAddresses.first.email, 'denilsam3394@gmail.com');
    });
  });
}
