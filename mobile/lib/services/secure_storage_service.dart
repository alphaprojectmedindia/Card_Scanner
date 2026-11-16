import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const String _tokenKey = 'jwt_auth_token';
  static const String _refreshTokenKey = 'jwt_refresh_token';
  static const String _accessTokenExpiryKey = 'jwt_access_token_expiry';
  static const String _refreshTokenExpiryKey = 'jwt_refresh_token_expiry';
  static const String _userIdKey = 'auth_user_id';
  static const String _userEmailKey = 'auth_user_email';
  static const String _cachedProfileKey = 'cached_user_profile';
  static const String _cachedConnectionsCountKey = 'cached_connections_count';
  static const String _anonInstallIdKey = 'auth_anonymous_install_id';

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

  Future<void> saveCachedProfile(String profileJson) async {
    await _storage.write(key: _cachedProfileKey, value: profileJson);
  }

  Future<String?> getCachedProfile() async {
    return await _storage.read(key: _cachedProfileKey);
  }

  Future<void> saveCachedConnectionsCount(int count) async {
    await _storage.write(
        key: _cachedConnectionsCountKey, value: count.toString());
  }

  Future<int> getCachedConnectionsCount() async {
    final str = await _storage.read(key: _cachedConnectionsCountKey);
    return int.tryParse(str ?? '') ?? 0;
  }

  Future<void> clearAuth() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _accessTokenExpiryKey);
    await _storage.delete(key: _refreshTokenExpiryKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _userEmailKey);
    await _storage.delete(key: _cachedProfileKey);
    await _storage.delete(key: _cachedConnectionsCountKey);
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

  /// Generates or retrieves a unique persistent device-scoped anonymous identity
  /// to ensure no unauthenticated production session collides under a shared 'default_user'.
  Future<String> getAnonymousInstallId() async {
    final existing = await _storage.read(key: _anonInstallIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    final id = 'anon_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    await _storage.write(key: _anonInstallIdKey, value: id);
    return id;
  }
}
