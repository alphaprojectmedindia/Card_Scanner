import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:digital_share/config/api_config.dart';
import 'package:digital_share/screens/auth/register_screen.dart';
import 'package:digital_share/services/api_client.dart';
import 'package:digital_share/services/auth_service.dart';
import 'package:digital_share/services/secure_storage_service.dart';

class InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};

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

void main() {
  group('Production Render API Configuration Tests', () {
    test('Default production base URL points to card-scanner-128g onrender.com', () {
      expect(ApiConfig.baseUrl, equals('https://card-scanner-128g.onrender.com'));
    });

    test('Register endpoint points to https://card-scanner-128g.onrender.com/api/auth/register', () {
      expect(
        ApiConfig.registerEndpoint,
        equals('https://card-scanner-128g.onrender.com/api/auth/register'),
      );
    });

    test('Login endpoint points to https://card-scanner-128g.onrender.com/api/auth/login', () {
      expect(
        ApiConfig.loginEndpoint,
        equals('https://card-scanner-128g.onrender.com/api/auth/login'),
      );
    });
  });

  group('AuthService Registration Tests', () {
    late InMemorySecureStorage inMemoryStorage;
    late SecureStorageService secureStorageService;

    setUp(() {
      inMemoryStorage = InMemorySecureStorage();
      secureStorageService = SecureStorageService(storage: inMemoryStorage);
    });

    test('Successful registration serializes request and saves auth tokens', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), equals('https://card-scanner-128g.onrender.com/api/auth/register'));
        expect(request.method, equals('POST'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['email'], equals('test@example.com'));
        expect(body['password'], equals('Password123!'));
        expect(body['confirmPassword'], equals('Password123!'));
        expect(body['phoneNumber'], equals('+15551234567'));

        return http.Response(
          jsonEncode({
            'token': 'mock-access-token-jwt',
            'accessToken': 'mock-access-token-jwt',
            'refreshToken': 'mock-refresh-token-xyz',
            'expirationUtc': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
            'accessTokenExpiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
            'refreshTokenExpiresAt': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
            'userId': 'user-uuid-12345',
            'email': 'test@example.com',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, storageService: secureStorageService);
      final authService = AuthService(apiClient: apiClient, storageService: secureStorageService);

      final authResponse = await authService.register(
        email: 'test@example.com',
        password: 'Password123!',
        confirmPassword: 'Password123!',
        phoneNumber: '+15551234567',
      );

      expect(authResponse.accessToken, equals('mock-access-token-jwt'));
      expect(authResponse.refreshToken, equals('mock-refresh-token-xyz'));
      expect(authResponse.userId, equals('user-uuid-12345'));
      expect(authResponse.email, equals('test@example.com'));

      final storedToken = await secureStorageService.getAuthToken();
      final storedRefreshToken = await secureStorageService.getRefreshToken();
      expect(storedToken, equals('mock-access-token-jwt'));
      expect(storedRefreshToken, equals('mock-refresh-token-xyz'));
    });

    test('Duplicate email returns 409 Conflict with friendly error message', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'A user with this email address already exists.',
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, storageService: secureStorageService);
      final authService = AuthService(apiClient: apiClient, storageService: secureStorageService);

      expect(
        () => authService.register(
          email: 'duplicate@example.com',
          password: 'Password123!',
          confirmPassword: 'Password123!',
        ),
        throwsA(isA<ConflictException>().having(
          (e) => e.message,
          'message',
          contains('already exists'),
        )),
      );
    });

    test('404 proxy error "Application not found" maps to helpful server reachability message', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'error',
            'code': 404,
            'message': 'Application not found',
          }),
          404,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, storageService: secureStorageService);
      final authService = AuthService(apiClient: apiClient, storageService: secureStorageService);

      expect(
        () => authService.register(
          email: 'test@example.com',
          password: 'Password123!',
          confirmPassword: 'Password123!',
        ),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('Unable to reach the Digital Share API server'),
        )),
      );
    });

    test('502/503 cold-start gateway error maps to friendly startup message', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Service Unavailable', 503);
      });

      final apiClient = ApiClient(httpClient: mockClient, storageService: secureStorageService);
      final authService = AuthService(apiClient: apiClient, storageService: secureStorageService);

      expect(
        () => authService.register(
          email: 'test@example.com',
          password: 'Password123!',
          confirmPassword: 'Password123!',
        ),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('temporarily unavailable or starting up'),
        )),
      );
    });
  });

  group('RegisterScreen UI Widget Tests', () {
    testWidgets('Renders all required fields including mandatory mobile number and register button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RegisterScreen(),
        ),
      );

      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
      expect(find.text('Mobile Number *'), findsOneWidget);
      expect(find.text('Register Account'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });
  });
}

