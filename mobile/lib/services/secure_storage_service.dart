import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const String _tokenKey = 'jwt_auth_token';
  static const String _refreshTokenKey = 'jwt_refresh_token';
  static const String _accessTokenExpiryKey = 'jwt_access_token_expiry';
  static const String _refreshTokenExpiryKey = 'jwt_refresh_token_expiry';
  static const String _userIdKey = 'auth_user_id';
  static const String _userEmailKey = 'auth_user_email';

  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions:
                  IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  /// Saves access token alone (legacy compatibility).
  Future<void> saveAuthToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  /// Crash-safe token pair storage: writes new rotating refresh token first,
  /// then access token, followed by metadata.
  Future<void> saveAuthTokens({
    required String accessToken,
    required String refreshToken,
    DateTime? accessTokenExpiresAt,
    DateTime? refreshTokenExpiresAt,
  }) async {
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _tokenKey, value: accessToken);
    if (accessTokenExpiresAt != null) {
      await _storage.write(
        key: _accessTokenExpiryKey,
        value: accessTokenExpiresAt.toIso8601String(),
      );
    }
    if (refreshTokenExpiresAt != null) {
      await _storage.write(
        key: _refreshTokenExpiryKey,
        value: refreshTokenExpiresAt.toIso8601String(),
      );
    }
  }

  Future<String?> getAuthToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _refreshTokenKey);
  }

  Future<DateTime?> getAccessTokenExpiry() async {
    final str = await _storage.read(key: _accessTokenExpiryKey);
    if (str == null || str.isEmpty) return null;
    return DateTime.tryParse(str)?.toUtc();
  }

  Future<DateTime?> getRefreshTokenExpiry() async {
    final str = await _storage.read(key: _refreshTokenExpiryKey);
    if (str == null || str.isEmpty) return null;
    return DateTime.tryParse(str)?.toUtc();
  }

  Future<void> saveUserInfo(
      {required String userId, required String email}) async {
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _userEmailKey, value: email);
  }

  Future<String?> getUserId() async {
    return await _storage.read(key: _userIdKey);
  }

  Future<String?> getUserEmail() async {
    return await _storage.read(key: _userEmailKey);
  }

  Future<void> clearAuth() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _accessTokenExpiryKey);
    await _storage.delete(key: _refreshTokenExpiryKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _userEmailKey);
  }

  Future<bool> hasToken() async {
    final token = await getAuthToken();
    if (token != null && token.isNotEmpty) return true;
    final refresh = await getRefreshToken();
    return refresh != null && refresh.isNotEmpty;
  }

  Future<bool> hasRefreshToken() async {
    final token = await getRefreshToken();
    return token != null && token.isNotEmpty;
  }
}
