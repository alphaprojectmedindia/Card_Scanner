import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/models/user_profile.dart';
import 'package:digital_share/screens/profile/edit_profile_screen.dart';
import 'package:digital_share/screens/profile/profile_screen.dart';
import 'package:digital_share/services/api_client.dart';
import 'package:digital_share/services/pending_card_capture_store.dart';
import 'package:digital_share/services/pending_profile_photo_store.dart';
import 'package:digital_share/services/profile_service.dart';

class FakeImagePicker extends ImagePicker {
  XFile? nextFile;
  ImageSource? lastSource;
  int pickCount = 0;
  int lostDataCount = 0;
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
    pickCount++;
    return nextFile;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    lostDataCount++;
    return lostDataResponse;
  }
}

class TestProfileService extends ProfileService {
  UserProfile profile;
  int uploadCallCount = 0;
  String? lastUploadedFilePath;
  String? lastFilename;
  String? lastContentType;
  Exception? errorToThrow;

  TestProfileService({UserProfile? initialProfile, this.errorToThrow})
      : profile = initialProfile ??
            UserProfile(
              id: 'profile-1',
              userId: 'user-1',
              email: 'john.doe@example.com',
              fullName: 'John Doe',
              shareId: 'test-share-id-1234567890',
              profilePhotoUrl: null,
              createdAtUtc: DateTime.utc(2026, 1, 1),
              updatedAtUtc: DateTime.utc(2026, 1, 1),
            );

  @override
  Future<UserProfile> getMyProfile() async => profile;

  @override
  Future<UserProfile> uploadProfilePhoto({
    String? filePath,
    List<int>? fileBytes,
    String? filename,
    String contentType = 'image/jpeg',
  }) async {
    uploadCallCount++;
    lastUploadedFilePath = filePath;
    lastFilename = filename;
    lastContentType = contentType;

    if (errorToThrow != null) {
      throw errorToThrow!;
    }

    profile = UserProfile(
      id: profile.id,
      userId: profile.userId,
      email: profile.email,
      fullName: profile.fullName,
      shareId: profile.shareId,
      profilePhotoUrl: '/uploads/profile-photos/new_photo_guid_123.jpg',
      createdAtUtc: profile.createdAtUtc,
      updatedAtUtc: DateTime.utc(2026, 10, 20, 12, 0, 0),
    );
    return profile;
  }
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
}

File _createTestImageFile({required String name, int sizeBytes = 1024}) {
  final tempDir = Directory.systemTemp.path;
  final file = File('$tempDir/$name');
  file.writeAsBytesSync(List<int>.filled(sizeBytes, 0xFF));
  return file;
}

void main() {
  setUp(() {
    PendingProfilePhotoStore.resetForTesting();
    PendingCardCaptureStore.resetForTesting();
  });

  tearDown(() {
    PendingProfilePhotoStore.resetForTesting();
    PendingCardCaptureStore.resetForTesting();
  });

  final baseProfile = UserProfile(
    id: 'user-id-1',
    userId: 'user-id-1',
    email: 'john.doe@example.com',
    fullName: 'John Doe',
    jobTitle: 'Software Engineer',
    company: 'Tech Corp',
    shareId: 'shareid123456789012345',
    profilePhotoUrl: null,
    createdAtUtc: DateTime.utc(2026, 1, 1),
    updatedAtUtc: DateTime.utc(2026, 1, 1),
  );

  group('Profile Photo Android Lifecycle & Upload Tests (16 Scenarios)', () {
    // 1. Camera returns image normally -> upload invoked exactly once.
    testWidgets('1. Camera returns image normally -> upload invoked exactly once', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(initialProfile: baseProfile);

      final testImage = _createTestImageFile(name: 'test_camera.jpg');
      addTearDown(() {
        if (testImage.existsSync()) testImage.deleteSync();
      });
      fakePicker.nextFile = XFile(testImage.path);

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Change/Add Photo
      final changePhotoBtn = find.text('Add Photo');
      expect(changePhotoBtn, findsOneWidget);
      await tester.tap(changePhotoBtn);
      await tester.pumpAndSettle();

      // Tap Take Photo
      final takePhotoOption = find.text('Take Photo');
      expect(takePhotoOption, findsOneWidget);
      await tester.tap(takePhotoOption);
      await tester.pumpAndSettle();

      expect(fakePicker.pickCount, 1);
      expect(fakePicker.lastSource, ImageSource.camera);
      expect(testService.uploadCallCount, 1);
      expect(testService.profile.profilePhotoUrl, contains('new_photo_guid_123.jpg'));
      expect(find.text('Profile photo uploaded successfully!'), findsOneWidget);
      expect(await PendingProfilePhotoStore.loadPendingCapture(), isNull);
    });

    // 2. Camera cancelled -> upload not invoked.
    testWidgets('2. Camera cancelled -> upload not invoked', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(initialProfile: baseProfile);
      fakePicker.nextFile = null; // User cancelled camera
      fakePicker.lostDataResponse = LostDataResponse.empty();

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();

      expect(fakePicker.pickCount, 1);
      expect(testService.uploadCallCount, 0);
      expect(await PendingProfilePhotoStore.loadPendingCapture(), isNull);
    });

    // 3. Lost picker data recovered -> upload invoked exactly once.
    testWidgets('3. Lost picker data recovered -> upload invoked exactly once', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(initialProfile: baseProfile);

      final testImage = _createTestImageFile(name: 'test_lost_data.jpg');
      addTearDown(() {
        if (testImage.existsSync()) testImage.deleteSync();
      });

      // pickImage returns null due to Activity recreation, but retrieveLostData has file
      fakePicker.nextFile = null;
      fakePicker.lostDataResponse = LostDataResponse(
        file: XFile(testImage.path),
        type: RetrieveType.image,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();

      expect(fakePicker.pickCount, 1);
      expect(testService.uploadCallCount, 1);
      expect(testService.profile.profilePhotoUrl, contains('new_photo_guid_123.jpg'));
      expect(find.text('Profile photo uploaded successfully!'), findsOneWidget);
      expect(await PendingProfilePhotoStore.loadPendingCapture(), isNull);
    });

    // 4. Pending profile-photo capture survives lifecycle recreation.
    test('4. Pending profile-photo capture survives lifecycle recreation', () async {
      await PendingProfilePhotoStore.savePendingCapture(source: 'camera');

      // Check that loading loads it from disk
      final loaded = await PendingProfilePhotoStore.loadPendingCapture();
      expect(loaded, isNotNull);
      expect(loaded!['action'], 'profile_photo_capture');
      expect(loaded['source'], 'camera');

      // Clear removes it
      await PendingProfilePhotoStore.clear();
      final cleared = await PendingProfilePhotoStore.loadPendingCapture();
      expect(cleared, isNull);
    });

    // 5. Multiple resume callbacks -> no duplicate upload.
    testWidgets('5. Multiple resume callbacks -> no duplicate upload', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(initialProfile: baseProfile);

      final testImage = _createTestImageFile(name: 'test_multi_resume.jpg');
      addTearDown(() {
        if (testImage.existsSync()) testImage.deleteSync();
      });

      fakePicker.lostDataResponse = LostDataResponse(
        file: XFile(testImage.path),
        type: RetrieveType.image,
      );

      // Save pending capture as if external camera had opened
      await PendingProfilePhotoStore.savePendingCapture(source: 'camera');

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger resumed lifecycle state multiple times
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(testService.uploadCallCount, 1);
    });

    // 6. Gallery returns image -> upload invoked exactly once.
    testWidgets('6. Gallery returns image -> upload invoked exactly once', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(initialProfile: baseProfile);

      final testImage = _createTestImageFile(name: 'test_gallery.png');
      addTearDown(() {
        if (testImage.existsSync()) testImage.deleteSync();
      });
      fakePicker.nextFile = XFile(testImage.path);

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose from Gallery'));
      await tester.pumpAndSettle();

      expect(fakePicker.pickCount, 1);
      expect(fakePicker.lastSource, ImageSource.gallery);
      expect(testService.uploadCallCount, 1);
      expect(testService.lastContentType, 'image/png');
    });

    // 7. File missing -> safe failure.
    testWidgets('7. File missing -> safe failure', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(initialProfile: baseProfile);

      fakePicker.nextFile = XFile('/non_existent_directory/missing_image.jpg');

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();

      expect(testService.uploadCallCount, 0);
      expect(find.text('The captured image file could not be found. Please try again.'), findsOneWidget);
      expect(await PendingProfilePhotoStore.loadPendingCapture(), isNull);
    });

    // 8. Zero-byte file -> safe failure.
    testWidgets('8. Zero-byte file -> safe failure', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(initialProfile: baseProfile);

      final emptyFile = _createTestImageFile(name: 'zero_byte.jpg', sizeBytes: 0);
      addTearDown(() {
        if (emptyFile.existsSync()) emptyFile.deleteSync();
      });
      fakePicker.nextFile = XFile(emptyFile.path);

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();

      expect(testService.uploadCallCount, 0);
      expect(find.text('The captured image is empty (0 bytes). Please take another photo.'), findsOneWidget);
      expect(await PendingProfilePhotoStore.loadPendingCapture(), isNull);
    });

    // 9. HTTP 401 -> handled safely.
    testWidgets('9. HTTP 401 -> handled safely', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(
        initialProfile: baseProfile,
        errorToThrow: UnauthorizedException('Invalid credentials or session expired.'),
      );

      final testImage = _createTestImageFile(name: 'test_401.jpg');
      addTearDown(() {
        if (testImage.existsSync()) testImage.deleteSync();
      });
      fakePicker.nextFile = XFile(testImage.path);

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();

      expect(testService.uploadCallCount, 1);
      expect(find.text('Invalid credentials or session expired.'), findsOneWidget);
      expect(await PendingProfilePhotoStore.loadPendingCapture(), isNull);
    });

    // 10. HTTP 413 -> useful size-related failure.
    testWidgets('10. HTTP 413 -> useful size-related failure', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(
        initialProfile: baseProfile,
        errorToThrow: ApiException('The uploaded file is too large. Maximum allowed size is 5 MB.', statusCode: 413),
      );

      final testImage = _createTestImageFile(name: 'test_413.jpg');
      addTearDown(() {
        if (testImage.existsSync()) testImage.deleteSync();
      });
      fakePicker.nextFile = XFile(testImage.path);

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();

      expect(testService.uploadCallCount, 1);
      expect(find.text('The uploaded file is too large. Maximum allowed size is 5 MB.'), findsOneWidget);
    });

    // 11. HTTP 415 -> useful image-format failure.
    testWidgets('11. HTTP 415 -> useful image-format failure', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(
        initialProfile: baseProfile,
        errorToThrow: ApiException('Unsupported file format. Please upload a JPEG, PNG, WebP, or GIF image.', statusCode: 415),
      );

      final testImage = _createTestImageFile(name: 'test_415.jpg');
      addTearDown(() {
        if (testImage.existsSync()) testImage.deleteSync();
      });
      fakePicker.nextFile = XFile(testImage.path);

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();

      expect(testService.uploadCallCount, 1);
      expect(find.text('Unsupported file format. Please upload a JPEG, PNG, WebP, or GIF image.'), findsOneWidget);
    });

    // 12. HTTP 500 -> safe failure.
    testWidgets('12. HTTP 500 -> safe failure', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(
        initialProfile: baseProfile,
        errorToThrow: ApiException('Server error (500). Please try again.', statusCode: 500),
      );

      final testImage = _createTestImageFile(name: 'test_500.jpg');
      addTearDown(() {
        if (testImage.existsSync()) testImage.deleteSync();
      });
      fakePicker.nextFile = XFile(testImage.path);

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();

      expect(testService.uploadCallCount, 1);
      expect(find.text('Server error (500). Please try again.'), findsOneWidget);
      expect(await PendingProfilePhotoStore.loadPendingCapture(), isNull);
    });

    // 13. Upload success -> updated profile/photo state.
    testWidgets('13. Upload success -> updated profile/photo state', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(initialProfile: baseProfile);

      final testImage = _createTestImageFile(name: 'test_success.jpg');
      addTearDown(() {
        if (testImage.existsSync()) testImage.deleteSync();
      });
      fakePicker.nextFile = XFile(testImage.path);

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();

      expect(testService.uploadCallCount, 1);
      expect(testService.profile.profilePhotoUrl, isNotNull);
      // Button label switches from 'Add Photo' to 'Change Photo'
      expect(find.text('Change Photo'), findsOneWidget);
    });

    // 14. Successful upload on ProfileScreen -> new photo remains displayed.
    testWidgets('14. ProfileScreen recovers lost data and updates profile photo', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(initialProfile: baseProfile);

      final testImage = _createTestImageFile(name: 'test_profilescreen_recover.jpg');
      addTearDown(() {
        if (testImage.existsSync()) testImage.deleteSync();
      });

      fakePicker.lostDataResponse = LostDataResponse(
        file: XFile(testImage.path),
        type: RetrieveType.image,
      );

      // Simulate process death having occurred while taking a profile photo
      await PendingProfilePhotoStore.savePendingCapture(source: 'camera');

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            initialProfile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakePicker.lostDataCount, 1);
      expect(testService.uploadCallCount, 1);
      expect(testService.profile.profilePhotoUrl, contains('new_photo_guid_123.jpg'));
      expect(find.text('Profile photo uploaded successfully!'), findsOneWidget);
      expect(await PendingProfilePhotoStore.loadPendingCapture(), isNull);
    });

    // 15. Camera cancellation clears pending state.
    testWidgets('15. Camera cancellation clears pending state', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(initialProfile: baseProfile);

      fakePicker.nextFile = null;
      fakePicker.lostDataResponse = LostDataResponse.empty();

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();

      expect(await PendingProfilePhotoStore.loadPendingCapture(), isNull);
      expect(testService.uploadCallCount, 0);
    });

    // 16. Profile-photo lost-data recovery does not interfere with PendingCardCaptureStore/business-card recovery.
    testWidgets('16. Profile-photo recovery does not interfere with PendingCardCaptureStore', (tester) async {
      _setPhoneViewport(tester);
      final fakePicker = FakeImagePicker();
      final testService = TestProfileService(initialProfile: baseProfile);

      // Business card has pending capture staged
      await PendingCardCaptureStore.savePendingCapture(
        side: CardSide.front,
        frontPath: '/path/to/front.jpg',
      );

      final testImage = _createTestImageFile(name: 'test_isolated_profile.jpg');
      addTearDown(() {
        if (testImage.existsSync()) testImage.deleteSync();
      });
      fakePicker.nextFile = XFile(testImage.path);

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: baseProfile,
            profileService: testService,
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();

      // Profile photo uploaded successfully
      expect(testService.uploadCallCount, 1);

      // PendingCardCaptureStore was NOT touched or cleared by profile photo flow
      final cardPending = await PendingCardCaptureStore.loadPendingCapture();
      expect(cardPending, isNotNull);
      expect(cardPending!['side'], CardSide.front.name);
      expect(cardPending['frontPath'], '/path/to/front.jpg');
    });
  });
}
