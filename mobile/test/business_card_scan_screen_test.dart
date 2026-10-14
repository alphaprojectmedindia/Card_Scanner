import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:digital_share/screens/scan/business_card_review_screen.dart';
import 'package:digital_share/screens/scan/business_card_scan_screen.dart';
import 'package:digital_share/services/business_card_ocr_service.dart';

class FakeImagePicker extends ImagePicker {
  XFile? fileToReturn;
  ImageSource? lastSource;

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
    return fileToReturn;
  }
}

class FakeOcrService implements IBusinessCardOcrService {
  String returnText;

  FakeOcrService({this.returnText = ''});

  @override
  Future<String> recognizeTextFromPath(String imagePath) async {
    return returnText;
  }
}

void main() {
  group('BusinessCardScanScreen Widget Tests', () {
    testWidgets('Renders two clear choices: Digital Share QR and Physical Business Card',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BusinessCardScanScreen(),
        ),
      );

      expect(find.text('Choose Scan Mode'), findsOneWidget);
      expect(find.byKey(const Key('scan_digital_share_qr_button')), findsOneWidget);
      expect(find.byKey(const Key('scan_physical_card_button')), findsOneWidget);
    });

    testWidgets('Tapping Scan Physical Business Card reveals Take Photo and Gallery choices',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BusinessCardScanScreen(),
        ),
      );

      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inline_take_photo_button')), findsOneWidget);
      expect(find.byKey(const Key('inline_choose_gallery_button')), findsOneWidget);
    });

    testWidgets('Handles user cancelling image selection gracefully', (tester) async {
      final fakePicker = FakeImagePicker()..fileToReturn = null;
      final fakeOcr = FakeOcrService();

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(
            imagePicker: fakePicker,
            ocrService: fakeOcr,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inline_take_photo_button')));
      await tester.pumpAndSettle();

      expect(fakePicker.lastSource, ImageSource.camera);
      // Still on scan screen without crash or loading state
      expect(find.byType(BusinessCardScanScreen), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Displays dialog when no text is detected on the business card',
        (tester) async {
      final fakePicker = FakeImagePicker()
        ..fileToReturn = XFile('test/dummy_card.png');
      final fakeOcr = FakeOcrService(returnText: '   ');

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(
            imagePicker: fakePicker,
            ocrService: fakeOcr,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inline_choose_gallery_button')));
      await tester.pumpAndSettle();

      expect(find.text('No Text Detected'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('Navigates to BusinessCardReviewScreen when OCR detects card details',
        (tester) async {
      final fakePicker = FakeImagePicker()
        ..fileToReturn = XFile('test/dummy_card.png');
      final fakeOcr = FakeOcrService(
        returnText: '''
Rahul Kumar
Senior Developer
ABC Technologies
Mobile: +91 98765 43210
Email: rahul@abctech.com
''',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessCardScanScreen(
            imagePicker: fakePicker,
            ocrService: fakeOcr,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('scan_physical_card_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inline_take_photo_button')));
      await tester.pumpAndSettle();

      expect(find.byType(BusinessCardReviewScreen), findsOneWidget);
      expect(find.text('Business Card Details'), findsOneWidget);
      expect(find.text('Rahul Kumar'), findsOneWidget);
    });
  });
}
