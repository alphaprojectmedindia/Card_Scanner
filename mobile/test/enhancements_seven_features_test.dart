import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/widgets/custom_bottom_navigation_bar.dart';
import 'package:digital_share/services/legal_consent_service.dart';
import 'package:digital_share/screens/legal/mandatory_consent_dialog.dart';
import 'package:digital_share/screens/scan/widgets/business_card_camera_overlay.dart';
import 'package:digital_share/screens/connections/saved_contacts_screen.dart';
import 'package:digital_share/models/imported_contact.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Feature 3: CustomBottomNavigationBar 5-Destination Layout', () {
    testWidgets('renders all 5 navigation items with prominent center Scan button in light and dark themes', (tester) async {
      int selectedIndex = 0;

      // Test Light Theme
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            bottomNavigationBar: CustomBottomNavigationBar(
              currentIndex: selectedIndex,
              onTap: (idx) => selectedIndex = idx,
            ),
          ),
        ),
      );

      // Verify all 5 navigation items exist
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Contacts'), findsOneWidget);
      expect(find.text('Meetings'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      // Verify prominent Scan button with QR icon exists
      expect(find.byKey(const Key('bottom_nav_scan_button')), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);

      // Tap on Contacts tab (index 1)
      await tester.tap(find.text('Contacts'));
      expect(selectedIndex, 1);

      // Tap on Scan central button (index 2)
      await tester.tap(find.byKey(const Key('bottom_nav_scan_button')));
      expect(selectedIndex, 2);

      // Tap on Meetings (index 3)
      await tester.tap(find.text('Meetings'));
      expect(selectedIndex, 3);

      // Tap on Profile (index 4)
      await tester.tap(find.text('Profile'));
      expect(selectedIndex, 4);

      // Test Dark Theme
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            bottomNavigationBar: CustomBottomNavigationBar(
              currentIndex: selectedIndex,
              onTap: (idx) => selectedIndex = idx,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(const Key('bottom_nav_scan_button')), findsOneWidget);
    });
  });

  group('Feature 4 & 5: Legal Consent & Jurisdictions', () {
    test('LegalConsentService detects country jurisdictions correctly', () {
      final service = LegalConsentService();

      expect(service.detectJurisdictionFromLocale('en_IN'), 'IN');
      expect(service.detectJurisdictionFromLocale('hi_IN'), 'IN');
      expect(service.detectJurisdictionFromLocale('de_DE'), 'EU');
      expect(service.detectJurisdictionFromLocale('fr_FR'), 'EU');
      expect(service.detectJurisdictionFromLocale('en_GB'), 'GB');
      expect(service.detectJurisdictionFromLocale('en_US'), 'US');
      expect(service.detectJurisdictionFromLocale('ja_JP'), 'GLOBAL');
    });

    test('LegalConsentService provides country-specific compliance documents', () {
      final service = LegalConsentService();

      final indiaDocs = service.getLegalDocuments('IN');
      expect(indiaDocs.termsAndConditionsMarkdown, contains('DPDP Act, 2023'));
      expect(indiaDocs.privacyPolicyMarkdown, contains('DPDP Act 2023'));
      expect(indiaDocs.termsAndConditionsMarkdown, contains('Medindia4u.com'));
      expect(indiaDocs.cookiePolicyMarkdown, contains('Cookie'));

      final euDocs = service.getLegalDocuments('EU');
      expect(euDocs.termsAndConditionsMarkdown, contains('Terms and Conditions (EU)'));
      expect(euDocs.privacyPolicyMarkdown, contains('International Data Protection Standard'));

      final usDocs = service.getLegalDocuments('US');
      expect(usDocs.termsAndConditionsMarkdown, contains('Terms and Conditions (US)'));
      expect(usDocs.privacyPolicyMarkdown, contains('International Data Protection Standard'));
    });

    testWidgets('MandatoryConsentDialog is unchecked by default and disables submit until checked', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MandatoryConsentDialog(
              initialJurisdiction: 'IN',
              onConsentGranted: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Heading and Medindia branding
      expect(find.text('Terms & Privacy Update'), findsOneWidget);
      expect(find.textContaining('Powered by Medindia4u.com'), findsOneWidget);

      // Checkboxes are unchecked by default
      final requiredCheckboxFinder = find.byKey(const Key('mandatory_consent_checkbox'));
      expect(requiredCheckboxFinder, findsOneWidget);
      final CheckboxListTile requiredCheckbox = tester.widget(requiredCheckboxFinder);
      expect(requiredCheckbox.value, isFalse);

      // Accept button is initially disabled
      final acceptButtonFinder = find.byKey(const Key('confirm_consent_button'));
      expect(acceptButtonFinder, findsOneWidget);
      final FilledButton acceptButton = tester.widget(acceptButtonFinder);
      expect(acceptButton.onPressed, isNull);

      // Tapping required terms checkbox enables the button
      await tester.tap(requiredCheckboxFinder);
      await tester.pumpAndSettle();

      final FilledButton enabledAcceptButton = tester.widget(acceptButtonFinder);
      expect(enabledAcceptButton.onPressed, isNotNull);
    });
  });

  group('Feature 6: Camera Auto-Detection Viewfinder Overlay', () {
    testWidgets('renders auto-capture badge, outline, and toggles mode', (tester) async {
      bool autoCaptureActive = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessCardCameraOverlay(
              guidanceMessage: 'Card detected — Hold steady...',
              isReady: true,
              isAutoCapture: autoCaptureActive,
              onToggleAutoCapture: () => autoCaptureActive = !autoCaptureActive,
              detectedCardRect: const Rect.fromLTWH(40, 100, 300, 180),
              onCapture: () {},
              onCancel: () {},
              onToggleTorch: () {},
              onPickGallery: () {},
            ),
          ),
        ),
      );

      // Guidance message text displayed
      expect(find.text('Card detected — Hold steady...'), findsOneWidget);

      // Auto capture chip indicator is present
      expect(find.byKey(const Key('toggle_auto_capture_button')), findsOneWidget);
      expect(find.text('Auto Capture: Active'), findsOneWidget);

      // Shutter button is present
      expect(find.byKey(const Key('camera_capture_shutter_button')), findsOneWidget);

      // Toggle auto capture
      await tester.tap(find.byKey(const Key('toggle_auto_capture_button')));
      expect(autoCaptureActive, isFalse);
    });
  });

  group('Feature 3 & Search: SavedContactsScreen Unified Contact Filtering', () {
    testWidgets('filters contacts by name, company, and memory keyword', (tester) async {
      final sampleContacts = [
        ImportedContact(
          id: 'c1',
          fullName: 'Dr. (Prof.) Sudhir Bhandari',
          company: 'SMS Medical College',
          jobTitle: 'Professor Emeritus',
          phoneNumbers: const [ImportedContactPhone(number: '0141-279505')],
          emailAddresses: const [ImportedContactEmail(email: 'sudhir@example.com')],
          rememberThisContact: 'met at chennai conference',
          createdAtUtc: DateTime.utc(2026, 11, 17),
          updatedAtUtc: DateTime.utc(2026, 11, 17),
        ),
        ImportedContact(
          id: 'c2',
          fullName: 'Alice Johnson',
          company: 'Acme Cloud Corp',
          jobTitle: 'VP Technology',
          phoneNumbers: const [ImportedContactPhone(number: '555-0199')],
          emailAddresses: const [ImportedContactEmail(email: 'alice@acme.com')],
          rememberThisContact: 'Coffee in Austin',
          createdAtUtc: DateTime.utc(2026, 11, 17),
          updatedAtUtc: DateTime.utc(2026, 11, 17),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SavedContactsScreen(
            initialContacts: sampleContacts,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Both contacts rendered initially
      expect(find.text('Dr. (Prof.) Sudhir Bhandari'), findsOneWidget);
      expect(find.text('Alice Johnson'), findsOneWidget);

      // Search by memory 'chennai'
      await tester.enterText(find.byType(TextField), 'chennai');
      await tester.pumpAndSettle();

      // Only Sudhir Bhandari matches memory 'chennai'
      expect(find.text('Dr. (Prof.) Sudhir Bhandari'), findsOneWidget);
      expect(find.text('Alice Johnson'), findsNothing);

      // Memory badge is visible on the card
      expect(find.text('Memory: met at chennai conference'), findsOneWidget);

      // Search by company 'Acme'
      await tester.enterText(find.byType(TextField), 'Acme');
      await tester.pumpAndSettle();

      expect(find.text('Dr. (Prof.) Sudhir Bhandari'), findsNothing);
      expect(find.text('Alice Johnson'), findsOneWidget);
      expect(find.text('Memory: Coffee in Austin'), findsOneWidget);
    });
  });
}

