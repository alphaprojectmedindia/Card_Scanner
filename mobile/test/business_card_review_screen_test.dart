import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/screens/scan/business_card_review_screen.dart';

void main() {
  group('BusinessCardReviewScreen Widget Tests', () {
    final sampleData = BusinessCardData(
      fullName: 'Rahul Kumar',
      jobTitle: 'Senior Developer',
      company: 'ABC Technologies',
      phoneNumbers: const [
        BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile'),
        BusinessCardPhone(number: '+91 44 2345 6789', label: 'Office'),
      ],
      emailAddresses: const [
        BusinessCardEmail(email: 'rahul@abctech.com', label: 'Work'),
        BusinessCardEmail(email: 'rahul.personal@gmail.com', label: 'Personal'),
      ],
      website: 'www.abctech.com',
      address: 'Chennai, Tamil Nadu',
      rawRecognizedText: 'Sample OCR text',
    );

    testWidgets('Renders all business card fields accurately', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: sampleData),
        ),
      );

      expect(find.text('Business Card Details'), findsOneWidget);

      final nameField = tester.widget<TextFormField>(find.byKey(const Key('review_name_field')));
      expect(nameField.controller?.text, 'Rahul Kumar');

      final titleField = tester.widget<TextFormField>(find.byKey(const Key('review_job_title_field')));
      expect(titleField.controller?.text, 'Senior Developer');

      final companyField = tester.widget<TextFormField>(find.byKey(const Key('review_company_field')));
      expect(companyField.controller?.text, 'ABC Technologies');

      final phone0 = tester.widget<TextFormField>(find.byKey(const Key('phone_field_0')));
      expect(phone0.controller?.text, '+91 98765 43210');

      final phone1 = tester.widget<TextFormField>(find.byKey(const Key('phone_field_1')));
      expect(phone1.controller?.text, '+91 44 2345 6789');

      final email0 = tester.widget<TextFormField>(find.byKey(const Key('email_field_0')));
      expect(email0.controller?.text, 'rahul@abctech.com');

      final email1 = tester.widget<TextFormField>(find.byKey(const Key('email_field_1')));
      expect(email1.controller?.text, 'rahul.personal@gmail.com');

      final websiteField = tester.widget<TextFormField>(find.byKey(const Key('review_website_field')));
      expect(websiteField.controller?.text, 'www.abctech.com');

      final addressField = tester.widget<TextFormField>(find.byKey(const Key('review_address_field')));
      expect(addressField.controller?.text, 'Chennai, Tamil Nadu');
    });

    testWidgets('Allows adding a new phone number', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: sampleData),
        ),
      );

      expect(find.byKey(const Key('phone_field_0')), findsOneWidget);
      expect(find.byKey(const Key('phone_field_1')), findsOneWidget);
      expect(find.byKey(const Key('phone_field_2')), findsNothing);

      // Scroll to add phone button
      await tester.ensureVisible(find.byKey(const Key('add_phone_button')));
      await tester.tap(find.byKey(const Key('add_phone_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('phone_field_2')), findsOneWidget);
    });

    testWidgets('Allows deleting a phone number', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: sampleData),
        ),
      );

      expect(find.byKey(const Key('delete_phone_0')), findsOneWidget);
      expect(find.byKey(const Key('delete_phone_1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete_phone_0')));
      await tester.pumpAndSettle();

      // Only one phone entry remains
      expect(find.byKey(const Key('delete_phone_0')), findsOneWidget);
      expect(find.byKey(const Key('delete_phone_1')), findsNothing);

      final remainingPhone = tester.widget<TextFormField>(find.byKey(const Key('phone_field_0')));
      expect(remainingPhone.controller?.text, '+91 44 2345 6789');
    });

    testWidgets('Allows adding a new email address', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: sampleData),
        ),
      );

      expect(find.byKey(const Key('email_field_0')), findsOneWidget);
      expect(find.byKey(const Key('email_field_1')), findsOneWidget);
      expect(find.byKey(const Key('email_field_2')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('add_email_button')));
      await tester.tap(find.byKey(const Key('add_email_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('email_field_2')), findsOneWidget);
    });

    testWidgets('Allows deleting an email address', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: sampleData),
        ),
      );

      expect(find.byKey(const Key('delete_email_0')), findsOneWidget);
      expect(find.byKey(const Key('delete_email_1')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('delete_email_0')));
      await tester.tap(find.byKey(const Key('delete_email_0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_email_0')), findsOneWidget);
      expect(find.byKey(const Key('delete_email_1')), findsNothing);

      final remainingEmail = tester.widget<TextFormField>(find.byKey(const Key('email_field_0')));
      expect(remainingEmail.controller?.text, 'rahul.personal@gmail.com');
    });

    testWidgets('Confirm Details pops updated BusinessCardData', (tester) async {
      BusinessCardData? returnedData;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                returnedData = await Navigator.of(context).push<BusinessCardData>(
                  MaterialPageRoute(
                    builder: (_) => BusinessCardReviewScreen(cardData: sampleData),
                  ),
                );
              },
              child: const Text('Open Review'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Review'));
      await tester.pumpAndSettle();

      // Edit name field
      await tester.enterText(find.byKey(const Key('review_name_field')), 'Rahul K. Sharma');
      await tester.pumpAndSettle();

      // Tap Confirm Details
      await tester.ensureVisible(find.byKey(const Key('confirm_details_button')));
      await tester.tap(find.byKey(const Key('confirm_details_button')));
      await tester.pumpAndSettle();

      expect(returnedData, isNotNull);
      expect(returnedData!.fullName, 'Rahul K. Sharma');
      expect(returnedData!.company, 'ABC Technologies');
    });
  });
}
