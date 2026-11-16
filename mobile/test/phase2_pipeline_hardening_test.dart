import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/card_analysis_result.dart';
import 'package:digital_share/services/business_card_parser.dart';
import 'package:digital_share/services/ocr/ocr_observation.dart';
import 'package:digital_share/services/ocr/paddle_ocr_engine.dart';
import 'package:digital_share/services/storage/local_scan_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2 — Person Name and Company Classification Hardening', () {
    final parser = BusinessCardParser();

    test('Two-word capitalized company names are NOT classified as person name', () {
      final cardExamples = [
        'Apex Healthcare\n+1 555 123 4567\ninfo@apexhealth.com',
        'Blue Horizon Technologies\n100 Tech Park\n+1 555 987 6543',
        'Summit Consulting\nwww.summitconsulting.com\ncontact@summit.com',
        'Global Business Solutions\nSales Office\n+1 555 222 3333',
      ];

      for (final text in cardExamples) {
        final result = parser.parse(text);
        expect(result.fullName ?? '', isNot('Apex Healthcare'));
        expect(result.fullName ?? '', isNot('Blue Horizon Technologies'));
        expect(result.fullName ?? '', isNot('Summit Consulting'));
        expect(result.fullName ?? '', isNot('Global Business Solutions'));
        expect(result.company, isNotEmpty);
      }
    });

    test('Person name returns empty string if no positive personal signals exist', () {
      const text = 'Alpha Beta\nGamma Delta\n+1 555 123 4567';
      final result = parser.parse(text);
      // Without honorific, credentials, initials, job title, or email match, neither qualifies confidently
      expect(result.fullName == null || result.fullName!.isEmpty, isTrue);
    });

    test('Person name is confidently recognized with honorific or job title adjacency', () {
      const textWithHonorific = 'Dr. Robert Smith\nCardiology Specialist\nApex Healthcare\n+1 555 123 4567';
      final result1 = parser.parse(textWithHonorific);
      expect(result1.fullName, equals('Dr. Robert Smith'));
      expect(result1.jobTitle, contains('Cardiology'));
      expect(result1.company, equals('Apex Healthcare'));

      const textWithAdjacency = 'Apex Healthcare\nElena Rostova\nSenior Software Engineer\nelena@apex.com';
      final result2 = parser.parse(textWithAdjacency);
      expect(result2.fullName, equals('Elena Rostova'));
      expect(result2.jobTitle, equals('Senior Software Engineer'));
      expect(result2.company, equals('Apex Healthcare'));
    });
  });

  group('Phase 2 — Designation versus Company Classification', () {
    final parser = BusinessCardParser();

    test('Job title containing Services, Solutions, or Enterprises is classified as jobTitle, not company', () {
      final testCases = [
        {
          'text': 'Acme Corp\nSarah Jenkins\nHead of Client Services\n+1 555 111 2222',
          'expectedTitle': 'Head of Client Services',
          'expectedCompany': 'Acme Corp',
        },
        {
          'text': 'TechFlow Inc\nMichael Chang\nDirector of Cloud Solutions\nmichael@techflow.io',
          'expectedTitle': 'Director of Cloud Solutions',
          'expectedCompany': 'TechFlow Inc',
        },
        {
          'text': 'Global Dynamics\nDavid Miller\nVice President - Enterprise Services\ndavid@gd.com',
          'expectedTitle': 'Vice President - Enterprise Services',
          'expectedCompany': 'Global Dynamics',
        },
        {
          'text': 'Vanguard Systems\nAlexander Wright\nManaging Director\n+1 555 333 4444',
          'expectedTitle': 'Managing Director',
          'expectedCompany': 'Vanguard Systems',
        },
        {
          'text': 'Apex Marine Services\nJohn Taylor\nSenior Software Engineer\njohn@apexmarine.com',
          'expectedTitle': 'Senior Software Engineer',
          'expectedCompany': 'Apex Marine Services',
        },
      ];

      for (final tc in testCases) {
        final result = parser.parse(tc['text']!);
        expect(result.jobTitle?.toLowerCase(), equals(tc['expectedTitle']!.toLowerCase()));
        expect(result.company?.toLowerCase(), equals(tc['expectedCompany']!.toLowerCase()));
      }
    });

    test('Apex Marine Services without personal role is recognized as company', () {
      const text = 'Apex Marine Services\n+1 555 888 9999\ninfo@apexmarine.com';
      final result = parser.parse(text);
      expect(result.company, equals('Apex Marine Services'));
      expect(result.jobTitle, isNull);
    });
  });

  group('Phase 2 — Contact Details Non-Destructive Union Merging', () {
    test('Preserves multiple baseline phones when AI response returns only one', () {
      final baseline = BusinessCardData(
        fullName: 'Alice Smith',
        company: 'Innovate LLC',
        phoneNumbers: const [
          BusinessCardPhone(number: '+1 (555) 123-4567', label: 'Mobile'),
          BusinessCardPhone(number: '+1 (555) 987-6543', label: 'Office'),
          BusinessCardPhone(number: '+1 (555) 000-1111', label: 'Fax'),
        ],
        emailAddresses: const [
          BusinessCardEmail(email: 'alice@innovate.com', label: 'Work'),
          BusinessCardEmail(email: 'alice.personal@gmail.com', label: 'Personal'),
        ],
      );

      const aiResult = CardAnalysisResult(
        clientRequestId: 'req_test',
        analysisCacheKey: 'cache_test',
        fullName: ExtractedField(value: 'Alice Smith', confidence: 0.99),
        phoneNumbers: [
          ExtractedPhone(number: '+1 555 123 4567', label: 'Cellular', confidence: 0.95),
        ],
        emailAddresses: [
          ExtractedEmail(email: 'alice@innovate.com', confidence: 0.98),
        ],
      );

      final merged = aiResult.toBusinessCardData(baseline);

      // Baseline phones must NOT be truncated to 1
      expect(merged.phoneNumbers.length, equals(3));
      expect(merged.phoneNumbers.any((p) => p.number.contains('987')), isTrue);
      expect(merged.phoneNumbers.any((p) => p.number.contains('000')), isTrue);

      // Baseline emails must NOT be truncated to 1
      expect(merged.emailAddresses.length, equals(2));
      expect(merged.emailAddresses.any((e) => e.email.contains('gmail.com')), isTrue);
    });

    test('Safely adds newly discovered phone numbers from AI response', () {
      final baseline = BusinessCardData(
        fullName: 'Bob Brown',
        company: 'Vanguard',
        phoneNumbers: const [
          BusinessCardPhone(number: '+1 555 111 2222', label: 'Main'),
        ],
      );

      const aiResult = CardAnalysisResult(
        clientRequestId: 'req_test',
        analysisCacheKey: 'cache_test',
        phoneNumbers: [
          ExtractedPhone(number: '+1 555 111 2222', label: 'Direct'),
          ExtractedPhone(number: '+1 555 999 8888', label: 'Mobile'),
        ],
      );

      final merged = aiResult.toBusinessCardData(baseline);
      expect(merged.phoneNumbers.length, equals(2));
      expect(merged.phoneNumbers.any((p) => p.number.contains('999')), isTrue);
    });
  });

  group('Phase 2 — PaddleOCR Column-Aware Reading Order', () {
    test('Two-column layout does not zig-zag across columns', () {
      final engine = PaddleOcrEngine();

      // Synthetic two-column card (Width 800, Height 400)
      // Header: (100, 20) to (700, 60)
      // Left column:
      //   L1: (50, 100) to (300, 140)
      //   L2: (50, 160) to (300, 200)
      //   L3: (50, 220) to (300, 260)
      // Right column:
      //   R1: (450, 105) to (750, 145) (Y overlaps L1)
      //   R2: (450, 165) to (750, 205) (Y overlaps L2)
      //   R3: (450, 225) to (750, 265) (Y overlaps L3)

      final header = const PaddleTextBox(minX: 100, minY: 20, maxX: 700, maxY: 60, score: 0.99);
      final l1 = const PaddleTextBox(minX: 50, minY: 100, maxX: 300, maxY: 140, score: 0.95);
      final l2 = const PaddleTextBox(minX: 50, minY: 160, maxX: 300, maxY: 200, score: 0.95);
      final l3 = const PaddleTextBox(minX: 50, minY: 220, maxX: 300, maxY: 260, score: 0.95);
      final r1 = const PaddleTextBox(minX: 450, minY: 105, maxX: 750, maxY: 145, score: 0.95);
      final r2 = const PaddleTextBox(minX: 450, minY: 165, maxX: 750, maxY: 205, score: 0.95);
      final r3 = const PaddleTextBox(minX: 450, minY: 225, maxX: 750, maxY: 265, score: 0.95);

      final input = [r2, l1, r1, header, l3, r3, l2];
      final sorted = engine.sortBoxesReadingOrderForTesting(input);

      // Verify Header comes first
      expect(sorted[0], equals(header));

      // Verify left column boxes are read before right column boxes (no interleaving L1, R1, L2, R2)
      final l1Idx = sorted.indexOf(l1);
      final l2Idx = sorted.indexOf(l2);
      final l3Idx = sorted.indexOf(l3);
      final r1Idx = sorted.indexOf(r1);
      final r2Idx = sorted.indexOf(r2);
      final r3Idx = sorted.indexOf(r3);

      expect(l1Idx < l2Idx, isTrue);
      expect(l2Idx < l3Idx, isTrue);
      expect(l3Idx < r1Idx, isTrue); // Entire left column precedes right column!
      expect(r1Idx < r2Idx, isTrue);
      expect(r2Idx < r3Idx, isTrue);
    });
  });

  group('Phase 2 — Scan Cache Observations and Migration', () {
    late Directory tempDir;
    late LocalScanCacheManager cacheManager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ds_cache_test_');
      cacheManager = LocalScanCacheManager(cacheDirectory: tempDir);
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('CachedScanEntry preserves and restores OCR observations', () async {
      final frontObs = [
        const OcrObservation(
          id: 'paddle_0',
          text: 'Jane Doe',
          boundingBox: Rect.fromLTWH(50, 100, 200, 40),
          normalizedBoundingBox: Rect.fromLTWH(0.05, 0.1, 0.2, 0.04),
          confidence: 0.98,
          engine: 'PaddleOCR',
          lineIndex: 0,
        ),
      ];

      final cardData = BusinessCardData(
        fullName: 'Jane Doe',
        company: 'Acme Corp',
      );

      await cacheManager.putScanResult(
        imageFingerprint: 'fp_1234567890abcdef',
        frontRawText: 'Jane Doe\nAcme Corp',
        parsedData: cardData,
        frontObservations: frontObs,
        frontLines: ['Jane Doe', 'Acme Corp'],
      );

      final retrieved = await cacheManager.getScanResult('fp_1234567890abcdef');
      expect(retrieved, isNotNull);
      expect(retrieved!.frontObservations.length, equals(1));
      expect(retrieved.frontObservations.first['text'], equals('Jane Doe'));
      expect(retrieved.frontObservations.first['engine'], equals('PaddleOCR'));
      expect(retrieved.frontLines, equals(['Jane Doe', 'Acme Corp']));

      // Reconstruct observation from cache
      final restoredObs = OcrObservation.fromJson(retrieved.frontObservations.first);
      expect(restoredObs.text, equals('Jane Doe'));
      expect(restoredObs.confidence, equals(0.98));
    });

    test('LocalScanCacheManager migrates from legacy temp files when persistent cache empty', () async {
      final legacyFpFile = File('${Directory.systemTemp.path}/digital_share_fingerprint_cache.json');
      try {
        // Write synthetic legacy cache entry
        final legacyData = [
          {
            'imageFingerprint': 'legacy_fp_999',
            'frontRawText': 'Legacy Card Text',
            'parsedData': {'fullName': 'Legacy Person', 'phoneNumbers': []},
            'cachedAt': DateTime.now().toIso8601String(),
          }
        ];
        await legacyFpFile.writeAsString(jsonEncode(legacyData));

        final freshPersistentDir = await Directory.systemTemp.createTemp('ds_persistent_');
        final persistentManager = LocalScanCacheManager(cacheDirectory: freshPersistentDir);

        final result = await persistentManager.getScanResult('legacy_fp_999');
        expect(result, isNotNull);
        expect(result!.frontRawText, equals('Legacy Card Text'));

        await freshPersistentDir.delete(recursive: true);
      } finally {
        if (await legacyFpFile.exists()) {
          await legacyFpFile.delete();
        }
      }
    });
  });
}

