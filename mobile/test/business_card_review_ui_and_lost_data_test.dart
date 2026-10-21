import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/screens/scan/business_card_review_screen.dart';
import 'package:digital_share/screens/scan/business_card_scan_screen.dart';
import 'package:digital_share/services/business_card_ocr_service.dart';
import 'package:digital_share/services/pending_card_capture_store.dart';
import 'package:digital_share/widgets/business_card_email_editor.dart';
import 'package:digital_share/widgets/business_card_phone_editor.dart';

class FakeImagePicker extends ImagePicker {
  XFile? nextFile;
  ImageSource? lastSource;
  LostDataResponse lostDataResponse = LostDataResponse.empty();

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    lastSource = source;
    return nextFile;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    return lostDataResponse;
  }
}

class FakeOcrService implements IBusinessCardOcrService {
  String frontText;
  String backText;

  FakeOcrService({
    this.frontText = '',
    this.backText = '',
  });

  @override
  Future<String> recognizeTextFromPath(String imagePath) async {
    return frontText;
  }

  @override
  Future<OcrSideResult> processCardSide({
    required String imagePath,
    required CardSide side,
    String? source,
  }) async {
    final text = side == CardSide.front ? frontText : backText;
    return OcrSideResult.fromText(
      side: side,
      imagePath: imagePath,
      rawText: text,
    );
  }
}

void main() {
  setUp(() {
    PendingCardCaptureStore.resetForTesting();
  });

  tearDown(() {
    PendingCardCaptureStore.resetForTesting();
  });

  final sampleData = BusinessCardData(
    fullName: 'Dr. John Doe',
    jobTitle: 'Chief Medical Officer',
    company: 'Medindia Healthcare',
    phoneNumbers: const [
      BusinessCardPhone(number: '+91 98400 25680', label: 'Mobile'),
      BusinessCardPhone(number: '044 45242424', label: 'Office'),
    ],
    emailAddresses: const [
      BusinessCardEmail(email: 'shroffmed@gmail.com', label: 'Personal'),
      BusinessCardEmail(email: 'shroff@medindia.net', label: 'Work'),
    ],
    website: 'https://www.medindia.net',
    address: 'Chennai, Tamil Nadu, India',
    rawRecognizedText: 'Sample OCR text',
  );

  group('Automated Tests for Business Card Review UI & Lost Data Recovery', () {
    // -------------------------------------------------------------------------
    // 1. Review phone row has no Type dropdown
    // -------------------------------------------------------------------------
    testWidgets('1. Review phone row has no Type dropdown', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: sampleData),
        ),
      );
      await tester.pumpAndSettle();

      final phoneEditorFinder = find.byType(BusinessCardPhoneEditor);
      expect(phoneEditorFinder, findsOneWidget);

      final typeDropdownFinder = find.descendant(
        of: phoneEditorFinder,
        matching: find.byType(DropdownButtonFormField<String?>),
      );
      expect(typeDropdownFinder, findsNothing);
      expect(find.text('PHONE NUMBERS'), findsOneWidget);
      expect(find.text('2 detected'), findsAtLeastNWidgets(1));
    });

    // -------------------------------------------------------------------------
    // 2. Review email row has no Type dropdown
    // -------------------------------------------------------------------------
    testWidgets('2. Review email row has no Type dropdown', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: sampleData),
        ),
      );
      await tester.pumpAndSettle();

      final emailEditorFinder = find.byType(BusinessCardEmailEditor);
      expect(emailEditorFinder, findsOneWidget);

      final typeDropdownFinder = find.descendant(
        of: emailEditorFinder,
        matching: find.byType(DropdownButtonFormField<String?>),
      );
      expect(typeDropdownFinder, findsNothing);
      expect(find.text('EMAIL ADDRESSES'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 3. Long phone number renders without overflow
    // -------------------------------------------------------------------------
    testWidgets('3. Long phone number renders without overflow on narrow screens', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final longPhoneData = BusinessCardData(
        fullName: 'Jane Doe',
        phoneNumbers: const [
          BusinessCardPhone(
            number: '+1 (555) 019-2834 ext. 12345678901234567890',
            label: 'Mobile',
          ),
        ],
        rawRecognizedText: 'Sample',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: longPhoneData),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('+1 (555) 019-2834 ext. 12345678901234567890'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 4. Long email renders without overflow
    // -------------------------------------------------------------------------
    testWidgets('4. Long email renders without overflow on narrow screens', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final longEmailData = BusinessCardData(
        fullName: 'Jane Doe',
        emailAddresses: const [
          BusinessCardEmail(
            email: 'supercalifragilisticexpialidocious.corporate.representative@verylongenterprisedomainname.international.org',
            label: 'Work',
          ),
        ],
        rawRecognizedText: 'Sample',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: longEmailData),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('supercalifragilisticexpialidocious.corporate.representative@verylongenterprisedomainname.international.org'),
        findsOneWidget,
      );
    });

    // -------------------------------------------------------------------------
    // 5. Phone remains editable
    // -------------------------------------------------------------------------
    testWidgets('5. Phone remains editable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: sampleData),
        ),
      );
      await tester.pumpAndSettle();

      final phoneFieldFinder = find.byKey(const Key('phone_field_0'));
      expect(phoneFieldFinder, findsOneWidget);

      final phoneTextField = tester.widget<TextField>(
        find.descendant(of: phoneFieldFinder, matching: find.byType(TextField)),
      );
      expect(phoneTextField.keyboardType, TextInputType.phone);

      await tester.enterText(phoneFieldFinder, '+91 99999 88888');
      await tester.pumpAndSettle();

      final updatedPhone = tester.widget<TextFormField>(phoneFieldFinder);
      expect(updatedPhone.controller?.text, '+91 99999 88888');
    });

    // -------------------------------------------------------------------------
    // 6. Email remains editable
    // -------------------------------------------------------------------------
    testWidgets('6. Email remains editable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: sampleData),
        ),
      );
      await tester.pumpAndSettle();

      final emailFieldFinder = find.byKey(const Key('email_field_0'));
      expect(emailFieldFinder, findsOneWidget);

      final emailTextField = tester.widget<TextField>(
        find.descendant(of: emailFieldFinder, matching: find.byType(TextField)),
      );
      expect(emailTextField.keyboardType, TextInputType.emailAddress);

      await tester.enterText(emailFieldFinder, 'newemail@example.com');
      await tester.pumpAndSettle();

      final updatedEmail = tester.widget<TextFormField>(emailFieldFinder);
      expect(updatedEmail.controller?.text, 'newemail@example.com');
    });

    // -------------------------------------------------------------------------
    // 7. Remove phone works
    // -------------------------------------------------------------------------
    testWidgets('7. Remove phone works', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: sampleData),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('phone_field_0')), findsOneWidget);
      expect(find.byKey(const Key('phone_field_1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete_phone_0')));
      await tester.pumpAndSettle();

      // Only one phone entry remains
      expect(find.byKey(const Key('phone_field_0')), findsOneWidget);
      expect(find.byKey(const Key('phone_field_1')), findsNothing);

      final remaining = tester.widget<TextFormField>(find.byKey(const Key('phone_field_0')));
      expect(remaining.controller?.text, '044 45242424');
    });

    // -------------------------------------------------------------------------
    // 8. Remove email works
    // -------------------------------------------------------------------------
    testWidgets('8. Remove email works', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: sampleData),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('email_field_0')), findsOneWidget);
      expect(find.byKey(const Key('email_field_1')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('delete_email_0')));
      await tester.tap(find.byKey(const Key('delete_email_0')));
      await tester.pumpAndSettle();

      // Only one email entry remains
      expect(find.byKey(const Key('email_field_0')), findsOneWidget);
      expect(find.byKey(const Key('email_field_1')), findsNothing);

      final remaining = tester.widget<TextFormField>(find.byKey(const Key('email_field_0')));
      expect(remaining.controller?.text, 'shroff@medindia.net');
    });

    // -------------------------------------------------------------------------
    // 9. Add phone works
    // -------------------------------------------------------------------------
    testWidgets('9. Add phone works', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: sampleData),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('phone_field_2')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('add_phone_button')));
      await tester.tap(find.byKey(const Key('add_phone_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('phone_field_2')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 10. Add email works
    // -------------------------------------------------------------------------
    testWidgets('10. Add email works', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardReviewScreen(cardData: sampleData),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('email_field_2')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('add_email_button')));
      await tester.tap(find.byKey(const Key('add_email_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('email_field_2')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 11. Normal front camera result stages front
    // -------------------------------------------------------------------------
    testWidgets('11. Normal front camera result stages front', (tester) async {
      final fakePicker = FakeImagePicker()..nextFile = XFile('front_photo.jpg');
      final fakeOcr = FakeOcrService();

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(
            imagePicker: fakePicker,
            ocrService: fakeOcr,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('inline_take_photo_button')));
      await tester.tap(find.byKey(const Key('inline_take_photo_button')));
      await tester.pumpAndSettle();

      expect(fakePicker.lastSource, ImageSource.camera);
      // Front is staged; preview shown, does not immediately trigger OCR
      expect(find.text('FRONT SIDE'), findsOneWidget);
      expect(find.text('Scan Details (1 Side)'), findsOneWidget);
      expect(find.byKey(const Key('add_back_side_button')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 12. Normal back camera result stages back
    // -------------------------------------------------------------------------
    testWidgets('12. Normal back camera result stages back', (tester) async {
      final fakePicker = FakeImagePicker()..nextFile = XFile('front_photo.jpg');
      final fakeOcr = FakeOcrService();

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(
            imagePicker: fakePicker,
            ocrService: fakeOcr,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Stage front
      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('inline_take_photo_button')));
      await tester.tap(find.byKey(const Key('inline_take_photo_button')));
      await tester.pumpAndSettle();

      // Now add back side via camera
      fakePicker.nextFile = XFile('back_photo.jpg');
      await tester.ensureVisible(find.byKey(const Key('add_back_side_button')));
      await tester.tap(find.byKey(const Key('add_back_side_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('back_camera_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('back_camera_button')));
      await tester.pumpAndSettle();

      expect(fakePicker.lastSource, ImageSource.camera);
      expect(find.text('FRONT SIDE'), findsOneWidget);
      expect(find.textContaining('BACK SIDE'), findsOneWidget);
      expect(find.byKey(const Key('remove_back_button')), findsOneWidget);
      expect(find.text('Scan Details (Front & Back)'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 13. Lost front camera result restores front
    // -------------------------------------------------------------------------
    testWidgets('13. Lost front camera result restores front', (tester) async {
      await PendingCardCaptureStore.savePendingCapture(
        side: CardSide.front,
      );

      final fakePicker = FakeImagePicker()
        ..lostDataResponse = LostDataResponse(file: XFile('lost_front.jpg'));
      final fakeOcr = FakeOcrService();

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(
            imagePicker: fakePicker,
            ocrService: fakeOcr,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Front should be recovered and staged in preview mode without immediately running OCR
      expect(find.text('FRONT SIDE'), findsOneWidget);
      expect(find.text('Scan Details (1 Side)'), findsOneWidget);
      expect(find.byKey(const Key('add_back_side_button')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 14. Lost back camera result restores back
    // -------------------------------------------------------------------------
    testWidgets('14. Lost back camera result restores back', (tester) async {
      // Create a dummy front file so it exists
      final frontTemp = File('${Directory.systemTemp.path}/staged_front_test.jpg')
        ..writeAsStringSync('dummy_image_data');

      addTearDown(() {
        if (frontTemp.existsSync()) frontTemp.deleteSync();
      });

      await PendingCardCaptureStore.savePendingCapture(
        side: CardSide.back,
        frontPath: frontTemp.path,
      );

      final fakePicker = FakeImagePicker()
        ..lostDataResponse = LostDataResponse(file: XFile('lost_back.jpg'));
      final fakeOcr = FakeOcrService();

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(
            imagePicker: fakePicker,
            ocrService: fakeOcr,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Front is restored from saved path, back is restored from lost data
      expect(find.text('FRONT SIDE'), findsOneWidget);
      expect(find.textContaining('BACK SIDE'), findsOneWidget);
      expect(find.byKey(const Key('remove_back_button')), findsOneWidget);
      expect(find.text('Scan Details (Front & Back)'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 15. Camera cancellation preserves state
    // -------------------------------------------------------------------------
    testWidgets('15. Camera cancellation preserves state', (tester) async {
      final fakePicker = FakeImagePicker()..nextFile = XFile('front_photo.jpg');
      final fakeOcr = FakeOcrService();

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(
            imagePicker: fakePicker,
            ocrService: fakeOcr,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Stage front
      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('inline_take_photo_button')));
      await tester.tap(find.byKey(const Key('inline_take_photo_button')));
      await tester.pumpAndSettle();

      expect(find.text('FRONT SIDE'), findsOneWidget);

      // User tries to take back photo, but cancels
      fakePicker.nextFile = null;
      await tester.ensureVisible(find.byKey(const Key('add_back_side_button')));
      await tester.tap(find.byKey(const Key('add_back_side_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('back_camera_button')));
      await tester.pumpAndSettle();

      // Front card remains staged and back remains unset
      expect(find.text('FRONT SIDE'), findsOneWidget);
      expect(find.text('BACK SIDE'), findsNothing);
      expect(find.text('Scan Details (1 Side)'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 16. Lost-data exception does not crash
    // -------------------------------------------------------------------------
    testWidgets('16. Lost-data exception does not crash', (tester) async {
      await PendingCardCaptureStore.savePendingCapture(
        side: CardSide.front,
      );

      final fakePicker = FakeImagePicker()
        ..lostDataResponse = LostDataResponse(
          exception: PlatformException(
            code: 'CAMERA_ERROR',
            message: 'Camera service terminated unexpectedly by OS',
          ),
        );
      final fakeOcr = FakeOcrService();

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(
            imagePicker: fakePicker,
            ocrService: fakeOcr,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error dialog displayed gracefully without crash
      expect(find.text('Image Capture Error'), findsOneWidget);
      expect(find.text('Camera service terminated unexpectedly by OS'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(BusinessCardScanScreen), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 17. No lost data does nothing
    // -------------------------------------------------------------------------
    testWidgets('17. No lost data does nothing', (tester) async {
      final fakePicker = FakeImagePicker()..lostDataResponse = LostDataResponse.empty();
      final fakeOcr = FakeOcrService();

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(
            imagePicker: fakePicker,
            ocrService: fakeOcr,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Stays in normal mode selection without staging or errors
      expect(find.text('Choose Scan Mode'), findsOneWidget);
      expect(find.text('FRONT SIDE'), findsNothing);
    });
  });
}
