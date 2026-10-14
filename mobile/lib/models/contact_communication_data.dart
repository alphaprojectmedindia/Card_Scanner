import 'business_card_email.dart';
import 'business_card_phone.dart';
import 'shared_profile.dart';

/// Lightweight communication DTO bridging physical business cards and registered Digital Share profiles
/// for WhatsApp, Email, and follow-up messaging.
class ContactCommunicationData {
  final String displayName;
  final List<BusinessCardPhone> phones;
  final List<BusinessCardEmail> emails;
  final String? company;
  final String? jobTitle;
  final String? website;
  final String? address;

  const ContactCommunicationData({
    required this.displayName,
    required this.phones,
    required this.emails,
    this.company,
    this.jobTitle,
    this.website,
    this.address,
  });

  /// Factory creating communication data from a registered Digital Share profile.
  factory ContactCommunicationData.fromSharedProfile(SharedProfile profile) {
    final phoneList = <BusinessCardPhone>[];
    if (profile.phoneNumber != null && profile.phoneNumber!.trim().isNotEmpty) {
      phoneList.add(
        BusinessCardPhone(
          number: profile.phoneNumber!.trim(),
          label: 'Mobile',
        ),
      );
    }

    final emailList = <BusinessCardEmail>[];
    if (profile.email.trim().isNotEmpty) {
      emailList.add(
        BusinessCardEmail(
          email: profile.email.trim(),
          label: 'Email',
        ),
      );
    }

    return ContactCommunicationData(
      displayName: profile.displayName,
      phones: phoneList,
      emails: emailList,
      company: profile.company,
      jobTitle: profile.jobTitle,
      website: profile.website,
      address: profile.address,
    );
  }
}
