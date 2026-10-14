import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/shared_profile.dart';
import 'package:digital_share/models/saved_connection.dart';
import 'package:digital_share/screens/scan/scanned_profile_screen.dart';
import 'package:digital_share/services/connection_service.dart';
import 'package:digital_share/services/contact_service.dart';

class FakeContactService implements IContactService {
  final ContactSaveResult resultToReturn;
  bool saveCalled = false;

  FakeContactService({this.resultToReturn = const ContactSaveResult(
    status: ContactSaveStatus.success,
    message: 'Contact saved to your phone.',
  )});

  @override
  Contact buildContactFromProfile(SharedProfile profile) => Contact();

  @override
  Future<ContactSaveResult> saveSharedProfileToPhone(SharedProfile profile) async {
    saveCalled = true;
    return resultToReturn;
  }

  @override
  Contact buildContactFromBusinessCard({
    required String? fullName,
    required String? company,
    required String? jobTitle,
    required String? website,
    required String? address,
    required List<BusinessCardPhone> phones,
    required List<BusinessCardEmail> emails,
  }) =>
      Contact();

  @override
  Future<ContactSaveResult> saveBusinessCardToPhone({
    required String? fullName,
    required String? company,
    required String? jobTitle,
    required String? website,
    required String? address,
    required List<BusinessCardPhone> phones,
    required List<BusinessCardEmail> emails,
    bool force = false,
  }) async {
    saveCalled = true;
    return resultToReturn;
  }
}

class FakeConnectionService extends ConnectionService {
  bool saveCalled = false;
  final bool shouldThrowConflict;

  FakeConnectionService({this.shouldThrowConflict = false});

  @override
  Future<SavedConnection> saveConnection(String shareId) async {
    saveCalled = true;
    return SavedConnection(
      shareId: shareId,
      fullName: 'Test User',
      savedAtUtc: DateTime.now().toUtc(),
    );
  }
}

void main() {
  group('ScannedProfileScreen Widget Tests', () {
    final sampleSharedProfile = SharedProfile(
      shareId: 'x7F9K2mQ8pL4vYkVl6VUbG7T',
      fullName: 'Jordan Lee',
      email: 'jordan.lee@example.com',
      phoneNumber: '+1-555-4321',
      jobTitle: 'VP of Engineering',
      company: 'Quantum Innovations',
      website: 'https://quantuminnovations.io',
      address: 'Boston, MA',
      bio: 'Connecting technology leaders globally.',
    );

    testWidgets('Renders scanned profile information and Phase 4 action buttons', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScannedProfileScreen(
            profile: sampleSharedProfile,
            contactService: FakeContactService(),
            connectionService: FakeConnectionService(),
          ),
        ),
      );

      // Verify Screen Title
      expect(find.text('Scanned Digital Card'), findsOneWidget);

      // Verify Scanned Details
      expect(find.text('Jordan Lee'), findsOneWidget);
      expect(find.text('VP of Engineering • Quantum Innovations'), findsOneWidget);
      expect(find.text('jordan.lee@example.com'), findsOneWidget);
      expect(find.text('+1-555-4321'), findsOneWidget);
      expect(find.text('https://quantuminnovations.io'), findsOneWidget);
      expect(find.text('Boston, MA'), findsOneWidget);
      expect(find.text('Connecting technology leaders globally.'), findsOneWidget);

      // Verify 3 Actions
      expect(find.text('Save Both'), findsOneWidget);
      expect(find.text('Save to Phone'), findsOneWidget);
      expect(find.text('Save in App'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('Tapping Save to Phone invokes contact service and displays feedback', (WidgetTester tester) async {
      final fakeContactService = FakeContactService();

      await tester.pumpWidget(
        MaterialApp(
          home: ScannedProfileScreen(
            profile: sampleSharedProfile,
            contactService: fakeContactService,
            connectionService: FakeConnectionService(),
          ),
        ),
      );

      final saveToPhoneBtn = find.text('Save to Phone');
      await tester.ensureVisible(saveToPhoneBtn);
      await tester.tap(saveToPhoneBtn);
      await tester.pump(); // Start async operation
      await tester.pump(const Duration(seconds: 1)); // Complete operation

      expect(fakeContactService.saveCalled, true);
      expect(find.text('Contact saved to your phone.'), findsOneWidget);
    });

    testWidgets('Tapping Save in App invokes connection service and displays feedback', (WidgetTester tester) async {
      final fakeConnectionService = FakeConnectionService();

      await tester.pumpWidget(
        MaterialApp(
          home: ScannedProfileScreen(
            profile: sampleSharedProfile,
            contactService: FakeContactService(),
            connectionService: fakeConnectionService,
          ),
        ),
      );

      final saveInAppBtn = find.text('Save in App');
      await tester.ensureVisible(saveInAppBtn);
      await tester.tap(saveInAppBtn);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(fakeConnectionService.saveCalled, true);
      expect(find.text('Saved in Digital Share.'), findsOneWidget);
    });

    testWidgets('Tapping Save Both executes both operations and shows combined success', (WidgetTester tester) async {
      final fakeContactService = FakeContactService();
      final fakeConnectionService = FakeConnectionService();

      await tester.pumpWidget(
        MaterialApp(
          home: ScannedProfileScreen(
            profile: sampleSharedProfile,
            contactService: fakeContactService,
            connectionService: fakeConnectionService,
          ),
        ),
      );

      final saveBothBtn = find.text('Save Both');
      await tester.ensureVisible(saveBothBtn);
      await tester.tap(saveBothBtn);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(fakeContactService.saveCalled, true);
      expect(fakeConnectionService.saveCalled, true);
      expect(find.text('Saved to Digital Share and your phone.'), findsOneWidget);
    });
  });
}
