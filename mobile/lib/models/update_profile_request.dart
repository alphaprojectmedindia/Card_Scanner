class UpdateProfileRequest {
  final String? fullName;
  final String? phoneNumber;
  final String email;
  final String? jobTitle;
  final String? company;
  final String? website;
  final String? address;
  final String? bio;
  final String? profilePhotoUrl;

  UpdateProfileRequest({
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

  Map<String, dynamic> toJson() {
    return {
      'fullName': fullName?.trim().isEmpty == true ? null : fullName?.trim(),
      'phoneNumber': phoneNumber?.trim().isEmpty == true ? null : phoneNumber?.trim(),
      'email': email.trim(),
      'jobTitle': jobTitle?.trim().isEmpty == true ? null : jobTitle?.trim(),
      'company': company?.trim().isEmpty == true ? null : company?.trim(),
      'website': website?.trim().isEmpty == true ? null : website?.trim(),
      'address': address?.trim().isEmpty == true ? null : address?.trim(),
      'bio': bio?.trim().isEmpty == true ? null : bio?.trim(),
      'profilePhotoUrl': profilePhotoUrl?.trim().isEmpty == true ? null : profilePhotoUrl?.trim(),
    };
  }
}
