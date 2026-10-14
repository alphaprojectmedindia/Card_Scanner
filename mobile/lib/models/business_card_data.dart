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

  const BusinessCardData({
    this.fullName,
    this.company,
    this.jobTitle,
    this.phoneNumbers = const [],
    this.emailAddresses = const [],
    this.website,
    this.address,
    this.rawRecognizedText = '',
  });

  BusinessCardData copyWith({
    String? fullName,
    String? company,
    String? jobTitle,
    List<BusinessCardPhone>? phoneNumbers,
    List<BusinessCardEmail>? emailAddresses,
    String? website,
    String? address,
    String? rawRecognizedText,
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
      );

  @override
  String toString() =>
      'BusinessCardData(fullName: $fullName, company: $company, jobTitle: $jobTitle, phones: ${phoneNumbers.length}, emails: ${emailAddresses.length}, website: $website, address: $address)';
}
