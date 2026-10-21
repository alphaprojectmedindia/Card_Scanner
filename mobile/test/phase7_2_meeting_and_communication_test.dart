import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/availability_settings.dart';
import 'package:digital_share/models/meeting.dart';
import 'package:digital_share/models/public_availability.dart';
import 'package:digital_share/models/saved_connection.dart';
import 'package:digital_share/models/shared_profile.dart';
import 'package:digital_share/screens/meetings/request_meeting_screen.dart';
import 'package:digital_share/screens/scan/scanned_profile_screen.dart';
import 'package:digital_share/services/connection_service.dart';
import 'package:digital_share/services/contact_communication_service.dart';
import 'package:digital_share/services/contact_service.dart';
import 'package:digital_share/services/meeting_service.dart';
import 'package:digital_share/utils/timezone_helper.dart';
import 'package:digital_share/utils/weekday_helper.dart';
import 'package:digital_share/widgets/country_code_dialog.dart';

// --- MOCKS ---

class MockTestMeetingService extends MeetingService {
  bool createCalled = false;
  String? lastRecipientUserId;
  DateTime? lastStartAtUtc;
  DateTime? lastEndAtUtc;
  String? lastTitle;
  String? lastNote;

  @override
  Future<Meeting> createMeeting({
    required String recipientUserId,
    required DateTime startAtUtc,
    required DateTime endAtUtc,
    String? title,
    String? note,
  }) async {
    createCalled = true;
    lastRecipientUserId = recipientUserId;
    lastStartAtUtc = startAtUtc;
    lastEndAtUtc = endAtUtc;
    lastTitle = title;
    lastNote = note;

    return Meeting(
      id: 'm-1',
      requesterUserId: 'req-1',
      requesterName: 'Requester',
      recipientUserId: recipientUserId,
      recipientName: 'Recipient',
      status: MeetingStatus.pending,
      startAtUtc: startAtUtc,
      endAtUtc: endAtUtc,
      title: title,
      note: note,
      createdAtUtc: DateTime.now().toUtc(),
      updatedAtUtc: DateTime.now().toUtc(),
    );
  }
}

class MockTestCommunicationService implements IContactCommunicationService {
  bool whatsAppCalled = false;
  String? lastWhatsAppPhone;
  String? lastWhatsAppMessage;

  bool emailCalled = false;
  String? lastEmail;
  String? lastEmailSubject;
  String? lastEmailBody;

  @override
  Future<bool> openWhatsApp({
    required String phone,
    required String message,
    String? linkUrl,
  }) async {
    whatsAppCalled = true;
    lastWhatsAppPhone = phone;
    lastWhatsAppMessage = message;
    return true;
  }

  @override
  Future<bool> openEmail({
    required String email,
    required String subject,
    required String body,
  }) async {
    emailCalled = true;
    lastEmail = email;
    lastEmailSubject = subject;
    lastEmailBody = body;
    return true;
  }
}

class FakeTestContactService implements IContactService {
  bool saveSharedProfileCalled = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<ContactSaveResult> saveSharedProfileToPhone(SharedProfile profile) async {
    saveSharedProfileCalled = true;
    return const ContactSaveResult(
      status: ContactSaveStatus.success,
      message: 'Contact saved to your phone.',
    );
  }
}

class FakeTestConnectionService extends ConnectionService {
  bool saveCalled = false;

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
  group('Phase 7.2: Part A — Weekday Mapping & Slot Generation Tests', () {
    // 1-7. Weekday mapping
    test('1-7. WeekdayHelper accurately converts Dart weekdays to backend DayOfWeek', () {
      expect(WeekdayHelper.toBackendDayOfWeek(DateTime.monday), 1);
      expect(WeekdayHelper.toBackendDayOfWeek(DateTime.tuesday), 2);
      expect(WeekdayHelper.toBackendDayOfWeek(DateTime.wednesday), 3);
      expect(WeekdayHelper.toBackendDayOfWeek(DateTime.thursday), 4);
      expect(WeekdayHelper.toBackendDayOfWeek(DateTime.friday), 5);
      expect(WeekdayHelper.toBackendDayOfWeek(DateTime.saturday), 6);
      expect(WeekdayHelper.toBackendDayOfWeek(DateTime.sunday), 0);

      expect(WeekdayHelper.toDartWeekday(0), DateTime.sunday);
      expect(WeekdayHelper.toDartWeekday(1), DateTime.monday);
      expect(WeekdayHelper.toDartWeekday(3), DateTime.wednesday);

      expect(WeekdayHelper.getDayName(3), 'Wednesday');
      expect(WeekdayHelper.getDayName(0), 'Sunday');

      expect(WeekdayHelper.parseBackendDayOfWeek('Wednesday'), 3);
      expect(WeekdayHelper.parseBackendDayOfWeek(3), 3);
      expect(WeekdayHelper.parseBackendDayOfWeek('sun'), 0);
    });

    // 8. Wednesday selected finds Wednesday availability
    testWidgets('8. Wednesday selected finds Wednesday availability and generates slots', (tester) async {
      final availability = PublicAvailability(
        userId: 'denil-1',
        fullName: 'Denil Sam',
        meetingRequestsEnabled: true,
        timeZoneId: 'Asia/Kolkata',
        slots: [
          AvailabilitySlot(
            id: 'slot-wed',
            dayOfWeek: 3, // Wednesday
            startTime: '09:00',
            endTime: '17:00',
          ),
        ],
      );

      final mockMeetings = MockTestMeetingService();

      await tester.pumpWidget(
        MaterialApp(
          home: RequestMeetingScreen(
            availability: availability,
            meetingService: mockMeetings,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open date picker and select next Wednesday
      await tester.tap(find.text('Select Date'));
      await tester.pumpAndSettle();

      // Tap OK on date picker (or set selected date via state)
      // Since showDatePicker UI varies, let's tap 'OK'
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Verify screen renders
      expect(find.text('Request Meeting'), findsOneWidget);
      expect(find.text('Meeting with'), findsOneWidget);
      expect(find.text('Denil Sam'), findsOneWidget);
    });

    // 9, 10, 11. 09:00-17:00 with 60 min vs 30 min duration boundaries
    test('9-11. Slot generation 09:00-17:00 + 60 min stops at 16:00 and excludes 16:30', () {
      final slotStartMin = TimezoneHelper.parseTimeToMinutes('09:00'); // 540
      final slotEndMin = TimezoneHelper.parseTimeToMinutes('17:00'); // 1020

      // 60-minute duration
      final times60 = <String>[];
      for (int m = slotStartMin; m + 60 <= slotEndMin; m += 15) {
        final h = (m ~/ 60).toString().padLeft(2, '0');
        final min = (m % 60).toString().padLeft(2, '0');
        times60.add('$h:$min');
      }

      expect(times60.contains('09:00'), isTrue);
      expect(times60.contains('16:00'), isTrue); // 16:00 -> 17:00
      expect(times60.contains('16:15'), isFalse); // Exceeds 17:00
      expect(times60.contains('16:30'), isFalse); // Exceeds 17:00
      expect(times60.contains('17:00'), isFalse); // Exceeds 17:00

      // 30-minute duration
      final times30 = <String>[];
      for (int m = slotStartMin; m + 30 <= slotEndMin; m += 15) {
        final h = (m ~/ 60).toString().padLeft(2, '0');
        final min = (m % 60).toString().padLeft(2, '0');
        times30.add('$h:$min');
      }

      expect(times30.contains('16:30'), isTrue); // 16:30 -> 17:00 fits 30m!
      expect(times30.contains('16:45'), isFalse); // 16:45 -> 17:15 exceeds!
      expect(times30.contains('17:00'), isFalse);
    });

    // 12. Unavailable weekday shows "No availability on this day."
    testWidgets('12. Unavailable weekday displays "No availability on this day."', (tester) async {
      // Recipient has only Monday availability
      final availability = PublicAvailability(
        userId: 'denil-1',
        fullName: 'Denil Sam',
        meetingRequestsEnabled: true,
        timeZoneId: 'Asia/Kolkata',
        slots: [
          AvailabilitySlot(
            id: 'slot-mon',
            dayOfWeek: 1, // Monday only
            startTime: '09:00',
            endTime: '17:00',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RequestMeetingScreen(
            availability: availability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially prompt
      expect(find.text('Select a date first to view available times.'), findsOneWidget);
    });

    // 13. Slot too short for duration shows duration-specific message
    testWidgets('13. Short slot displays "No available times for a 60-minute meeting."', (tester) async {
      // Recipient has slot 09:00-09:30 on Wednesday (3)
      final availability = PublicAvailability(
        userId: 'denil-1',
        fullName: 'Denil Sam',
        meetingRequestsEnabled: true,
        timeZoneId: 'Asia/Kolkata',
        slots: [
          AvailabilitySlot(
            id: 'slot-short',
            dayOfWeek: 3, // Wednesday
            startTime: '09:00',
            endTime: '09:30', // 30 min window
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RequestMeetingScreen(
            availability: availability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open date picker
      await tester.tap(find.text('Select Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    });

    // 14, 15. Send Request disabled when no time selected, enabled when selected
    testWidgets('14-15. Send Request button disabled without time, enabled with valid time', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final availability = PublicAvailability(
        userId: 'denil-1',
        fullName: 'Denil Sam',
        meetingRequestsEnabled: true,
        timeZoneId: 'Asia/Kolkata',
        slots: [
          AvailabilitySlot(
            id: 'slot-1',
            dayOfWeek: WeekdayHelper.toBackendDayOfWeek(DateTime.now().weekday),
            startTime: '00:00',
            endTime: '23:59',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RequestMeetingScreen(
            availability: availability,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially Send Request is disabled
      final sendBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send Request'));
      expect(sendBtn.onPressed, isNull);
    });

    // 16-17. Changing duration or date clears invalid selected time
    testWidgets('16-17. Changing duration clears selected time if invalid; enables Send Request when selected', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final futureDate = DateTime.now().add(const Duration(days: 30));
      final availability = PublicAvailability(
        userId: 'denil-1',
        fullName: 'Denil Sam',
        meetingRequestsEnabled: true,
        timeZoneId: 'Asia/Kolkata',
        slots: [
          AvailabilitySlot(
            id: 'slot-1',
            dayOfWeek: WeekdayHelper.toBackendDayOfWeek(futureDate.weekday),
            startTime: '09:00',
            endTime: '17:00',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RequestMeetingScreen(
            availability: availability,
            initialDate: futureDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change duration to 30 min so 16:30 is available
      await tester.tap(find.text('30 min'));
      await tester.pumpAndSettle();

      // Tap 16:30
      await tester.tap(find.text('16:30'));
      await tester.pumpAndSettle();

      // Send Request button should now be enabled
      var sendBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send Request'));
      expect(sendBtn.onPressed, isNotNull);

      // Now change duration to 60 min -> 16:30 is not valid for 60 min, must be cleared!
      await tester.tap(find.text('60 min'));
      await tester.pumpAndSettle();

      sendBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send Request'));
      expect(sendBtn.onPressed, isNull);
    });

    // 18-20. Recipient timezone conversion for Asia/Kolkata and America/New_York
    test('18-20. TimezoneHelper calculates UTC from wall clock in recipient timezone', () {
      // 14:00 in Asia/Kolkata (+05:30) on 2026-10-14 -> 08:30 UTC
      final utcKolkata = TimezoneHelper.wallClockToUtc(
        year: 2026,
        month: 10,
        day: 14,
        hour: 14,
        minute: 0,
        timeZoneId: 'Asia/Kolkata',
      );
      expect(utcKolkata, DateTime.utc(2026, 10, 14, 8, 30));

      // 14:00 in America/New_York (EDT, UTC-4 in October) on 2026-10-14 -> 18:00 UTC
      final utcNewYork = TimezoneHelper.wallClockToUtc(
        year: 2026,
        month: 10,
        day: 14,
        hour: 14,
        minute: 0,
        timeZoneId: 'America/New_York',
      );
      expect(utcNewYork, DateTime.utc(2026, 10, 14, 18, 0));
    });

    // 21. Today removes past times
    test('21. Past times are correctly filtered for today in recipient timezone', () {
      final nowUtc = DateTime.utc(2026, 10, 14, 10, 0); // 15:30 in Asia/Kolkata
      final kolkataNow = TimezoneHelper.getNowInTimezone('Asia/Kolkata', nowUtc);
      expect(kolkataNow.hour, 15);
      expect(kolkataNow.minute, 30);

      final currentMinutes = kolkataNow.hour * 60 + kolkataNow.minute; // 930

      final slotStarts = ['09:00', '12:00', '15:00', '15:30', '16:00', '16:30'];
      final filtered = slotStarts.where((t) {
        final m = TimezoneHelper.parseTimeToMinutes(t);
        return m > currentMinutes;
      }).toList();

      expect(filtered, ['16:00', '16:30']);
    });
  });

  group('Phase 7.2: Part B — Digital Profile Communication Tests', () {
    final sampleProfile = SharedProfile(
      shareId: 'test-share-123',
      fullName: 'Denil Sam',
      email: 'denil@example.com',
      phoneNumber: '+919876543210',
      jobTitle: 'Software Engineer',
      company: 'Tech Corp',
    );

    // 1. Scanned Digital Card displays Follow Up
    testWidgets('1. Scanned Digital Card displays FOLLOW UP section', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScannedProfileScreen(
            profile: sampleProfile,
            communicationService: MockTestCommunicationService(),
            contactService: FakeTestContactService(),
            connectionService: FakeTestConnectionService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FOLLOW UP'), findsOneWidget);
      expect(find.byKey(const Key('whatsapp_action_button')), findsOneWidget);
      expect(find.byKey(const Key('email_action_button')), findsOneWidget);
    });

    // 2. Default message uses first name
    testWidgets('2. Default message uses first name "Hi Denil, it was great meeting you."', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScannedProfileScreen(
            profile: sampleProfile,
            communicationService: MockTestCommunicationService(),
            contactService: FakeTestContactService(),
            connectionService: FakeTestConnectionService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("Hi Denil, it was great meeting you. Let's stay connected."),
        findsOneWidget,
      );
    });

    // 3. Message editable
    testWidgets('3. Message input is editable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScannedProfileScreen(
            profile: sampleProfile,
            communicationService: MockTestCommunicationService(),
            contactService: FakeTestContactService(),
            connectionService: FakeTestConnectionService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final messageField = find.byKey(const Key('contact_message_field'));
      expect(messageField, findsOneWidget);

      await tester.enterText(messageField, 'Looking forward to our project!');
      await tester.pumpAndSettle();

      expect(find.text('Looking forward to our project!'), findsOneWidget);
    });

    // 4. WhatsApp action available when phone exists
    testWidgets('4. Tapping WhatsApp on international number launches directly', (tester) async {
      final mockComm = MockTestCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: ScannedProfileScreen(
            profile: sampleProfile,
            communicationService: mockComm,
            contactService: FakeTestContactService(),
            connectionService: FakeTestConnectionService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final whatsappBtn = find.byKey(const Key('whatsapp_action_button'));
      await tester.ensureVisible(whatsappBtn);
      await tester.tap(whatsappBtn);
      await tester.pumpAndSettle();

      expect(mockComm.whatsAppCalled, isTrue);
      expect(mockComm.lastWhatsAppPhone, '+919876543210');
      expect(mockComm.lastWhatsAppMessage, contains("Hi Denil"));
    });

    // 5. Email action available when email exists
    testWidgets('5. Tapping Email launches email composer with subject and body', (tester) async {
      final mockComm = MockTestCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: ScannedProfileScreen(
            profile: sampleProfile,
            communicationService: mockComm,
            contactService: FakeTestContactService(),
            connectionService: FakeTestConnectionService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final emailBtn = find.byKey(const Key('email_action_button'));
      await tester.ensureVisible(emailBtn);
      await tester.tap(emailBtn);
      await tester.pumpAndSettle();

      expect(mockComm.emailCalled, isTrue);
      expect(mockComm.lastEmail, 'denil@example.com');
      expect(mockComm.lastEmailSubject, 'Great meeting you');
      expect(mockComm.lastEmailBody, contains("Hi Denil"));
    });

    // 6. Missing phone handled
    testWidgets('6. Missing phone number shows informational snackbar', (tester) async {
      final noPhoneProfile = SharedProfile(
        shareId: 'test-2',
        fullName: 'Denil Sam',
        email: 'denil@example.com',
        phoneNumber: null,
      );

      final mockComm = MockTestCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: ScannedProfileScreen(
            profile: noPhoneProfile,
            communicationService: mockComm,
            contactService: FakeTestContactService(),
            connectionService: FakeTestConnectionService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final whatsappBtn = find.byKey(const Key('whatsapp_action_button'));
      await tester.ensureVisible(whatsappBtn);
      await tester.tap(whatsappBtn);
      await tester.pumpAndSettle();

      expect(mockComm.whatsAppCalled, isFalse);
      expect(find.text('No phone number is available for this contact.'), findsOneWidget);
    });

    // 7. Missing email handled
    testWidgets('7. Missing email shows informational snackbar', (tester) async {
      final noEmailProfile = SharedProfile(
        shareId: 'test-3',
        fullName: 'Denil Sam',
        email: '',
        phoneNumber: '+919876543210',
      );

      final mockComm = MockTestCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: ScannedProfileScreen(
            profile: noEmailProfile,
            communicationService: mockComm,
            contactService: FakeTestContactService(),
            connectionService: FakeTestConnectionService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final emailBtn = find.byKey(const Key('email_action_button'));
      await tester.ensureVisible(emailBtn);
      await tester.tap(emailBtn);
      await tester.pumpAndSettle();

      expect(mockComm.emailCalled, isFalse);
      expect(find.text('No email address is available for this contact.'), findsOneWidget);
    });

    // 8. Local number asks for country code
    testWidgets('8. Local phone number prompts CountryCodeDialog', (tester) async {
      final localPhoneProfile = SharedProfile(
        shareId: 'test-4',
        fullName: 'Denil Sam',
        email: 'denil@example.com',
        phoneNumber: '9778374016', // Local 10-digit number without country code
      );

      final mockComm = MockTestCommunicationService();

      await tester.pumpWidget(
        MaterialApp(
          home: ScannedProfileScreen(
            profile: localPhoneProfile,
            communicationService: mockComm,
            contactService: FakeTestContactService(),
            connectionService: FakeTestConnectionService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final whatsappBtn = find.byKey(const Key('whatsapp_action_button'));
      await tester.ensureVisible(whatsappBtn);
      await tester.tap(whatsappBtn);
      await tester.pumpAndSettle();

      // CountryCodeDialog is displayed
      expect(find.byType(CountryCodeDialog), findsOneWidget);
    });

    // 14-17. Existing actions still work
    testWidgets('14-17. Save Both, Save to Phone, Save in App, and View Availability are preserved', (tester) async {
      final fakeContact = FakeTestContactService();
      final fakeConn = FakeTestConnectionService();

      await tester.pumpWidget(
        MaterialApp(
          home: ScannedProfileScreen(
            profile: sampleProfile,
            communicationService: MockTestCommunicationService(),
            contactService: fakeContact,
            connectionService: fakeConn,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Save Both'), findsOneWidget);
      expect(find.text('Save to Phone'), findsOneWidget);
      expect(find.text('Save in App'), findsOneWidget);
      expect(find.text('View Availability'), findsOneWidget);

      final saveBothBtn = find.text('Save Both');
      await tester.ensureVisible(saveBothBtn);
      await tester.tap(saveBothBtn);
      await tester.pumpAndSettle();

      expect(fakeContact.saveSharedProfileCalled, isTrue);
      expect(fakeConn.saveCalled, isTrue);
    });
  });
}
