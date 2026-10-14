import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/imported_contact.dart';
import 'package:digital_share/screens/connections/imported_contact_details_screen.dart';
import 'package:digital_share/screens/scan/business_card_review_screen.dart';
import 'package:digital_share/services/contact_communication_service.dart';
import 'package:digital_share/services/contact_service.dart';
import 'package:digital_share/widgets/contact_message_composer.dart';

class MockCommunicationService implements IContactCommunicationService {
  bool openWhatsAppCalled = false;
  String? lastWhatsAppPhone;
  String? lastWhatsAppMessage;
  bool shouldSucceedWhatsApp = true;

  bool openEmailCalled = false;
  String? lastEmailRecipient;
  String? lastEmailSubject;
  String? lastEmailBody;
  bool shouldSucceedEmail = true;

  @override
  Future<bool> openWhatsApp({
    required String phone,
    required String message,
  }) async {
    openWhatsAppCalled = true;
    lastWhatsAppPhone = phone;
    lastWhatsAppMessage = message;
    return shouldSucceedWhatsApp;
  }

  @override
  Future<bool> openEmail({
    required String email,
    required String subject,
    required String body,
  }) async {
    openEmailCalled = true;
    lastEmailRecipient = email;
    lastEmailSubject = subject;
    lastEmailBody = body;
    return shouldSucceedEmail;
  }
}

class MockPhoneContactService extends ContactService {
  bool saveBusinessCardCalled = false;
  List<BusinessCardPhone>? lastSavedPhones;
  List<BusinessCardEmail>? lastSavedEmails;
  ContactSaveResult resultToReturn;

  MockPhoneContactService({
    this.resultToReturn = const ContactSaveResult(
      status: ContactSaveStatus.success,
      message: 'Contact added to your phone.',
    ),
  });

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
    saveBusinessCardCalled = true;
    lastSavedPhones = phones;
    lastSavedEmails = emails;
    return resultToReturn;
  }
}

void main() {
  group('Phase 5C: ContactMessageComposer Component Tests', () {
    testWidgets('3. Message is editable and does not erase', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Rahul Kumar',
              phones: [BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile')],
              emails: [BusinessCardEmail(email: 'rahul@abc.com', label: 'Work')],
            ),
          ),
        ),
      );

      final messageField = find.byKey(const Key('contact_message_field'));
      expect(messageField, findsOneWidget);
      expect(
        tester.widget<TextFormField>(messageField).controller?.text,
        "Hi Rahul, it was great meeting you. Let's stay connected.",
      );

      // Edit the text
      await tester.enterText(messageField, "Custom edited message for Rahul");
      await tester.pump();

      expect(
        tester.widget<TextFormField>(messageField).controller?.text,
        "Custom edited message for Rahul",
      );
    });

    testWidgets('4. WhatsApp shows error when no phone numbers are available', (tester) async {
      final mockComm = MockCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Rahul Kumar',
              phones: const [],
              emails: const [BusinessCardEmail(email: 'rahul@abc.com', label: 'Work')],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('whatsapp_action_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openWhatsAppCalled, isFalse);
      expect(find.text('No phone number is available for this contact.'), findsOneWidget);
    });

    testWidgets('5. One phone opens WhatsApp directly without selection dialog', (tester) async {
      final mockComm = MockCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Rahul Kumar',
              phones: const [
                BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile'),
              ],
              emails: const [],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('whatsapp_action_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openWhatsAppCalled, isTrue);
      expect(mockComm.lastWhatsAppPhone, '+91 98765 43210');
      expect(
        mockComm.lastWhatsAppMessage,
        "Hi Rahul, it was great meeting you. Let's stay connected.",
      );
      // No selection dialog was shown
      expect(find.text('Send WhatsApp Message To'), findsNothing);
    });

    testWidgets('6, 7. Multiple phones display selector and passes selected phone', (tester) async {
      final mockComm = MockCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Rahul Kumar',
              phones: const [
                BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile'),
                BusinessCardPhone(number: '+91 44 2345 6789', label: 'Office'),
              ],
              emails: const [],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('whatsapp_action_button')));
      await tester.pumpAndSettle();

      // Selection dialog rendered
      expect(find.text('Send WhatsApp Message To'), findsOneWidget);
      expect(find.text('Mobile'), findsOneWidget);
      expect(find.text('Office'), findsOneWidget);

      // Select the second phone (Office: +91 44 2345 6789)
      await tester.tap(find.byKey(const Key('phone_radio_+91 44 2345 6789')));
      await tester.pumpAndSettle();

      // Tap Continue
      await tester.tap(find.byKey(const Key('continue_phone_selection_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openWhatsAppCalled, isTrue);
      expect(mockComm.lastWhatsAppPhone, '+91 44 2345 6789');
    });

    testWidgets('8, 9. Cancelling phone selector sends nothing and preserves typed message', (tester) async {
      final mockComm = MockCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Rahul Kumar',
              phones: const [
                BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile'),
                BusinessCardPhone(number: '+91 44 2345 6789', label: 'Office'),
              ],
              emails: const [],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      // Type customized message
      await tester.enterText(
        find.byKey(const Key('contact_message_field')),
        'My preserved custom text',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('whatsapp_action_button')));
      await tester.pumpAndSettle();

      expect(find.text('Send WhatsApp Message To'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.byKey(const Key('cancel_phone_selection_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openWhatsAppCalled, isFalse);
      expect(find.text('Send WhatsApp Message To'), findsNothing);

      // Message is still intact!
      final field = tester.widget<TextFormField>(find.byKey(const Key('contact_message_field')));
      expect(field.controller?.text, 'My preserved custom text');
    });

    testWidgets('10. WhatsApp launch failure handled gracefully', (tester) async {
      final mockComm = MockCommunicationService()..shouldSucceedWhatsApp = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Rahul Kumar',
              phones: const [BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile')],
              emails: const [],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('whatsapp_action_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openWhatsAppCalled, isTrue);
      expect(find.text('Unable to open WhatsApp for this number.'), findsOneWidget);
    });

    testWidgets('Phase 6.1: Local number (8078709703) is NOT launched immediately and requests country code', (tester) async {
      final mockComm = MockCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Ansaf',
              phones: const [BusinessCardPhone(number: '8078709703', label: 'Mobile')],
              emails: const [],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('whatsapp_action_button')));
      await tester.pumpAndSettle();

      // NOT launched immediately
      expect(mockComm.openWhatsAppCalled, isFalse);

      // Country code dialog is shown
      expect(find.text('Country code required'), findsOneWidget);
      expect(find.text('WhatsApp requires an international phone number.'), findsOneWidget);
      expect(find.text('8078709703'), findsOneWidget);
      expect(find.byKey(const Key('country_code_input_field')), findsOneWidget);

      // Default country code is +91
      final codeField = tester.widget<TextFormField>(find.byKey(const Key('country_code_input_field')));
      expect(codeField.controller?.text, '+91');
    });

    testWidgets('Phase 6.1: Confirming +91 country code produces international recipient and launches WhatsApp', (tester) async {
      final mockComm = MockCommunicationService();
      const storedPhones = [BusinessCardPhone(number: '8078709703', label: 'Mobile')];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Ansaf',
              phones: storedPhones,
              emails: const [],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('whatsapp_action_button')));
      await tester.pumpAndSettle();

      expect(find.text('Country code required'), findsOneWidget);

      // Tap Continue
      await tester.tap(find.byKey(const Key('continue_country_code_button')));
      await tester.pumpAndSettle();

      // Dialog closed
      expect(find.text('Country code required'), findsNothing);

      // WhatsApp opened with international number
      expect(mockComm.openWhatsAppCalled, isTrue);
      expect(mockComm.lastWhatsAppPhone, '+91 8078709703');

      // Stored phone in list is unchanged
      expect(storedPhones.first.number, '8078709703');
    });

    testWidgets('Phase 6.1: User can enter +44 country code and launches international recipient', (tester) async {
      final mockComm = MockCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'John',
              phones: const [BusinessCardPhone(number: '7700 900123', label: 'Mobile')],
              emails: const [],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('whatsapp_action_button')));
      await tester.pumpAndSettle();

      expect(find.text('Country code required'), findsOneWidget);

      // Edit country code to +44
      await tester.enterText(find.byKey(const Key('country_code_input_field')), '+44');
      await tester.pump();

      // Tap Continue
      await tester.tap(find.byKey(const Key('continue_country_code_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openWhatsAppCalled, isTrue);
      expect(mockComm.lastWhatsAppPhone, '+44 7700 900123');
    });

    testWidgets('Phase 6.1: Cancelling country code dialog launches nothing and preserves message', (tester) async {
      final mockComm = MockCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Ansaf',
              phones: const [BusinessCardPhone(number: '8078709703', label: 'Mobile')],
              emails: const [],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      // Enter custom message
      await tester.enterText(
        find.byKey(const Key('contact_message_field')),
        'Preserved message after country code cancel',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('whatsapp_action_button')));
      await tester.pumpAndSettle();

      expect(find.text('Country code required'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.byKey(const Key('cancel_country_code_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openWhatsAppCalled, isFalse);
      expect(find.text('Country code required'), findsNothing);

      // Message remains
      final field = tester.widget<TextFormField>(find.byKey(const Key('contact_message_field')));
      expect(field.controller?.text, 'Preserved message after country code cancel');
    });

    testWidgets('Phase 6.1: Multiple phones: selecting local number then asks for country code', (tester) async {
      final mockComm = MockCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Ansaf',
              phones: const [
                BusinessCardPhone(number: '8078709703', label: 'Mobile'),
                BusinessCardPhone(number: '+91 44 2345 6789', label: 'Office'),
              ],
              emails: const [],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('whatsapp_action_button')));
      await tester.pumpAndSettle();

      // Step 1: Phone selection dialog shown first
      expect(find.text('Send WhatsApp Message To'), findsOneWidget);
      expect(find.text('Country code required'), findsNothing);

      // Select Mobile (local number 8078709703)
      await tester.tap(find.byKey(const Key('phone_radio_8078709703')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('continue_phone_selection_button')));
      await tester.pumpAndSettle();

      // Step 2: Now CountryCodeDialog appears
      expect(find.text('Country code required'), findsOneWidget);
      expect(find.text('8078709703'), findsOneWidget);

      // Confirm with +91
      await tester.tap(find.byKey(const Key('continue_country_code_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openWhatsAppCalled, isTrue);
      expect(mockComm.lastWhatsAppPhone, '+91 8078709703');
    });

    testWidgets('Phase 6.1: Multiple phones: selecting international number launches without country code dialog', (tester) async {
      final mockComm = MockCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Ansaf',
              phones: const [
                BusinessCardPhone(number: '8078709703', label: 'Mobile'),
                BusinessCardPhone(number: '+91 44 2345 6789', label: 'Office'),
              ],
              emails: const [],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('whatsapp_action_button')));
      await tester.pumpAndSettle();

      // Phone selection dialog shown
      expect(find.text('Send WhatsApp Message To'), findsOneWidget);

      // Select Office (+91 44 2345 6789)
      await tester.tap(find.byKey(const Key('phone_radio_+91 44 2345 6789')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('continue_phone_selection_button')));
      await tester.pumpAndSettle();

      // CountryCodeDialog NOT shown
      expect(find.text('Country code required'), findsNothing);

      // WhatsApp launched directly
      expect(mockComm.openWhatsAppCalled, isTrue);
      expect(mockComm.lastWhatsAppPhone, '+91 44 2345 6789');
    });

    testWidgets('11. Email shows error when no email addresses are available', (tester) async {
      final mockComm = MockCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Rahul Kumar',
              phones: const [BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile')],
              emails: const [],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('email_action_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openEmailCalled, isFalse);
      expect(find.text('No email address is available for this contact.'), findsOneWidget);
    });

    testWidgets('12, 17. One email opens composer directly with subject and body populated', (tester) async {
      final mockComm = MockCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Rahul Kumar',
              phones: const [],
              emails: const [
                BusinessCardEmail(email: 'rahul@abc.com', label: 'Work'),
              ],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('email_action_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openEmailCalled, isTrue);
      expect(mockComm.lastEmailRecipient, 'rahul@abc.com');
      expect(mockComm.lastEmailSubject, 'Great meeting you');
      expect(
        mockComm.lastEmailBody,
        "Hi Rahul, it was great meeting you. Let's stay connected.",
      );
      expect(find.text('Send Email To'), findsNothing);
    });

    testWidgets('13, 14. Multiple emails display selector and passes selected email', (tester) async {
      final mockComm = MockCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Rahul Kumar',
              phones: const [],
              emails: const [
                BusinessCardEmail(email: 'rahul@abc.com', label: 'Work'),
                BusinessCardEmail(email: 'rahul.personal@gmail.com', label: 'Personal'),
              ],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('email_action_button')));
      await tester.pumpAndSettle();

      expect(find.text('Send Email To'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);

      // Select Personal email
      await tester.tap(find.byKey(const Key('email_radio_rahul.personal@gmail.com')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('continue_email_selection_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openEmailCalled, isTrue);
      expect(mockComm.lastEmailRecipient, 'rahul.personal@gmail.com');
    });

    testWidgets('15. Cancelling email selector sends nothing', (tester) async {
      final mockComm = MockCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Rahul Kumar',
              phones: const [],
              emails: const [
                BusinessCardEmail(email: 'rahul@abc.com', label: 'Work'),
                BusinessCardEmail(email: 'rahul.personal@gmail.com', label: 'Personal'),
              ],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('email_action_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cancel_email_selection_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openEmailCalled, isFalse);
    });

    testWidgets('16. Email launch failure handled gracefully', (tester) async {
      final mockComm = MockCommunicationService()..shouldSucceedEmail = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Rahul Kumar',
              phones: const [],
              emails: const [BusinessCardEmail(email: 'rahul@abc.com', label: 'Work')],
              communicationService: mockComm,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('email_action_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openEmailCalled, isTrue);
      expect(find.text('Unable to open an email application on this device.'), findsOneWidget);
    });

    testWidgets('23. Contacts permission denial handled', (tester) async {
      final mockContact = MockPhoneContactService(
        resultToReturn: const ContactSaveResult(
          status: ContactSaveStatus.permissionDenied,
          message: 'Contacts permission was not granted.',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Rahul Kumar',
              phones: const [BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile')],
              emails: const [],
              contactService: mockContact,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('add_to_contacts_action_button')));
      await tester.pumpAndSettle();

      expect(mockContact.saveBusinessCardCalled, isTrue);
      expect(find.text('Contacts permission was not granted.'), findsOneWidget);
    });

    testWidgets('24. Contact save success feedback shown and remains on screen', (tester) async {
      final mockContact = MockPhoneContactService(
        resultToReturn: const ContactSaveResult(
          status: ContactSaveStatus.success,
          message: 'Contact added to your phone.',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageComposer(
              fullName: 'Rahul Kumar',
              phones: const [BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile')],
              emails: const [],
              contactService: mockContact,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('add_to_contacts_action_button')));
      await tester.pumpAndSettle();

      expect(mockContact.saveBusinessCardCalled, isTrue);
      expect(find.text('Contact added to your phone.'), findsOneWidget);
      // Remained on screen
      expect(find.byKey(const Key('add_to_contacts_action_button')), findsOneWidget);
    });
  });

  group('Phase 5C: Integration in Screens', () {
    testWidgets('25. Communication section works on freshly scanned BusinessCardReviewScreen', (tester) async {
      final mockComm = MockCommunicationService();
      final mockContact = MockPhoneContactService();

      final cardData = BusinessCardData(
        fullName: 'Rahul Kumar',
        company: 'ABC Technologies',
        jobTitle: 'Senior Developer',
        phoneNumbers: const [
          BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile'),
        ],
        emailAddresses: const [
          BusinessCardEmail(email: 'rahul@abc.com', label: 'Work'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(
            cardData: cardData,
            communicationService: mockComm,
            phoneContactService: mockContact,
          ),
        ),
      );

      // Verify Message Composer is present
      expect(find.text('Message'), findsOneWidget);
      expect(find.byKey(const Key('whatsapp_action_button')), findsOneWidget);
      expect(find.byKey(const Key('email_action_button')), findsOneWidget);
      expect(find.byKey(const Key('add_to_contacts_action_button')), findsOneWidget);

      // Tap WhatsApp
      await tester.ensureVisible(find.byKey(const Key('whatsapp_action_button')));
      await tester.tap(find.byKey(const Key('whatsapp_action_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openWhatsAppCalled, isTrue);
      expect(mockComm.lastWhatsAppPhone, '+91 98765 43210');
    });

    testWidgets('26. Communication section works on saved ImportedContactDetailsScreen', (tester) async {
      final mockComm = MockCommunicationService();
      final mockContact = MockPhoneContactService();

      const contact = ImportedContact(
        id: 'saved-card-1',
        fullName: 'Priya Sharma',
        company: 'Innovate Labs',
        jobTitle: 'Product Lead',
        phoneNumbers: [
          ImportedContactPhone(number: '+91 91234 56789', label: 'Mobile'),
        ],
        emailAddresses: [
          ImportedContactEmail(email: 'priya@innovate.com', label: 'Work'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ImportedContactDetailsScreen(
            contact: contact,
            communicationService: mockComm,
            phoneContactService: mockContact,
          ),
        ),
      );

      // Verify Message Composer is present
      expect(find.text('Message'), findsOneWidget);
      expect(find.byKey(const Key('whatsapp_action_button')), findsOneWidget);
      expect(find.byKey(const Key('email_action_button')), findsOneWidget);
      expect(find.byKey(const Key('add_to_contacts_action_button')), findsOneWidget);

      // Tap Email
      await tester.ensureVisible(find.byKey(const Key('email_action_button')));
      await tester.tap(find.byKey(const Key('email_action_button')));
      await tester.pumpAndSettle();

      expect(mockComm.openEmailCalled, isTrue);
      expect(mockComm.lastEmailRecipient, 'priya@innovate.com');
      expect(mockComm.lastEmailSubject, 'Great meeting you');
    });
  });
}
