import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/services/onboarding_tutorial_service.dart';
import 'package:digital_share/services/secure_storage_service.dart';
import 'package:digital_share/widgets/onboarding_tutorial_overlay.dart';

class _TestSecureStorage extends FlutterSecureStorage {
  final Map<String, String> data = {};

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

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnboardingTutorialOverlay 11-Step Walkthrough Component Tests', () {
    late List<GlobalKey> keys;
    late List<OnboardingStepData> testSteps;

    setUp(() {
      keys = List.generate(10, (_) => GlobalKey());

      testSteps = [
        OnboardingStepData(
          stepNumber: 1,
          heading: 'Welcome and Home Dashboard',
          description:
              'Welcome to Digital Share! Your central hub to monitor your network, track card counters, access quick actions, and navigate all features seamlessly.',
          targetKey: keys[0],
          icon: Icons.dashboard_rounded,
        ),
        OnboardingStepData(
          stepNumber: 2,
          heading: 'Business Card Scanner',
          description:
              'Scan physical business cards instantly using your camera or gallery. AI OCR extracts details accurately so you can review and edit before saving.',
          targetKey: keys[1],
          icon: Icons.badge_rounded,
        ),
        OnboardingStepData(
          stepNumber: 3,
          heading: 'My Connections',
          description:
              'All your saved business cards and connections are stored here. View complete contact details, search by personal memories, and initiate quick calls or emails.',
          targetKey: keys[2],
          icon: Icons.people_alt_outlined,
        ),
        OnboardingStepData(
          stepNumber: 4,
          heading: 'Favorites and Contact Organization',
          description:
              'Star important contacts as favorites for instant access. Organize your network effortlessly so your key relationships are always at your fingertips.',
          targetKey: keys[3],
          icon: Icons.star_rounded,
        ),
        OnboardingStepData(
          stepNumber: 5,
          heading: 'My Digital Card',
          description:
              'Your personal digital business card. Share your live contact details, title, company, and customized QR code with others in seconds.',
          targetKey: keys[4],
          icon: Icons.qr_code_2_rounded,
        ),
        OnboardingStepData(
          stepNumber: 6,
          heading: 'QR Generator and QR Scanner',
          description:
              'Generate customized QR codes for websites, Wi-Fi networks, contact info, and locations, or scan any standard QR code around you.',
          targetKey: keys[5],
          icon: Icons.qr_code_scanner_rounded,
        ),
        OnboardingStepData(
          stepNumber: 7,
          heading: 'Meetings',
          description:
              'Keep track of upcoming meetings, pending meeting requests, and your scheduling history. Seamlessly connected with your availability.',
          targetKey: keys[6],
          icon: Icons.calendar_today_rounded,
        ),
        OnboardingStepData(
          stepNumber: 8,
          heading: 'Availability',
          description:
              'Configure your weekly working hours and timezone settings so your connections know exactly when you are available to meet.',
          targetKey: keys[7],
          icon: Icons.schedule_rounded,
        ),
        OnboardingStepData(
          stepNumber: 9,
          heading: 'Shared Items',
          description:
              'View digital business cards and contact items shared with you across Digital Share, organized and accessible at any time.',
          targetKey: keys[8],
          icon: Icons.share_rounded,
        ),
        OnboardingStepData(
          stepNumber: 10,
          heading: 'Profile and Settings',
          description:
              'View and update your personal information, job title, company, address, bio, and appearance preferences, or sign out securely.',
          targetKey: keys[9],
          icon: Icons.person_outline_rounded,
        ),
        const OnboardingStepData(
          stepNumber: 11,
          heading: 'Finish Tour',
          description:
              "You're all set! You are ready to scan physical cards, connect with professionals, schedule meetings, and share your digital card.",
          targetKey: null,
          icon: Icons.check_circle_rounded,
        ),
      ];
    });

    testWidgets('Step 1 displays counter 1 / 11, heading, and disabled Previous button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SizedBox(key: keys[0], width: 200, height: 100),
                OnboardingTutorialOverlay(
                  steps: testSteps,
                  onFinish: () {},
                  onEndTour: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 / 11'), findsOneWidget);
      expect(find.text('Welcome and Home Dashboard'), findsOneWidget);

      // Verify button row layout: Previous, Next, End Tour in same row
      final navBar = tester.widget<Row>(find.byKey(const Key('tutorial_navigation_bar')));
      expect(navBar.children.length, greaterThanOrEqualTo(3));

      // Previous button on Step 1 is disabled
      final prevBtn = tester.widget<OutlinedButton>(find.byKey(const Key('tutorial_previous_button')));
      expect(prevBtn.onPressed, isNull);

      // Next and End Tour are present
      expect(find.byKey(const Key('tutorial_next_button')), findsOneWidget);
      expect(find.byKey(const Key('tutorial_end_tour_button')), findsOneWidget);
    });

    testWidgets('Tapping Next navigates through steps and verifies exact titles',
        (tester) async {
      int activeStep = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ...keys.map((k) => SizedBox(key: k, width: 200, height: 100)),
                OnboardingTutorialOverlay(
                  steps: testSteps,
                  onStepChanged: (step) => activeStep = step,
                  onFinish: () {},
                  onEndTour: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1 -> Step 2: Business Card Scanner
      await tester.tap(find.byKey(const Key('tutorial_next_button')));
      await tester.pumpAndSettle();
      expect(activeStep, 1);
      expect(find.text('2 / 11'), findsOneWidget);
      expect(find.text('Business Card Scanner'), findsOneWidget);

      // Step 2 -> Step 3: My Connections (Exact Title)
      await tester.tap(find.byKey(const Key('tutorial_next_button')));
      await tester.pumpAndSettle();
      expect(activeStep, 2);
      expect(find.text('3 / 11'), findsOneWidget);
      expect(find.text('My Connections'), findsOneWidget);

      // Step 3 -> Step 4: Favorites and Contact Organization
      await tester.tap(find.byKey(const Key('tutorial_next_button')));
      await tester.pumpAndSettle();
      expect(activeStep, 3);
      expect(find.text('4 / 11'), findsOneWidget);
      expect(find.text('Favorites and Contact Organization'), findsOneWidget);

      // Step 4 -> Step 5: My Digital Card (Exact Title)
      await tester.tap(find.byKey(const Key('tutorial_next_button')));
      await tester.pumpAndSettle();
      expect(activeStep, 4);
      expect(find.text('5 / 11'), findsOneWidget);
      expect(find.text('My Digital Card'), findsOneWidget);

      // Step 5 -> Step 6: QR Generator and QR Scanner
      await tester.tap(find.byKey(const Key('tutorial_next_button')));
      await tester.pumpAndSettle();
      expect(activeStep, 5);
      expect(find.text('6 / 11'), findsOneWidget);
      expect(find.text('QR Generator and QR Scanner'), findsOneWidget);

      // Step 6 -> Step 7: Meetings (Exact Title)
      await tester.tap(find.byKey(const Key('tutorial_next_button')));
      await tester.pumpAndSettle();
      expect(activeStep, 6);
      expect(find.text('7 / 11'), findsOneWidget);
      expect(find.text('Meetings'), findsOneWidget);

      // Step 7 -> Step 8: Availability (Exact Title)
      await tester.tap(find.byKey(const Key('tutorial_next_button')));
      await tester.pumpAndSettle();
      expect(activeStep, 7);
      expect(find.text('8 / 11'), findsOneWidget);
      expect(find.text('Availability'), findsOneWidget);

      // Step 8 -> Step 9: Shared Items
      await tester.tap(find.byKey(const Key('tutorial_next_button')));
      await tester.pumpAndSettle();
      expect(activeStep, 8);
      expect(find.text('9 / 11'), findsOneWidget);
      expect(find.text('Shared Items'), findsOneWidget);

      // Step 9 -> Step 10: Profile and Settings
      await tester.tap(find.byKey(const Key('tutorial_next_button')));
      await tester.pumpAndSettle();
      expect(activeStep, 9);
      expect(find.text('10 / 11'), findsOneWidget);
      expect(find.text('Profile and Settings'), findsOneWidget);

      // Step 10 -> Step 11: Finish Tour (Final step)
      await tester.tap(find.byKey(const Key('tutorial_next_button')));
      await tester.pumpAndSettle();
      expect(activeStep, 10);
      expect(find.text('11 / 11'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('tutorial_heading'))).data,
        'Finish Tour',
      );
      expect(find.byKey(const Key('tutorial_finish_button')), findsOneWidget);
      expect(find.byKey(const Key('tutorial_end_tour_button')), findsNothing);

      // Tapping Previous goes back to Step 10
      await tester.tap(find.byKey(const Key('tutorial_previous_button')));
      await tester.pumpAndSettle();
      expect(activeStep, 9);
      expect(find.text('10 / 11'), findsOneWidget);
      expect(find.text('Profile and Settings'), findsOneWidget);
    });

    testWidgets('End Tour immediately triggers onEndTour callback on any step',
        (tester) async {
      bool endTourCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SizedBox(key: keys[0], width: 200, height: 100),
                OnboardingTutorialOverlay(
                  steps: testSteps,
                  onFinish: () {},
                  onEndTour: () => endTourCalled = true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tutorial_end_tour_button')));
      await tester.pumpAndSettle();

      expect(endTourCalled, isTrue);
    });

    testWidgets('Final Step 11 displays completion checkmark, counter 11 / 11, and Finish Tour button',
        (tester) async {
      bool finishCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                OnboardingTutorialOverlay(
                  steps: testSteps,
                  initialStep: 10, // Step 11 (index 10)
                  onFinish: () => finishCalled = true,
                  onEndTour: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('11 / 11'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('tutorial_heading'))).data,
        'Finish Tour',
      );
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      // In step 11, End Tour is replaced by Finish Tour
      expect(find.byKey(const Key('tutorial_end_tour_button')), findsNothing);
      expect(find.byKey(const Key('tutorial_finish_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('tutorial_finish_button')));
      await tester.pumpAndSettle();

      expect(finishCalled, isTrue);
    });
  });

  group('OnboardingTutorialService & Persistence Tests', () {
    late SecureStorageService storage;
    late OnboardingTutorialService service;

    setUp(() async {
      final mockStorage = _TestSecureStorage();
      storage = SecureStorageService(storage: mockStorage);
      service = OnboardingTutorialService.instance;
      service.setStorageForTesting(storage);
    });

    test('First time user should show tutorial', () async {
      final shouldShow = await service.shouldShowTutorial('user-test-001');
      expect(shouldShow, isTrue);
    });

    test('Marking completed suppresses tutorial for that user', () async {
      await service.markCompleted('user-test-001');
      final shouldShow = await service.shouldShowTutorial('user-test-001');
      expect(shouldShow, isFalse);
    });

    test('Multi-user isolation: user 1 completion does not affect user 2', () async {
      await service.markCompleted('user-test-001');
      final user1ShouldShow = await service.shouldShowTutorial('user-test-001');
      final user2ShouldShow = await service.shouldShowTutorial('user-test-002');

      expect(user1ShouldShow, isFalse);
      expect(user2ShouldShow, isTrue);
    });

    test('Reset tutorial allows replay', () async {
      await service.markCompleted('user-test-001');
      expect(await service.shouldShowTutorial('user-test-001'), isFalse);

      await service.resetTutorial('user-test-001');
      expect(await service.shouldShowTutorial('user-test-001'), isTrue);
    });

    test('requestTourStart triggers shouldStartTourNotifier', () {
      service.shouldStartTourNotifier.value = false;
      bool notified = false;
      service.shouldStartTourNotifier.addListener(() {
        if (service.shouldStartTourNotifier.value) notified = true;
      });

      service.requestTourStart();
      expect(notified, isTrue);
      expect(service.shouldStartTourNotifier.value, isTrue);
    });
  });
}
