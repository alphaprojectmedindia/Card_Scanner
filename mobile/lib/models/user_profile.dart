class UserProfile {
  final String id;
  final String userId;
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
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  UserProfile({
    required this.id,
    required this.userId,
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
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  /// Display helper to get a presentable name
  String get displayName {
    if (fullName != null && fullName!.trim().isNotEmpty) {
      return fullName!.trim();
    }
    return email.split('@').first;
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
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
      createdAtUtc: json['createdAtUtc'] != null
          ? DateTime.parse(json['createdAtUtc'] as String)
          : DateTime.now().toUtc(),
      updatedAtUtc: json['updatedAtUtc'] != null
          ? DateTime.parse(json['updatedAtUtc'] as String)
          : DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
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
      'createdAtUtc': createdAtUtc.toIso8601String(),
      'updatedAtUtc': updatedAtUtc.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? id,
    String? userId,
    String? shareId,
    String? fullName,
    String? phoneNumber,
    String? email,
    String? jobTitle,
    String? company,
    String? website,
    String? address,
    String? bio,
    String? profilePhotoUrl,
    DateTime? createdAtUtc,
    DateTime? updatedAtUtc,
  }) {
    return UserProfile(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      shareId: shareId ?? this.shareId,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      jobTitle: jobTitle ?? this.jobTitle,
      company: company ?? this.company,
      website: website ?? this.website,
      address: address ?? this.address,
      bio: bio ?? this.bio,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }
}
