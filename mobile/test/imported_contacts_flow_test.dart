import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/check_duplicate_result.dart';
import 'package:digital_share/models/field_evidence.dart';
import 'package:digital_share/models/imported_contact.dart';
import 'package:digital_share/models/saved_connection.dart';
import 'package:digital_share/screens/connections/connections_screen.dart';
import 'package:digital_share/screens/connections/imported_contact_details_screen.dart';
import 'package:digital_share/screens/scan/business_card_review_screen.dart';
import 'package:digital_share/services/api_client.dart';
import 'package:digital_share/services/connection_service.dart';
import 'package:digital_share/services/imported_contact_service.dart';

class MockConnectionService extends ConnectionService {
  final List<SavedConnection> mockConnections;
  MockConnectionService({this.mockConnections = const []});

  @override
  Future<List<SavedConnection>> getConnections() async => mockConnections;
}

class MockImportedContactService extends ImportedContactService {
  bool checkDuplicateCalled = false;
  bool saveContactCalled = false;
  bool deleteContactCalled = false;
  bool updateContactCalled = false;

  CheckDuplicateResult duplicateResult;
  List<ImportedContact> contactsToReturn;
  ImportedContact? savedContactReturn;
  bool shouldThrowError = false;

  MockImportedContactService({
    this.duplicateResult = const CheckDuplicateResult(isDuplicate: false),
    this.contactsToReturn = const [],
    this.savedContactReturn,
  });

  @override
  Future<CheckDuplicateResult> checkDuplicate({
    required List<String> phoneNumbers,
    required List<String> emailAddresses,
  }) async {
    checkDuplicateCalled = true;
    if (shouldThrowError) {
      throw ApiException('Duplicate check network error');
    }
    return duplicateResult;
  }

  @override
  Future<ImportedContact> saveContact(
    Map<String, dynamic> contactData, {
    String? frontImagePath,
    String? backImagePath,
    String? rawRecognizedText,
    String? frontRawText,
    String? backRawText,
    List<Map<String, dynamic>> frontObservations = const [],
    List<Map<String, dynamic>> backObservations = const [],
    String? ocrEngineName,
    String? ocrModelVersion,
    double? overallOcrConfidence,
    Map<String, FieldEvidence> fieldEvidence = const {},
    String? parserVersion,
    String? preprocessingVersion,
    String? imageFingerprint,
    String? imageDHash,
    String? notes,
  }) async {
    saveContactCalled = true;
    if (shouldThrowError) {
      throw ApiException('Failed to save contact');
    }
    return savedContactReturn ??
        ImportedContact(
          id: 'new-id-123',
          fullName: contactData['fullName'] as String?,
          company: contactData['company'] as String?,
        );
  }

  @override
  Future<List<ImportedContact>> getContacts() async {
    if (shouldThrowError) {
      throw ApiException('Unable to load cards');
    }
    return contactsToReturn;
  }

  @override
  Future<ImportedContact> updateContact(
    String id,
    Map<String, dynamic> updatedData,
  ) async {
    updateContactCalled = true;
    if (shouldThrowError) {
      throw ApiException('Failed to update contact');
    }
    return ImportedContact(
      id: id,
      fullName: updatedData['fullName'] as String?,
      company: updatedData['company'] as String?,
      jobTitle: updatedData['jobTitle'] as String?,
      website: updatedData['website'] as String?,
      address: updatedData['address'] as String?,
      phoneNumbers: (updatedData['phoneNumbers'] as List<dynamic>?)
              ?.map((p) => ImportedContactPhone(
                    number: p['number'] as String,
                    label: p['label'] as String?,
                  ))
              .toList() ??
          const [],
      emailAddresses: (updatedData['emailAddresses'] as List<dynamic>?)
              ?.map((e) => ImportedContactEmail(
                    email: e['email'] as String,
                    label: e['label'] as String?,
                  ))
              .toList() ??
          const [],
    );
  }

  @override
  Future<void> deleteContact(String id) async {
    deleteContactCalled = true;
    if (shouldThrowError) {
      throw ApiException('Failed to delete contact');
    }
  }
}

void main() {
  final sampleExistingContact = ImportedContact(
    id: 'existing-card-1',
    fullName: 'Rahul Kumar',
    company: 'ABC Technologies',
    jobTitle: 'Senior Developer',
    website: 'www.abc.com',
    address: 'Chennai, Tamil Nadu',
    phoneNumbers: const [
      ImportedContactPhone(
        id: 'p1',
        number: '+91 98765 43210',
        normalizedNumber: '+919876543210',
        label: 'Mobile',
      ),
      ImportedContactPhone(
        id: 'p2',
        number: '+91 44 2345 6789',
        normalizedNumber: '+914423456789',
        label: 'Office',
      ),
    ],
    emailAddresses: const [
      ImportedContactEmail(
        id: 'e1',
        email: 'rahul@abc.com',
        normalizedEmail: 'rahul@abc.com',
        label: 'Work',
      ),
      ImportedContactEmail(
        id: 'e2',
        email: 'rahul.personal@gmail.com',
        normalizedEmail: 'rahul.personal@gmail.com',
        label: 'Personal',
      ),
    ],
  );

  final sampleScannedCard = BusinessCardData(
    fullName: 'Rahul Kumar',
    company: 'ABC Technologies',
    jobTitle: 'Senior Developer',
    website: 'www.abc.com',
    address: 'Chennai, Tamil Nadu',
    phoneNumbers: const [
      BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile'),
    ],
    emailAddresses: const [
      BusinessCardEmail(email: 'rahul@abc.com', label: 'Work'),
    ],
  );

  group('Phase 5B: Save in Digital Share & Duplicate Detection Flow', () {
    testWidgets(
        'Save in Digital Share checks duplicate and saves when no duplicate exists',
        (tester) async {
      final mockService = MockImportedContactService(
        duplicateResult: const CheckDuplicateResult(isDuplicate: false),
      );

      BusinessCardData? returned;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  returned = await Navigator.of(context).push<BusinessCardData>(
                    MaterialPageRoute(
                      builder: (_) => BusinessCardReviewScreen(
                        cardData: sampleScannedCard,
                        contactService: mockService,
                      ),
                    ),
                  );
                },
                child: const Text('Open Review'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Review'));
      await tester.pumpAndSettle();

      expect(find.text('Save in Digital Share'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('confirm_details_button')));
      await tester.tap(find.byKey(const Key('confirm_details_button')));
      await tester.pumpAndSettle();

      expect(mockService.checkDuplicateCalled, isTrue);
      expect(mockService.saveContactCalled, isTrue);
      expect(find.text('Saved in Digital Share!'), findsOneWidget);
      expect(returned, isNotNull);
    });

    testWidgets(
        'Duplicate check match displays Already Saved popup with OK and Show Details buttons',
        (tester) async {
      final mockService = MockImportedContactService(
        duplicateResult: CheckDuplicateResult(
          isDuplicate: true,
          existingContact: sampleExistingContact,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(
            cardData: sampleScannedCard,
            contactService: mockService,
          ),
        ),
      );

      await tester.ensureVisible(find.byKey(const Key('confirm_details_button')));
      await tester.tap(find.byKey(const Key('confirm_details_button')));
      await tester.pumpAndSettle();

      expect(mockService.checkDuplicateCalled, isTrue);
      expect(mockService.saveContactCalled, isFalse); // Did not create duplicate

      // Popup visible
      expect(find.text('Already Saved'), findsOneWidget);
      expect(
        find.text('This business card/contact is already saved in Digital Share.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('duplicate_dialog_ok_button')), findsOneWidget);
      expect(find.byKey(const Key('duplicate_dialog_show_details_button')), findsOneWidget);
    });

    testWidgets('Tapping OK closes popup and remains on review screen',
        (tester) async {
      final mockService = MockImportedContactService(
        duplicateResult: CheckDuplicateResult(
          isDuplicate: true,
          existingContact: sampleExistingContact,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(
            cardData: sampleScannedCard,
            contactService: mockService,
          ),
        ),
      );

      await tester.ensureVisible(find.byKey(const Key('confirm_details_button')));
      await tester.tap(find.byKey(const Key('confirm_details_button')));
      await tester.pumpAndSettle();

      // Tap OK
      await tester.tap(find.byKey(const Key('duplicate_dialog_ok_button')));
      await tester.pumpAndSettle();

      // Popup closed, still on review screen
      expect(find.text('Already Saved'), findsNothing);
      expect(find.text('Business Card Details'), findsOneWidget);
      expect(find.text('Save in Digital Share'), findsOneWidget);
      expect(mockService.saveContactCalled, isFalse);
    });

    testWidgets('Tapping Show Details opens existing contact details screen',
        (tester) async {
      final mockService = MockImportedContactService(
        duplicateResult: CheckDuplicateResult(
          isDuplicate: true,
          existingContact: sampleExistingContact,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(
            cardData: sampleScannedCard,
            contactService: mockService,
          ),
        ),
      );

      await tester.ensureVisible(find.byKey(const Key('confirm_details_button')));
      await tester.tap(find.byKey(const Key('confirm_details_button')));
      await tester.pumpAndSettle();

      // Tap Show Details
      await tester.tap(find.byKey(const Key('duplicate_dialog_show_details_button')));
      await tester.pumpAndSettle();

      // Dialog closed, on details screen
      expect(find.text('Already Saved'), findsNothing);
      expect(find.text('Contact Details'), findsOneWidget);
      expect(find.text('Rahul Kumar'), findsOneWidget);
      expect(find.text('Senior Developer • ABC Technologies'), findsOneWidget);
      expect(find.text('+91 98765 43210'), findsOneWidget);
      expect(find.text('+91 44 2345 6789'), findsOneWidget);
      expect(find.text('rahul@abc.com'), findsOneWidget);
    });

    testWidgets('Handles duplicate check API error gracefully', (tester) async {
      final mockService = MockImportedContactService()
        ..shouldThrowError = true;

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(
            cardData: sampleScannedCard,
            contactService: mockService,
          ),
        ),
      );

      await tester.ensureVisible(find.byKey(const Key('confirm_details_button')));
      await tester.tap(find.byKey(const Key('confirm_details_button')));
      await tester.pumpAndSettle();

      expect(find.text('Duplicate check network error'), findsOneWidget);
      expect(find.text('Business Card Details'), findsOneWidget);
    });
  });

  group('Phase 5B: Saved Business Cards List & ConnectionsScreen', () {
    testWidgets('Switching to Business Cards tab displays saved cards',
        (tester) async {
      final mockService = MockImportedContactService(
        contactsToReturn: [sampleExistingContact],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionsScreen(
            connectionService: MockConnectionService(),
            importedContactService: mockService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially on Digital Share tab
      expect(find.text('Digital Share'), findsOneWidget);
      expect(find.text('Business Cards'), findsOneWidget);

      // Switch tab to Business Cards
      await tester.tap(find.text('Business Cards'));
      await tester.pumpAndSettle();

      expect(find.text('Rahul Kumar'), findsOneWidget);
      expect(find.text('+91 98765 43210'), findsOneWidget);
    });

    testWidgets('Business Cards empty state when no physical cards saved',
        (tester) async {
      final mockService = MockImportedContactService(
        contactsToReturn: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionsScreen(
            connectionService: MockConnectionService(),
            importedContactService: mockService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Business Cards'));
      await tester.pumpAndSettle();

      expect(find.text('No Business Cards Yet'), findsOneWidget);
      expect(
        find.text('Scan physical business cards using the scanner to save them here.'),
        findsOneWidget,
      );
    });

    testWidgets('Filters saved business cards by search text', (tester) async {
      final mockService = MockImportedContactService(
        contactsToReturn: [
          sampleExistingContact,
          const ImportedContact(
            id: 'card-2',
            fullName: 'Anita Roy',
            company: 'Tech Solutions',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionsScreen(
            connectionService: MockConnectionService(),
            importedContactService: mockService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Business Cards'));
      await tester.pumpAndSettle();

      expect(find.text('Rahul Kumar'), findsOneWidget);
      expect(find.text('Anita Roy'), findsOneWidget);

      // Search for 'Anita'
      await tester.enterText(
          find.byKey(const Key('business_cards_search_field')), 'Anita');
      await tester.pumpAndSettle();

      expect(find.text('Anita Roy'), findsOneWidget);
      expect(find.text('Rahul Kumar'), findsNothing);
    });

    testWidgets('Tapping delete button prompts confirmation dialog',
        (tester) async {
      final mockService = MockImportedContactService(
        contactsToReturn: [sampleExistingContact],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionsScreen(
            connectionService: MockConnectionService(),
            importedContactService: mockService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Business Cards'));
      await tester.pumpAndSettle();

      // Tap delete icon
      await tester.tap(find.byTooltip('Delete business card'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Business Card'), findsOneWidget);
      expect(
        find.text('Delete Rahul Kumar from your saved business cards?'),
        findsOneWidget,
      );

      // Confirm delete
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(mockService.deleteContactCalled, isTrue);
      expect(find.text('Deleted Rahul Kumar.'), findsOneWidget);
    });
  });

  group('Phase 5B: Contact Details Screen & Editing', () {
    testWidgets('Renders all fields, multiple phones, and multiple emails',
        (tester) async {
      final mockService = MockImportedContactService();

      await tester.pumpWidget(
        MaterialApp(
          home: ImportedContactDetailsScreen(
            contact: sampleExistingContact,
            contactService: mockService,
          ),
        ),
      );

      expect(find.text('Contact Details'), findsOneWidget);
      expect(find.text('Rahul Kumar'), findsOneWidget);
      expect(find.text('Senior Developer • ABC Technologies'), findsOneWidget);

      // Multiple phones
      expect(find.text('+91 98765 43210'), findsOneWidget);
      expect(find.text('Mobile'), findsOneWidget);
      expect(find.text('+91 44 2345 6789'), findsOneWidget);
      expect(find.text('Office'), findsOneWidget);

      // Multiple emails
      expect(find.text('rahul@abc.com'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('rahul.personal@gmail.com'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);

      // Website and address
      expect(find.text('www.abc.com'), findsOneWidget);
      expect(find.text('Chennai, Tamil Nadu'), findsOneWidget);
    });

    testWidgets('Tapping edit opens EditImportedContactScreen and updates contact',
        (tester) async {
      final mockService = MockImportedContactService();

      await tester.pumpWidget(
        MaterialApp(
          home: ImportedContactDetailsScreen(
            contact: sampleExistingContact,
            contactService: mockService,
          ),
        ),
      );

      // Tap edit button in AppBar
      await tester.tap(find.byKey(const Key('edit_imported_contact_button')));
      await tester.pumpAndSettle();

      expect(find.text('Edit Business Card'), findsOneWidget);
      expect(find.byKey(const Key('edit_name_field')), findsOneWidget);

      // Edit name
      await tester.enterText(
          find.byKey(const Key('edit_name_field')), 'Rahul Kumar Updated');
      await tester.pumpAndSettle();

      // Tap Save Changes
      await tester.ensureVisible(find.byKey(const Key('save_imported_contact_button')));
      await tester.tap(find.byKey(const Key('save_imported_contact_button')));
      await tester.pumpAndSettle();

      expect(mockService.updateContactCalled, isTrue);
      expect(find.text('Contact updated successfully.'), findsOneWidget);
      expect(find.text('Rahul Kumar Updated'), findsOneWidget);
    });

    testWidgets('Delete contact from details screen with user confirmation',
        (tester) async {
      final mockService = MockImportedContactService();

      bool? deleted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  deleted = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ImportedContactDetailsScreen(
                        contact: sampleExistingContact,
                        contactService: mockService,
                      ),
                    ),
                  );
                },
                child: const Text('Open Details'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Details'));
      await tester.pumpAndSettle();

      // Tap delete in AppBar
      await tester.tap(find.byKey(const Key('delete_imported_contact_button')));
      await tester.pumpAndSettle();

      expect(find.text('Delete Business Card'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(mockService.deleteContactCalled, isTrue);
      expect(find.text('Deleted Rahul Kumar.'), findsOneWidget);
      expect(deleted, isTrue);
    });
  });
}
