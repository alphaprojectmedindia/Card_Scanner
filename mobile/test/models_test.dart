import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/auth_response.dart';
import 'package:digital_share/models/saved_connection.dart';
import 'package:digital_share/models/shared_profile.dart';
import 'package:digital_share/models/user_profile.dart';
import 'package:digital_share/models/update_profile_request.dart';

void main() {
  group('AuthResponse Serialization Tests', () {
    test('fromJson parses backend JSON contract accurately', () {
      final json = {
        'token': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
        'expirationUtc': '2026-10-08T15:00:00Z',
        'userId': 'user-123-uuid',
        'email': 'developer@digitalshare.com',
      };

      final auth = AuthResponse.fromJson(json);

      expect(auth.token, 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...');
      expect(auth.userId, 'user-123-uuid');
      expect(auth.email, 'developer@digitalshare.com');
      expect(auth.expirationUtc.isUtc, true);
    });

    test('toJson produces expected structure', () {
      final auth = AuthResponse(
        token: 'token123',
        expirationUtc: DateTime.utc(2026, 10, 8, 12, 0, 0),
        userId: 'uid-456',
        email: 'user@example.com',
      );

      final json = auth.toJson();
      expect(json['token'], 'token123');
      expect(json['userId'], 'uid-456');
      expect(json['email'], 'user@example.com');
      expect(json['expirationUtc'], '2026-10-08T12:00:00.000Z');
    });
  });

  group('UserProfile Serialization Tests', () {
    test('fromJson parses complete backend profile response including shareId', () {
      final json = {
        'id': 'profile-guid-001',
        'userId': 'user-guid-001',
        'shareId': 'x7F9K2mQ8pL4vYkVl6VUbG7T',
        'fullName': 'Jane Doe',
        'phoneNumber': '+1-555-0144',
        'email': 'jane.doe@example.com',
        'jobTitle': 'Principal Architect',
        'company': 'Digital Share Corp',
        'website': 'https://janedoe.dev',
        'address': '789 Tech Boulevard, Austin, TX',
        'bio': 'Passionate about mobile security and distributed systems.',
        'profilePhotoUrl': 'https://janedoe.dev/photo.jpg',
        'createdAtUtc': '2026-10-08T10:00:00Z',
        'updatedAtUtc': '2026-10-08T11:00:00Z',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'profile-guid-001');
      expect(profile.userId, 'user-guid-001');
      expect(profile.shareId, 'x7F9K2mQ8pL4vYkVl6VUbG7T');
      expect(profile.fullName, 'Jane Doe');
      expect(profile.displayName, 'Jane Doe');
      expect(profile.phoneNumber, '+1-555-0144');
      expect(profile.email, 'jane.doe@example.com');
      expect(profile.jobTitle, 'Principal Architect');
      expect(profile.company, 'Digital Share Corp');
      expect(profile.website, 'https://janedoe.dev');
      expect(profile.address, '789 Tech Boulevard, Austin, TX');
      expect(profile.bio, 'Passionate about mobile security and distributed systems.');
      expect(profile.profilePhotoUrl, 'https://janedoe.dev/photo.jpg');
    });

    test('displayName falls back to email prefix if fullName is null or empty', () {
      final profile = UserProfile(
        id: '1',
        userId: 'u1',
        shareId: 'share-1234567890123456',
        fullName: null,
        email: 'alex.smith@company.com',
        createdAtUtc: DateTime.now().toUtc(),
        updatedAtUtc: DateTime.now().toUtc(),
      );

      expect(profile.displayName, 'alex.smith');
    });
  });

  group('SharedProfile Serialization Tests', () {
    test('fromJson parses public shared profile response accurately', () {
      final json = {
        'shareId': 'x7F9K2mQ8pL4vYkVl6VUbG7T',
        'fullName': 'Person Alpha',
        'phoneNumber': '+1-555-9999',
        'email': 'alpha@example.com',
        'jobTitle': 'Lead Designer',
        'company': 'Creative Studio',
        'website': 'https://creativestudio.com',
        'address': 'New York, NY',
        'bio': 'Designing modern digital experiences.',
        'profilePhotoUrl': 'https://creativestudio.com/alpha.png',
      };

      final shared = SharedProfile.fromJson(json);

      expect(shared.shareId, 'x7F9K2mQ8pL4vYkVl6VUbG7T');
      expect(shared.fullName, 'Person Alpha');
      expect(shared.displayName, 'Person Alpha');
      expect(shared.phoneNumber, '+1-555-9999');
      expect(shared.email, 'alpha@example.com');
      expect(shared.jobTitle, 'Lead Designer');
      expect(shared.company, 'Creative Studio');
      expect(shared.website, 'https://creativestudio.com');
      expect(shared.address, 'New York, NY');
      expect(shared.bio, 'Designing modern digital experiences.');
      expect(shared.profilePhotoUrl, 'https://creativestudio.com/alpha.png');
    });

    test('toJson produces expected structure', () {
      final shared = SharedProfile(
        shareId: 's-1234567890123456',
        email: 'shared@example.com',
        fullName: 'Test User',
      );

      final json = shared.toJson();
      expect(json['shareId'], 's-1234567890123456');
      expect(json['email'], 'shared@example.com');
      expect(json['fullName'], 'Test User');
      expect(json['phoneNumber'], isNull);
    });
  });

  group('SavedConnection Serialization Tests', () {
    test('fromJson and toJson parse connection contract correctly', () {
      final json = {
        'shareId': 'conn-share-id-123',
        'fullName': 'Bob Connection',
        'phoneNumber': '+1-234-567-8900',
        'email': 'bob@connection.com',
        'jobTitle': 'CTO',
        'company': 'Connect Corp',
        'website': 'https://connectcorp.com',
        'address': 'Seattle, WA',
        'bio': 'Connecting people.',
        'profilePhotoUrl': 'https://connectcorp.com/bob.jpg',
        'savedAtUtc': '2026-10-08T12:30:00.000Z',
      };

      final connection = SavedConnection.fromJson(json);

      expect(connection.shareId, 'conn-share-id-123');
      expect(connection.fullName, 'Bob Connection');
      expect(connection.displayName, 'Bob Connection');
      expect(connection.phoneNumber, '+1-234-567-8900');
      expect(connection.email, 'bob@connection.com');
      expect(connection.jobTitle, 'CTO');
      expect(connection.company, 'Connect Corp');
      expect(connection.website, 'https://connectcorp.com');
      expect(connection.address, 'Seattle, WA');
      expect(connection.bio, 'Connecting people.');
      expect(connection.profilePhotoUrl, 'https://connectcorp.com/bob.jpg');
      expect(connection.savedAtUtc, DateTime.utc(2026, 10, 8, 12, 30, 0));

      final sharedProfile = connection.toSharedProfile();
      expect(sharedProfile.shareId, 'conn-share-id-123');
      expect(sharedProfile.fullName, 'Bob Connection');
      expect(sharedProfile.email, 'bob@connection.com');
    });
  });

  group('UpdateProfileRequest Tests', () {
    test('toJson trims strings and sends null for empty optional fields', () {
      final request = UpdateProfileRequest(
        fullName: '  Bob Smith  ',
        phoneNumber: '',
        email: 'bob@example.com',
        jobTitle: '  Engineer  ',
        company: '  ',
        website: 'https://bob.com',
      );

      final json = request.toJson();
      expect(json['fullName'], 'Bob Smith');
      expect(json['phoneNumber'], isNull);
      expect(json['email'], 'bob@example.com');
      expect(json['jobTitle'], 'Engineer');
      expect(json['company'], isNull);
      expect(json['website'], 'https://bob.com');
    });
  });
}
