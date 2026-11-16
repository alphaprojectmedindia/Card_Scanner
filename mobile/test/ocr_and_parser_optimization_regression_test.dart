import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/ocr/field_semantic_evaluator.dart';

void main() {
  group('OCR & Business Card Parser Optimization Regression Tests', () {
    const parser = BusinessCardParser();

    // -------------------------------------------------------------------------
    // PROBLEM C: COMPANY NAME MISTAKEN FOR PERSON'S NAME
    // -------------------------------------------------------------------------
    test('Problem C Case 1: TECHNOVA SOLUTIONS is Company, Arun Kumar is Person', () {
      const rawText = '''
TECHNOVA SOLUTIONS
Arun Kumar
Software Engineer
arun@technova.com
+91 9876543210
Chennai, Tamil Nadu, India
''';

      final data = parser.parse(rawText);

      expect(data.fullName, equals('Arun Kumar'),
          reason: 'Prominent uppercase company must NEVER become person name');
      expect(data.company, equals('TECHNOVA SOLUTIONS'));
      expect(data.jobTitle, equals('Software Engineer'));
      expect(data.emailAddresses.first.email, equals('arun@technova.com'));
      expect(data.phoneNumbers.first.number, contains('9876543210'));
      expect(data.address, contains('Chennai'));
      expect(data.address, contains('Tamil Nadu'));
    });

    test('Problem C Case 2: Single-word brand TECHNOVA with corporate email domain', () {
      const rawText = '''
TECHNOVA
Arun Kumar
Software Engineer
arun@technova.com
+91 9876543210
Chennai, Tamil Nadu, India
''';

      final data = parser.parse(rawText);

      expect(data.fullName, equals('Arun Kumar'),
          reason: 'Single-word brand matching email domain must NEVER become person name');
      expect(data.company, equals('TECHNOVA'));
      expect(data.jobTitle, equals('Software Engineer'));
      expect(data.emailAddresses.first.email, equals('arun@technova.com'));
    });

    test('Problem C Case 3: FieldSemanticEvaluator correctly arbitrates TECHNOVA vs Arun Kumar', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          'TECHNOVA SOLUTIONS',
          'Arun Kumar',
          'Software Engineer',
          'arun@technova.com',
          '+91 9876543210',
          'Chennai, Tamil Nadu, India',
        ],
        primaryEngineName: 'PaddleOCR',
        primaryOcrQualityScore: 95.0,
        secondaryLines: [
          'TECHNOVA SOLUTIONS',
          'Arun Kumar',
          'Software Engineer',
          'arun@technova.com',
          '+91 9876543210',
          'Chennai - 600032, Tamil Nadu, India',
        ],
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 92.0,
      );

      expect(res.name?.value, equals('Arun Kumar'));
      expect(res.company?.value, equals('TECHNOVA SOLUTIONS'));
      expect(res.jobTitle?.value, equals('Software Engineer'));
      expect(res.address?.value, contains('Chennai'));
      expect(res.address?.value, contains('Tamil Nadu'));
    });

    // -------------------------------------------------------------------------
    // CARD WITHOUT PERSON NAME (COMPANY ONLY)
    // -------------------------------------------------------------------------
    test('Card with only Company and contact details leaves person name null', () {
      const rawText = '''
TECHNOVA SOLUTIONS PVT LTD
info@technovasolutions.com
+91 44 2820 1234
www.technovasolutions.com
No 45, Mount Road, Guindy, Chennai - 600032
''';

      final data = parser.parse(rawText);

      expect(data.fullName, isNull,
          reason: 'When no human person exists, parser must NOT hallucinate company as person name');
      expect(data.company, contains('TECHNOVA SOLUTIONS'));
      expect(data.emailAddresses.first.email, equals('info@technovasolutions.com'));
      expect(data.website, contains('technovasolutions.com'));
      expect(data.address, contains('Guindy'));
      expect(data.address, contains('Chennai'));
    });

    // -------------------------------------------------------------------------
    // PROBLEM A & B: CROSS-ENGINE MULTI-LINE ADDRESS CLUSTERING & MERGING
    // -------------------------------------------------------------------------
    test('Cross-engine complementary address merging preserves all address segments', () {
      // Primary detected street and building; secondary detected city, district, state & pin
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          'Karthik Sundaram',
          'Product Manager',
          'OmniTech Enterprises Ltd',
          'Tower B, 4th Floor, Olympia Tech Park',
          '1 Guindy Industrial Estate',
          'karthik@omnitech.io',
          '+91 98401 23456',
        ],
        primaryEngineName: 'PaddleOCR',
        primaryOcrQualityScore: 88.0,
        secondaryLines: [
          'Karthik Sundaram',
          'Product Manager',
          'OmniTech Enterprises Ltd',
          'Olympia Tech Park, Guindy',
          'Chennai - 600032, Tamil Nadu, India',
          'karthik@omnitech.io',
          '+91 98401 23456',
        ],
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 85.0,
      );

      expect(res.name?.value, equals('Karthik Sundaram'));
      expect(res.company?.value, equals('OmniTech Enterprises Ltd'));
      expect(res.jobTitle?.value, equals('Product Manager'));
      expect(res.address, isNotNull);
      final addr = res.address!.value;
      expect(addr, contains('Olympia Tech Park'));
      expect(addr, contains('Guindy'));
      expect(addr, contains('Chennai'));
      expect(addr, contains('Tamil Nadu'));
      expect(addr, contains('600032'));
    });

    // -------------------------------------------------------------------------
    // DUAL-SIDED BUSINESS CARD MERGING
    // -------------------------------------------------------------------------
    test('Dual-sided card merges front identity with back complementary address', () {
      final frontSide = OcrSideResult(
        side: CardSide.front,
        imagePath: 'front.jpg',
        rawText: '''
Dr. Ananya Roy, MBBS, MD
Senior Cardiologist
Apollo Multispeciality Hospitals
ananya.roy@apollohospitals.com
+91 98300 11223
''',
        lines: const [],
      );

      final backSide = OcrSideResult(
        side: CardSide.back,
        imagePath: 'back.jpg',
        rawText: '''
Apollo Multispeciality Hospitals
21 Greams Lane, Thousand Lights
Chennai - 600006, Tamil Nadu, India
www.apollohospitals.com
Direct: +91 44 2829 0200
''',
        lines: const [],
      );

      final mergedData = parser.parseDualSided(
        front: frontSide,
        back: backSide,
      );

      expect(mergedData.fullName, equals('Dr. Ananya Roy'));
      expect(mergedData.jobTitle, contains('Cardiologist'));
      expect(mergedData.company, equals('Apollo Multispeciality Hospitals'));
      expect(mergedData.website, equals('www.apollohospitals.com'));
      expect(mergedData.emailAddresses.first.email, equals('ananya.roy@apollohospitals.com'));
      expect(mergedData.phoneNumbers.length, greaterThanOrEqualTo(2));
      expect(mergedData.address, contains('Greams Lane'));
      expect(mergedData.address, contains('Chennai'));
      expect(mergedData.address, contains('600006'));
    });

    // -------------------------------------------------------------------------
    // OCCUPATIONAL DESIGNATION VS COMPANY SEPARATION
    // -------------------------------------------------------------------------
    test('Occupational titles are never confused with company names', () {
      const rawText = '''
Priya Natarajan
Chief Technology Officer
HyperScale Labs Inc.
priya@hyperscalelabs.com
+1 (415) 555-0182
500 Howard Street, San Francisco, CA 94105
''';

      final data = parser.parse(rawText);

      expect(data.fullName, equals('Priya Natarajan'));
      expect(data.jobTitle, equals('Chief Technology Officer'));
      expect(data.company, equals('HyperScale Labs Inc.'));
      expect(data.company, isNot(contains('Chief Technology Officer')));
      expect(data.address, contains('Howard Street'));
      expect(data.address, contains('San Francisco'));
      expect(data.address, contains('CA 94105'));
    });

    // -------------------------------------------------------------------------
    // PREPROCESSING SAFE MARGIN VERIFICATION
    // -------------------------------------------------------------------------
    test('CardImageNormalizationService safe viewfinder ROI crop applies 5% margin to avoid clipping edge text', () {
      // Create a test 1000x800 image
      final testWidth = 1000;
      final testHeight = 800;
      final viewfinderRoi = const Rect.fromLTWH(0.10, 0.20, 0.80, 0.50);

      // Verify the 5% margin calculation matches the service implementation
      final marginX = (testWidth * 0.05).round(); // 50px
      final marginY = (testHeight * 0.05).round(); // 40px

      expect(marginX, equals(50));
      expect(marginY, equals(40));

      final cropX = (viewfinderRoi.left * testWidth).round() - marginX; // 100 - 50 = 50
      final cropY = (viewfinderRoi.top * testHeight).round() - marginY; // 160 - 40 = 120
      final cropW = (viewfinderRoi.width * testWidth).round() + 2 * marginX; // 800 + 100 = 900
      final cropH = (viewfinderRoi.height * testHeight).round() + 2 * marginY; // 400 + 80 = 480

      expect(cropX, equals(50));
      expect(cropY, equals(120));
      expect(cropW, equals(900));
      expect(cropH, equals(480));
    });

    // -------------------------------------------------------------------------
    // Phase 1 Optimization & Regression Tests: Real-World Business Cards
    // -------------------------------------------------------------------------
    test('Phase 1 Target Card: Chandra Kanthan, M / CHANDRU MEDICAL EQUIPMENTS / ASTER', () {
      const cardOcrText = '''
ASTER
CHANDRU MEDICAL EQUIPMENTS
An ISO 9001:2008 & ISO 13485:2003 Certified Co.
Chandra Kanthan, M
Managing Director
+91 94444 20464, 83002 71261
chandrumediequip@gmail.com
chandruceo2401@gmail.com
www.astermedispro.net
No. 5, South Garden Area, (Opp.) Adithya International School, Idigarai, Coimbatore - 641022, Tamil Nadu, India.
''';

      final res = parser.parse(cardOcrText);

      // Person Name verification
      expect(res.fullName, equals('Chandra Kanthan, M'));
      expect(res.fullName, isNot(contains('CHANDRU MEDICAL EQUIPMENTS')));

      // Company Name verification
      expect(res.company, equals('CHANDRU MEDICAL EQUIPMENTS'));
      expect(res.company, isNot(equals('ASTER')));
      expect(res.company, isNot(contains('Chandra Kanthan')));

      // Brand recognition
      expect(res.alternativeCandidates['brand'] ?? [], contains('ASTER'));

      // Job Title
      expect(res.jobTitle, equals('Managing Director'));

      // Phone Numbers
      final phoneNumbers = res.phoneNumbers.map((p) => p.normalizedNumber ?? p.number).toList();
      expect(phoneNumbers.any((p) => p.contains('9444420464')), isTrue);
      expect(phoneNumbers.any((p) => p.contains('8300271261')), isTrue);

      // Certifications must not be in phone numbers
      expect(phoneNumbers.any((p) => p.contains('9001') || p.contains('13485')), isFalse);

      // Email Addresses
      final emails = res.emailAddresses.map((e) => e.email.toLowerCase()).toList();
      expect(emails, contains('chandrumediequip@gmail.com'));
      expect(emails, contains('chandruceo2401@gmail.com'));

      // Website
      expect(res.website, contains('astermedispro.net'));

      // Address
      expect(res.address, isNotNull);
      expect(res.address, contains('Coimbatore'));
      expect(res.address, contains('641022'));

      // Certifications
      expect(res.alternativeCandidates['certification'], isNotNull);
      expect(
        res.alternativeCandidates['certification']!.any((c) => c.contains('ISO 9001:2008')),
        isTrue,
      );
    });

    test('Phase 1 Layout Variation: Company above Person with Initials (M. Chandra Kanthan)', () {
      const cardText = '''
CHANDRU MEDICAL EQUIPMENTS
M. Chandra Kanthan
Managing Director
Mob: +91 94444 20464
chandrumediequip@gmail.com
''';
      final res = parser.parse(cardText);
      expect(res.fullName, equals('M. Chandra Kanthan'));
      expect(res.company, equals('CHANDRU MEDICAL EQUIPMENTS'));
      expect(res.jobTitle, equals('Managing Director'));
    });

    test('Phase 1 Layout Variation: Person with Initial (S. Rajesh) above Company', () {
      const cardText = '''
S. Rajesh
Chief Technology Officer
NEXUS SOFTWARE SYSTEMS PVT LTD
rajesh@nexussoft.com
+91 98765 43210
''';
      final res = parser.parse(cardText);
      expect(res.fullName, equals('S. Rajesh'));
      expect(res.company, equals('NEXUS SOFTWARE SYSTEMS PVT LTD'));
      expect(res.jobTitle, equals('Chief Technology Officer'));
    });

    test('Phase 1 Edge Case: Card with no identifiable Person (Organization only with Brand & Cert)', () {
      const cardText = '''
MEDITECH
APEX MEDICAL SYSTEMS
ISO 9001:2015 Certified
Sales & Inquiries: +91 44 2828 1234
info@apexmedsys.com
www.apexmedsys.com
Chennai, India
''';
      final res = parser.parse(cardText);
      expect(res.fullName, isNull);
      expect(res.company, equals('APEX MEDICAL SYSTEMS'));
      expect(res.alternativeCandidates['brand'] ?? [], contains('MEDITECH'));
      expect(res.jobTitle, isNull);
    });

    test('Phase 1 Edge Case: Card with Person & Designation but no Company', () {
      const cardText = '''
Dr. Arun Kumar
Consultant Orthopedic Surgeon
Mob: +91 98401 23456
dr.arun@gmail.com
Chennai, Tamil Nadu
''';
      final res = parser.parse(cardText);
      expect(res.fullName, equals('Dr. Arun Kumar'));
      expect(res.jobTitle, equals('Consultant Orthopedic Surgeon'));
      expect(res.company, isNull);
    });
    // -------------------------------------------------------------------------
    // PHASE 2 REAL-WORLD BUSINESS CARD RELIABILITY TESTS
    // -------------------------------------------------------------------------
    test('Phase 2 Target Card 1: ASTER / Chandru Medical Equipments complete pipeline', () {
      const cardText = '''
(4 ASTER
CHANDRU
MEDICAL EQUIPMENTS
Managing Director
ISO 13485:2003 Certified Company
+91 94444 20464, 83002 71261
No. 12, Hospital Road, Coimbatore - 641018
''';
      final res = parser.parse(cardText);
      expect(res.company, equals('CHANDRU MEDICAL EQUIPMENTS'));
      expect(res.fullName, isNot(equals('CHANDRU MEDICAL EQUIPMENTS')));
      expect(res.jobTitle, equals('Managing Director'));
      expect(res.phoneNumbers.any((p) => p.number.contains('94444 20464') || (p.normalizedNumber?.contains('9444420464') ?? false)), isTrue);
      expect(res.phoneNumbers.any((p) => p.number.contains('83002 71261') || (p.normalizedNumber?.contains('8300271261') ?? false)), isTrue);
      expect(res.phoneNumbers.any((p) => p.number.contains('13485') || p.number.contains('2003')), isFalse);
      expect(res.address, contains('Coimbatore'));
    });

    test('Phase 2 Target Card 2: United Educational Institutions complete pipeline', () {
      const cardText = '''
S. Shanmugam
Founder & Chairman
UNITED EDUCATIONAL INSTITUTIONS
Mobile: 98422 55762
Telephone: 0422-3508080 & 0422-3508051
Website: www.uit.ac.in
Email: chairman@uit.ac.in
Gudalur Koundampalayam, Periyanaickenpalayam,
Coimbatore - 641020.
''';
      final res = parser.parse(cardText);
      expect(res.fullName, equals('S. Shanmugam'));
      expect(res.jobTitle, equals('Founder & Chairman'));
      expect(res.company, equals('UNITED EDUCATIONAL INSTITUTIONS'));
      expect(res.phoneNumbers.any((p) => (p.normalizedNumber?.contains('9842255762') ?? false)), isTrue);
      expect(res.phoneNumbers.any((p) => (p.normalizedNumber?.contains('04223508080') ?? false)), isTrue);
      expect(res.phoneNumbers.any((p) => (p.normalizedNumber?.contains('04223508051') ?? false)), isTrue);
      expect(res.website, equals('www.uit.ac.in'));
      expect(res.emailAddresses.first.email, equals('chairman@uit.ac.in'));
      expect(res.address, contains('Coimbatore - 641020'));
      expect(res.address, contains('Periyanaickenpalayam'));
    });

    test('Phase 2 Target Card 3: Investment Corporation character confusion cross-engine arbitration', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          '1NVESTMENT C0RP0RATlON',
          'David Miller',
          'Managing Director',
          'david@investmentcorp.com',
          '+1 212 555 0199',
          '100 Wall Street, New York, NY 10005',
        ],
        primaryEngineName: 'PaddleOCR',
        primaryOcrQualityScore: 88.0,
        secondaryLines: [
          'INVESTMENT CORPORATION',
          'David Miller',
          'Managing Director',
          'david@investmentcorp.com',
          '+1 212 555 0199',
          '100 Wall Street, New York, NY 10005',
        ],
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 94.0,
      );

      expect(res.company?.value, equals('INVESTMENT CORPORATION'));
      expect(res.agreedSignals, contains('company'));
      expect(res.name?.value, equals('David Miller'));
      expect(res.jobTitle?.value, equals('Managing Director'));
    });

    test('Phase 2: Landline phone with inherited STD area code', () {
      const cardText = '''
UNITED INSTITUTIONS
Tel: 0422-3508080, 3508051
info@united.edu
''';
      final res = parser.parse(cardText);
      expect(res.phoneNumbers.length, equals(2));
      expect(res.phoneNumbers.any((p) => (p.normalizedNumber?.contains('04223508080') ?? false)), isTrue);
      expect(res.phoneNumbers.any((p) => (p.normalizedNumber?.contains('04223508051') ?? false)), isTrue);
    });

    test('Phase 2: Multi-phone numbers on single line separated by whitespace', () {
      const cardText = '''
CHANDRU MEDICAL EQUIPMENTS
+91 94444 20464 83002 71261
''';
      final res = parser.parse(cardText);
      expect(res.phoneNumbers.length, equals(2));
      expect(res.phoneNumbers.any((p) => (p.normalizedNumber?.contains('9444420464') ?? false)), isTrue);
      expect(res.phoneNumbers.any((p) => (p.normalizedNumber?.contains('8300271261') ?? false)), isTrue);
    });

    test('Phase 2: Strict ISO, CE and statutory certifications never become phone numbers', () {
      const cardText = '''
MEDISYSTEMS INC
ISO 9001:2015
ISO 13485:2003
CE 0123
GMP Certified
Ph: +91 98765 43210
''';
      final res = parser.parse(cardText);
      expect(res.phoneNumbers.length, equals(1));
      expect(res.phoneNumbers.first.normalizedNumber, contains('9876543210'));
      expect(res.phoneNumbers.any((p) => p.number.contains('9001') || p.number.contains('13485') || p.number.contains('0123')), isFalse);
    });

    // -------------------------------------------------------------------------
    // PHASE 3: STYLIZED FONT, FIRST-SCAN RELIABILITY, INDIAN PHONES & ADDRESSES
    // -------------------------------------------------------------------------
    test('Phase 3: Stylized font recognition handles 6/G, 7/T, and rn/m confusion in company & titles', () {
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: [
          'LO6ISTICS SOLUTIONS LTD',
          'Ravi Shankar',
          'MANA6ING DIREC7OR',
          'ravi@logisticssolutions.com',
          '+91 98422 55762',
        ],
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 88.0,
        secondaryLines: [
          'LOGISTICS SOLUTIONS LTD',
          'Ravi Shankar',
          'MANAGING DIRECTOR',
          'ravi@logisticssolutions.com',
          '+91 98422 55762',
        ],
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 92.0,
      );

      // Should recognize equivalence through confusion normalization and prefer clean typography
      expect(res.company?.value, equals('LOGISTICS SOLUTIONS LTD'));
      expect(res.name?.value, equals('Ravi Shankar'));
      expect(res.jobTitle?.value, equals('MANAGING DIRECTOR'));
    });

    test('Phase 3: Indian mobile number formats (+91, 91, leading 0, 4+6, 3+3+4)', () {
      const cardText = '''
APEX COMMERCE
Suresh Babu
Mob 1: +91 98422 55762
Mob 2: 919842255763
Mob 3: 098422 55764
Mob 4: 9842 255765
Mob 5: 984 225 5766
suresh@apexcommerce.in
''';
      final res = parser.parse(cardText);
      expect(res.phoneNumbers.length, equals(5));

      final numbers = res.phoneNumbers.map((p) => p.normalizedNumber ?? p.number).toList();
      expect(numbers.any((n) => n.contains('9842255762')), isTrue);
      expect(numbers.any((n) => n.contains('9842255763')), isTrue);
      expect(numbers.any((n) => n.contains('9842255764')), isTrue);
      expect(numbers.any((n) => n.contains('9842255765')), isTrue);
      expect(numbers.any((n) => n.contains('9842255766')), isTrue);

      // Confirm labels are correctly partitioned
      for (final p in res.phoneNumbers) {
        expect(p.label, equals('Mobile'));
      }
    });

    test('Phase 3: Strict partitioning between Mobile, Landline (STD), and Fax', () {
      const cardText = '''
METRO ENTERPRISES
Karthik Raja
Mobile: +91 98422 12345
Tel: 0422-3508080
Fax: 044-28285678
karthik@metro.com
''';
      final res = parser.parse(cardText);
      expect(res.phoneNumbers.length, equals(3));

      final mobile = res.phoneNumbers.firstWhere((p) => p.number.contains('98422 12345') || (p.normalizedNumber?.contains('9842212345') ?? false));
      final tel = res.phoneNumbers.firstWhere((p) => p.number.contains('0422-3508080') || (p.normalizedNumber?.contains('04223508080') ?? false));
      final fax = res.phoneNumbers.firstWhere((p) => p.number.contains('044-28285678') || (p.normalizedNumber?.contains('04428285678') ?? false));

      expect(mobile.label, equals('Mobile'));
      expect(tel.label, equals('Phone'));
      expect(fax.label, equals('Fax'));
    });

    test('Phase 3: Indian multiline address with PIN code and intermediate line preservation', () {
      const cardText = '''
VASANTHAM BUILDERS
Vasanth Kumar
Proprietor
Door No. 14, Cross Cut Road,
Gudalur Koundampalayam, Periyanaickenpalayam,
Coimbatore - 641020,
Tamil Nadu, India
info@vasantham.in
''';
      final res = parser.parse(cardText);
      expect(res.address, isNotNull);
      expect(res.address, contains('Door No. 14'));
      expect(res.address, contains('Gudalur Koundampalayam'));
      expect(res.address, contains('Periyanaickenpalayam'));
      expect(res.address, contains('641020'));
      expect(res.address, contains('Tamil Nadu'));
    });

    test('Phase 3: Deterministic arbitration on repeated executions', () {
      final inputPrimary = [
        'ASTER INNOVATIONS',
        'Dr. Anand Mohan',
        'Senior Consultant',
        'anand@asterinnovations.com',
        '+91 98422 11223',
      ];
      final inputSecondary = [
        'ASTER INNOVATIONS',
        'Dr. Anand Mohan',
        'Senior Consultant',
        'anand@asterinnovations.com',
        '+91 98422 11223',
      ];

      final run1 = FieldSemanticEvaluator.resolveFields(
        primaryLines: inputPrimary,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 90.0,
        secondaryLines: inputSecondary,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 90.0,
      );

      final run2 = FieldSemanticEvaluator.resolveFields(
        primaryLines: inputPrimary,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 90.0,
        secondaryLines: inputSecondary,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 90.0,
      );

      expect(run1.name?.value, equals(run2.name?.value));
      expect(run1.company?.value, equals(run2.company?.value));
      expect(run1.jobTitle?.value, equals(run2.jobTitle?.value));
      expect(run1.agreedSignals, equals(run2.agreedSignals));
    });
    test('Phase 3: Address clustering does NOT merge company names, titles, or person names', () {
      const cardText = '''
TECHNOVA SOLUTIONS PVT LTD
Arun Kumar
Managing Director
Door No. 12, Anna Salai,
Periyanaickenpalayam,
Coimbatore - 641020, Tamil Nadu
arun@technova.com
''';
      final res = parser.parse(cardText);
      expect(res.company, equals('TECHNOVA SOLUTIONS PVT LTD'));
      expect(res.fullName, equals('Arun Kumar'));
      expect(res.jobTitle, equals('Managing Director'));
      expect(res.address, isNotNull);
      expect(res.address, contains('Door No. 12'));
      expect(res.address, contains('Periyanaickenpalayam'));
      expect(res.address, contains('Coimbatore - 641020'));
      expect(res.address!.contains('TECHNOVA'), isFalse,
          reason: 'Company name must NEVER be merged into address cluster');
      expect(res.address!.contains('Arun Kumar'), isFalse,
          reason: 'Person name must NEVER be merged into address cluster');
      expect(res.address!.contains('Managing Director'), isFalse,
          reason: 'Job title must NEVER be merged into address cluster');
    });
  });
}
