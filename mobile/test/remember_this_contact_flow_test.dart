import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/imported_contact.dart';
import 'package:digital_share/services/storage/local_contact_record.dart';
import 'package:digital_share/services/storage/local_contact_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalContactRepository localRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('remember_contact_test_');
    localRepo = LocalContactRepository(storageDirectory: tempDir);
    await localRepo.ensureLoaded();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Remember This Contact - Model & Compatibility Tests', () {
    test('ImportedContact serializes and deserializes rememberThisContact', () {
      final contact = ImportedContact(
        id: 'c_test_1',
        fullName: 'Dr. (Prof.) Sudhir Bhandari',
        company: 'SMS Hospital',
        jobTitle: 'Professor Emeritus',
        rememberThisContact: 'met at chennai',
        createdAtUtc: DateTime.utc(2026, 11, 17),
        updatedAtUtc: DateTime.utc(2026, 11, 17),
      );

      expect(contact.effectiveMemory, 'met at chennai');
      final jsonMap = contact.toJson();
      expect(jsonMap['rememberThisContact'], 'met at chennai');
      expect(jsonMap['personalRemark'], 'met at chennai'); // Synced for backward compatibility

      final deserialized = ImportedContact.fromJson(jsonMap);
      expect(deserialized.id, 'c_test_1');
      expect(deserialized.rememberThisContact, 'met at chennai');
      expect(deserialized.personalRemark, 'met at chennai');
      expect(deserialized.effectiveMemory, 'met at chennai');
    });

    test('ImportedContact handles legacy personalRemark seamlessly', () {
      final legacyJson = {
        'id': 'c_legacy_1',
        'fullName': 'Legacy Contact',
        'personalRemark': 'Legacy Note from 2025',
      };

      final contact = ImportedContact.fromJson(legacyJson);
      expect(contact.effectiveMemory, 'Legacy Note from 2025');
      expect(contact.rememberThisContact, 'Legacy Note from 2025');
      expect(contact.personalRemark, 'Legacy Note from 2025');
    });

    test('LocalContactRecord preserves rememberThisContact across copies and conversions', () {
      final now = DateTime.now();
      final record = LocalContactRecord(
        id: 'rec_100',
        userId: 'u_1',
        fullName: 'Jane Doe',
        rememberThisContact: 'Met at coffee shop in Austin',
        createdAt: now,
        updatedAt: now,
      );

      expect(record.rememberThisContact, 'Met at coffee shop in Austin');

      final imported = record.toImportedContact();
      expect(imported.effectiveMemory, 'Met at coffee shop in Austin');

      final updated = record.copyWith(fullName: 'Jane Smith');
      expect(updated.fullName, 'Jane Smith');
      expect(updated.rememberThisContact, 'Met at coffee shop in Austin');

      final modifiedMemory = record.copyWith(rememberThisContact: 'Met in New York');
      expect(modifiedMemory.rememberThisContact, 'Met in New York');

      final cleared = modifiedMemory.copyWith(clearRememberThisContact: true);
      expect(cleared.rememberThisContact, isNull);
    });

    test('LocalContactRepository persists and updates rememberThisContact', () async {
      final saved = await localRepo.saveContact({
        'fullName': 'Dr. Sudhir Bhandari',
        'company': 'SMS Medical College',
        'rememberThisContact': 'met at chennai',
        'phoneNumbers': [
          {'number': '0141-279505'}
        ],
      });

      expect(saved.effectiveMemory, 'met at chennai');

      // Ordinary update should keep memory intact
      final updated = await localRepo.updateContact(saved.id, {
        'jobTitle': 'Principal & Controller',
      });

      expect(updated.jobTitle, 'Principal & Controller');
      expect(updated.effectiveMemory, 'met at chennai');

      // Explicit memory update
      final memoryUpdated = await localRepo.updateContact(saved.id, {
        'rememberThisContact': 'met at chennai medical conference 2026',
      });
      expect(memoryUpdated.effectiveMemory, 'met at chennai medical conference 2026');
    });
  });

  group('Remember This Contact - Search Filtering Logic Tests', () {
    test('Filtering matches by memory query even if name does not match', () {
      final contacts = [
        ImportedContact(
          id: 'c1',
          fullName: 'Dr. (Prof.) Sudhir Bhandari',
          company: 'SMS Medical',
          jobTitle: 'professor emeritus',
          phoneNumbers: [const ImportedContactPhone(number: '0141-279505')],
          rememberThisContact: 'met at chennai',
        ),
        ImportedContact(
          id: 'c2',
          fullName: 'Elon Musk',
          company: 'Tesla',
          jobTitle: 'CEO',
          phoneNumbers: [const ImportedContactPhone(number: '123-456-7890')],
          rememberThisContact: 'Met at Austin Gigafactory',
        ),
      ];

      // Simulated filtering logic matching ConnectionsScreen
      List<ImportedContact> filterContacts(String query) {
        if (query.trim().isEmpty) return contacts;
        final q = query.toLowerCase().trim();
        return contacts.where((c) {
          final name = (c.fullName ?? '').toLowerCase();
          final company = (c.company ?? '').toLowerCase();
          final job = (c.jobTitle ?? '').toLowerCase();
          final phones = c.phoneNumbers.map((p) => p.number.toLowerCase()).join(' ');
          final emails = c.emailAddresses.map((e) => e.email.toLowerCase()).join(' ');
          final address = (c.address ?? '').toLowerCase();
          final memory = (c.effectiveMemory ?? '').toLowerCase();
          return name.contains(q) ||
              company.contains(q) ||
              job.contains(q) ||
              phones.contains(q) ||
              emails.contains(q) ||
              address.contains(q) ||
              memory.contains(q);
        }).toList();
      }

      // Query "chennai" should find Dr. Sudhir Bhandari via memory
      final chennaiResults = filterContacts('chennai');
      expect(chennaiResults.length, 1);
      expect(chennaiResults.first.fullName, 'Dr. (Prof.) Sudhir Bhandari');

      // Query "austin" should find Elon Musk via memory
      final austinResults = filterContacts('austin');
      expect(austinResults.length, 1);
      expect(austinResults.first.fullName, 'Elon Musk');

      // Query "bhandari" should match via name
      final nameResults = filterContacts('bhandari');
      expect(nameResults.length, 1);
      expect(nameResults.first.fullName, 'Dr. (Prof.) Sudhir Bhandari');

      // Query "nonexistent" returns 0
      final emptyResults = filterContacts('nonexistent');
      expect(emptyResults.isEmpty, isTrue);
    });
  });
}
