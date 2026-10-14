import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/user_profile.dart';
import 'package:digital_share/screens/profile/edit_profile_screen.dart';

void main() {
  final sampleProfile = UserProfile(
    id: 'usr-123',
    userId: 'u1',
    shareId: 'alpha1234567890123',
    fullName: 'Jane Doe',
    email: 'jane@example.com',
    phoneNumber: '+1 555-0199',
    jobTitle: 'Lead Engineer',
    company: 'Tech Corp',
    website: 'https://jane.example.com',
    address: 'Austin, TX',
    bio: 'Software engineer and designer.',
    profilePhotoUrl: null,
    createdAtUtc: DateTime(2025, 1, 1),
    updatedAtUtc: DateTime(2025, 1, 1),
  );

  Widget createTestWidget({UserProfile? profile}) {
    return MaterialApp(
      home: EditProfileScreen(
        profile: profile ?? sampleProfile,
      ),
    );
  }

  group('EditProfileScreen Widget Tests', () {
    testWidgets('Renders avatar placeholder, Add Photo button and no Profile Photo URL text field', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Top circular avatar should be present
      expect(find.byType(CircleAvatar), findsOneWidget);

      // "Add Photo" action button should be present because profilePhotoUrl is null
      expect(find.text('Add Photo'), findsOneWidget);

      // CRITICAL REQUIREMENT: Profile Photo URL text field must NOT exist
      expect(find.text('Profile Photo URL'), findsNothing);

      // Form fields should be present
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email Address *'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('Shows Change Photo when profile already has a photo URL', (tester) async {
      final profileWithPhoto = sampleProfile.copyWith(
        profilePhotoUrl: '/uploads/profile-photos/abc12345.jpg',
      );

      await tester.pumpWidget(createTestWidget(profile: profileWithPhoto));
      await tester.pumpAndSettle();

      expect(find.text('Change Photo'), findsOneWidget);
      expect(find.text('Add Photo'), findsNothing);
      expect(find.text('Profile Photo URL'), findsNothing);
    });

    testWidgets('Tapping photo action shows options modal sheet with Take Photo, Choose from Gallery, Cancel', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap "Add Photo" button
      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      // Bottom sheet should display options
      expect(find.text('Profile Photo'), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Cancel dismisses bottom sheet
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Take Photo'), findsNothing);
    });
  });
}
