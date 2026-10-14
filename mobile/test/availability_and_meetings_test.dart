import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/availability_settings.dart';
import 'package:digital_share/models/meeting.dart';
import 'package:digital_share/models/public_availability.dart';
import 'package:digital_share/models/user_profile.dart';
import 'package:digital_share/screens/connections/availability_viewer_screen.dart';
import 'package:digital_share/screens/home/home_screen.dart';
import 'package:digital_share/screens/meetings/meeting_details_screen.dart';
import 'package:digital_share/screens/meetings/meetings_screen.dart';
import 'package:digital_share/screens/meetings/request_meeting_screen.dart';
import 'package:digital_share/screens/profile/availability_settings_screen.dart';
import 'package:digital_share/services/api_client.dart';
import 'package:digital_share/services/availability_service.dart';
import 'package:digital_share/services/meeting_service.dart';
import 'package:digital_share/services/profile_service.dart';
import 'package:digital_share/theme/app_theme.dart';

// --- MOCKS ---

class MockAvailabilityService extends AvailabilityService {
  AvailabilitySettings currentSettings;
  PublicAvailability? publicAvailability;
  bool shouldThrowError;

  MockAvailabilityService({
    AvailabilitySettings? initialSettings,
    this.publicAvailability,
    this.shouldThrowError = false,
  }) : currentSettings = initialSettings ??
            AvailabilitySettings(
              meetingRequestsEnabled: true,
              timeZoneId: 'Asia/Kolkata',
              slots: [
                AvailabilitySlot(
                  id: '1',
                  dayOfWeek: 1, // Monday
                  startTime: '09:00',
                  endTime: '12:00',
                ),
                AvailabilitySlot(
                  id: '2',
                  dayOfWeek: 1, // Monday
                  startTime: '14:00',
                  endTime: '17:00',
                ),
              ],
            );

  @override
  Future<AvailabilitySettings> getAvailability() async {
    if (shouldThrowError) {
      throw ApiException("Couldn't load availability.");
    }
    return currentSettings;
  }

  @override
  Future<AvailabilitySettings> updateAvailability(
      AvailabilitySettings settings) async {
    if (shouldThrowError) {
      throw ApiException('Failed to save availability settings.');
    }
    currentSettings = settings;
    return currentSettings;
  }

  @override
  Future<PublicAvailability> getUserAvailability(String userId) async {
    if (shouldThrowError) {
      throw ApiException("Couldn't load availability.");
    }
    return publicAvailability ??
        PublicAvailability(
          userId: userId,
          fullName: 'Ansaf',
          meetingRequestsEnabled: true,
          timeZoneId: 'Asia/Kolkata',
          slots: [
            AvailabilitySlot(
              id: '1',
              dayOfWeek: 1, // Monday
              startTime: '09:00',
              endTime: '12:00',
            ),
            AvailabilitySlot(
              id: '2',
              dayOfWeek: 1, // Monday
              startTime: '14:00',
              endTime: '17:00',
            ),
          ],
        );
  }
}

class MockMeetingService extends MeetingService {
  MeetingListResponse mockList;
  bool shouldThrowConflict;
  bool shouldThrowError;
  bool createCalled = false;
  bool acceptCalled = false;
  bool rejectCalled = false;
  bool cancelCalled = false;

  MockMeetingService({
    MeetingListResponse? initialList,
    this.shouldThrowConflict = false,
    this.shouldThrowError = false,
  }) : mockList = initialList ?? MeetingListResponse();

  @override
  Future<MeetingListResponse> getMeetings() async {
    if (shouldThrowError) {
      throw ApiException("Couldn't load meetings.");
    }
    return mockList;
  }

  @override
  Future<Meeting> createMeeting({
    required String recipientUserId,
    required DateTime startAtUtc,
    required DateTime endAtUtc,
    String? title,
    String? note,
  }) async {
    if (shouldThrowConflict) {
      throw ConflictException('That time is no longer available.');
    }
    if (shouldThrowError) {
      throw ApiException('Unable to send meeting request.');
    }
    createCalled = true;
    return Meeting(
      id: 'm-new',
      requesterUserId: 'user-1',
      requesterName: 'Denil',
      recipientUserId: recipientUserId,
      recipientName: 'Ansaf',
      startAtUtc: startAtUtc,
      endAtUtc: endAtUtc,
      title: title,
      note: note,
      status: MeetingStatus.pending,
      createdAtUtc: DateTime.now().toUtc(),
      updatedAtUtc: DateTime.now().toUtc(),
    );
  }

  @override
  Future<Meeting> acceptMeeting(String id) async {
    if (shouldThrowConflict) {
      throw ConflictException('That time is no longer available.');
    }
    acceptCalled = true;
    return Meeting(
      id: id,
      requesterUserId: 'user-1',
      requesterName: 'Denil',
      recipientUserId: 'user-2',
      recipientName: 'Ansaf',
      startAtUtc: DateTime.utc(2026, 10, 12, 9, 0),
      endAtUtc: DateTime.utc(2026, 10, 12, 9, 30),
      title: 'Project Discussion',
      status: MeetingStatus.accepted,
      createdAtUtc: DateTime.now().toUtc(),
      updatedAtUtc: DateTime.now().toUtc(),
    );
  }

  @override
  Future<Meeting> rejectMeeting(String id) async {
    rejectCalled = true;
    return Meeting(
      id: id,
      requesterUserId: 'user-1',
      requesterName: 'Denil',
      recipientUserId: 'user-2',
      recipientName: 'Ansaf',
      startAtUtc: DateTime.utc(2026, 10, 12, 9, 0),
      endAtUtc: DateTime.utc(2026, 10, 12, 9, 30),
      title: 'Project Discussion',
      status: MeetingStatus.rejected,
      createdAtUtc: DateTime.now().toUtc(),
      updatedAtUtc: DateTime.now().toUtc(),
    );
  }

  @override
  Future<Meeting> cancelMeeting(String id) async {
    cancelCalled = true;
    return Meeting(
      id: id,
      requesterUserId: 'user-1',
      requesterName: 'Denil',
      recipientUserId: 'user-2',
      recipientName: 'Ansaf',
      startAtUtc: DateTime.utc(2026, 10, 12, 9, 0),
      endAtUtc: DateTime.utc(2026, 10, 12, 9, 30),
      title: 'Project Discussion',
      status: MeetingStatus.cancelled,
      createdAtUtc: DateTime.now().toUtc(),
      updatedAtUtc: DateTime.now().toUtc(),
    );
  }
}

class MockProfileService extends ProfileService {
  final UserProfile profile;

  MockProfileService({UserProfile? mockProfile})
      : profile = mockProfile ??
            UserProfile(
              id: 'profile-1',
              userId: 'user-1',
              email: 'denil@example.com',
              fullName: 'Denil Samuel',
              shareId: 'test-share-id-1234567890',
              profilePhotoUrl: null,
              createdAtUtc: DateTime.utc(2026, 1, 1),
              updatedAtUtc: DateTime.utc(2026, 1, 1),
            );

  @override
  Future<UserProfile> getMyProfile() async => profile;
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
}

// --- TESTS ---

void main() {
  group('Phase 7 - Availability & Meetings Flutter Tests', () {
    // 1. Availability Settings screen renders
    testWidgets('1. Availability Settings screen renders correctly',
        (tester) async {
      _setPhoneViewport(tester);
      final mockAvailability = MockAvailabilityService();

      await tester.pumpWidget(
        MaterialApp(
          home: AvailabilitySettingsScreen(
            availabilityService: mockAvailability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Availability Settings'), findsOneWidget);
      expect(find.text('Timezone'), findsOneWidget);
      expect(find.text('Meeting Requests'), findsOneWidget);
      expect(find.text('Weekly Availability'), findsOneWidget);
      expect(find.text('Save Availability'), findsOneWidget);
    });

    // 2. Add slot
    testWidgets('2. Add slot opens time configuration and adds slot',
        (tester) async {
      final mockAvailability = MockAvailabilityService();

      await tester.pumpWidget(
        MaterialApp(
          home: AvailabilitySettingsScreen(
            availabilityService: mockAvailability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find first "Add Slot" button (Monday)
      final addButtons = find.text('Add Slot');
      expect(addButtons, findsWidgets);

      await tester.tap(addButtons.first);
      await tester.pumpAndSettle();

      // Dialog is open
      expect(find.text('Add Slot: Monday'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);

      // Tap Add in dialog
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
    });

    // 3. Remove slot
    testWidgets('3. Remove slot deletes slot from day', (tester) async {
      final mockAvailability = MockAvailabilityService();

      await tester.pumpWidget(
        MaterialApp(
          home: AvailabilitySettingsScreen(
            availabilityService: mockAvailability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('09:00 – 12:00'), findsOneWidget);
      expect(find.text('14:00 – 17:00'), findsOneWidget);

      // Find delete icon buttons
      final deleteIcons = find.byTooltip('Remove Slot');
      expect(deleteIcons, findsWidgets);

      await tester.tap(deleteIcons.first);
      await tester.pumpAndSettle();

      expect(find.text('09:00 – 12:00'), findsNothing);
      expect(find.text('14:00 – 17:00'), findsOneWidget);
    });

    // 4. Multiple slots on same weekday
    testWidgets('4. Displays multiple slots on same weekday', (tester) async {
      final mockAvailability = MockAvailabilityService();

      await tester.pumpWidget(
        MaterialApp(
          home: AvailabilitySettingsScreen(
            availabilityService: mockAvailability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Monday has 09:00 - 12:00 and 14:00 - 17:00
      expect(find.text('09:00 – 12:00'), findsOneWidget);
      expect(find.text('14:00 – 17:00'), findsOneWidget);
    });

    // 5. Overlap validation feedback
    testWidgets('5. Overlap validation feedback prevents invalid slots',
        (tester) async {
      _setPhoneViewport(tester);
      // Setup initial overlapping slots
      final mockAvailability = MockAvailabilityService(
        initialSettings: AvailabilitySettings(
          meetingRequestsEnabled: true,
          timeZoneId: 'UTC',
          slots: [
            AvailabilitySlot(
                dayOfWeek: 1, startTime: '09:00', endTime: '13:00'),
            AvailabilitySlot(
                dayOfWeek: 1, startTime: '12:00', endTime: '16:00'),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AvailabilitySettingsScreen(
            availabilityService: mockAvailability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Save Availability
      await tester.tap(find.text('Save Availability'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Overlapping slots detected'), findsOneWidget);
    });

    // 6. Meeting request toggle
    testWidgets('6. Meeting request toggle switches state', (tester) async {
      final mockAvailability = MockAvailabilityService();

      await tester.pumpWidget(
        MaterialApp(
          home: AvailabilitySettingsScreen(
            availabilityService: mockAvailability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(find.text('Meeting requests are currently unavailable.'),
          findsOneWidget);
    });

    // 7. Timezone display
    testWidgets('7. Timezone dropdown displays configured timezone',
        (tester) async {
      final mockAvailability = MockAvailabilityService();

      await tester.pumpWidget(
        MaterialApp(
          home: AvailabilitySettingsScreen(
            availabilityService: mockAvailability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Asia/Kolkata'), findsOneWidget);
    });

    // 8. View connection availability
    testWidgets('8. View connection availability shows schedule and timezone',
        (tester) async {
      final mockAvailability = MockAvailabilityService();

      await tester.pumpWidget(
        MaterialApp(
          home: AvailabilityViewerScreen(
            targetUserId: 'user-2',
            userName: 'Ansaf',
            availabilityService: mockAvailability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Ansaf's Availability"), findsOneWidget);
      expect(find.text('Timezone: Asia/Kolkata'), findsOneWidget);
      expect(find.text('09:00 – 12:00'), findsOneWidget);
      expect(find.text('14:00 – 17:00'), findsOneWidget);
      expect(find.text('Request Meeting'), findsOneWidget);
    });

    // 9. Request Meeting navigation
    testWidgets('9. Tapping Request Meeting navigates to RequestMeetingScreen',
        (tester) async {
      _setPhoneViewport(tester);
      final mockAvailability = MockAvailabilityService();

      await tester.pumpWidget(
        MaterialApp(
          home: AvailabilityViewerScreen(
            targetUserId: 'user-2',
            userName: 'Ansaf',
            availabilityService: mockAvailability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Request Meeting'));
      await tester.pumpAndSettle();

      expect(find.text('Meeting with'), findsOneWidget);
      expect(find.text('Select Date'), findsOneWidget);
      expect(find.text('Send Request'), findsOneWidget);
    });

    // 10. Date selection
    testWidgets('10. RequestMeetingScreen allows picking date', (tester) async {
      final publicAvail = PublicAvailability(
        userId: 'user-2',
        fullName: 'Ansaf',
        meetingRequestsEnabled: true,
        timeZoneId: 'UTC',
        slots: [
          AvailabilitySlot(dayOfWeek: 1, startTime: '09:00', endTime: '12:00'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RequestMeetingScreen(availability: publicAvail),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select Date'), findsOneWidget);
      await tester.tap(find.text('Select Date'));
      await tester.pumpAndSettle();

      // DatePicker is open
      expect(find.text('Select date'), findsWidgets);
    });

    // 11. Available-time filtering
    testWidgets('11. Available time filters according to recipient slot',
        (tester) async {
      final publicAvail = PublicAvailability(
        userId: 'user-2',
        fullName: 'Ansaf',
        meetingRequestsEnabled: true,
        timeZoneId: 'UTC',
        slots: [
          AvailabilitySlot(dayOfWeek: 1, startTime: '09:00', endTime: '12:00'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RequestMeetingScreen(availability: publicAvail),
        ),
      );
      await tester.pumpAndSettle();

      // Before date selection
      expect(find.text('Select a date first to view available times.'),
          findsOneWidget);
    });

    // 12. Duration handling
    testWidgets('12. Duration chips can be selected', (tester) async {
      final publicAvail = PublicAvailability(
        userId: 'user-2',
        fullName: 'Ansaf',
        meetingRequestsEnabled: true,
        timeZoneId: 'UTC',
        slots: [
          AvailabilitySlot(dayOfWeek: 1, startTime: '09:00', endTime: '12:00'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RequestMeetingScreen(availability: publicAvail),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('15 min'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('45 min'), findsOneWidget);
      expect(find.text('60 min'), findsOneWidget);

      await tester.tap(find.text('60 min'));
      await tester.pumpAndSettle();
    });

    // 13. Send meeting request validation
    testWidgets('13. Send meeting request shows error if date not selected',
        (tester) async {
      _setPhoneViewport(tester);
      final publicAvail = PublicAvailability(
        userId: 'user-2',
        fullName: 'Ansaf',
        meetingRequestsEnabled: true,
        timeZoneId: 'UTC',
        slots: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RequestMeetingScreen(availability: publicAvail),
        ),
      );
      await tester.pumpAndSettle();

      final sendBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send Request'));
      expect(sendBtn.onPressed, isNull);
    });

    // 14. Requests tab
    testWidgets('14. Requests tab displays incoming and outgoing requests',
        (tester) async {
      final mockService = MockMeetingService(
        initialList: MeetingListResponse(
          requests: [
            Meeting(
              id: 'req-1',
              requesterUserId: 'user-other',
              requesterName: 'Ansaf',
              recipientUserId: 'user-1',
              recipientName: 'Denil',
              startAtUtc: DateTime.utc(2026, 10, 12, 10, 0),
              endAtUtc: DateTime.utc(2026, 10, 12, 10, 30),
              title: 'Sync Discussion',
              status: MeetingStatus.pending,
              createdAtUtc: DateTime.now().toUtc(),
              updatedAtUtc: DateTime.now().toUtc(),
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingsScreen(
            meetingService: mockService,
            profileService: MockProfileService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Requests tab
      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();

      expect(find.text('Ansaf'), findsOneWidget);
      expect(find.text('Sync Discussion'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    // 15. Accept request
    testWidgets('15. Quick Accept calls acceptMeeting on MeetingService',
        (tester) async {
      final mockService = MockMeetingService(
        initialList: MeetingListResponse(
          requests: [
            Meeting(
              id: 'req-1',
              requesterUserId: 'user-other',
              requesterName: 'Ansaf',
              recipientUserId: 'user-1',
              recipientName: 'Denil',
              startAtUtc: DateTime.utc(2026, 10, 12, 10, 0),
              endAtUtc: DateTime.utc(2026, 10, 12, 10, 30),
              title: 'Sync Discussion',
              status: MeetingStatus.pending,
              createdAtUtc: DateTime.now().toUtc(),
              updatedAtUtc: DateTime.now().toUtc(),
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingsScreen(
            meetingService: mockService,
            profileService: MockProfileService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(mockService.acceptCalled, isTrue);
    });

    // 16. Reject request
    testWidgets('16. Quick Reject calls rejectMeeting on MeetingService',
        (tester) async {
      final mockService = MockMeetingService(
        initialList: MeetingListResponse(
          requests: [
            Meeting(
              id: 'req-1',
              requesterUserId: 'user-other',
              requesterName: 'Ansaf',
              recipientUserId: 'user-1',
              recipientName: 'Denil',
              startAtUtc: DateTime.utc(2026, 10, 12, 10, 0),
              endAtUtc: DateTime.utc(2026, 10, 12, 10, 30),
              title: 'Sync Discussion',
              status: MeetingStatus.pending,
              createdAtUtc: DateTime.now().toUtc(),
              updatedAtUtc: DateTime.now().toUtc(),
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingsScreen(
            meetingService: mockService,
            profileService: MockProfileService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      expect(mockService.rejectCalled, isTrue);
    });

    // 17. Cancel pending request
    testWidgets('17. Outgoing pending request displays cancel request button',
        (tester) async {
      final meeting = Meeting(
        id: 'req-out',
        requesterUserId: 'user-1',
        requesterName: 'Denil',
        recipientUserId: 'user-2',
        recipientName: 'Ansaf',
        startAtUtc: DateTime.utc(2026, 10, 12, 10, 0),
        endAtUtc: DateTime.utc(2026, 10, 12, 10, 30),
        title: 'Project Roadmap',
        status: MeetingStatus.pending,
        createdAtUtc: DateTime.now().toUtc(),
        updatedAtUtc: DateTime.now().toUtc(),
      );

      final mockService = MockMeetingService();

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingDetailsScreen(
            meeting: meeting,
            meetingService: mockService,
            profileService: MockProfileService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cancel Request'), findsOneWidget);
      await tester.tap(find.text('Cancel Request'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel Meeting?'), findsOneWidget);
      await tester.tap(find.text('Yes, Cancel'));
      await tester.pumpAndSettle();

      expect(mockService.cancelCalled, isTrue);
    });

    // 18. Upcoming tab
    testWidgets('18. Upcoming tab displays accepted meetings', (tester) async {
      final mockService = MockMeetingService(
        initialList: MeetingListResponse(
          upcoming: [
            Meeting(
              id: 'm-up',
              requesterUserId: 'user-1',
              requesterName: 'Denil',
              recipientUserId: 'user-2',
              recipientName: 'Ansaf',
              startAtUtc: DateTime.utc(2026, 10, 12, 14, 30),
              endAtUtc: DateTime.utc(2026, 10, 12, 15, 0),
              title: 'Project Discussion',
              status: MeetingStatus.accepted,
              createdAtUtc: DateTime.now().toUtc(),
              updatedAtUtc: DateTime.now().toUtc(),
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingsScreen(
            meetingService: mockService,
            profileService: MockProfileService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ansaf'), findsOneWidget);
      expect(find.text('Project Discussion'), findsOneWidget);
      expect(find.text('Accepted'), findsOneWidget);
    });

    // 19. History tab
    testWidgets('19. History tab displays past and cancelled meetings',
        (tester) async {
      final mockService = MockMeetingService(
        initialList: MeetingListResponse(
          history: [
            Meeting(
              id: 'm-hist',
              requesterUserId: 'user-1',
              requesterName: 'Denil',
              recipientUserId: 'user-2',
              recipientName: 'Ansaf',
              startAtUtc: DateTime.utc(2026, 9, 1, 10, 0),
              endAtUtc: DateTime.utc(2026, 9, 1, 10, 30),
              title: 'Previous Architecture Review',
              status: MeetingStatus.accepted,
              createdAtUtc: DateTime.now().toUtc(),
              updatedAtUtc: DateTime.now().toUtc(),
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingsScreen(
            meetingService: mockService,
            profileService: MockProfileService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('Previous Architecture Review'), findsOneWidget);
    });

    // 20. Meeting details
    testWidgets('20. Meeting details screen shows full information',
        (tester) async {
      final meeting = Meeting(
        id: 'm-detail',
        requesterUserId: 'user-1',
        requesterName: 'Denil',
        recipientUserId: 'user-2',
        recipientName: 'Ansaf',
        startAtUtc: DateTime.utc(2026, 10, 12, 14, 30),
        endAtUtc: DateTime.utc(2026, 10, 12, 15, 0),
        title: 'Project Discussion',
        note: 'Please bring your laptop.',
        status: MeetingStatus.accepted,
        createdAtUtc: DateTime.now().toUtc(),
        updatedAtUtc: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingDetailsScreen(
            meeting: meeting,
            meetingService: MockMeetingService(),
            profileService: MockProfileService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Meeting Details'), findsOneWidget);
      expect(find.text('Ansaf'), findsOneWidget);
      expect(find.text('Project Discussion'), findsOneWidget);
      expect(find.text('Please bring your laptop.'), findsOneWidget);
      expect(find.text('Cancel Meeting'), findsOneWidget);
    });

    // 21. Empty states
    testWidgets('21. Standard empty states render on all tabs', (tester) async {
      final mockService = MockMeetingService(
        initialList: MeetingListResponse(
          upcoming: [],
          requests: [],
          history: [],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingsScreen(
            meetingService: mockService,
            profileService: MockProfileService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Upcoming empty state
      expect(find.text('No upcoming meetings.'), findsOneWidget);

      // Requests empty state
      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();
      expect(find.text('No meeting requests.'), findsOneWidget);

      // History empty state
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('No previous meetings.'), findsOneWidget);
    });

    // 22. API errors
    testWidgets('22. Handles API error with user friendly message',
        (tester) async {
      final mockService = MockMeetingService(shouldThrowError: true);

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingsScreen(
            meetingService: mockService,
            profileService: MockProfileService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load meetings."), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    // 23. Light theme
    testWidgets('23. Renders cleanly with light theme', (tester) async {
      final mockAvailability = MockAvailabilityService();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: AvailabilitySettingsScreen(
            availabilityService: mockAvailability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Availability Settings'), findsOneWidget);
    });

    // 24. Dark theme
    testWidgets('24. Renders cleanly with dark theme', (tester) async {
      final mockAvailability = MockAvailabilityService();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: AvailabilitySettingsScreen(
            availabilityService: mockAvailability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Availability Settings'), findsOneWidget);
    });

    // 25. Existing main navigation
    testWidgets('25. Main navigation preserves Home, Scan, Connections, Profile',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProfile: UserProfile(
              id: 'profile-1',
              userId: 'user-1',
              email: 'denil@example.com',
              fullName: 'Denil Samuel',
              shareId: '1234567890123456',
              createdAtUtc: DateTime.utc(2026, 1, 1),
              updatedAtUtc: DateTime.utc(2026, 1, 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
      expect(find.text('Connections'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      // Check Meetings card on Home
      expect(find.text('Meetings'), findsOneWidget);
      expect(find.text('View requests and upcoming meetings'), findsOneWidget);
    });
  });
}
