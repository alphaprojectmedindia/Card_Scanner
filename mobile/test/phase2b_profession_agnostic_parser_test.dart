import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/business_card_parser.dart';

void main() {
  const parser = BusinessCardParser();

  group('Phase 2B: Profession-Agnostic Business Card Understanding Tests', () {
    // -------------------------------------------------------------------------
    // 1. Doctor / hospital
    // -------------------------------------------------------------------------
    test('1. Doctor / hospital card parses person, designation, organization and extracts department and credentials', () {
      const text = '''
APOLLO HOSPITALS
Dr. Anil Kumar, MBBS, MD
Consultant Cardiologist
Department of Cardiology
Tel: +91 44 2829 0200
anil.kumar@apollohospitals.com
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Dr. Anil Kumar');
      expect(res.jobTitle, 'Consultant Cardiologist');
      expect(res.company, 'APOLLO HOSPITALS');
      expect(res.alternativeCandidates['credentials'], isNotEmpty);
      expect(res.alternativeCandidates['credentials']!.first, contains('MBBS'));
      expect(res.alternativeCandidates['department'], isNotEmpty);
      expect(res.alternativeCandidates['department']!.first, contains('Cardiology'));
      expect(res.parsingNotes.any((n) => n.contains('Cardiology')), isTrue);
    });

    // -------------------------------------------------------------------------
    // 2. Dentist / clinic
    // -------------------------------------------------------------------------
    test('2. Dentist / clinic card parses doctor name and orthodontist designation', () {
      const text = '''
SMILE DENTAL CARE
Dr. Sarah Mathew, BDS, MDS
Orthodontist
+91 98401 23456
sarah@smiledentalcare.com
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Dr. Sarah Mathew');
      expect(res.jobTitle, 'Orthodontist');
      expect(res.company, 'SMILE DENTAL CARE');
      expect(res.alternativeCandidates['credentials'], isNotEmpty);
    });

    // -------------------------------------------------------------------------
    // 3. Surgeon / hospital
    // -------------------------------------------------------------------------
    test('3. Surgeon / hospital card classifies surgeon title without corrupting name', () {
      const text = '''
FORTIS HEALTHCARE
Dr. Rajesh Verma, MS, MCh
Senior Consultant Neurosurgeon
Department of Neurosurgery
rajesh.verma@fortishealthcare.com
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Dr. Rajesh Verma');
      expect(res.jobTitle, 'Senior Consultant Neurosurgeon');
      expect(res.company, 'FORTIS HEALTHCARE');
      expect(res.alternativeCandidates['department']!.first, contains('Neurosurgery'));
    });

    // -------------------------------------------------------------------------
    // 4. Advocate / law practice
    // -------------------------------------------------------------------------
    test('4. Advocate / legal card does not treat High Court as person name', () {
      const text = '''
PRIYA MENON
Advocate
High Court of Kerala
Mob: +91 98470 12345
priya.menon@keralabar.org
''';
      final res = parser.parse(text);
      expect(res.fullName, 'PRIYA MENON');
      expect(res.jobTitle, 'Advocate');
      expect(res.company, 'High Court of Kerala');
    });

    // -------------------------------------------------------------------------
    // 5. Chartered accountant
    // -------------------------------------------------------------------------
    test('5. Chartered accountant card recognizes CA firm and CA designation', () {
      const text = '''
K. S. RAMAN & CO
Suresh Raman, FCA
Chartered Accountant
Office: 044 2499 1122
suresh@ksraman.com
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Suresh Raman');
      expect(res.jobTitle, 'Chartered Accountant');
      expect(res.company, 'K. S. RAMAN & CO');
      expect(res.alternativeCandidates['credentials']!.first, contains('FCA'));
    });

    // -------------------------------------------------------------------------
    // 6. Professor / university
    // -------------------------------------------------------------------------
    test('6. Professor / university card recognizes associate professor without merging department', () {
      const text = '''
Dr. Arun Joseph
Associate Professor
Department of Mechanical Engineering
XYZ University
arun.joseph@xyz.edu
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Dr. Arun Joseph');
      expect(res.jobTitle, 'Associate Professor');
      expect(res.company, 'XYZ University');
      expect(res.alternativeCandidates['department']!.first, contains('Mechanical Engineering'));
    });

    // -------------------------------------------------------------------------
    // 7. Research scientist / institute
    // -------------------------------------------------------------------------
    test('7. Research scientist / institute card handles PhD and division', () {
      const text = '''
NATIONAL INSTITUTE OF IMMUNOLOGY
Dr. Meera Nambiar, PhD
Principal Research Scientist
Division of Molecular Biology
meera@nii.res.in
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Dr. Meera Nambiar');
      expect(res.jobTitle, 'Principal Research Scientist');
      expect(res.company, 'NATIONAL INSTITUTE OF IMMUNOLOGY');
      expect(res.alternativeCandidates['credentials']!.first, contains('PhD'));
      expect(res.alternativeCandidates['department']!.first, contains('Molecular Biology'));
    });

    // -------------------------------------------------------------------------
    // 8. Civil engineer / construction company
    // -------------------------------------------------------------------------
    test('8. Civil engineer / construction card identifies engineering role', () {
      const text = '''
BHARAT INFRA PROJECTS LTD
Anand Deshmukh
Senior Civil Engineer
anand@bharatinfra.com
+91 98220 33445
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Anand Deshmukh');
      expect(res.jobTitle, 'Senior Civil Engineer');
      expect(res.company, 'BHARAT INFRA PROJECTS LTD');
    });

    // -------------------------------------------------------------------------
    // 9. Architect
    // -------------------------------------------------------------------------
    test('9. Architect card recognizes chief architect and studio', () {
      const text = '''
STUDIO ARTHA ARCHITECTS
Vikram Joshi
Chief Architect
vikram@studioartha.com
www.studioartha.com
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Vikram Joshi');
      expect(res.jobTitle, 'Chief Architect');
      expect(res.company, 'STUDIO ARTHA ARCHITECTS');
    });

    // -------------------------------------------------------------------------
    // 10. CEO / company
    // -------------------------------------------------------------------------
    test('10. Executive CEO card handles ampersand in Founder & CEO', () {
      const text = '''
Robert Sterling
Founder & CEO
Apex Global Holdings
robert@apexholdings.com
+1 (555) 019-2834
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Robert Sterling');
      expect(res.jobTitle, 'Founder & CEO');
      expect(res.company, 'Apex Global Holdings');
    });

    // -------------------------------------------------------------------------
    // 11. Small-business proprietor
    // -------------------------------------------------------------------------
    test('11. Small-business proprietor card recognizes tradesperson title', () {
      const text = '''
RAHUL ELECTRICALS
Suresh Kumar
Proprietor & Electrical Contractor
+91 94440 12345
rahul.electricals@gmail.com
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Suresh Kumar');
      expect(res.jobTitle, 'Proprietor & Electrical Contractor');
      expect(res.company, 'RAHUL ELECTRICALS');
    });

    // -------------------------------------------------------------------------
    // 12. Photographer
    // -------------------------------------------------------------------------
    test('12. Photographer creative professional card classifies role', () {
      const text = '''
ARJUN KAPOOR
Commercial & Portrait Photographer
Light & Shadow Studios
+91 98402 34567
arjun@lightandshadow.in
''';
      final res = parser.parse(text);
      expect(res.fullName, 'ARJUN KAPOOR');
      expect(res.jobTitle, 'Commercial & Portrait Photographer');
      expect(res.company, 'Light & Shadow Studios');
    });

    // -------------------------------------------------------------------------
    // 13. Journalist / editor
    // -------------------------------------------------------------------------
    test('13. Media journalist card recognizes editorial role', () {
      const text = '''
THE DAILY CHRONICLE
Sunita Rao
Senior Investigative Journalist
editorial@chronicle.com
+91 11 2334 5566
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Sunita Rao');
      expect(res.jobTitle, 'Senior Investigative Journalist');
      expect(res.company, 'THE DAILY CHRONICLE');
    });

    // -------------------------------------------------------------------------
    // 14. Real-estate agent
    // -------------------------------------------------------------------------
    test('14. Real-estate broker card identifies licensed broker role', () {
      const text = '''
PRESTIGE HOMES REALTY
David Miller
Licensed Real Estate Broker
david@prestigehomes.com
+1 212 555 0140
''';
      final res = parser.parse(text);
      expect(res.fullName, 'David Miller');
      expect(res.jobTitle, 'Licensed Real Estate Broker');
      expect(res.company, 'PRESTIGE HOMES REALTY');
    });

    // -------------------------------------------------------------------------
    // 15. Hotel professional
    // -------------------------------------------------------------------------
    test('15. Hotel professional card recognizes Executive Chef with honorific', () {
      const text = '''
GRAND PALACE HOTEL
Chef Marcus Dupont
Executive Chef
Food & Beverage Department
marcus.dupont@grandpalace.com
''';
      final res = parser.parse(text);
      expect(res.fullName, contains('Marcus Dupont'));
      expect(res.jobTitle, 'Executive Chef');
      expect(res.company, 'GRAND PALACE HOTEL');
    });

    // -------------------------------------------------------------------------
    // 16. Travel consultant
    // -------------------------------------------------------------------------
    test('16. Travel consultant card recognizes agency and advisor role', () {
      const text = '''
VOYAGE HORIZONS TOURS
Elena Rostova
Senior Travel Consultant
info@voyagehorizons.com
+33 1 42 68 55 00
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Elena Rostova');
      expect(res.jobTitle, 'Senior Travel Consultant');
      expect(res.company, 'VOYAGE HORIZONS TOURS');
    });

    // -------------------------------------------------------------------------
    // 17. Electrician
    // -------------------------------------------------------------------------
    test('17. Electrician trade card classifies industrial electrician role', () {
      const text = '''
SPARKSAFE SERVICES
Ramesh Patel
Licensed Industrial Electrician
+91 98200 11223
ramesh@sparksafe.in
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Ramesh Patel');
      expect(res.jobTitle, 'Licensed Industrial Electrician');
      expect(res.company, 'SPARKSAFE SERVICES');
    });

    // -------------------------------------------------------------------------
    // 18. Mechanic
    // -------------------------------------------------------------------------
    test('18. Mechanic automotive card recognizes master mechanic', () {
      const text = '''
PRECISION AUTO WORKSHOP
Frank Kowalski
Master Automotive Mechanic
service@precisionauto.com
(555) 019-3344
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Frank Kowalski');
      expect(res.jobTitle, 'Master Automotive Mechanic');
      expect(res.company, 'PRECISION AUTO WORKSHOP');
    });

    // -------------------------------------------------------------------------
    // 19. Government / organization employee
    // -------------------------------------------------------------------------
    test('19. Government employee card classifies assistant commissioner without name corruption', () {
      const text = '''
Rajiv Nair
Assistant Commissioner
Department of Revenue
Government of Karnataka
rajiv.nair@karnataka.gov.in
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Rajiv Nair');
      expect(res.jobTitle, 'Assistant Commissioner');
      expect(res.company, 'Government of Karnataka');
      expect(res.alternativeCandidates['department']!.first, contains('Revenue'));
    });

    // -------------------------------------------------------------------------
    // 20. Sales professional
    // -------------------------------------------------------------------------
    test('20. Sales professional card recognizes corporate representative role', () {
      const text = '''
NEXORA ENTERPRISES
Pooja Bhatt
Corporate Sales Representative
pooja@nexora.com
+91 98111 22334
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Pooja Bhatt');
      expect(res.jobTitle, 'Corporate Sales Representative');
      expect(res.company, 'NEXORA ENTERPRISES');
    });

    // -------------------------------------------------------------------------
    // 21. Banker
    // -------------------------------------------------------------------------
    test('21. Banker card classifies Vice President and identifies bank', () {
      const text = '''
HORIZON COMMERCIAL BANK
Amit Sharma
Vice President
Corporate Banking Division
amit.sharma@horizonbank.com
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Amit Sharma');
      expect(res.jobTitle, 'Vice President');
      expect(res.company, 'HORIZON COMMERCIAL BANK');
    });

    // -------------------------------------------------------------------------
    // 22. Insurance advisor
    // -------------------------------------------------------------------------
    test('22. Insurance advisor card recognizes compound financial advisor title', () {
      const text = '''
RELIANCE LIFE CARE
Neha Gupta
Senior Financial & Insurance Advisor
neha@reliancelife.in
+91 98765 43210
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Neha Gupta');
      expect(res.jobTitle, 'Senior Financial & Insurance Advisor');
      expect(res.company, 'RELIANCE LIFE CARE');
    });

    // -------------------------------------------------------------------------
    // 23. Consultant
    // -------------------------------------------------------------------------
    test('23. Management consultant card recognizes consulting title and group', () {
      const text = '''
STRATEGY PARTNERS GROUP
Daniel Craig
Management Consultant
daniel@strategypartners.com
+44 20 7946 0958
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Daniel Craig');
      expect(res.jobTitle, 'Management Consultant');
      expect(res.company, 'STRATEGY PARTNERS GROUP');
    });

    // -------------------------------------------------------------------------
    // 24. Freelancer / individual professional
    // -------------------------------------------------------------------------
    test('24. Freelancer card classifies copywriter role without organization requirement', () {
      const text = '''
SOPHIA TAYLOR
Freelance Copywriter & Content Strategist
sophia@sophiacopy.com
www.sophiacopy.com
''';
      final res = parser.parse(text);
      expect(res.fullName, 'SOPHIA TAYLOR');
      expect(res.jobTitle, 'Freelance Copywriter & Content Strategist');
      expect(res.company, isNull);
    });

    // -------------------------------------------------------------------------
    // 25. Healthcare professional with multiple credentials
    // -------------------------------------------------------------------------
    test('25. Healthcare professional with compound credentials preserves all credentials', () {
      const text = '''
Dr. Anil Kumar, MBBS, MD, DM, FRCP
Consultant Cardiologist
Heart Care Clinic
anil@heartcare.org
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Dr. Anil Kumar');
      expect(res.jobTitle, 'Consultant Cardiologist');
      expect(res.company, 'Heart Care Clinic');
      expect(res.alternativeCandidates['credentials']!.first, contains('MBBS'));
      expect(res.alternativeCandidates['credentials']!.first, contains('MD'));
      expect(res.alternativeCandidates['credentials']!.first, contains('FRCP'));
    });

    // -------------------------------------------------------------------------
    // 26. Unknown "Marine Surveyor"
    // -------------------------------------------------------------------------
    test('26. Unknown "Marine Surveyor" is inferred contextually without dictionary entry', () {
      const text = '''
Jane Doe
Marine Surveyor
Oceanic Inspection Services
jane@oceanicinspect.com
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Jane Doe');
      expect(res.jobTitle, 'Marine Surveyor');
      expect(res.company, 'Oceanic Inspection Services');
    });

    // -------------------------------------------------------------------------
    // 27. Unknown "Agricultural Entomologist"
    // -------------------------------------------------------------------------
    test('27. Unknown "Agricultural Entomologist" is inferred contextually without dictionary entry', () {
      const text = '''
John Smith
Agricultural Entomologist
ABC Research Institute
john.smith@abcresearch.org
''';
      final res = parser.parse(text);
      expect(res.fullName, 'John Smith');
      expect(res.jobTitle, 'Agricultural Entomologist');
      expect(res.company, 'ABC Research Institute');
    });

    // -------------------------------------------------------------------------
    // 28. Unknown profession with unusual two-word designation
    // -------------------------------------------------------------------------
    test('28. Unusual two-word designation "Horological Restorer" is inferred without dictionary', () {
      const text = '''
Lucas Vance
Horological Restorer
Heritage Timepieces Guild
lucas@heritagetime.com
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Lucas Vance');
      expect(res.jobTitle, 'Horological Restorer');
      expect(res.company, 'Heritage Timepieces Guild');
    });

    // -------------------------------------------------------------------------
    // 29. Person with no job title
    // -------------------------------------------------------------------------
    test('29. Person with no job title leaves jobTitle null safely without inventing one', () {
      const text = '''
Alexander Wright
Apex Holdings LLC
alex@apexholdings.com
+1 800 555 0199
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Alexander Wright');
      expect(res.company, 'Apex Holdings LLC');
      expect(res.jobTitle, isNull);
    });

    // -------------------------------------------------------------------------
    // 30. Organization-only card
    // -------------------------------------------------------------------------
    test('30. Organization-only card parses company without fabricating name or job title', () {
      const text = '''
GREEN VALLEY WELLNESS SANCTUARY
100 Forest View Road
Tel: +1 800 555 0199
contact@greenvalleywellness.org
www.greenvalleywellness.org
''';
      final res = parser.parse(text);
      expect(res.company, 'GREEN VALLEY WELLNESS SANCTUARY');
      expect(res.fullName, isNull);
      expect(res.jobTitle, isNull);
      expect(res.website, contains('greenvalleywellness.org'));
    });

    // -------------------------------------------------------------------------
    // 31. Individual professional with no organization
    // -------------------------------------------------------------------------
    test('31. Individual professional with no organization parses name and title without inventing company', () {
      const text = '''
Tara Sterling
Freelance Voiceover Artist
tara@taravoice.com
+1 415 555 0122
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Tara Sterling');
      expect(res.jobTitle, 'Freelance Voiceover Artist');
      expect(res.company, isNull);
    });

    // -------------------------------------------------------------------------
    // 32. Slogan between name and company
    // -------------------------------------------------------------------------
    test('32. Slogan between name and company is not classified as job title', () {
      const text = '''
Jane Doe
Building Better Communities
ABC Foundation
jane@abcfoundation.org
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Jane Doe');
      expect(res.company, 'ABC Foundation');
      expect(res.jobTitle, isNot(equals('Building Better Communities')));
      expect(res.alternativeCandidates['slogan']!.first, contains('Building Better Communities'));
    });

    // -------------------------------------------------------------------------
    // 33. Department between designation and organization
    // -------------------------------------------------------------------------
    test('33. Department between designation and organization does not corrupt company or designation', () {
      const text = '''
Dr. Arun Joseph
Associate Professor
Department of Mechanical Engineering
XYZ University
arun@xyz.edu
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Dr. Arun Joseph');
      expect(res.jobTitle, 'Associate Professor');
      expect(res.company, 'XYZ University');
      expect(res.alternativeCandidates['department']!.first, contains('Mechanical Engineering'));
    });

    // -------------------------------------------------------------------------
    // 34. Credentials on same line as name
    // -------------------------------------------------------------------------
    test('34. Credentials on same line as name are stripped cleanly from fullName', () {
      const text = '''
Dr. Anil Kumar, MBBS, MD
Consultant Cardiologist
City Hospital
anil@cityhospital.in
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Dr. Anil Kumar');
      expect(res.fullName, isNot(contains('MBBS')));
      expect(res.fullName, isNot(contains('MD')));
      expect(res.jobTitle, 'Consultant Cardiologist');
      expect(res.company, 'City Hospital');
      expect(res.alternativeCandidates['credentials']!.first, contains('MBBS, MD'));
    });

    // -------------------------------------------------------------------------
    // 35. Credentials on separate line
    // -------------------------------------------------------------------------
    test('35. Credentials on separate line are preserved and do not hijack designation or name', () {
      const text = '''
Dr. Sunil Varghese
MBBS, MD, FRCS
Senior Consultant
Metro Hospital
sunil@metrohospital.org
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Dr. Sunil Varghese');
      expect(res.jobTitle, 'Senior Consultant');
      expect(res.company, 'Metro Hospital');
      expect(res.alternativeCandidates['credentials']!.first, contains('MBBS'));
    });

    // -------------------------------------------------------------------------
    // 36. Multi-language-looking / unrecognized line must not be fabricated
    // -------------------------------------------------------------------------
    test('36. Unrecognized multi-language script is preserved non-destructively in unclassified alternatives', () {
      const text = '''
Kenji Sato
Chief Operating Officer
東邦産業株式会社
kenji@toho.co.jp
''';
      final res = parser.parse(text);
      expect(res.fullName, 'Kenji Sato');
      expect(res.jobTitle, 'Chief Operating Officer');
      expect(res.alternativeCandidates['unclassified'], isNotEmpty);
      expect(res.alternativeCandidates['unclassified']!.first, contains('東邦産業株式会社'));
      expect(res.parsingNotes.any((n) => n.contains('東邦産業株式会社')), isTrue);
    });

    // -------------------------------------------------------------------------
    // 37. Front/back card with profession on front and organization/address on back
    // -------------------------------------------------------------------------
    test('37. Front/back card merges profession from front and organization/address from back', () {
      final front = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/f.jpg',
        rawText: '''
Elena Rostova
Senior Travel Consultant
elena@travelsolutions.com
''',
      );

      final back = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: '/tmp/b.jpg',
        rawText: '''
Global Travel Solutions LLC
123 Boulevard Saint-Germain, Paris, France
+33 1 42 68 55 00
www.travelsolutions.com
''',
      );

      final data = parser.parseDualSided(front: front, back: back);
      expect(data.isDualSided, isTrue);
      expect(data.fullName, 'Elena Rostova');
      expect(data.jobTitle, 'Senior Travel Consultant');
      expect(data.company, 'Global Travel Solutions LLC');
      expect(data.address, contains('123 Boulevard'));
      expect(data.website, contains('travelsolutions.com'));
      expect(data.phoneNumbers.first.number, contains('42 68 55 00'));
      expect(data.emailAddresses.first.email, 'elena@travelsolutions.com');
    });
  });
}
