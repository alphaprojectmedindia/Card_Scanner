import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:digital_share/models/user_profile.dart';
import 'package:digital_share/screens/profile/digital_card_screen.dart';

void main() {
  group('DigitalCardScreen Widget Tests', () {
    testWidgets('Renders provided user profile data and dynamic QR code', (WidgetTester tester) async {
      final sampleProfile = UserProfile(
        id: 'guid-1',
        userId: 'uid-1',
        shareId: 'x7F9K2mQ8pL4vYkVl6VUbG7T',
        fullName: 'Alex Morgan',
        email: 'alex.morgan@example.com',
        phoneNumber: '+1-555-9876',
        jobTitle: 'Senior Cloud Architect',
        company: 'Apex Technologies',
        website: 'https://apextech.io',
        address: 'Seattle, WA',
        bio: 'Building next-gen digital share tools.',
        createdAtUtc: DateTime.now().toUtc(),
        updatedAtUtc: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DigitalCardScreen(initialProfile: sampleProfile),
        ),
      );

      // Verify contact card title and top badge
      expect(find.text('My Digital Card'), findsOneWidget);
      expect(find.text('DIGITAL SHARE'), findsOneWidget);

      // Verify dynamic profile values
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('Senior Cloud Architect'), findsOneWidget);
      expect(find.text('Apex Technologies'), findsOneWidget);
      expect(find.text('alex.morgan@example.com'), findsOneWidget);
      expect(find.text('+1-555-9876'), findsOneWidget);
      expect(find.text('https://apextech.io'), findsOneWidget);
      expect(find.text('Seattle, WA'), findsOneWidget);
      expect(find.text('Building next-gen digital share tools.'), findsOneWidget);

      // Verify real dynamic QR Image generation
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Scan to view my Digital Share card'), findsOneWidget);
    });
  });
}
