import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/imported_contact.dart';
import 'package:digital_share/screens/connections/imported_contact_details_screen.dart';
import 'package:digital_share/services/imported_contact_service.dart';
import 'package:digital_share/services/storage/local_contact_record.dart';
import 'package:digital_share/services/storage/local_contact_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalContactRepository localRepo;
  late ImportedContactService contactService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('contact_remarks_test_');
    localRepo = LocalContactRepository(storageDirectory: tempDir);
    await localRepo.ensureLoaded();
    contactService = ImportedContactService(localRepo: localRepo);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Feature 1: Contact Remarks Model & Persistence Tests', () {
    test('ImportedContact serializes and deserializes personalRemark', () {
      final contact = ImportedContact(
        id: 'c1',
        fullName: 'John Doe',
        company: 'Acme Corp',
        personalRemark: 'Met at Chennai conference 2026',
        createdAtUtc: DateTime.utc(2026, 11, 5),
        updatedAtUtc: DateTime.utc(2026, 11, 5),
      );

      final jsonMap = contact.toJson();
      expect(jsonMap['personalRemark'], 'Met at Chennai conference 2026');

      final deserialized = ImportedContact.fromJson(jsonMap);
      expect(deserialized.id, 'c1');
      expect(deserialized.fullName, 'John Doe');
      expect(deserialized.personalRemark, 'Met at Chennai conference 2026');
    });

    test('LocalContactRecord preserves personalRemark across copyWith and conversions', () {
      final now = DateTime.now();
      final record = LocalContactRecord(
        id: 'rec1',
        userId: 'user1',
        fullName: 'Jane Smith',
        personalRemark: 'Referred by Rajesh',
        createdAt: now,
        updatedAt: now,
      );

      expect(record.personalRemark, 'Referred by Rajesh');

      final imported = record.toImportedContact();
      expect(imported.personalRemark, 'Referred by Rajesh');

      final copy = record.copyWith(fullName: 'Jane Doe');
      expect(copy.fullName, 'Jane Doe');
      expect(copy.personalRemark, 'Referred by Rajesh');

      final updatedCopy = record.copyWith(personalRemark: 'Updated Remark');
      expect(updatedCopy.personalRemark, 'Updated Remark');

      final json = record.toJson();
      expect(json['personalRemark'], 'Referred by Rajesh');
      final fromJsonRecord = LocalContactRecord.fromJson(json);
      expect(fromJsonRecord.personalRemark, 'Referred by Rajesh');
    });

    test('LocalContactRepository preserves personalRemark on ordinary update', () async {
      final saved = await localRepo.saveContact({
        'fullName': 'Alice Wonderland',
        'personalRemark': 'Important client from Bangalore',
        'phoneNumbers': [
          {'number': '+91 91234 56789'}
        ],
      });

      expect(saved.personalRemark, 'Important client from Bangalore');

      // Ordinary update without changing personalRemark
      final updated = await localRepo.updateContact(saved.id, {
        'company': 'Wonderland Tech',
      });

      expect(updated.company, 'Wonderland Tech');
      expect(updated.personalRemark, 'Important client from Bangalore');

      // Explicitly clear remark
      final cleared = await localRepo.updateContact(saved.id, {
        'personalRemark': null,
      });
      expect(cleared.personalRemark, isNull);
    });
  });

  group('Feature 1: Contact Remarks Details Screen Widget Tests', () {
    testWidgets('Shows default text when no personal remark exists', (tester) async {
      final contact = ImportedContact(
        id: 'test_c1',
        fullName: 'Michael Scott',
        company: 'Dunder Mifflin',
        personalRemark: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ImportedContactDetailsScreen(
            contact: contact,
            contactService: contactService,
          ),
        ),
      );

      expect(find.text('MY PERSONAL REMARK'), findsOneWidget);
      expect(find.text('No personal remark added yet.'), findsOneWidget);
      expect(find.text('Add Remark'), findsOneWidget);
    });

    testWidgets('Shows remark text and Edit button when remark exists', (tester) async {
      final contact = ImportedContact(
        id: 'test_c2',
        fullName: 'Dwight Schrute',
        company: 'Schrute Farms',
        personalRemark: 'Assistant to the Regional Manager. Beet enthusiast.',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ImportedContactDetailsScreen(
            contact: contact,
            contactService: contactService,
          ),
        ),
      );

      expect(find.text('MY PERSONAL REMARK'), findsOneWidget);
      expect(find.text('Assistant to the Regional Manager. Beet enthusiast.'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });
  });
}
