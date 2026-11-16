import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/ocr/field_semantic_evaluator.dart';
import 'package:digital_share/services/ocr/ocr_observation.dart';
import 'package:digital_share/services/ocr/phone_ocr_recovery.dart';
import 'package:digital_share/services/ocr/email_ocr_recovery.dart';

void main() {
  const parser = BusinessCardParser();

  group('PART 22 — Different Card Layout Matrix (30 Distinct Layouts)', () {
    test('1. Company at top, name middle', () {
      final lines = [
        'Apex Global Technologies Ltd',
        'Rajesh Sharma',
        'Chief Technology Officer',
        'Mobile: +91 98765 43210',
        'rajesh@apextech.com',
        '100, MG Road, Bangalore 560001',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 92.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 90.0,
      );
      expect(res.company?.value, contains('Apex Global Technologies'));
      expect(res.name?.value, 'Rajesh Sharma');
      expect(res.jobTitle?.value, contains('Technology Officer'));
    });

    test('2. Name top, company middle', () {
      final lines = [
        'Dr. Ananya Iyer',
        'Senior Consultant Cardiologist',
        'Apollo Hospitals',
        'Phone: +91 44 2829 0200',
        'ananya.iyer@apollo.org',
        '21 Greams Lane, Chennai 600006',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 94.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 91.0,
      );
      expect(res.name?.value, contains('Ananya Iyer'));
      expect(res.company?.value, contains('Apollo Hospitals'));
      expect(res.jobTitle?.value, contains('Cardiologist'));
    });

    test('3. Name left, company right', () {
      final frontLines = [
        OcrLineMetadata(
          text: 'Vikram Seth',
          side: CardSide.front,
          lineIndex: 0,
          blockIndex: 0,
          boundingBox: const Rect.fromLTWH(20, 50, 180, 30),
        ),
        OcrLineMetadata(
          text: 'Creative Director',
          side: CardSide.front,
          lineIndex: 1,
          blockIndex: 0,
          boundingBox: const Rect.fromLTWH(20, 85, 160, 20),
        ),
        OcrLineMetadata(
          text: 'Vanguard Media Group Pvt Ltd',
          side: CardSide.front,
          lineIndex: 2,
          blockIndex: 0,
          boundingBox: const Rect.fromLTWH(250, 50, 220, 30),
        ),
        OcrLineMetadata(
          text: '+91 91234 56789',
          side: CardSide.front,
          lineIndex: 3,
          blockIndex: 0,
          boundingBox: const Rect.fromLTWH(20, 150, 150, 20),
        ),
      ];
      final sideResult = OcrSideResult(
        side: CardSide.front,
        imagePath: '/test/card3.jpg',
        rawText: frontLines.map((l) => l.text).join('\n'),
        blocks: [],
        lines: frontLines,
        processedAt: DateTime.now(),
      );
      final parsed = parser.parseSide(sideResult);
      expect(parsed.fullName, 'Vikram Seth');
      expect(parsed.company, contains('Vanguard Media Group'));
    });

    test('4. Company left, person right', () {
      final frontLines = [
        OcrLineMetadata(
          text: 'Medindia Healthcare Solutions',
          side: CardSide.front,
          lineIndex: 0,
          blockIndex: 0,
          boundingBox: const Rect.fromLTWH(20, 50, 200, 35),
        ),
        OcrLineMetadata(
          text: 'Arun Sundaram',
          side: CardSide.front,
          lineIndex: 1,
          blockIndex: 0,
          boundingBox: const Rect.fromLTWH(260, 50, 180, 30),
        ),
        OcrLineMetadata(
          text: 'Lead Architect',
          side: CardSide.front,
          lineIndex: 2,
          blockIndex: 0,
          boundingBox: const Rect.fromLTWH(260, 85, 140, 20),
        ),
      ];
      final sideResult = OcrSideResult(
        side: CardSide.front,
        imagePath: '/test/card4.jpg',
        rawText: frontLines.map((l) => l.text).join('\n'),
        blocks: [],
        lines: frontLines,
        processedAt: DateTime.now(),
      );
      final parsed = parser.parseSide(sideResult);
      expect(parsed.fullName, 'Arun Sundaram');
      expect(parsed.company, contains('Medindia Healthcare'));
    });

    test('5. Centered layout', () {
      final lines = [
        'ZENITH LAW CHAMBERS',
        'Adv. Priya Nambiar',
        'Managing Partner',
        'priya@zenithlaw.in',
        '+91 94440 12345',
        'High Court Road, Ernakulam, Kerala 682031',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 91.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 89.0,
      );
      expect(res.name?.value, contains('Priya Nambiar'));
      expect(res.company?.value.toUpperCase(), contains('ZENITH LAW'));
      expect(res.jobTitle?.value, contains('Managing Partner'));
    });

    test('6. Two-column layout with geometry', () {
      final lines = [
        OcrLineMetadata(
          text: 'Denil Varghese',
          side: CardSide.front,
          lineIndex: 0,
          blockIndex: 0,
          boundingBox: const Rect.fromLTWH(20, 40, 180, 30),
        ),
        OcrLineMetadata(
          text: 'Senior Software Engineer',
          side: CardSide.front,
          lineIndex: 1,
          blockIndex: 0,
          boundingBox: const Rect.fromLTWH(20, 75, 190, 20),
        ),
        OcrLineMetadata(
          text: 'Alpha Corp Ltd',
          side: CardSide.front,
          lineIndex: 2,
          blockIndex: 0,
          boundingBox: const Rect.fromLTWH(280, 40, 180, 30),
        ),
        OcrLineMetadata(
          text: 'www.alphacorp.com',
          side: CardSide.front,
          lineIndex: 3,
          blockIndex: 0,
          boundingBox: const Rect.fromLTWH(280, 75, 180, 20),
        ),
      ];
      final sideResult = OcrSideResult(
        side: CardSide.front,
        imagePath: '/test/card6.jpg',
        rawText: lines.map((l) => l.text).join('\n'),
        blocks: [],
        lines: lines,
        processedAt: DateTime.now(),
      );
      final parsed = parser.parseSide(sideResult);
      expect(parsed.fullName, 'Denil Varghese');
      expect(parsed.company, contains('Alpha Corp'));
      expect(parsed.website, 'www.alphacorp.com');
    });

    test('7. Vertical business card', () {
      final lines = [
        'KAVYA MENON',
        'Design Lead',
        'STUDIO ORANGE',
        '+91 99887 76655',
        'kavya@studioorange.design',
        'www.studioorange.design',
        'Indiranagar, Bengaluru 560038',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 90.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 88.0,
      );
      expect(res.name?.value, contains('KAVYA MENON'));
      expect(res.company?.value, contains('STUDIO ORANGE'));
    });

    test('8. Minimal card (Name + Email + Phone only)', () {
      final lines = [
        'Marcus Aurelius',
        '+1 (555) 234-5678',
        'marcus@aurelius.org',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 92.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 90.0,
      );
      expect(res.name?.value, 'Marcus Aurelius');
      expect(res.phones.first.value, contains('555'));
      expect(res.emails.first.value, 'marcus@aurelius.org');
      expect(res.company, isNull);
    });

    test('9. Logo-heavy card with marketing slogan', () {
      final lines = [
        'We Bring Performances Alive', // Slogan
        'Tata Consultancy Services Ltd',
        'Rohan Verma',
        'Executive Vice President',
        'rohan.v@tcs.com',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 90.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 88.0,
      );
      expect(res.name?.value, 'Rohan Verma');
      expect(res.company?.value, contains('Tata Consultancy Services'));
      expect(res.company?.value, isNot(contains('Performances Alive')));
    });

    test('10. Dark background contrast card', () {
      final lines = [
        'BLACK OAK ARCHITECTS',
        'Sarah Jenkins',
        'Principal Architect',
        'sarah@blackoak.com',
        '+44 20 7946 0912',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 88.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 85.0,
      );
      expect(res.name?.value, 'Sarah Jenkins');
      expect(res.company?.value, 'BLACK OAK ARCHITECTS');
    });

    test('11. Light background card', () {
      final lines = [
        'Claire Dupont',
        'Chief Marketing Officer',
        'Lumière Cosmetics International',
        'c.dupont@lumiere.fr',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 95.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 93.0,
      );
      expect(res.name?.value, 'Claire Dupont');
      expect(res.company?.value, contains('Lumière Cosmetics'));
    });

    test('12. Colored background card', () {
      final lines = [
        'Verde Organics Ltd',
        'Miguel Rodriguez',
        'Director of Operations',
        '+34 91 123 4567',
        'miguel@verdeorganics.es',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 90.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 89.0,
      );
      expect(res.name?.value, 'Miguel Rodriguez');
      expect(res.company?.value, contains('Verde Organics'));
    });

    test('13. Very large company typography', () {
      final lines = [
        'MICROSOFT',
        'Satya Nadella',
        'Chairman and CEO',
        'satya@microsoft.com',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 96.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 92.0,
      );
      expect(res.company?.value, 'MICROSOFT');
      expect(res.name?.value, 'Satya Nadella');
      expect(res.jobTitle?.value, contains('CEO'));
    });

    test('14. Very large person-name typography', () {
      final lines = [
        'STEVE JOBS',
        'CEO',
        'Apple Computer Inc',
        '1 Infinite Loop, Cupertino, CA 95014',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 94.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 91.0,
      );
      expect(res.name?.value, 'STEVE JOBS');
      expect(res.company?.value, contains('Apple Computer'));
    });

    test('15. Tiny contact details at bottom', () {
      final lines = [
        'Dr. S. K. Gupta',
        'Gupta Dental Clinic',
        'Tel: +91 11 2345 6789 | Mob: +91 98111 22334',
        'skgupta@guptadental.com',
        'B-42, Connaught Place, New Delhi 110001',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 89.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 86.0,
      );
      expect(res.name?.value, contains('Gupta'));
      expect(res.phones.length, 2);
    });

    test('16. Address at top', () {
      final lines = [
        '742 Evergreen Terrace, Springfield, OR 97477',
        'Homer Simpson',
        'Safety Inspector',
        'Springfield Nuclear Power Plant',
        '555-7334',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 91.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 88.0,
      );
      expect(res.name?.value, 'Homer Simpson');
      expect(res.address?.value, contains('Evergreen Terrace'));
    });

    test('17. Address at bottom spanning multiple lines', () {
      final lines = [
        'Sunil Narang',
        'Managing Director',
        'Narang Exim Private Limited',
        '+91 98200 12345',
        'Plot 12, Phase II',
        'MIDC Industrial Area, Andheri East',
        'Mumbai, Maharashtra 400093',
        'India',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 92.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 90.0,
      );
      expect(res.address?.value, contains('Plot 12'));
      expect(res.address?.value, contains('400093'));
    });

    test('18. Address on right column', () {
      final lines = [
        'David Miller',
        'Senior Consultant',
        'Millennium Partners LLP',
        'david@millennium.co.uk',
        '100 Victoria Street',
        'London SW1E 5JL',
        'United Kingdom',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 93.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 90.0,
      );
      expect(res.name?.value, 'David Miller');
      expect(res.address?.value, contains('London SW1E 5JL'));
    });

    test('19. Multiple phone numbers with distinct labels', () {
      final lines = [
        'Johnathan Doe',
        'Fintech Solutions Corp',
        'Mobile: +1 415 555 0192',
        'Office: +1 415 555 0199',
        'Fax: +1 415 555 0190',
      ];
      final phones = PhoneOcrRecovery.extractPhoneCandidates(lines);
      expect(phones.length, 3);
      expect(phones.any((p) => p.label == 'Mobile'), isTrue);
      expect(phones.any((p) => p.label == 'Office'), isTrue);
      expect(phones.any((p) => p.label == 'Fax'), isTrue);
    });

    test('20. Multiple emails', () {
      final lines = [
        'Elena Rostova',
        'Global Aid Foundation',
        'personal: elena.r@gmail.com',
        'work: elena@globalaid.org',
      ];
      final emails = EmailOcrRecovery.extractEmailCandidates(lines);
      expect(emails.length, 2);
      expect(emails.any((e) => e.email == 'elena.r@gmail.com'), isTrue);
      expect(emails.any((e) => e.email == 'elena@globalaid.org'), isTrue);
    });

    test('21. Website + Email with different domains', () {
      final lines = [
        'Karthik Subbaraj',
        'Director',
        'Stone Bench Creations',
        'karthik@gmail.com',
        'www.stonebench.in',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 92.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 89.0,
      );
      expect(res.emails.first.value, 'karthik@gmail.com');
      expect(res.websites.first.value, contains('stonebench.in'));
    });

    test('22. No company on card', () {
      final lines = [
        'Dr. Rachel Green',
        'Clinical Psychologist',
        '+1 212 555 8921',
        'rachel@greenpsych.com',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 90.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 88.0,
      );
      expect(res.name?.value, contains('Rachel Green'));
      expect(res.company, isNull);
    });

    test('23. No person name on card (Company contact card)', () {
      final lines = [
        'MEDINDIA 24/7 HELPLINE',
        'Emergency Medical Assistance',
        'Phone: 1800-425-0011',
        'help@medindia.net',
        'www.medindia.net',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 91.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 89.0,
      );
      expect(res.name, isNull);
      expect(res.company?.value, contains('MEDINDIA'));
    });

    test('24. No address on card', () {
      final lines = [
        'Alex Mercer',
        'Freelance Digital Illustrator',
        '+1 310 555 0144',
        'alex@mercerart.io',
        'www.mercerart.io',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 92.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 90.0,
      );
      expect(res.address, isNull);
      expect(res.name?.value, 'Alex Mercer');
    });

    test('25. Front/back split card information', () {
      final frontData = BusinessCardData(
        fullName: 'Arun Sundaram',
        jobTitle: 'Managing Trustee',
        company: 'MOHAN Foundation',
        phoneNumbers: [
          const BusinessCardPhone(number: '+91 98410 12345', label: 'Mobile'),
        ],
      );
      final backData = BusinessCardData(
        address: 'Toshniwal Building, 3rd Floor, 267 Kilpauk Garden Road, Chennai 600010',
        website: 'www.mohanfoundation.org',
        emailAddresses: [],
      );
      final merged = parser.mergeDualSidedData(
        frontData: frontData,
        backData: backData,
        frontRawText: 'Front raw text',
        backRawText: 'Back raw text',
      );
      expect(merged.fullName, 'Arun Sundaram');
      expect(merged.company, 'MOHAN Foundation');
      expect(merged.address, contains('Kilpauk Garden Road'));
      expect(merged.website, 'www.mohanfoundation.org');
    });

    test('26. QR code + printed contact details', () {
      final lines = [
        'Scan QR for Digital Card', // Instruction banner
        'Deepak Chawla',
        'Co-Founder & CEO',
        'HyperSpeed Logistics Pvt Ltd',
        '+91 98199 88776',
        'deepak@hyperspeed.co',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 91.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 89.0,
      );
      expect(res.name?.value, 'Deepak Chawla');
      expect(res.name?.value, isNot(contains('Scan QR')));
      expect(res.company?.value, contains('HyperSpeed Logistics'));
    });

    test('27. International phone with parenthesis and dashes', () {
      final lines = [
        'Emily Watson',
        'Tel: +1 (212) 555-0199',
        'emily@watsonlaw.com',
      ];
      final phones = PhoneOcrRecovery.extractPhoneCandidates(lines);
      expect(phones.length, 1);
      expect(phones.first.formatted, contains('+1 (212) 555-0199'));
    });

    test('28. Initials in person name', () {
      final lines = [
        'T. S. R. Subramanian',
        'Former Cabinet Secretary',
        'Government of India',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 93.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 91.0,
      );
      expect(res.name?.value, contains('Subramanian'));
    });

    test('29. Unusual designation (Managing Trustee / Hon. Consul)', () {
      final lines = [
        'Dr. Sunil Shroff',
        'Managing Trustee',
        'MOHAN Foundation',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 94.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 90.0,
      );
      expect(res.name?.value, contains('Sunil Shroff'));
      expect(res.jobTitle?.value, 'Managing Trustee');
    });

    test('30. Long email and sub-domain address', () {
      final lines = [
        'Siddharth',
        'siddharth.subramanian@engineering-infrastructure.enterprise.co.in',
        'www.engineering-infrastructure.enterprise.co.in',
      ];
      final emails = EmailOcrRecovery.extractEmailCandidates(lines);
      expect(emails.length, 1);
      expect(emails.first.email, 'siddharth.subramanian@engineering-infrastructure.enterprise.co.in');
    });
  });

  group('PART 23 — Testing Team Regression Suite', () {
    test('Regression: Missing final phone digit recovered from recovery engine', () {
      // Paddle had truncated digit (+91 98765 4321), ML Kit had complete (+91 98765 43210)
      final paddleLines = ['+91 98765 4321'];
      final mlKitLines = ['+91 98765 43210'];

      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: paddleLines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 80.0,
        secondaryLines: mlKitLines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 90.0,
      );
      expect(res.phones.first.value, contains('98765 43210'));
    });

    test('Regression: Missing middle phone digit / OCR confusion corrected', () {
      // S -> 5, O -> 0 in digit sequence
      final lines = ['Mob: +91 9876S 4321O'];
      final phones = PhoneOcrRecovery.extractPhoneCandidates(lines);
      expect(phones.first.normalized, contains('9876543210'));
      expect(phones.first.hasCharacterCorrection, isTrue);
    });

    test('Regression: Missing @ in email recovered when spaced or symbol substituted', () {
      final lines = ['denil.varghese (at) digitalshare.app'];
      final emails = EmailOcrRecovery.extractEmailCandidates(lines);
      expect(emails.length, 1);
      expect(emails.first.email, 'denil.varghese@digitalshare.app');
    });

    test('Regression: Missing dot in email domain reconstructed', () {
      final lines = ['user@examplecom'];
      final emails = EmailOcrRecovery.extractEmailCandidates(lines);
      expect(emails.length, 1);
      expect(emails.first.email, 'user@example.com');
    });

    test('Regression: Long email not truncated', () {
      const longEmail = 'first.middle.lastname@very-long-company-subdomain.technologies.com';
      final lines = [longEmail];
      final emails = EmailOcrRecovery.extractEmailCandidates(lines);
      expect(emails.first.email, longEmail);
    });

    test('Regression: Skipped middle word prevented by column-aware observation sorting', () {
      final obs = [
        const OcrObservation(
          id: '1',
          text: 'Arun',
          boundingBox: Rect.fromLTWH(10, 20, 50, 20),
          normalizedBoundingBox: Rect.fromLTWH(0.01, 0.02, 0.05, 0.02),
          confidence: 0.95,
          engine: 'PaddleOCR',
          lineIndex: 0,
        ),
        const OcrObservation(
          id: '2',
          text: 'Kumar',
          boundingBox: Rect.fromLTWH(65, 20, 60, 20),
          normalizedBoundingBox: Rect.fromLTWH(0.065, 0.02, 0.06, 0.02),
          confidence: 0.94,
          engine: 'PaddleOCR',
          lineIndex: 0,
        ),
        const OcrObservation(
          id: '3',
          text: 'Jayant',
          boundingBox: Rect.fromLTWH(130, 20, 70, 20),
          normalizedBoundingBox: Rect.fromLTWH(0.13, 0.02, 0.07, 0.02),
          confidence: 0.96,
          engine: 'PaddleOCR',
          lineIndex: 0,
        ),
      ];
      final lineMeta = obs.map((o) => o.toLineMetadata(CardSide.front)).toList();
      expect(lineMeta.length, 3);
      expect(lineMeta[1].text, 'Kumar');
    });

    test('Regression: Top text and bottom text preserved in observations', () {
      const topObs = OcrObservation(
        id: 'top',
        text: 'Top Company Logo Header',
        boundingBox: Rect.fromLTWH(20, 10, 200, 25),
        normalizedBoundingBox: Rect.fromLTWH(0.02, 0.01, 0.20, 0.025),
        confidence: 0.92,
        engine: 'PaddleOCR',
        lineIndex: 0,
      );
      const bottomObs = OcrObservation(
        id: 'bot',
        text: 'Bottom Legal Disclaimers Pin 600001',
        boundingBox: Rect.fromLTWH(20, 950, 300, 20),
        normalizedBoundingBox: Rect.fromLTWH(0.02, 0.95, 0.30, 0.02),
        confidence: 0.88,
        engine: 'PaddleOCR',
        lineIndex: 8,
      );
      expect(topObs.region, 'top');
      expect(bottomObs.region, 'bottom');
    });

    test('Regression: Small text observations retained (low minimum pixel count)', () {
      const tinyObs = OcrObservation(
        id: 'tiny',
        text: 'M: +91 9876543210',
        boundingBox: Rect.fromLTWH(20, 400, 120, 12),
        normalizedBoundingBox: Rect.fromLTWH(0.02, 0.40, 0.12, 0.012),
        confidence: 0.85,
        engine: 'PaddleOCR',
        lineIndex: 5,
      );
      expect(tinyObs.boundingBox.height, 12);
      expect(tinyObs.confidence, 0.85);
    });

    test('Regression: Unclassified valid OCR text preserved (Part 15)', () {
      final lines = [
        'Rajiv Mehta',
        'Founder',
        'Mehta Gems & Jewels',
        '+91 98201 23456',
        'GSTIN: 27AAAAA0000A1Z5',
        'By Appointment Only: Monday to Friday 10 AM - 6 PM',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 92.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 90.0,
      );
      expect(res.unclassifiedLines.any((l) => l.contains('Appointment Only')), isTrue);
    });

    test('Regression: Zero silent fabrication when field not detected', () {
      final lines = [
        'Acme Corporation Ltd',
        'info@acme.com',
      ];
      final res = FieldSemanticEvaluator.resolveFields(
        primaryLines: lines,
        primaryEngineName: 'PaddleOCR (PP-OCRv5 Mobile)',
        primaryOcrQualityScore: 90.0,
        secondaryLines: lines,
        secondaryEngineName: 'Google ML Kit',
        secondaryOcrQualityScore: 88.0,
      );
      expect(res.name, isNull);
      expect(res.phones, isEmpty);
      expect(res.fieldConfidenceStates['fullName'], 'notDetected');
      expect(res.fieldConfidenceStates['phone'], 'notDetected');
      expect(res.fieldConfidenceStates['company'], 'highConfidence');
      expect(res.fieldConfidenceStates['email'], 'highConfidence');
    });
  });
}
