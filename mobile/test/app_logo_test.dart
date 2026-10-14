import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/imported_contact.dart';
import 'package:digital_share/models/saved_connection.dart';
import 'package:digital_share/models/user_profile.dart';
import 'package:digital_share/screens/auth/login_screen.dart';
import 'package:digital_share/screens/auth/register_screen.dart';
import 'package:digital_share/screens/home/home_screen.dart';
import 'package:digital_share/screens/profile/profile_screen.dart';
import 'package:digital_share/services/connection_service.dart';
import 'package:digital_share/services/imported_contact_service.dart';
import 'package:digital_share/widgets/digital_share_logo.dart';

class MockHomeScreenConnectionService extends ConnectionService {
  @override
  Future<List<SavedConnection>> getConnections() async => [];
}

class MockHomeScreenImportedContactService extends ImportedContactService {
  @override
  Future<List<ImportedContact>> getContacts() async => [];
}

void main() {
  group('Digital Share App Logo & Branding Tests', () {
    test('1. Asset files exist in mobile/assets/images directory', () {
      final logoFile = File('assets/images/digital_share_logo.png');
      expect(logoFile.existsSync(), isTrue, reason: 'Official logo PNG must exist');
      expect(logoFile.lengthSync(), greaterThan(100000), reason: 'Full quality original logo');

      final appIconFile = File('assets/images/app_icon.png');
      expect(appIconFile.existsSync(), isTrue, reason: 'iOS/Android launcher icon must exist');

      final fgIconFile = File('assets/images/app_icon_foreground.png');
      expect(fgIconFile.existsSync(), isTrue, reason: 'Android adaptive foreground icon must exist');
    });

    testWidgets('2. DigitalShareLogo widget renders Image.asset with correct parameters', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DigitalShareLogo(
              size: 64,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);

      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.image, isA<AssetImage>());
      final assetImage = imageWidget.image as AssetImage;
      expect(assetImage.assetName, 'assets/images/digital_share_logo.png');
      expect(imageWidget.fit, BoxFit.contain);
      expect(imageWidget.width, 64);
      expect(imageWidget.height, 64);
    });

    testWidgets('3. LoginScreen displays official DigitalShareLogo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DigitalShareLogo), findsOneWidget);
    });

    testWidgets('4. RegisterScreen displays official DigitalShareLogo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RegisterScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DigitalShareLogo), findsOneWidget);
    });

    testWidgets('5. HomeScreen displays DigitalShareLogo in branding AppBar', (tester) async {
      final sampleProfile = UserProfile(
        id: 'u-1',
        userId: 'u-1',
        shareId: 'ds-1',
        email: 'denil@example.com',
        fullName: 'Denil Sam',
        jobTitle: 'Software Engineer',
        company: 'NovaTech',
        createdAtUtc: DateTime.now().toUtc(),
        updatedAtUtc: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProfile: sampleProfile,
            connectionService: MockHomeScreenConnectionService(),
            importedContactService: MockHomeScreenImportedContactService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DigitalShareLogo), findsOneWidget);
      expect(find.text('Digital Share'), findsWidgets);
    });

    testWidgets('6. ProfileScreen displays DigitalShareLogo in about footer', (tester) async {
      final sampleProfile = UserProfile(
        id: 'u-1',
        userId: 'u-1',
        shareId: 'ds-1',
        email: 'denil@example.com',
        fullName: 'Denil Sam',
        createdAtUtc: DateTime.now().toUtc(),
        updatedAtUtc: DateTime.now().toUtc(),
      );

      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            initialProfile: sampleProfile,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DigitalShareLogo), findsOneWidget);
      expect(find.text('Smart Contact & Availability Sharing • v1.0.0'), findsOneWidget);
    });
  });
}
