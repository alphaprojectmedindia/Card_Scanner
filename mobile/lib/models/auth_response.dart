class AuthResponse {
  final String token;
  final String accessToken;
  final String refreshToken;
  final DateTime expirationUtc;
  final DateTime accessTokenExpiresAt;
  final DateTime? refreshTokenExpiresAt;
  final String userId;
  final String email;

  AuthResponse({
    required this.token,
    String? accessToken,
    this.refreshToken = '',
    required this.expirationUtc,
    DateTime? accessTokenExpiresAt,
    this.refreshTokenExpiresAt,
    required this.userId,
    required this.email,
  })  : accessToken = accessToken ?? token,
        accessTokenExpiresAt = accessTokenExpiresAt ?? expirationUtc;

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final rawToken = json['token'] as String? ?? '';
    final rawAccessToken = json['accessToken'] as String? ?? rawToken;
    final rawRefreshToken = json['refreshToken'] as String? ?? '';

    final expUtc = json['expirationUtc'] != null
        ? DateTime.parse(json['expirationUtc'] as String)
        : (json['accessTokenExpiresAt'] != null
            ? DateTime.parse(json['accessTokenExpiresAt'] as String)
            : DateTime.now().toUtc());

    final accessExp = json['accessTokenExpiresAt'] != null
        ? DateTime.parse(json['accessTokenExpiresAt'] as String)
        : expUtc;

    final refreshExp = json['refreshTokenExpiresAt'] != null
        ? DateTime.tryParse(json['refreshTokenExpiresAt'] as String)
        : null;

    return AuthResponse(
      token: rawToken.isNotEmpty ? rawToken : rawAccessToken,
      accessToken: rawAccessToken,
      refreshToken: rawRefreshToken,
      expirationUtc: expUtc,
      accessTokenExpiresAt: accessExp,
      refreshTokenExpiresAt: refreshExp,
      userId: json['userId'] as String? ?? '',
      email: json['email'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expirationUtc': expirationUtc.toIso8601String(),
      'accessTokenExpiresAt': accessTokenExpiresAt.toIso8601String(),
      if (refreshTokenExpiresAt != null)
        'refreshTokenExpiresAt': refreshTokenExpiresAt!.toIso8601String(),
      'userId': userId,
      'email': email,
    };
  }
}
