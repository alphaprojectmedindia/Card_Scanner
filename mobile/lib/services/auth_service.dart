import '../config/api_config.dart';
import '../models/auth_response.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

class AuthService {
  final ApiClient _apiClient;
  final SecureStorageService _storageService;

  AuthService({
    ApiClient? apiClient,
    SecureStorageService? storageService,
  })  : _storageService = storageService ?? SecureStorageService(),
        _apiClient = apiClient ?? ApiClient(storageService: storageService);

  Future<AuthResponse> register({
    required String email,
    required String password,
    required String confirmPassword,
    String? phoneNumber,
  }) async {
    final body = <String, dynamic>{
      'email': email.trim(),
      'password': password,
      'confirmPassword': confirmPassword,
    };
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      body['phoneNumber'] = phoneNumber.trim();
    }

    final response = await _apiClient.post(
      ApiConfig.registerEndpoint,
      body: body,
      requiresAuth: false,
    );

    final authResponse =
        AuthResponse.fromJson(response as Map<String, dynamic>);
    if (authResponse.refreshToken.isNotEmpty) {
      await _storageService.saveAuthTokens(
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
        accessTokenExpiresAt: authResponse.accessTokenExpiresAt,
        refreshTokenExpiresAt: authResponse.refreshTokenExpiresAt,
      );
    } else {
      await _storageService.saveAuthToken(authResponse.token);
    }

    await _storageService.saveUserInfo(
      userId: authResponse.userId,
      email: authResponse.email,
    );

    return authResponse;
  }

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      ApiConfig.loginEndpoint,
      body: {
        'email': email.trim(),
        'password': password,
      },
      requiresAuth: false,
    );

    final authResponse =
        AuthResponse.fromJson(response as Map<String, dynamic>);
    if (authResponse.refreshToken.isNotEmpty) {
      await _storageService.saveAuthTokens(
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
        accessTokenExpiresAt: authResponse.accessTokenExpiresAt,
        refreshTokenExpiresAt: authResponse.refreshTokenExpiresAt,
      );
    } else {
      await _storageService.saveAuthToken(authResponse.token);
    }

    await _storageService.saveUserInfo(
      userId: authResponse.userId,
      email: authResponse.email,
    );

    return authResponse;
  }

  Future<void> logout() async {
    try {
      final refreshToken = await _storageService.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _apiClient.post(
          ApiConfig.logoutEndpoint,
          body: {'refreshToken': refreshToken},
          requiresAuth: false,
        );
      }
    } catch (_) {
      // Local logout MUST still succeed if phone is offline or server unreachable
    } finally {
      await _storageService.clearAuth();
    }
  }

  Future<bool> hasStoredToken() async {
    return await _storageService.hasToken();
  }

  Future<bool> refreshToken() async {
    return await _apiClient.refreshTokens();
  }

  /// Permanently deletes the user's account and all associated data,
  /// requiring password reauthentication. Clears all stored tokens on completion.
  Future<void> deleteAccount({required String password}) async {
    try {
      await _apiClient.post(
        ApiConfig.deleteAccountEndpoint,
        body: {'password': password},
        requiresAuth: true,
      );
    } finally {
      await _storageService.clearAuth();
    }
  }
}
