import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:digital_share/config/api_config.dart';
import 'package:digital_share/models/user_profile.dart';
import 'package:digital_share/screens/auth/login_screen.dart';
import 'package:digital_share/screens/home/home_screen.dart';
import 'package:digital_share/screens/splash_screen.dart';
import 'package:digital_share/services/api_client.dart';
import 'package:digital_share/services/auth_service.dart';
import 'package:digital_share/services/profile_service.dart';
import 'package:digital_share/services/secure_storage_service.dart';

class InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};
  bool shouldThrowOnWrite = false;

  InMemorySecureStorage([Map<String, String>? initialData]) {
    if (initialData != null) {
      _data.addAll(initialData);
    }
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrowOnWrite) {
      throw Exception('Secure storage hardware failure');
    }
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map.from(_data);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.clear();
  }
}

class FakeHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) handler;

  FakeHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

class StubProfileService extends ProfileService {
  final Future<UserProfile> Function()? onGetMyProfile;

  StubProfileService({this.onGetMyProfile});

  @override
  Future<UserProfile> getMyProfile() async {
    if (onGetMyProfile != null) {
      return await onGetMyProfile!();
    }
    return UserProfile(
      id: 'prof_123',
      userId: 'usr_123',
      email: 'test@example.com',
      fullName: 'Alice Tester',
      shareId: 'x7F9K2mQ8pL4vYkVl6VUbG7T',
      createdAtUtc: DateTime.now(),
      updatedAtUtc: DateTime.now(),
    );
  }
}

void main() {
  group('Access Token + Rotating Refresh Token & Session Reliability Tests', () {
    // 1. Login stores access token securely
    test('1. Login stores access token securely', () async {
      final inMemoryStorage = InMemorySecureStorage();
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      final fakeClient = FakeHttpClient((req) async {
        return http.Response(
          jsonEncode({
            'accessToken': 'jwt.access.token.123',
            'refreshToken': 'crypted_refresh_token_456',
            'accessTokenExpiresAt': DateTime.now().add(const Duration(minutes: 60)).toIso8601String(),
            'refreshTokenExpiresAt': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
            'userId': 'usr_123',
            'email': 'test@example.com',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final authService = AuthService(
        apiClient: ApiClient(httpClient: fakeClient, storageService: secureStorage),
        storageService: secureStorage,
      );

      final response = await authService.login(
        email: 'test@example.com',
        password: 'Password123!',
      );

      expect(response.accessToken, equals('jwt.access.token.123'));
      expect(await secureStorage.getAuthToken(), equals('jwt.access.token.123'));
      expect(await secureStorage.hasToken(), isTrue);
    });

    // 2. Login stores refresh token securely
    test('2. Login stores refresh token securely', () async {
      final inMemoryStorage = InMemorySecureStorage();
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      final fakeClient = FakeHttpClient((req) async {
        return http.Response(
          jsonEncode({
            'accessToken': 'jwt.access.token.123',
            'refreshToken': 'crypted_refresh_token_456',
            'accessTokenExpiresAt': DateTime.now().add(const Duration(minutes: 60)).toIso8601String(),
            'refreshTokenExpiresAt': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
            'userId': 'usr_123',
            'email': 'test@example.com',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final authService = AuthService(
        apiClient: ApiClient(httpClient: fakeClient, storageService: secureStorage),
        storageService: secureStorage,
      );

      final response = await authService.login(
        email: 'test@example.com',
        password: 'Password123!',
      );

      expect(response.refreshToken, equals('crypted_refresh_token_456'));
      expect(await secureStorage.getRefreshToken(), equals('crypted_refresh_token_456'));
      expect(await secureStorage.hasRefreshToken(), isTrue);
      expect(await secureStorage.getAccessTokenExpiry(), isNotNull);
      expect(await secureStorage.getRefreshTokenExpiry(), isNotNull);
    });

    // 3. App restart restores token pair
    test('3. App restart restores token pair', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'restored.access.token',
        'jwt_refresh_token': 'restored.refresh.token',
        'auth_user_id': 'usr_restored',
        'auth_user_email': 'restored@example.com',
      });

      // Simulate app restart / fresh service instances
      final freshStorage = SecureStorageService(storage: inMemoryStorage);
      final freshAuthService = AuthService(storageService: freshStorage);

      expect(await freshAuthService.hasStoredToken(), isTrue);
      expect(await freshStorage.getAuthToken(), equals('restored.access.token'));
      expect(await freshStorage.getRefreshToken(), equals('restored.refresh.token'));
      expect(await freshStorage.getUserId(), equals('usr_restored'));
      expect(await freshStorage.getUserEmail(), equals('restored@example.com'));
    });

    // 4. Valid access token does not unnecessarily refresh
    test('4. Valid access token does not unnecessarily refresh', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'valid.active.token',
        'jwt_refresh_token': 'valid.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      int refreshCalls = 0;
      final fakeClient = FakeHttpClient((req) async {
        if (req.url.path.contains('/api/auth/refresh')) {
          refreshCalls++;
          return http.Response('{}', 200);
        }
        return http.Response('{"status":"ok"}', 200, headers: {'content-type': 'application/json'});
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);
      final result = await apiClient.get('https://example.com/api/profile/me');

      expect(result['status'], equals('ok'));
      expect(refreshCalls, equals(0)); // No refresh triggered!
    });

    // 5. 401 triggers refresh
    test('5. 401 triggers refresh', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'expired.access.token',
        'jwt_refresh_token': 'valid.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      int refreshCalls = 0;
      final fakeClient = FakeHttpClient((req) async {
        if (req.url.path.contains('/api/auth/refresh')) {
          refreshCalls++;
          return http.Response(
            jsonEncode({
              'accessToken': 'new.rotated.access.token',
              'refreshToken': 'new.rotated.refresh.token',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        // Check Authorization header
        final authHeader = req.headers['Authorization'] ?? req.headers['authorization'];
        if (authHeader == 'Bearer expired.access.token') {
          return http.Response('{"message":"Token expired"}', 401, headers: {'content-type': 'application/json'});
        }

        return http.Response('{"data":"profile_data"}', 200, headers: {'content-type': 'application/json'});
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);
      final res = await apiClient.get('https://example.com/api/profile/me');

      expect(refreshCalls, equals(1));
      expect(res['data'], equals('profile_data'));
    });

    // 6. Successful refresh replaces both tokens
    test('6. Successful refresh replaces both tokens', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'old.access.token',
        'jwt_refresh_token': 'old.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      final fakeClient = FakeHttpClient((req) async {
        if (req.url.path.contains('/api/auth/refresh')) {
          return http.Response(
            jsonEncode({
              'accessToken': 'brand.new.access.token',
              'refreshToken': 'brand.new.refresh.token',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.headers['authorization'] == 'Bearer old.access.token' ||
            req.headers['Authorization'] == 'Bearer old.access.token') {
          return http.Response('{"error":"unauthorized"}', 401, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"success":true}', 200, headers: {'content-type': 'application/json'});
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);
      await apiClient.get('https://example.com/api/connections');

      expect(await secureStorage.getAuthToken(), equals('brand.new.access.token'));
      expect(await secureStorage.getRefreshToken(), equals('brand.new.refresh.token'));
    });

    // 7. Original request retries once
    test('7. Original request retries once', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'old.access',
        'jwt_refresh_token': 'active.refresh',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      int resourceAttempts = 0;
      final fakeClient = FakeHttpClient((req) async {
        if (req.url.path.contains('/api/auth/refresh')) {
          return http.Response(
            jsonEncode({
              'accessToken': 'new.access',
              'refreshToken': 'new.refresh',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (req.url.path.contains('/api/resource')) {
          resourceAttempts++;
          if (resourceAttempts == 1) {
            return http.Response('Unauthorized', 401);
          }
          return http.Response('{"retried":true}', 200, headers: {'content-type': 'application/json'});
        }

        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);
      final res = await apiClient.get('https://example.com/api/resource');

      expect(resourceAttempts, equals(2)); // initial attempt + retry
      expect(res['retried'], isTrue);
    });

    // 8. Three simultaneous 401s produce ONE refresh request
    test('8. Three simultaneous 401s produce ONE refresh request', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'expired.access',
        'jwt_refresh_token': 'active.refresh',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      int refreshRequestCount = 0;
      final fakeClient = FakeHttpClient((req) async {
        if (req.url.path.contains('/api/auth/refresh')) {
          refreshRequestCount++;
          // Simulate slight network delay
          await Future.delayed(const Duration(milliseconds: 50));
          return http.Response(
            jsonEncode({
              'accessToken': 'fresh.access.token',
              'refreshToken': 'fresh.refresh.token',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        final authHeader = req.headers['authorization'] ?? req.headers['Authorization'];
        if (authHeader == 'Bearer expired.access') {
          return http.Response('Unauthorized', 401);
        }

        return http.Response('{"endpoint":"${req.url.path}"}', 200, headers: {'content-type': 'application/json'});
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);

      // Fire 3 simultaneous API calls
      final future1 = apiClient.get('https://example.com/api/profile/me');
      final future2 = apiClient.get('https://example.com/api/connections');
      final future3 = apiClient.get('https://example.com/api/meetings');

      final results = await Future.wait([future1, future2, future3]);

      // Exactly ONE refresh request made across the 3 concurrent 401s!
      expect(refreshRequestCount, equals(1));
      expect(results[0]['endpoint'], equals('/api/profile/me'));
      expect(results[1]['endpoint'], equals('/api/connections'));
      expect(results[2]['endpoint'], equals('/api/meetings'));
    });

    // 9. Failed refresh because invalid token logs user out
    test('9. Failed refresh because invalid token logs user out', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'expired.access',
        'jwt_refresh_token': 'invalid.tampered.refresh',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      final fakeClient = FakeHttpClient((req) async {
        if (req.url.path.contains('/api/auth/refresh')) {
          return http.Response(
            '{"message":"Invalid refresh token"}',
            400,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Unauthorized', 401);
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);

      await expectLater(
        apiClient.get('https://example.com/api/profile/me'),
        throwsA(isA<UnauthorizedException>()),
      );

      // Confirm credentials cleared from secure storage
      expect(await secureStorage.hasToken(), isFalse);
      expect(await secureStorage.getAuthToken(), isNull);
      expect(await secureStorage.getRefreshToken(), isNull);
    });

    // 10. Expired refresh token logs user out
    test('10. Expired refresh token logs user out', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'expired.access',
        'jwt_refresh_token': 'expired.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      final fakeClient = FakeHttpClient((req) async {
        if (req.url.path.contains('/api/auth/refresh')) {
          return http.Response(
            '{"message":"Refresh token has expired"}',
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Unauthorized', 401);
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);

      await expectLater(
        apiClient.get('https://example.com/api/profile/me'),
        throwsA(isA<UnauthorizedException>()),
      );

      // Confirm credentials cleared
      expect(await secureStorage.hasToken(), isFalse);
      expect(await secureStorage.getRefreshToken(), isNull);
    });

    // 11. Timeout does NOT clear tokens
    test('11. Timeout does NOT clear tokens', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'persisted.access.token',
        'jwt_refresh_token': 'persisted.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      final fakeClient = FakeHttpClient((req) async {
        throw TimeoutException('Request timed out');
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);

      await expectLater(
        apiClient.get('https://example.com/api/test'),
        throwsA(isA<ApiException>()),
      );

      // Tokens MUST still be intact!
      expect(await secureStorage.hasToken(), isTrue);
      expect(await secureStorage.getAuthToken(), equals('persisted.access.token'));
      expect(await secureStorage.getRefreshToken(), equals('persisted.refresh.token'));
    });

    // 12. SocketException does NOT clear tokens
    test('12. SocketException does NOT clear tokens', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'persisted.access.token',
        'jwt_refresh_token': 'persisted.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      final fakeClient = FakeHttpClient((req) async {
        throw const SocketException('Network unreachable');
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);

      await expectLater(
        apiClient.get('https://example.com/api/test'),
        throwsA(isA<ApiException>()),
      );

      // Tokens MUST still be intact!
      expect(await secureStorage.hasToken(), isTrue);
      expect(await secureStorage.getAuthToken(), equals('persisted.access.token'));
      expect(await secureStorage.getRefreshToken(), equals('persisted.refresh.token'));
    });

    // 13. HTTP 500 does NOT clear tokens
    test('13. HTTP 500 does NOT clear tokens', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'persisted.access.token',
        'jwt_refresh_token': 'persisted.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      final fakeClient = FakeHttpClient((req) async {
        return http.Response('Internal Server Error', 500);
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);

      await expectLater(
        apiClient.get('https://example.com/api/test'),
        throwsA(isA<ApiException>()),
      );

      expect(await secureStorage.hasToken(), isTrue);
      expect(await secureStorage.getAuthToken(), equals('persisted.access.token'));
      expect(await secureStorage.getRefreshToken(), equals('persisted.refresh.token'));
    });

    // 14. HTTP 502 does NOT clear tokens
    test('14. HTTP 502 does NOT clear tokens', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'persisted.access.token',
        'jwt_refresh_token': 'persisted.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      final fakeClient = FakeHttpClient((req) async {
        return http.Response('Bad Gateway', 502);
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);

      await expectLater(
        apiClient.get('https://example.com/api/test'),
        throwsA(isA<ApiException>()),
      );

      expect(await secureStorage.hasToken(), isTrue);
      expect(await secureStorage.getAuthToken(), equals('persisted.access.token'));
      expect(await secureStorage.getRefreshToken(), equals('persisted.refresh.token'));
    });

    // 15. HTTP 503 does NOT clear tokens
    test('15. HTTP 503 does NOT clear tokens', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'persisted.access.token',
        'jwt_refresh_token': 'persisted.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      final fakeClient = FakeHttpClient((req) async {
        return http.Response('Service Unavailable', 503);
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);

      await expectLater(
        apiClient.get('https://example.com/api/test'),
        throwsA(isA<ApiException>()),
      );

      expect(await secureStorage.hasToken(), isTrue);
      expect(await secureStorage.getAuthToken(), equals('persisted.access.token'));
      expect(await secureStorage.getRefreshToken(), equals('persisted.refresh.token'));
    });

    // 16. Offline startup preserves credentials
    testWidgets('16. Offline startup preserves credentials and navigates to HomeScreen', (tester) async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'offline.access.token',
        'jwt_refresh_token': 'offline.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);
      final authService = AuthService(storageService: secureStorage);
      final profileService = StubProfileService(
        onGetMyProfile: () async {
          throw const SocketException('No internet');
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            authService: authService,
            profileService: profileService,
            initialDelay: Duration.zero,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(await secureStorage.hasToken(), isTrue);
      expect(await secureStorage.getAuthToken(), equals('offline.access.token'));
      expect(await secureStorage.getRefreshToken(), equals('offline.refresh.token'));
    });

    // 17. Refresh endpoint 401 does not recursively trigger refresh
    test('17. Refresh endpoint 401 does not recursively trigger refresh', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'some.access.token',
        'jwt_refresh_token': 'bad.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      int refreshCalls = 0;
      final fakeClient = FakeHttpClient((req) async {
        if (req.url.path.contains('/api/auth/refresh')) {
          refreshCalls++;
          return http.Response('{"message":"Invalid refresh token"}', 401);
        }
        return http.Response('ok', 200);
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);

      // Call refresh directly
      final success = await apiClient.post(
        ApiConfig.refreshEndpoint,
        body: {'refreshToken': 'bad.refresh.token'},
        requiresAuth: false,
      ).then((_) => true).catchError((_) => false);

      expect(success, isFalse);
      expect(refreshCalls, equals(1)); // Only called once, didn't loop!
    });

    // 18. Retried request receiving another 401 does not loop
    test('18. Retried request receiving another 401 does not loop', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'stale.access.token',
        'jwt_refresh_token': 'valid.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      int resourceCalls = 0;
      int refreshCalls = 0;

      final fakeClient = FakeHttpClient((req) async {
        if (req.url.path.contains('/api/auth/refresh')) {
          refreshCalls++;
          return http.Response(
            jsonEncode({
              'accessToken': 'new.access.token',
              'refreshToken': 'new.refresh.token',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (req.url.path.contains('/api/profile/me')) {
          resourceCalls++;
          // Always return 401, even on retry
          return http.Response('{"message":"Still unauthorized"}', 401, headers: {'content-type': 'application/json'});
        }

        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);

      await expectLater(
        apiClient.get('https://example.com/api/profile/me'),
        throwsA(isA<UnauthorizedException>()),
      );

      // Exactly 1 refresh call and 2 resource calls (original + single retry), NO INFINITE LOOP
      expect(refreshCalls, equals(1));
      expect(resourceCalls, equals(2));
    });

    // 19. Explicit logout clears both local tokens
    test('19. Explicit logout clears both local tokens', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'active.access.token',
        'jwt_refresh_token': 'active.refresh.token',
        'auth_user_id': 'usr_999',
        'auth_user_email': 'alice@digitalshare.app',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      bool serverLogoutCalled = false;
      final fakeClient = FakeHttpClient((req) async {
        if (req.url.path.contains('/api/auth/logout')) {
          serverLogoutCalled = true;
          return http.Response('{"message":"Logged out"}', 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('ok', 200);
      });

      final authService = AuthService(
        apiClient: ApiClient(httpClient: fakeClient, storageService: secureStorage),
        storageService: secureStorage,
      );

      await authService.logout();

      expect(serverLogoutCalled, isTrue);
      expect(await secureStorage.hasToken(), isFalse);
      expect(await secureStorage.hasRefreshToken(), isFalse);
      expect(await secureStorage.getAuthToken(), isNull);
      expect(await secureStorage.getRefreshToken(), isNull);
      expect(await secureStorage.getUserId(), isNull);
      expect(await secureStorage.getUserEmail(), isNull);
    });

    // 20. Secure-storage replacement failure handled safely
    test('20. Secure-storage replacement failure handled safely', () async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'old.access.token',
        'jwt_refresh_token': 'old.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      final fakeClient = FakeHttpClient((req) async {
        if (req.url.path.contains('/api/auth/refresh')) {
          return http.Response(
            jsonEncode({
              'accessToken': 'new.access.token',
              'refreshToken': 'new.refresh.token',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Unauthorized', 401);
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);

      // Force storage write to throw an exception
      inMemoryStorage.shouldThrowOnWrite = true;

      // ApiClient should gracefully catch the write failure and throw UnauthorizedException
      await expectLater(
        apiClient.get('https://example.com/api/test'),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    // 21. Splash with expired access + valid refresh restores session
    testWidgets('21. Splash with expired access + valid refresh restores session', (tester) async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'expired.access.token',
        'jwt_refresh_token': 'valid.refresh.token',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      int refreshCalls = 0;
      final fakeClient = FakeHttpClient((req) async {
        if (req.url.path.contains('/api/auth/refresh')) {
          refreshCalls++;
          return http.Response(
            jsonEncode({
              'accessToken': 'refreshed.access.token',
              'refreshToken': 'refreshed.refresh.token',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        final authHeader = req.headers['authorization'] ?? req.headers['Authorization'];
        if (authHeader == 'Bearer expired.access.token') {
          return http.Response('Unauthorized', 401);
        }

        if (req.url.path.contains('/api/profile/me')) {
          return http.Response(
            jsonEncode({
              'id': 'prof_123',
              'userId': 'usr_123',
              'email': 'test@example.com',
              'fullName': 'Alice Restored',
              'shareId': 'x7F9K2mQ8pL4vYkVl6VUbG7T',
              'createdAtUtc': DateTime.now().toIso8601String(),
              'updatedAtUtc': DateTime.now().toIso8601String(),
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);
      final authService = AuthService(apiClient: apiClient, storageService: secureStorage);
      final profileService = ProfileService(apiClient: apiClient, storageService: secureStorage);

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            authService: authService,
            profileService: profileService,
            initialDelay: Duration.zero,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(refreshCalls, equals(1));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Alice Restored'), findsOneWidget);
      expect(await secureStorage.getAuthToken(), equals('refreshed.access.token'));
      expect(await secureStorage.getRefreshToken(), equals('refreshed.refresh.token'));
    });

    // 22. Splash with invalid refresh navigates to Login
    testWidgets('22. Splash with invalid refresh navigates to Login', (tester) async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'expired.access.token',
        'jwt_refresh_token': 'invalid.or.revoked.refresh',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);

      final fakeClient = FakeHttpClient((req) async {
        if (req.url.path.contains('/api/auth/refresh')) {
          return http.Response('{"message":"Invalid refresh token"}', 401);
        }
        return http.Response('Unauthorized', 401);
      });

      final apiClient = ApiClient(httpClient: fakeClient, storageService: secureStorage);
      final authService = AuthService(apiClient: apiClient, storageService: secureStorage);
      final profileService = ProfileService(apiClient: apiClient, storageService: secureStorage);

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            authService: authService,
            profileService: profileService,
            initialDelay: Duration.zero,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(await secureStorage.hasToken(), isFalse);
    });

    // 23. Existing auth reliability tests continue passing (pause/resume & offline recovery)
    testWidgets('23. Pause / resume preserves stored session', (tester) async {
      final inMemoryStorage = InMemorySecureStorage({
        'jwt_auth_token': 'valid.sample.jwt',
        'jwt_refresh_token': 'valid.sample.refresh',
      });
      final secureStorage = SecureStorageService(storage: inMemoryStorage);
      final authService = AuthService(storageService: secureStorage);

      expect(await authService.hasStoredToken(), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(await authService.hasStoredToken(), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(await authService.hasStoredToken(), isTrue);
      expect(await secureStorage.getAuthToken(), equals('valid.sample.jwt'));
      expect(await secureStorage.getRefreshToken(), equals('valid.sample.refresh'));
    });
  });
}
