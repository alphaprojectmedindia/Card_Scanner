import 'business_card_email.dart';
import 'business_card_phone.dart';

class BusinessCardData {
  final String? fullName;
  final String? company;
  final String? jobTitle;
  final List<BusinessCardPhone> phoneNumbers;
  final List<BusinessCardEmail> emailAddresses;
  final String? website;
  final String? address;
  final String rawRecognizedText;

  /// Holds plausible alternative values discovered during parsing (e.g. from the back side),
  /// keyed by field name: 'fullName', 'company', 'jobTitle', 'website', 'address'.
  final Map<String, List<String>> alternativeCandidates;

  /// Diagnostic notes or warnings recorded during extraction and merge.
  final List<String> parsingNotes;

  /// True if this data was produced from a dual-sided scan (front + back).
  final bool isDualSided;

  /// Isolated raw text from front side.
  final String? frontRawText;

  /// Isolated raw text from back side.
  final String? backRawText;

  const BusinessCardData({
    this.fullName,
    this.company,
    this.jobTitle,
    this.phoneNumbers = const [],
    this.emailAddresses = const [],
    this.website,
    this.address,
    this.rawRecognizedText = '',
    this.alternativeCandidates = const {},
    this.parsingNotes = const [],
    this.isDualSided = false,
    this.frontRawText,
    this.backRawText,
  });

  bool get isEmpty =>
      (fullName == null || fullName!.trim().isEmpty) &&
      (company == null || company!.trim().isEmpty) &&
      (jobTitle == null || jobTitle!.trim().isEmpty) &&
      phoneNumbers.isEmpty &&
      emailAddresses.isEmpty &&
      (website == null || website!.trim().isEmpty) &&
      (address == null || address!.trim().isEmpty);

  bool get isNotEmpty => !isEmpty;

  BusinessCardData copyWith({
    String? fullName,
    String? company,
    String? jobTitle,
    List<BusinessCardPhone>? phoneNumbers,
    List<BusinessCardEmail>? emailAddresses,
    String? website,
    String? address,
    String? rawRecognizedText,
    Map<String, List<String>>? alternativeCandidates,
    List<String>? parsingNotes,
    bool? isDualSided,
    String? frontRawText,
    String? backRawText,
  }) {
    return BusinessCardData(
      fullName: fullName ?? this.fullName,
      company: company ?? this.company,
      jobTitle: jobTitle ?? this.jobTitle,
      phoneNumbers: phoneNumbers ?? this.phoneNumbers,
      emailAddresses: emailAddresses ?? this.emailAddresses,
      website: website ?? this.website,
      address: address ?? this.address,
      rawRecognizedText: rawRecognizedText ?? this.rawRecognizedText,
      alternativeCandidates:
          alternativeCandidates ?? this.alternativeCandidates,
      parsingNotes: parsingNotes ?? this.parsingNotes,
      isDualSided: isDualSided ?? this.isDualSided,
      frontRawText: frontRawText ?? this.frontRawText,
      backRawText: backRawText ?? this.backRawText,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (fullName != null) 'fullName': fullName,
      if (company != null) 'company': company,
      if (jobTitle != null) 'jobTitle': jobTitle,
      'phoneNumbers': phoneNumbers.map((p) => p.toJson()).toList(),
      'emailAddresses': emailAddresses.map((e) => e.toJson()).toList(),
      if (website != null) 'website': website,
      if (address != null) 'address': address,
      'rawRecognizedText': rawRecognizedText,
      if (alternativeCandidates.isNotEmpty)
        'alternativeCandidates': alternativeCandidates,
      if (parsingNotes.isNotEmpty) 'parsingNotes': parsingNotes,
      'isDualSided': isDualSided,
      if (frontRawText != null) 'frontRawText': frontRawText,
      if (backRawText != null) 'backRawText': backRawText,
    };
  }

  factory BusinessCardData.fromJson(Map<String, dynamic> json) {
    return BusinessCardData(
      fullName: json['fullName'] as String?,
      company: json['company'] as String?,
      jobTitle: json['jobTitle'] as String?,
      phoneNumbers: (json['phoneNumbers'] as List<dynamic>?)
              ?.map((item) =>
                  BusinessCardPhone.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      emailAddresses: (json['emailAddresses'] as List<dynamic>?)
              ?.map((item) =>
                  BusinessCardEmail.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      website: json['website'] as String?,
      address: json['address'] as String?,
      rawRecognizedText: json['rawRecognizedText'] as String? ?? '',
      alternativeCandidates: (json['alternativeCandidates']
                  as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(
                  k, (v as List<dynamic>).map((e) => e.toString()).toList())) ??
          const {},
      parsingNotes: (json['parsingNotes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isDualSided: json['isDualSided'] as bool? ?? false,
      frontRawText: json['frontRawText'] as String?,
      backRawText: json['backRawText'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BusinessCardData) return false;
    if (fullName != other.fullName ||
        company != other.company ||
        jobTitle != other.jobTitle ||
        website != other.website ||
        address != other.address ||
        rawRecognizedText != other.rawRecognizedText ||
        isDualSided != other.isDualSided ||
        phoneNumbers.length != other.phoneNumbers.length ||
        emailAddresses.length != other.emailAddresses.length) {
      return false;
    }

    for (int i = 0; i < phoneNumbers.length; i++) {
      if (phoneNumbers[i] != other.phoneNumbers[i]) return false;
    }
    for (int i = 0; i < emailAddresses.length; i++) {
      if (emailAddresses[i] != other.emailAddresses[i]) return false;
    }

    return true;
  }

  @override
  int get hashCode => Object.hash(
        fullName,
        company,
        jobTitle,
        Object.hashAll(phoneNumbers),
        Object.hashAll(emailAddresses),
        website,
        address,
        rawRecognizedText,
        isDualSided,
      );

  @override
  String toString() =>
      'BusinessCardData(fullName: $fullName, company: $company, jobTitle: $jobTitle, phones: ${phoneNumbers.length}, emails: ${emailAddresses.length}, website: $website, address: $address, isDualSided: $isDualSided)';
}
