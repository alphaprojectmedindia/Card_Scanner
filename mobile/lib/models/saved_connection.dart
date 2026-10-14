import 'shared_profile.dart';

class SavedConnection {
  final String shareId;
  final String fullName;
  final String? phoneNumber;
  final String? email;
  final String? jobTitle;
  final String? company;
  final String? website;
  final String? address;
  final String? bio;
  final String? profilePhotoUrl;
  final DateTime savedAtUtc;

  SavedConnection({
    required this.shareId,
    required this.fullName,
    this.phoneNumber,
    this.email,
    this.jobTitle,
    this.company,
    this.website,
    this.address,
    this.bio,
    this.profilePhotoUrl,
    required this.savedAtUtc,
  });

  String get displayName {
    if (fullName.trim().isNotEmpty) {
      return fullName.trim();
    }
    if (email != null && email!.isNotEmpty) {
      return email!.split('@').first;
    }
    return 'Digital Share Contact';
  }

  SharedProfile toSharedProfile() {
    return SharedProfile(
      shareId: shareId,
      fullName: fullName,
      phoneNumber: phoneNumber,
      email: email ?? '',
      jobTitle: jobTitle,
      company: company,
      website: website,
      address: address,
      bio: bio,
      profilePhotoUrl: profilePhotoUrl,
    );
  }

  factory SavedConnection.fromJson(Map<String, dynamic> json) {
    return SavedConnection(
      shareId: json['shareId'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String?,
      email: json['email'] as String?,
      jobTitle: json['jobTitle'] as String?,
      company: json['company'] as String?,
      website: json['website'] as String?,
      address: json['address'] as String?,
      bio: json['bio'] as String?,
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      savedAtUtc: json['savedAtUtc'] != null
          ? DateTime.tryParse(json['savedAtUtc'] as String) ?? DateTime.now().toUtc()
          : DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shareId': shareId,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'email': email,
      'jobTitle': jobTitle,
      'company': company,
      'website': website,
      'address': address,
      'bio': bio,
      'profilePhotoUrl': profilePhotoUrl,
      'savedAtUtc': savedAtUtc.toIso8601String(),
    };
  }
}
