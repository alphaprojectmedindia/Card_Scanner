class AuthResponse {
  final String token;
  final DateTime expirationUtc;
  final String userId;
  final String email;

  AuthResponse({
    required this.token,
    required this.expirationUtc,
    required this.userId,
    required this.email,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      token: json['token'] as String? ?? '',
      expirationUtc: json['expirationUtc'] != null
          ? DateTime.parse(json['expirationUtc'] as String)
          : DateTime.now().toUtc(),
      userId: json['userId'] as String? ?? '',
      email: json['email'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'expirationUtc': expirationUtc.toIso8601String(),
      'userId': userId,
      'email': email,
    };
  }
}
