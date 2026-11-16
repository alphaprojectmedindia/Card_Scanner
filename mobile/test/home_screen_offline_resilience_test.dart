import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/imported_contact.dart';
import 'package:digital_share/models/saved_connection.dart';
import 'package:digital_share/models/user_profile.dart';
import 'package:digital_share/screens/home/home_screen.dart';
import 'package:digital_share/services/api_client.dart';
import 'package:digital_share/services/connection_service.dart';
import 'package:digital_share/services/imported_contact_service.dart';
import 'package:digital_share/services/profile_service.dart';
import 'package:digital_share/services/storage/local_contact_repository.dart';
import 'package:digital_share/services/pending_card_capture_store.dart';
import 'package:digital_share/services/pending_profile_photo_store.dart';
import 'package:digital_share/theme/app_theme.dart';

class MockResilientProfileService extends ProfileService {
  final Future<UserProfile> Function()? getMyProfileCallback;
  final Future<UserProfile?> Function()? getCachedProfileCallback;

  MockResilientProfileService({
    this.getMyProfileCallback,
    this.getCachedProfileCallback,
  });

  @override
  Future<UserProfile?> getCachedProfile() async {
    if (getCachedProfileCallback != null) {
      return getCachedProfileCallback!();
    }
    return null;
  }

  @override
  Future<UserProfile> getMyProfile() async {
    if (getMyProfileCallback != null) {
      return getMyProfileCallback!();
    }
    return UserProfile(
      id: 'usr-1',
      userId: 'usr-1',
      shareId: 'share-abc123456789',
      fullName: 'Alice Online',
      email: 'alice@example.com',
      createdAtUtc: DateTime.utc(2026, 1, 1),
      updatedAtUtc: DateTime.utc(2026, 1, 1),
    );
  }
}

class MockResilientConnectionService extends ConnectionService {
  final Future<List<SavedConnection>> Function()? getConnectionsCallback;
  final Future<int> Function()? getCachedConnectionsCountCallback;

  MockResilientConnectionService({
    this.getConnectionsCallback,
    this.getCachedConnectionsCountCallback,
  });

  @override
  Future<int> getCachedConnectionsCount() async {
    if (getCachedConnectionsCountCallback != null) {
      return getCachedConnectionsCountCallback!();
    }
    return 0;
  }

  @override
  Future<List<SavedConnection>> getConnections() async {
    if (getConnectionsCallback != null) {
      return getConnectionsCallback!();
    }
    return [];
  }
}

class FakeLocalContactRepository extends LocalContactRepository {
  final List<ImportedContact> contacts;

  FakeLocalContactRepository({this.contacts = const []});

  @override
  Future<List<ImportedContact>> getContacts() async => contacts;

  @override
  Future<void> ensureLoaded() async {}
}

class MockResilientImportedContactService extends ImportedContactService {
  final Future<List<ImportedContact>> Function()? getContactsCallback;
  final LocalContactRepository _repo;

  MockResilientImportedContactService({
    this.getContactsCallback,
    LocalContactRepository? mockRepo,
  })  : _repo = mockRepo ?? FakeLocalContactRepository(),
        super(localRepo: mockRepo ?? FakeLocalContactRepository());

  @override
  LocalContactRepository get localRepository => _repo;

  @override
  Future<List<ImportedContact>> getContacts() async {
    if (getContactsCallback != null) {
      return getContactsCallback!();
    }
    return _repo.getContacts();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalContactRepository localRepo;

  final sampleOfflineProfile = UserProfile(
    id: 'usr-local',
    userId: 'usr-local',
    shareId: 'share-local12345678',
    fullName: 'Bob Offline',
    email: 'bob@example.com',
    jobTitle: 'Field Architect',
    company: 'Offline Corp',
    createdAtUtc: DateTime.utc(2026, 1, 1),
    updatedAtUtc: DateTime.utc(2026, 1, 1),
  );

  setUp(() async {
    PendingCardCaptureStore.resetForTesting();
    PendingProfilePhotoStore.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('home_resilience_test_');
    localRepo = LocalContactRepository(storageDirectory: tempDir);
    await localRepo.ensureLoaded();
  });

  tearDown(() async {
    PendingCardCaptureStore.resetForTesting();
    PendingProfilePhotoStore.resetForTesting();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Widget createTestWidget({
    UserProfile? initialProfile,
    ProfileService? profileService,
    ConnectionService? connectionService,
    ImportedContactService? importedContactService,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: HomeScreen(
        initialProfile: initialProfile,
        profileService: profileService,
        connectionService: connectionService,
        importedContactService: importedContactService,
      ),
    );
  }

  group('Home Screen Offline Resilience & Timeout Handling Tests', () {
    testWidgets('1. Home screen with internet loads profile and updates counters without error', (tester) async {
      final profileService = MockResilientProfileService(
        getMyProfileCallback: () async => sampleOfflineProfile,
      );
      final connectionService = MockResilientConnectionService(
        getConnectionsCallback: () async => [
          SavedConnection(
            shareId: 'share-9876543210123',
            fullName: 'Remote Contact',
            email: 'remote@example.com',
            savedAtUtc: DateTime.now().toUtc(),
          ),
        ],
      );
      final importedService = MockResilientImportedContactService(
        mockRepo: localRepo,
        getContactsCallback: () async => [
          ImportedContact(
            id: 'card-1',
            fullName: 'Cardholder One',
            emailAddresses: const [ImportedContactEmail(email: 'card@example.com')],
            createdAtUtc: DateTime.now().toUtc(),
          ),
        ],
      );

      await tester.pumpWidget(createTestWidget(
        profileService: profileService,
        connectionService: connectionService,
        importedContactService: importedService,
      ));

      await tester.pumpAndSettle();

      // Verify profile is displayed
      expect(find.text('Bob Offline'), findsOneWidget);
      expect(find.text('Field Architect • Offline Corp'), findsOneWidget);

      // Verify counters
      expect(find.text('1 Connections'), findsOneWidget);
      expect(find.text('1 Cards'), findsOneWidget);

      // Verify no offline banner is shown
      expect(find.byKey(const Key('home_offline_status_banner')), findsNothing);

      // Verify Quick Actions are visible
      expect(find.byKey(const Key('home_business_card_scanner_card')), findsOneWidget);
      expect(find.byKey(const Key('home_universal_qr_scanner_card')), findsOneWidget);
    });

    testWidgets('2. Home screen without internet immediately loads local data & displays subtle offline banner', (tester) async {
      final fakeRepo = FakeLocalContactRepository(
        contacts: const [
          ImportedContact(id: 'c1', fullName: 'Card A'),
          ImportedContact(id: 'c2', fullName: 'Card B'),
          ImportedContact(id: 'c3', fullName: 'Card C'),
        ],
      );

      final profileService = MockResilientProfileService(
        getCachedProfileCallback: () async => sampleOfflineProfile,
        getMyProfileCallback: () async => throw ApiException('Unable to connect to the server. Please check your network connection.'),
      );
      final connectionService = MockResilientConnectionService(
        getCachedConnectionsCountCallback: () async => 5,
        getConnectionsCallback: () async => throw ApiException('Connection timed out. Please check your network connection and try again.'),
      );
      final importedService = MockResilientImportedContactService(
        mockRepo: fakeRepo,
        getContactsCallback: () async => throw ApiException('Connection timed out.'),
      );

      await tester.pumpWidget(createTestWidget(
        profileService: profileService,
        connectionService: connectionService,
        importedContactService: importedService,
      ));

      await tester.pumpAndSettle();

      // Crucial: Full-screen error must NOT be shown!
      expect(find.text('Try Again'), findsNothing); // Old full-screen button

      // Local profile and local cards must be rendered
      expect(find.text('Bob Offline'), findsOneWidget);
      expect(find.text('3 Cards'), findsOneWidget);
      expect(find.text('5 Connections'), findsOneWidget);

      // Non-intrusive offline banner must be visible
      expect(find.byKey(const Key('home_offline_status_banner')), findsOneWidget);
      expect(find.text('Offline — displaying local data.'), findsOneWidget);
      expect(find.byKey(const Key('home_retry_sync_button')), findsOneWidget);

      // Quick Actions must be completely accessible
      expect(find.byKey(const Key('home_business_card_scanner_card')), findsOneWidget);
      expect(find.byKey(const Key('home_universal_qr_scanner_card')), findsOneWidget);
      expect(find.byKey(const Key('home_qr_generator_card')), findsOneWidget);
    });

    testWidgets('3. Backend timeout retains local data and displays retry action', (tester) async {
      final fakeRepo = FakeLocalContactRepository(
        contacts: const [
          ImportedContact(id: 'cached1', fullName: 'Cached Card'),
        ],
      );

      final profileService = MockResilientProfileService(
        getCachedProfileCallback: () async => sampleOfflineProfile,
        getMyProfileCallback: () async => throw ApiException('Connection timed out. Please check your network connection and try again.'),
      );
      final connectionService = MockResilientConnectionService(
        getCachedConnectionsCountCallback: () async => 2,
        getConnectionsCallback: () async => throw ApiException('Connection timed out.'),
      );
      final importedService = MockResilientImportedContactService(
        mockRepo: fakeRepo,
        getContactsCallback: () async => throw ApiException('Connection timed out.'),
      );

      await tester.pumpWidget(createTestWidget(
        profileService: profileService,
        connectionService: connectionService,
        importedContactService: importedService,
      ));

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home_offline_status_banner')), findsOneWidget);
      expect(find.text('1 Cards'), findsOneWidget);
      expect(find.text('2 Connections'), findsOneWidget);
      expect(find.byKey(const Key('home_retry_sync_button')), findsOneWidget);
    });

    testWidgets('4. Empty contact database renders gracefully with 0 counts without error', (tester) async {
      final profileService = MockResilientProfileService(
        getMyProfileCallback: () async => sampleOfflineProfile,
      );
      final connectionService = MockResilientConnectionService(
        getConnectionsCallback: () async => [],
      );
      final importedService = MockResilientImportedContactService(
        mockRepo: localRepo,
        getContactsCallback: () async => [],
      );

      await tester.pumpWidget(createTestWidget(
        profileService: profileService,
        connectionService: connectionService,
        importedContactService: importedService,
      ));

      await tester.pumpAndSettle();

      expect(find.text('0 Connections'), findsOneWidget);
      expect(find.text('0 Cards'), findsOneWidget);
      expect(find.byKey(const Key('home_offline_status_banner')), findsNothing);
    });

    testWidgets('5. Restoring internet and tapping Retry refreshes dashboard and clears offline banner', (tester) async {
      bool isOnline = false;

      final profileService = MockResilientProfileService(
        getCachedProfileCallback: () async => sampleOfflineProfile,
        getMyProfileCallback: () async {
          if (!isOnline) {
            throw ApiException('Connection timed out.');
          }
          return sampleOfflineProfile;
        },
      );
      final connectionService = MockResilientConnectionService(
        getCachedConnectionsCountCallback: () async => 0,
        getConnectionsCallback: () async {
          if (!isOnline) {
            throw ApiException('Connection timed out.');
          }
          return [
            SavedConnection(
              shareId: 'share-1234567890123',
              fullName: 'Synced Friend',
              email: 'friend@example.com',
              savedAtUtc: DateTime.now().toUtc(),
            ),
          ];
        },
      );
      final importedService = MockResilientImportedContactService(
        mockRepo: localRepo,
        getContactsCallback: () async {
          if (!isOnline) {
            throw ApiException('Connection timed out.');
          }
          return [];
        },
      );

      await tester.pumpWidget(createTestWidget(
        profileService: profileService,
        connectionService: connectionService,
        importedContactService: importedService,
      ));

      await tester.pumpAndSettle();

      // Initially offline
      expect(find.byKey(const Key('home_offline_status_banner')), findsOneWidget);
      expect(find.text('0 Connections'), findsOneWidget);

      // Simulate internet restored
      isOnline = true;

      // Tap the Retry button on the offline banner
      await tester.tap(find.byKey(const Key('home_retry_sync_button')));
      await tester.pumpAndSettle();

      // Offline banner must be dismissed
      expect(find.byKey(const Key('home_offline_status_banner')), findsNothing);

      // Connections count must now be updated to 1
      expect(find.text('1 Connections'), findsOneWidget);
    });
  });
}
