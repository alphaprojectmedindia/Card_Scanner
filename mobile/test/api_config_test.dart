import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/config/api_config.dart';

void main() {
  group('ApiConfig Tests', () {
    test('Constructs accurate endpoint URLs relative to base URL', () {
      expect(ApiConfig.baseUrl, isNotEmpty);
      expect(ApiConfig.registerEndpoint, '${ApiConfig.baseUrl}/api/auth/register');
      expect(ApiConfig.loginEndpoint, '${ApiConfig.baseUrl}/api/auth/login');
      expect(ApiConfig.profileMeEndpoint, '${ApiConfig.baseUrl}/api/profile/me');
      expect(ApiConfig.uploadProfilePhotoEndpoint, '${ApiConfig.baseUrl}/api/profile/photo');
      expect(ApiConfig.getShareEndpoint('abc1234567890123'), '${ApiConfig.baseUrl}/api/share/abc1234567890123');
    });

    test('resolveImageUrl correctly resolves relative paths against base URL and preserves absolute URLs', () {
      expect(
        ApiConfig.resolveImageUrl('/uploads/profile-photos/test.jpg'),
        '${ApiConfig.baseUrl}/uploads/profile-photos/test.jpg',
      );
      expect(
        ApiConfig.resolveImageUrl('uploads/profile-photos/test.jpg'),
        '${ApiConfig.baseUrl}/uploads/profile-photos/test.jpg',
      );
      expect(
        ApiConfig.resolveImageUrl('https://cdn.example.com/avatar.png'),
        'https://cdn.example.com/avatar.png',
      );
      expect(
        ApiConfig.resolveImageUrl('http://192.168.1.15:5000/uploads/profile-photos/test.jpg'),
        'http://192.168.1.15:5000/uploads/profile-photos/test.jpg',
      );
      expect(ApiConfig.resolveImageUrl(null), isNull);
      expect(ApiConfig.resolveImageUrl(''), isNull);
      expect(ApiConfig.resolveImageUrl('   '), isNull);
    });

    test('buildShareUrl generates canonical Digital Share QR payload format', () {
      const shareId = 'x7F9K2mQ8pL4vYkVl6VUbG7T';
      final url = ApiConfig.buildShareUrl(shareId);
      expect(url, 'https://digitalshare.app/s/x7F9K2mQ8pL4vYkVl6VUbG7T');
    });

    test('extractShareId accurately extracts ShareId from valid Digital Share URLs', () {
      expect(
        ApiConfig.extractShareId('https://digitalshare.app/s/x7F9K2mQ8pL4vYkVl6VUbG7T'),
        'x7F9K2mQ8pL4vYkVl6VUbG7T',
      );
      expect(
        ApiConfig.extractShareId('http://digitalshare.app/s/x7F9K2mQ8pL4vYkVl6VUbG7T/'),
        'x7F9K2mQ8pL4vYkVl6VUbG7T',
      );
      expect(
        ApiConfig.extractShareId('digitalshare.app/s/x7F9K2mQ8pL4vYkVl6VUbG7T?src=qr'),
        'x7F9K2mQ8pL4vYkVl6VUbG7T',
      );
      expect(
        ApiConfig.extractShareId('x7F9K2mQ8pL4vYkVl6VUbG7T'),
        'x7F9K2mQ8pL4vYkVl6VUbG7T',
      );
    });

    test('extractShareId rejects malicious external URLs and invalid strings', () {
      expect(ApiConfig.extractShareId('https://malicious-site.example/login'), isNull);
      expect(ApiConfig.extractShareId('https://google.com'), isNull);
      expect(ApiConfig.extractShareId('random text that is not a share id'), isNull);
      expect(ApiConfig.extractShareId(''), isNull);
      expect(ApiConfig.extractShareId(null), isNull);
      expect(ApiConfig.extractShareId('short'), isNull); // Too short (<16 chars)
      expect(ApiConfig.extractShareId('https://digitalshare.app/s/invalid!char@'), isNull);
    });
  });
}
