class BusinessCardEmail {
  final String email;
  final String? normalizedEmail;
  final String? label;

  const BusinessCardEmail({
    required this.email,
    this.normalizedEmail,
    this.label,
  });

  /// Normalizes an email address for comparison: trims whitespace and lowercases.
  static String normalize(String raw) {
    return raw.trim().toLowerCase();
  }

  BusinessCardEmail copyWith({
    String? email,
    String? normalizedEmail,
    String? label,
  }) {
    return BusinessCardEmail(
      email: email ?? this.email,
      normalizedEmail: normalizedEmail ?? this.normalizedEmail,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      if (normalizedEmail != null) 'normalizedEmail': normalizedEmail,
      if (label != null) 'label': label,
    };
  }

  factory BusinessCardEmail.fromJson(Map<String, dynamic> json) {
    return BusinessCardEmail(
      email: json['email'] as String? ?? '',
      normalizedEmail: json['normalizedEmail'] as String?,
      label: json['label'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BusinessCardEmail &&
        other.email == email &&
        other.normalizedEmail == normalizedEmail &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(email, normalizedEmail, label);

  @override
  String toString() =>
      'BusinessCardEmail(email: $email, normalizedEmail: $normalizedEmail, label: $label)';
}
