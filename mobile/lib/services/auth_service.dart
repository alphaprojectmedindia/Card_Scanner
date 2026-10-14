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
  }) async {
    final response = await _apiClient.post(
      ApiConfig.registerEndpoint,
      body: {
        'email': email.trim(),
        'password': password,
        'confirmPassword': confirmPassword,
      },
      requiresAuth: false,
    );

    final authResponse = AuthResponse.fromJson(response as Map<String, dynamic>);
    await _storageService.saveAuthToken(authResponse.token);
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

    final authResponse = AuthResponse.fromJson(response as Map<String, dynamic>);
    await _storageService.saveAuthToken(authResponse.token);
    await _storageService.saveUserInfo(
      userId: authResponse.userId,
      email: authResponse.email,
    );

    return authResponse;
  }

  Future<void> logout() async {
    await _storageService.clearAuth();
  }

  Future<bool> hasStoredToken() async {
    return await _storageService.hasToken();
  }
}
