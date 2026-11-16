import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/services/ocr/duplicate_card_detector.dart';
import 'package:digital_share/services/ocr/image_hash_service.dart';
import 'package:digital_share/services/storage/local_contact_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late LocalContactRepository repo;
  late DuplicateCardDetector detector;
  const hashService = ImageHashService();

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('ds_duplicate_test_');
    repo = LocalContactRepository(
      storageDirectory: testDir,
      fileName: 'dup_contacts.json',
    );
    detector = DuplicateCardDetector(
      repository: repo,
      hashService: hashService,
    );
  });

  tearDown(() async {
    try {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('DuplicateCardDetector Stage 1 & 2 Tests', () {
    test('Stage 1: Detects exact SHA-256 image match with 1.0 confidence', () async {
      await repo.saveContact(
        {
          'fullName': 'Aria Montgomery',
          'company': 'Rosewood Publishing Ltd',
        },
        imageFingerprint: 'exact_sha256_aria_123',
      );

      final result = await detector.checkExactFingerprint('exact_sha256_aria_123');
      expect(result.isDuplicate, isTrue);
      expect(result.matchType, equals(DuplicateMatchType.exactImage));
      expect(result.confidence, equals(1.0));
      expect(result.matchedContact?.fullName, equals('Aria Montgomery'));
    });

    test('Stage 2: Detects duplicate by matching phone number digits', () async {
      await repo.saveContact({
        'fullName': 'Brian O\'Conner',
        'company': 'Racer Logic',
        'phoneNumbers': [
          {'number': '+1 (310) 555-0149', 'label': 'Mobile'}
        ],
        'emailAddresses': [
          {'email': 'brian@racerlogic.com', 'label': 'Work'}
        ],
      });

      const newScan = BusinessCardData(
        fullName: 'Brian OConner',
        company: 'Racer Logic Inc',
        phoneNumbers: [BusinessCardPhone(number: '310-555-0149')],
      );

      final result = await detector.checkSimilarity(cardData: newScan);
      expect(result.isDuplicate, isTrue);
      expect(result.matchedContact?.fullName, equals('Brian O\'Conner'));
      expect(result.confidence, greaterThanOrEqualTo(0.85));
    });

    test('Stage 2: Detects duplicate by matching email address', () async {
      await repo.saveContact({
        'fullName': 'Claire Redfield',
        'company': 'TerraSave',
        'emailAddresses': [
          {'email': 'claire.redfield@terrasave.org', 'label': 'Work'}
        ],
      });

      const newScan = BusinessCardData(
        fullName: 'Claire Redfield',
        emailAddresses: [BusinessCardEmail(email: 'CLAIRE.REDFIELD@TERRASAVE.ORG')],
      );

      final result = await detector.checkSimilarity(cardData: newScan);
      expect(result.isDuplicate, isTrue);
      expect(result.matchedContact?.fullName, equals('Claire Redfield'));
    });

    test('Stage 2: Detects high visual similarity with perceptual dHash', () async {
      const dHashA = '1010101010101010';
      const dHashSimilar = '1010101010101011'; // 1 bit difference

      final dist = hashService.hammingDistance(dHashA, dHashSimilar);
      expect(dist, equals(1));

      await repo.saveContact(
        {
          'fullName': 'Diana Prince',
          'company': 'Themyscira Cultural Arts',
        },
        imageDHash: dHashA,
      );

      const newScan = BusinessCardData(
        fullName: 'Diana Prince',
        company: 'Themyscira Arts',
      );

      final result = await detector.checkSimilarity(
        cardData: newScan,
        currentDHash: dHashSimilar,
      );
      expect(result.isDuplicate, isTrue);
      expect(result.matchedContact?.fullName, equals('Diana Prince'));
      expect(result.confidence, greaterThanOrEqualTo(0.90));
    });

    test('Returns noDuplicate when contact details are distinct', () async {
      await repo.saveContact({
        'fullName': 'Alice Walker',
        'company': 'Starlight Media',
        'phoneNumbers': [
          {'number': '+1 202 555 0111'}
        ],
      });

      const distinctCard = BusinessCardData(
        fullName: 'Zack Morris',
        company: 'Bayside Tech',
        phoneNumbers: [BusinessCardPhone(number: '+1 909 555 0999')],
        emailAddresses: [BusinessCardEmail(email: 'zack@bayside.com')],
      );

      final result = await detector.checkSimilarity(cardData: distinctCard);
      expect(result.isDuplicate, isFalse);
      expect(result.matchedContact, isNull);
    });
  });
}

