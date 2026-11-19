import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/widgets/medindia_branding_footer.dart';
import 'package:digital_share/screens/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MedindiaBrandingFooter Widget Tests', () {
    testWidgets('renders exact text "Powered by Medindia4u.com"', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MedindiaBrandingFooter(),
          ),
        ),
      );

      expect(find.text('Powered by Medindia4u.com'), findsOneWidget);
      expect(find.byKey(const Key('medindia_branding_footer_text')), findsOneWidget);
    });

    testWidgets('renders divider when showDivider is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MedindiaBrandingFooter(showDivider: true),
          ),
        ),
      );

      expect(find.byType(Divider), findsOneWidget);
      expect(find.text('Powered by Medindia4u.com'), findsOneWidget);
    });

    testWidgets('does not render divider when showDivider is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MedindiaBrandingFooter(showDivider: false),
          ),
        ),
      );

      expect(find.byType(Divider), findsNothing);
      expect(find.text('Powered by Medindia4u.com'), findsOneWidget);
    });
  });

  group('SplashScreen Branding Verification', () {
    testWidgets('displays "Powered by Medindia4u.com" below logo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(initialDelay: Duration.zero),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('splash_medindia_branding_text')), findsOneWidget);
      expect(find.text('Powered by Medindia4u.com'), findsOneWidget);
    });
  });
}
