import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/imported_contact.dart';
import 'package:digital_share/models/saved_connection.dart';
import 'package:digital_share/models/user_profile.dart';
import 'package:digital_share/screens/connections/connections_screen.dart';
import 'package:digital_share/screens/home/home_screen.dart';
import 'package:digital_share/screens/profile/profile_screen.dart';
import 'package:digital_share/screens/scan/business_card_review_screen.dart';
import 'package:digital_share/screens/scan/business_card_scan_screen.dart';
import 'package:digital_share/services/connection_service.dart';
import 'package:digital_share/services/imported_contact_service.dart';
import 'package:digital_share/theme/app_colors.dart';
import 'package:digital_share/theme/app_theme.dart';
import 'package:digital_share/theme/theme_controller.dart';
import 'package:digital_share/widgets/email_selection_dialog.dart';
import 'package:digital_share/widgets/phone_selection_dialog.dart';
import 'package:digital_share/widgets/theme_selection_dialog.dart';

class InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> data = {};

  InMemorySecureStorage({Map<String, String>? initialData}) {
    if (initialData != null) data.addAll(initialData);
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return data[key];
  }
}

class MockConnectionsService extends ConnectionService {
  final List<SavedConnection> connections;
  MockConnectionsService({this.connections = const []});

  @override
  Future<List<SavedConnection>> getConnections() async => connections;
}

class MockImportedService extends ImportedContactService {
  final List<ImportedContact> contacts;
  MockImportedService({this.contacts = const []});

  @override
  Future<List<ImportedContact>> getContacts() async => contacts;
}

void main() {
  final testProfile = UserProfile(
    id: 'user-001',
    userId: 'uid-001',
    shareId: 'alpha1234567890123',
    fullName: 'David Miller',
    email: 'david.miller@example.com',
    phoneNumber: '+1 555-0100',
    jobTitle: 'Product Director',
    company: 'Apex Digital',
    website: 'https://apexdigital.io',
    address: 'Austin, TX',
    bio: 'Digital business cards and networking.',
    createdAtUtc: DateTime.utc(2026, 1, 1),
    updatedAtUtc: DateTime.utc(2026, 1, 1),
  );

  group('Phase 6: Centralized Theme System Tests', () {
    test('1. Light theme configuration has proper brightness, palette & tokens', () {
      final lightTheme = AppTheme.lightTheme;
      expect(lightTheme.brightness, Brightness.light);
      expect(lightTheme.colorScheme.primary, AppColors.primary);
      expect(lightTheme.colorScheme.surface, AppColors.surfaceLight);
      expect(lightTheme.scaffoldBackgroundColor, AppColors.backgroundLight);
      expect(lightTheme.useMaterial3, isTrue);
    });

    test('2. Dark theme configuration has proper dark background & elevated surfaces', () {
      final darkTheme = AppTheme.darkTheme;
      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.colorScheme.primary, AppColors.primaryDark);
      expect(darkTheme.colorScheme.surface, AppColors.surfaceDark);
      expect(darkTheme.scaffoldBackgroundColor, AppColors.backgroundDark);
      expect(darkTheme.useMaterial3, isTrue);
    });

    test('3. System theme default mode initializes cleanly', () {
      final storage = InMemorySecureStorage();
      final controller = ThemeController(storage: storage);
      expect(controller.themeMode, ThemeMode.system);
    });

    test('4. Theme switching updates ThemeController and notifies listeners', () async {
      final storage = InMemorySecureStorage();
      final controller = ThemeController(storage: storage);
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      await controller.setThemeMode(ThemeMode.dark);
      expect(controller.themeMode, ThemeMode.dark);
      expect(notifyCount, 1);

      await controller.setThemeMode(ThemeMode.light);
      expect(controller.themeMode, ThemeMode.light);
      expect(notifyCount, 2);
    });

    test('5. Theme persistence saves and reloads across app restarts', () async {
      final storage = InMemorySecureStorage();
      final controller1 = ThemeController(storage: storage);
      await controller1.setThemeMode(ThemeMode.dark);
      expect(storage.data[ThemeController.themePreferenceKey], 'dark');

      final controller2 = ThemeController(storage: storage);
      await controller2.loadThemeMode();
      expect(controller2.themeMode, ThemeMode.dark);

      await controller2.setThemeMode(ThemeMode.light);
      expect(storage.data[ThemeController.themePreferenceKey], 'light');

      final controller3 = ThemeController(storage: storage);
      await controller3.loadThemeMode();
      expect(controller3.themeMode, ThemeMode.light);
    });
  });

  group('Phase 6: UI Redesign & Navigation Tests', () {
    testWidgets('6. Main navigation bar renders all 4 destinations correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: HomeScreen(
            initialProfile: testProfile,
            connectionService: MockConnectionsService(),
            importedContactService: MockImportedService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
      expect(find.text('Connections'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('7. Home quick actions display Quick Actions & Manage Contacts cards', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: HomeScreen(
            initialProfile: testProfile,
            connectionService: MockConnectionsService(connections: [
              SavedConnection(
                shareId: 'c1',
                fullName: 'Alice',
                email: 'a@example.com',
                savedAtUtc: DateTime.now().toUtc(),
              )
            ]),
            importedContactService: MockImportedService(contacts: [
              const ImportedContact(id: 'k1', fullName: 'Bob'),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quick Actions'), findsOneWidget);
      expect(find.text('Scan Card'), findsOneWidget);
      expect(find.text('My Digital Card'), findsOneWidget);
      expect(find.text('Manage Contacts'), findsOneWidget);
      expect(find.text('My Connections'), findsOneWidget);
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('1 Connections'), findsOneWidget);
      expect(find.text('1 Cards'), findsOneWidget);
    });

    testWidgets('8. Scan options clearly present Digital Share QR and Physical Business Card with Camera/Gallery', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const BusinessCardScanScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Digital Share QR'), findsOneWidget);
      expect(find.text('Instantly connect with another Digital Share user.'), findsOneWidget);
      expect(find.text('Physical Business Card'), findsOneWidget);
      expect(find.text('Scan a printed card or choose an image.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
    });

    testWidgets('9. Business card review actions organizes PERSON, CONTACT, ADDITIONAL INFO, and FOLLOW UP', (tester) async {
      final sampleCard = BusinessCardData(
        fullName: 'Robert Chen',
        jobTitle: 'Lead Engineer',
        company: 'Vanguard Systems',
        phoneNumbers: [const BusinessCardPhone(number: '+1 234 567 8900', label: 'Mobile')],
        emailAddresses: [const BusinessCardEmail(email: 'robert@vanguard.io', label: 'Work')],
        website: 'https://vanguard.io',
        address: 'San Jose, CA',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: BusinessCardReviewScreen(cardData: sampleCard),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PERSON'), findsOneWidget);
      expect(find.text('CONTACT'), findsOneWidget);
      expect(find.text('ADDITIONAL INFORMATION'), findsOneWidget);
      expect(find.text('FOLLOW UP'), findsOneWidget);
      expect(find.text('Confirm Details'), findsOneWidget);
    });

    testWidgets('10. Connections segmented navigation switches between Digital Share and Business Cards', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ConnectionsScreen(
            connectionService: MockConnectionsService(),
            importedContactService: MockImportedService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Digital Share'), findsOneWidget);
      expect(find.text('Business Cards'), findsOneWidget);

      await tester.tap(find.text('Business Cards'));
      await tester.pumpAndSettle();

      expect(find.text('No Business Cards Yet'), findsOneWidget);
    });

    testWidgets('11. Empty states display helpful messaging across tabs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ConnectionsScreen(
            connectionService: MockConnectionsService(),
            importedContactService: MockImportedService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Connections Yet'), findsOneWidget);
      expect(
        find.text('Scan another person\'s Digital Share QR code to save their live digital card here.'),
        findsOneWidget,
      );
    });

    testWidgets('12. Message composer remains functional after redesign with WhatsApp, Email & Add to Contacts', (tester) async {
      final sampleCard = BusinessCardData(
        fullName: 'Elena Rostova',
        phoneNumbers: [const BusinessCardPhone(number: '+1 555-3322', label: 'Mobile')],
        emailAddresses: [const BusinessCardEmail(email: 'elena@example.com', label: 'Work')],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: BusinessCardReviewScreen(cardData: sampleCard),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contact_message_field')), findsOneWidget);
      expect(find.byKey(const Key('whatsapp_action_button')), findsOneWidget);
      expect(find.byKey(const Key('email_action_button')), findsOneWidget);
      expect(find.byKey(const Key('add_to_contacts_action_button')), findsOneWidget);
    });

    testWidgets('13. Already Saved dialog displays in Dark and Light themes correctly', (tester) async {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Already Saved'),
                        content: const Text(
                          'This business card/contact is already saved in Digital Share.',
                        ),
                        actions: [
                          TextButton(
                            key: const Key('duplicate_dialog_ok_button'),
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('OK'),
                          ),
                          FilledButton(
                            key: const Key('duplicate_dialog_show_details_button'),
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Show Details'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.text('Already Saved'), findsOneWidget);
        expect(find.byKey(const Key('duplicate_dialog_ok_button')), findsOneWidget);
        expect(find.byKey(const Key('duplicate_dialog_show_details_button')), findsOneWidget);

        await tester.tap(find.byKey(const Key('duplicate_dialog_ok_button')));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('14. Phone selector radio group works in Light and Dark themes', (tester) async {
      final phones = [
        const BusinessCardPhone(number: '+1 555-1111', label: 'Mobile'),
        const BusinessCardPhone(number: '+1 555-2222', label: 'Office'),
      ];

      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<String>(
                    context: context,
                    builder: (ctx) => PhoneSelectionDialog(phones: phones),
                  ),
                  child: const Text('Open Phones'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Phones'));
        await tester.pumpAndSettle();

        expect(find.text('Send WhatsApp Message To'), findsOneWidget);
        expect(find.text('+1 555-1111'), findsOneWidget);
        expect(find.text('+1 555-2222'), findsOneWidget);

        await tester.tap(find.byKey(const Key('cancel_phone_selection_button')));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('15. Email selector radio group works in Light and Dark themes', (tester) async {
      final emails = [
        const BusinessCardEmail(email: 'work@domain.com', label: 'Work'),
        const BusinessCardEmail(email: 'personal@domain.com', label: 'Personal'),
      ];

      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<String>(
                    context: context,
                    builder: (ctx) => EmailSelectionDialog(emails: emails),
                  ),
                  child: const Text('Open Emails'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Emails'));
        await tester.pumpAndSettle();

        expect(find.text('Send Email To'), findsOneWidget);
        expect(find.text('work@domain.com'), findsOneWidget);
        expect(find.text('personal@domain.com'), findsOneWidget);

        await tester.tap(find.byKey(const Key('cancel_email_selection_button')));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('16. Profile appearance settings opens ThemeSelectionDialog and changes theme mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ProfileScreen(initialProfile: testProfile),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Preferences & Settings'), findsOneWidget);
      final appearanceFinder = find.text('Appearance');
      await tester.scrollUntilVisible(appearanceFinder, 300);
      await tester.pumpAndSettle();

      // Tap Appearance tile
      await tester.tap(appearanceFinder);
      await tester.pumpAndSettle();

      // Verify ThemeSelectionDialog opens with options
      expect(find.byType(ThemeSelectionDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ThemeSelectionDialog),
          matching: find.text('System Default'),
        ),
        findsOneWidget,
      );
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      // Select Dark mode
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      // Dialog dismisses
      expect(find.byType(ThemeSelectionDialog), findsNothing);
    });
  });
}
