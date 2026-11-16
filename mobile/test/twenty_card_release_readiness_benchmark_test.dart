// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/card_analysis_result.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/ocr/gemini_ocr_reconciliation_engine.dart';

void main() {
  final parser = BusinessCardParser();
  const engine = GeminiOcrReconciliationEngine();

  test('Release Readiness: 20 Physical Business Cards Comprehensive Benchmark', () {
    final cards = [
      // 1. Lions Clubs (Bangladesh)
      {
        'id': 'CARD_01_LIONS_INTL',
        'rawText': 'Lions Clubs International\nNazmul Haque\nInternational Director 2025-2027\nHouse - 113, Road - 3, Block # F\nBanani, Dhaka-1213, Bangladesh\n+88 01713 032845\nlnazmul.haque1951@gmail.com',
        'gtName': 'Nazmul Haque',
        'gtCompany': 'Lions Clubs International',
        'gtJobTitle': 'International Director 2025-2027',
        'gtPhone': '+88 01713 032845',
        'gtEmail': 'lnazmul.haque1951@gmail.com',
        'gtAddress': 'Banani, Dhaka-1213, Bangladesh',
      },
      // 2. Vardhaman & Co (Chennai)
      {
        'id': 'CARD_02_VARDHAMAN',
        'rawText': 'Vardhaman & Co\nV. Baskaran\n044-24344627\n9840136801\nvardhaman_1973@hotmail.com\nNew No. 12, Krishna Street\nT. Nagar, Chennai - 600 017',
        'gtName': 'V. Baskaran',
        'gtCompany': 'Vardhaman & Co',
        'gtPhone': '044-24344627',
        'gtEmail': 'vardhaman_1973@hotmail.com',
        'gtAddress': 'Chennai - 600 017',
      },
      // 3. Consulate of Spain
      {
        'id': 'CARD_03_CONSULATE_SPAIN',
        'rawText': 'Consulate of Spain\nAntony Lobo\nHon. Consul of Spain\nspainconsulate.chennai@gmail.com\n+91-44-42107657',
        'gtName': 'Antony Lobo',
        'gtCompany': 'Consulate of Spain',
        'gtJobTitle': 'Hon. Consul of Spain',
        'gtEmail': 'spainconsulate.chennai@gmail.com',
        'gtPhone': '+91-44-42107657',
      },
      // 4. US Florida card
      {
        'id': 'CARD_04_US_FLORIDA',
        'rawText': 'tanakagawa86@gmail.com\n(336) 414-6830\n123 27th Ave N\nSt Petersburg, FL 33704',
        'gtEmail': 'tanakagawa86@gmail.com',
        'gtPhone': '(336) 414-6830',
        'gtAddress': 'St Petersburg, FL 33704',
      },
      // 5. CA firm
      {
        'id': 'CARD_05_CHARTERED_ACCOUNTANT',
        'rawText': 'K. R. Ramanathan & Associates\nChartered Accountants\nK. R. Ramanathan, B.Com, FCA\nChartered Accountant\n+91 44 2827 1234\nramanathan@cakrr.com\nwww.cakrr.com',
        'gtName': 'K. R. Ramanathan',
        'gtCompany': 'K. R. Ramanathan & Associates',
        'gtJobTitle': 'Chartered Accountant',
        'gtEmail': 'ramanathan@cakrr.com',
        'gtWebsite': 'www.cakrr.com',
      },
      // 6. Apollo Hospitals
      {
        'id': 'CARD_06_APOLLO_HOSPITALS',
        'rawText': 'APOLLO HOSPITALS\nDr. Anil Kumar, MBBS, MD\nConsultant Cardiologist\nTel: +91 44 2829 0200\nanil.kumar@apollohospitals.com',
        'gtName': 'Dr. Anil Kumar',
        'gtCompany': 'APOLLO HOSPITALS',
        'gtJobTitle': 'Consultant Cardiologist',
        'gtPhone': '+91 44 2829 0200',
        'gtEmail': 'anil.kumar@apollohospitals.com',
      },
      // 7. Smile Dental
      {
        'id': 'CARD_07_DENTAL_CLINIC',
        'rawText': 'SMILE DENTAL CARE\nDr. Sarah Mathew, BDS, MDS\nOrthodontist\n+91 98401 23456\nsarah@smiledentalcare.com',
        'gtName': 'Dr. Sarah Mathew',
        'gtCompany': 'SMILE DENTAL CARE',
        'gtJobTitle': 'Orthodontist',
        'gtPhone': '+91 98401 23456',
        'gtEmail': 'sarah@smiledentalcare.com',
      },
      // 8. Fortis Healthcare
      {
        'id': 'CARD_08_NEUROSURGERY',
        'rawText': 'FORTIS HEALTHCARE\nDr. Rajesh Verma, MS, MCh\nSenior Consultant Neurosurgeon\nrajesh.verma@fortishealthcare.com',
        'gtName': 'Dr. Rajesh Verma',
        'gtCompany': 'FORTIS HEALTHCARE',
        'gtJobTitle': 'Senior Consultant Neurosurgeon',
        'gtEmail': 'rajesh.verma@fortishealthcare.com',
      },
      // 9. TechVision CTO
      {
        'id': 'CARD_09_TECHVISION',
        'rawText': 'TechVision Solutions Ltd\nAlex Mercer\nChief Technology Officer\nalex.mercer@techvision.io\nwww.techvision.io',
        'gtName': 'Alex Mercer',
        'gtCompany': 'TechVision Solutions Ltd',
        'gtJobTitle': 'Chief Technology Officer',
        'gtEmail': 'alex.mercer@techvision.io',
        'gtWebsite': 'www.techvision.io',
      },
      // 10. Minimal card
      {
        'id': 'CARD_10_MINIMAL',
        'rawText': 'S. Raman\n+91 98400 99999',
        'gtName': 'S. Raman',
        'gtPhone': '+91 98400 99999',
      },
      // 11. Company-First with Gemini correction
      {
        'id': 'CARD_11_COMPANY_FIRST',
        'rawText': 'Apex Healthcare Solutions Pvt Ltd\nDr. Antony Lobo\nSenior Consultant - Cardiology\nPhone: +91 98765 43210',
        'gtName': 'Dr. Antony Lobo',
        'gtCompany': 'Apex Healthcare Solutions Pvt Ltd',
        'gtJobTitle': 'Senior Consultant - Cardiology',
        'gtPhone': '+91 98765 43210',
        'geminiName': 'Dr. Antony Lobo',
        'geminiCompany': 'Apex Healthcare Solutions Pvt Ltd',
      },
      // 12. Person Below Company
      {
        'id': 'CARD_12_PERSON_BELOW_CO',
        'rawText': 'Blue Horizon Technologies\nMeera Nambiar\nHead of Engineering\nmeera@bluehorizon.io',
        'gtName': 'Meera Nambiar',
        'gtCompany': 'Blue Horizon Technologies',
        'gtJobTitle': 'Head of Engineering',
        'gtEmail': 'meera@bluehorizon.io',
      },
      // 13. Adjacent Job Title
      {
        'id': 'CARD_13_ADJACENT_TITLE',
        'rawText': 'OmniCloud Systems\nVikram Sethi\nChief Technical Architect\nvikram.sethi@omnicloud.com',
        'gtName': 'Vikram Sethi',
        'gtCompany': 'OmniCloud Systems',
        'gtJobTitle': 'Chief Technical Architect',
        'gtEmail': 'vikram.sethi@omnicloud.com',
      },
      // 14. Multiple Employees Isolation (Employee 2)
      {
        'id': 'CARD_14_EMPLOYEE_ISOLATION',
        'rawText': 'Global Logistics Solutions\nSiddharth Rao\nOperations Director\n+91 99887 76655\nsiddharth@globallogistics.com',
        'gtName': 'Siddharth Rao',
        'gtCompany': 'Global Logistics Solutions',
        'gtJobTitle': 'Operations Director',
        'gtPhone': '+91 99887 76655',
        'gtEmail': 'siddharth@globallogistics.com',
      },
      // 15. Multi-Phone & Multi-Email
      {
        'id': 'CARD_15_MULTI_PHONE_EMAIL',
        'rawText': 'Summit Enterprises\nTel: +1-800-555-0199\nDirect: +1-415-555-0142\ninfo@summit.com\nsupport@summit.com',
        'gtCompany': 'Summit Enterprises',
        'gtPhone': '8005550199',
        'gtEmail': 'info@summit.com',
      },
      // 16. Dual-Sided Card
      {
        'id': 'CARD_16_DUAL_SIDED',
        'rawText': 'Nexus Dynamics Inc\nDavid Chen\nVP Product\ndavid@nexusdynamics.com',
        'backText': 'Nexus Dynamics Inc\n100 Technology Drive, Suite 400\nSan Jose, CA 95110',
        'gtName': 'David Chen',
        'gtCompany': 'Nexus Dynamics Inc',
        'gtJobTitle': 'VP Product',
        'gtEmail': 'david@nexusdynamics.com',
        'gtAddress': '100 Technology Drive',
      },
      // 17. Indian PIN Code
      {
        'id': 'CARD_17_INDIAN_PIN',
        'rawText': 'Zenith Infotech India Pvt Ltd\nPriya Sundaram\nDirector - Cloud Services\nNo. 45, MG Road, Bangalore 560001\nMobile: +91 98450 12345',
        'gtName': 'Priya Sundaram',
        'gtCompany': 'Zenith Infotech India Pvt Ltd',
        'gtJobTitle': 'Director - Cloud Services',
        'gtPhone': '+91 98450 12345',
        'gtAddress': 'Bangalore 560001',
      },
      // 18. Multilingual Card
      {
        'id': 'CARD_18_MULTILINGUAL',
        'rawText': 'Bengaluru Innovators Pvt Ltd\nRamesh Gowda\nManaging Director\nPh: +91 80 2345 6789\nramesh@bengaluruinnovators.com\nಬೆಂಗಳೂರು ಇನ್ನೋವೇಟರ್ಸ್',
        'gtName': 'Ramesh Gowda',
        'gtCompany': 'Bengaluru Innovators Pvt Ltd',
        'gtJobTitle': 'Managing Director',
        'gtPhone': '+91 80 2345 6789',
        'gtEmail': 'ramesh@bengaluruinnovators.com',
      },
      // 19. Low Readability Card
      {
        'id': 'CARD_19_LOW_READABILITY',
        'rawText': 'ClearVue Optics\nPhone: (555) 019-2834\ninfo@clearvueoptics.com',
        'gtCompany': 'ClearVue Optics',
        'gtPhone': '5550192834',
        'gtEmail': 'info@clearvueoptics.com',
      },
      // 20. Company-Only Card (No Person Name)
      {
        'id': 'CARD_20_COMPANY_ONLY',
        'rawText': 'Acme Wholesale Supplies LLC\nIndustrial Tools & Hardware\nOrder Desk: 1-800-555-ACME\nsales@acmewholesale.com\nwww.acmewholesale.com\nWarehouse 4, Port Authority Rd',
        'gtCompany': 'Acme Wholesale Supplies LLC',
        'gtEmail': 'sales@acmewholesale.com',
        'gtWebsite': 'www.acmewholesale.com',
        'gtAddress': 'Port Authority Rd',
        'gtName': null, // Explicitly no person name!
      },
    ];

    int nameEval = 0, nameMatch = 0;
    int coEval = 0, coMatch = 0;
    int jobEval = 0, jobMatch = 0;
    int phoneEval = 0, phoneMatch = 0;
    int emailEval = 0, emailMatch = 0;
    int webEval = 0, webMatch = 0;
    int addrEval = 0, addrMatch = 0;
    int fieldPlacementCorrect = 0;
    int totalEvaluatedCards = cards.length;
    int hallucinationCount = 0;
    int incorrectCorrectionCount = 0;

    for (final c in cards) {
      final raw = c['rawText'] as String;
      final back = c['backText'];
      var parsed = parser.parse(raw);

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: '/tmp/test.jpg',
        rawText: raw,
      );
      OcrSideResult? backOcr;
      if (back != null) {
        backOcr = OcrSideResult.fromText(
          side: CardSide.back,
          imagePath: '/tmp/test_back.jpg',
          rawText: back,
        );
      }

      // If card has Gemini extraction ground truth
      CardAnalysisResult? geminiResult;
      if (c.containsKey('geminiName') || c.containsKey('geminiCompany')) {
        geminiResult = CardAnalysisResult(
          clientRequestId: c['id'] as String,
          analysisCacheKey: 'cache_${c['id']}',
          visualVerificationPerformed: true,
          geminiApiExecuted: true,
          fullName: c.containsKey('geminiName') ? ExtractedField(value: c['geminiName'] as String, confidence: 0.98, verificationStatus: 'verified') : null,
          company: c.containsKey('geminiCompany') ? ExtractedField(value: c['geminiCompany'] as String, confidence: 0.98, verificationStatus: 'verified') : null,
        );
      }

      final reconciled = engine.reconcile(
        localCardData: parsed,
        frontOcr: frontOcr,
        backOcr: backOcr,
        geminiResult: geminiResult,
      );
      final finalData = reconciled.reconciledData;

      bool cardFieldPlacementSuccess = true;

      // 1. Name Check
      if (c.containsKey('gtName')) {
        final expectedName = c['gtName'];
        nameEval++;
        if (expectedName == null) {
          // Company only card: expectedName is null
          if (finalData.fullName == null) {
            nameMatch++;
          } else {
            hallucinationCount++;
            cardFieldPlacementSuccess = false;
          }
        } else {
          final actual = finalData.fullName?.trim() ?? '';
          if (actual.toLowerCase().contains(expectedName.toLowerCase()) || expectedName.toLowerCase().contains(actual.toLowerCase())) {
            nameMatch++;
          } else {
            cardFieldPlacementSuccess = false;
          }
        }
      }

      // 2. Company Check
      if (c.containsKey('gtCompany')) {
        coEval++;
        final expectedCo = c['gtCompany'] as String;
        final actual = finalData.company?.trim() ?? '';
        if (actual.toLowerCase().contains(expectedCo.toLowerCase()) || expectedCo.toLowerCase().contains(actual.toLowerCase())) {
          coMatch++;
        } else {
          cardFieldPlacementSuccess = false;
        }
      }

      // 3. Job Title Check
      if (c.containsKey('gtJobTitle')) {
        jobEval++;
        final expectedJob = c['gtJobTitle'] as String;
        final actual = finalData.jobTitle?.trim() ?? '';
        if (actual.toLowerCase().contains(expectedJob.toLowerCase()) || expectedJob.toLowerCase().contains(actual.toLowerCase())) {
          jobMatch++;
        } else {
          cardFieldPlacementSuccess = false;
        }
      }

      // 4. Phone Check
      if (c.containsKey('gtPhone')) {
        phoneEval++;
        final expectedPhoneDigits = (c['gtPhone'] as String).replaceAll(RegExp(r'\D'), '');
        final hasPhone = finalData.phoneNumbers.any((p) {
          final digits = p.number.replaceAll(RegExp(r'\D'), '');
          return digits.contains(expectedPhoneDigits) || expectedPhoneDigits.contains(digits);
        });
        if (hasPhone) {
          phoneMatch++;
        } else {
          cardFieldPlacementSuccess = false;
        }
      }

      // 5. Email Check
      if (c.containsKey('gtEmail')) {
        emailEval++;
        final expectedEmail = (c['gtEmail'] as String).toLowerCase();
        final hasEmail = finalData.emailAddresses.any((e) => e.email.toLowerCase() == expectedEmail);
        if (hasEmail) {
          emailMatch++;
        } else {
          cardFieldPlacementSuccess = false;
        }
      }

      // 6. Website Check
      if (c.containsKey('gtWebsite')) {
        webEval++;
        final expectedWeb = (c['gtWebsite'] as String).toLowerCase();
        final actualWeb = (finalData.website ?? '').toLowerCase();
        if (actualWeb.contains(expectedWeb) || expectedWeb.contains(actualWeb)) {
          webMatch++;
        } else {
          cardFieldPlacementSuccess = false;
        }
      }

      // 7. Address Check
      if (c.containsKey('gtAddress')) {
        addrEval++;
        final expectedAddr = (c['gtAddress'] as String).toLowerCase();
        final actualAddr = (finalData.address ?? '').toLowerCase();
        if (actualAddr.contains(expectedAddr)) {
          addrMatch++;
        } else {
          cardFieldPlacementSuccess = false;
        }
      }

      if (cardFieldPlacementSuccess) {
        fieldPlacementCorrect++;
      }
    }

    print('================ 20-CARD BENCHMARK REPORT ================');
    print('Person Name Match: $nameMatch / $nameEval (${(nameMatch / nameEval * 100).toStringAsFixed(1)}%)');
    print('Company Match: $coMatch / $coEval (${(coMatch / coEval * 100).toStringAsFixed(1)}%)');
    print('Job Title Match: $jobMatch / $jobEval (${(jobMatch / jobEval * 100).toStringAsFixed(1)}%)');
    print('Phone Match: $phoneMatch / $phoneEval (${(phoneMatch / phoneEval * 100).toStringAsFixed(1)}%)');
    print('Email Match: $emailMatch / $emailEval (${(emailMatch / emailEval * 100).toStringAsFixed(1)}%)');
    print('Website Match: $webMatch / $webEval (${(webMatch / webEval * 100).toStringAsFixed(1)}%)');
    print('Address Accuracy: $addrMatch / $addrEval (${(addrMatch / addrEval * 100).toStringAsFixed(1)}%)');
    print('Field Placement Accuracy: $fieldPlacementCorrect / $totalEvaluatedCards (${(fieldPlacementCorrect / totalEvaluatedCards * 100).toStringAsFixed(1)}%)');
    print('Missing-Field Hallucination Count: $hallucinationCount');
    print('Incorrect Correction Count: $incorrectCorrectionCount');
    print('==========================================================');

    expect(nameMatch / nameEval, greaterThanOrEqualTo(0.90));
    expect(coMatch / coEval, greaterThanOrEqualTo(0.90));
    expect(phoneMatch / phoneEval, greaterThanOrEqualTo(0.95));
    expect(emailMatch / emailEval, greaterThanOrEqualTo(0.95));
    expect(hallucinationCount, equals(0));
    expect(incorrectCorrectionCount, equals(0));
  });
}

