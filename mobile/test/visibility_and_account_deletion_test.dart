import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/user_profile.dart';
import 'package:digital_share/screens/profile/account_visibility_screen.dart';
import 'package:digital_share/screens/profile/delete_account_screen.dart';
import 'package:digital_share/services/auth_service.dart';
import 'package:digital_share/services/profile_service.dart';

class FakeProfileService extends ProfileService {
  bool currentVisibility;
  FakeProfileService({this.currentVisibility = false});

  @override
  Future<bool> getVisibility() async => currentVisibility;

  @override
  Future<bool> updateVisibility(bool isPublic) async {
    currentVisibility = isPublic;
    return currentVisibility;
  }
}

class FakeAuthService extends AuthService {
  bool deleteCalled = false;
  String? lastPassword;

  @override
  Future<void> deleteAccount({required String password}) async {
    deleteCalled = true;
    lastPassword = password;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Feature 2: Account Visibility Model & UI Tests', () {
    test('UserProfile defaults isPublic to false', () {
      final profile = UserProfile(
        id: 'u1',
        userId: 'u1',
        shareId: 'share1',
        email: 'test@example.com',
        createdAtUtc: DateTime.utc(2026, 11, 5),
        updatedAtUtc: DateTime.utc(2026, 11, 5),
      );

      expect(profile.isPublic, isFalse);

      final json = profile.toJson();
      expect(json['isPublic'], isFalse);

      final copy = profile.copyWith(isPublic: true);
      expect(copy.isPublic, isTrue);

      final deserialized = UserProfile.fromJson(copy.toJson());
      expect(deserialized.isPublic, isTrue);
    });

    testWidgets('AccountVisibilityScreen renders Private default and allows toggling to Public', (tester) async {
      final fakeService = FakeProfileService(currentVisibility: false);

      await tester.pumpWidget(
        MaterialApp(
          home: AccountVisibilityScreen(
            profileService: fakeService,
            initialIsPublic: false,
          ),
        ),
      );

      expect(find.text('Account Visibility'), findsOneWidget);
      expect(find.text('Private Account'), findsOneWidget);
      expect(find.text('Public Account'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);

      // Tap Public option
      await tester.tap(find.byKey(const Key('visibility_public_option')));
      await tester.pumpAndSettle();

      expect(fakeService.currentVisibility, isTrue);
    });
  });

  group('Feature 3: Delete Account Multi-Step Flow Tests', () {
    testWidgets('DeleteAccountScreen navigates through 4 steps with validations', (tester) async {
      final fakeAuth = FakeAuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: DeleteAccountScreen(
            authService: fakeAuth,
            initialCardCount: 3,
            initialConnectionCount: 5,
            initialMeetingCount: 2,
          ),
        ),
      );

      // Step 1: Warning
      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(find.text('Delete Your Account Permanently'), findsOneWidget);
      expect(find.text('What will be deleted:'), findsOneWidget);

      // Advance to Step 2
      await tester.tap(find.byKey(const Key('delete_account_next_button')));
      await tester.pumpAndSettle();

      // Step 2: Data summary
      expect(find.text('Step 2 of 4'), findsOneWidget);
      expect(find.text('Data Impact Summary'), findsOneWidget);

      // Advance to Step 3
      await tester.tap(find.byKey(const Key('delete_account_next_button')));
      await tester.pumpAndSettle();

      // Step 3: Password Reauthentication
      expect(find.text('Step 3 of 4'), findsOneWidget);
      expect(find.text('Confirm Your Password'), findsOneWidget);

      // Attempting to advance with empty password should fail
      await tester.tap(find.byKey(const Key('delete_account_next_button')));
      await tester.pumpAndSettle();
      expect(find.text('Password is required to proceed.'), findsOneWidget);

      // Enter password
      await tester.enterText(find.byKey(const Key('delete_account_password_field')), 'SecretPassword123!');
      await tester.tap(find.byKey(const Key('delete_account_next_button')));
      await tester.pumpAndSettle();

      // Step 4: Final Confirmation
      expect(find.text('Step 4 of 4'), findsOneWidget);
      expect(find.text('Final Warning'), findsOneWidget);

      // Attempt without checkbox
      await tester.tap(find.byKey(const Key('delete_account_confirm_button')));
      await tester.pumpAndSettle();
      expect(find.text('You must confirm that you understand this action is permanent.'), findsOneWidget);

      // Check the checkbox
      await tester.tap(find.byKey(const Key('delete_account_understand_checkbox')));
      await tester.pumpAndSettle();

      // Attempt without typing DELETE
      await tester.tap(find.byKey(const Key('delete_account_confirm_button')));
      await tester.pumpAndSettle();
      expect(find.text("Please type 'DELETE' in the confirmation field to confirm."), findsOneWidget);

      // Enter 'DELETE'
      await tester.enterText(find.byKey(const Key('delete_account_confirm_text_field')), 'DELETE');
      await tester.pumpAndSettle();

      // Tap confirm button
      await tester.tap(find.byKey(const Key('delete_account_confirm_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(fakeAuth.deleteCalled, isTrue);
      expect(fakeAuth.lastPassword, 'SecretPassword123!');
    });
  });
}
