class BusinessCardPhone {
  final String number;
  final String? normalizedNumber;
  final String? label;

  const BusinessCardPhone({
    required this.number,
    this.normalizedNumber,
    this.label,
  });

  /// Normalizes a phone number for comparison and duplicate detection.
  /// Preserves leading '+', removes spaces, hyphens, parentheses, dots, etc.
  static String normalize(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    return cleaned;
  }

  BusinessCardPhone copyWith({
    String? number,
    String? normalizedNumber,
    String? label,
  }) {
    return BusinessCardPhone(
      number: number ?? this.number,
      normalizedNumber: normalizedNumber ?? this.normalizedNumber,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      if (normalizedNumber != null) 'normalizedNumber': normalizedNumber,
      if (label != null) 'label': label,
    };
  }

  factory BusinessCardPhone.fromJson(Map<String, dynamic> json) {
    return BusinessCardPhone(
      number: json['number'] as String? ?? '',
      normalizedNumber: json['normalizedNumber'] as String?,
      label: json['label'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BusinessCardPhone &&
        other.number == number &&
        other.normalizedNumber == normalizedNumber &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(number, normalizedNumber, label);

  @override
  String toString() =>
      'BusinessCardPhone(number: $number, normalizedNumber: $normalizedNumber, label: $label)';
}
