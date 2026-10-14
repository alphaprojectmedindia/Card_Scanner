class SharedProfile {
  final String shareId;
  final String? fullName;
  final String? phoneNumber;
  final String email;
  final String? jobTitle;
  final String? company;
  final String? website;
  final String? address;
  final String? bio;
  final String? profilePhotoUrl;

  SharedProfile({
    required this.shareId,
    this.fullName,
    this.phoneNumber,
    required this.email,
    this.jobTitle,
    this.company,
    this.website,
    this.address,
    this.bio,
    this.profilePhotoUrl,
  });

  String get displayName {
    if (fullName != null && fullName!.trim().isNotEmpty) {
      return fullName!.trim();
    }
    return email.split('@').first;
  }

  factory SharedProfile.fromJson(Map<String, dynamic> json) {
    return SharedProfile(
      shareId: json['shareId'] as String? ?? '',
      fullName: json['fullName'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      email: json['email'] as String? ?? '',
      jobTitle: json['jobTitle'] as String?,
      company: json['company'] as String?,
      website: json['website'] as String?,
      address: json['address'] as String?,
      bio: json['bio'] as String?,
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
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
    };
  }
}
