import 'package:flutter_contacts/flutter_contacts.dart';
import '../models/business_card_email.dart';
import '../models/business_card_phone.dart';
import '../models/shared_profile.dart';

enum ContactSaveStatus {
  success,
  duplicateFound,
  permissionDenied,
  permissionPermanentlyDenied,
  invalidContact,
  failed,
}

class ContactSaveResult {
  final ContactSaveStatus status;
  final String message;

  const ContactSaveResult({
    required this.status,
    required this.message,
  });

  bool get isSuccess => status == ContactSaveStatus.success;
}

abstract class IContactService {
  Future<ContactSaveResult> saveSharedProfileToPhone(SharedProfile profile);
  Contact buildContactFromProfile(SharedProfile profile);

  Future<ContactSaveResult> saveBusinessCardToPhone({
    required String? fullName,
    required String? company,
    required String? jobTitle,
    required String? website,
    required String? address,
    required List<BusinessCardPhone> phones,
    required List<BusinessCardEmail> emails,
    bool force = false,
  });

  Contact buildContactFromBusinessCard({
    required String? fullName,
    required String? company,
    required String? jobTitle,
    required String? website,
    required String? address,
    required List<BusinessCardPhone> phones,
    required List<BusinessCardEmail> emails,
  });
}

class ContactService implements IContactService {
  @override
  Contact buildContactFromProfile(SharedProfile profile) {
    // 1. Name Mapping
    final fullName = (profile.fullName ?? '').trim();
    String? firstName;
    String? lastName;

    if (fullName.isNotEmpty) {
      final parts = fullName.split(' ');
      if (parts.length == 1) {
        firstName = parts[0];
      } else {
        firstName = parts.first;
        lastName = parts.sublist(1).join(' ');
      }
    } else {
      firstName = profile.displayName;
    }

    final name = Name(
      first: firstName,
      last: lastName,
    );

    // 2. Phone Mapping
    final List<Phone> phones = [];
    if (profile.phoneNumber != null && profile.phoneNumber!.trim().isNotEmpty) {
      phones.add(
        Phone(
          number: profile.phoneNumber!.trim(),
          label: const Label(PhoneLabel.mobile),
        ),
      );
    }

    // 3. Email Mapping
    final List<Email> emails = [];
    if (profile.email.trim().isNotEmpty) {
      emails.add(
        Email(
          address: profile.email.trim(),
          label: const Label(EmailLabel.work),
        ),
      );
    }

    // 4. Company & Job Title Mapping
    final List<Organization> organizations = [];
    final hasCompany =
        profile.company != null && profile.company!.trim().isNotEmpty;
    final hasJobTitle =
        profile.jobTitle != null && profile.jobTitle!.trim().isNotEmpty;
    if (hasCompany || hasJobTitle) {
      organizations.add(
        Organization(
          name: hasCompany ? profile.company!.trim() : null,
          jobTitle: hasJobTitle ? profile.jobTitle!.trim() : null,
        ),
      );
    }

    // 5. Website Mapping
    final List<Website> websites = [];
    if (profile.website != null && profile.website!.trim().isNotEmpty) {
      websites.add(
        Website(
          url: profile.website!.trim(),
          label: const Label(WebsiteLabel.homepage),
        ),
      );
    }

    // 6. Postal Address Mapping
    final List<Address> addresses = [];
    if (profile.address != null && profile.address!.trim().isNotEmpty) {
      addresses.add(
        Address(
          formatted: profile.address!.trim(),
          street: profile.address!.trim(),
          label: const Label(AddressLabel.work),
        ),
      );
    }

    return Contact(
      name: name,
      phones: phones,
      emails: emails,
      organizations: organizations,
      websites: websites,
      addresses: addresses,
    );
  }

  @override
  Contact buildContactFromBusinessCard({
    required String? fullName,
    required String? company,
    required String? jobTitle,
    required String? website,
    required String? address,
    required List<BusinessCardPhone> phones,
    required List<BusinessCardEmail> emails,
  }) {
    // 1. Name Mapping
    final trimmedName = (fullName ?? '').trim();
    String? firstName;
    String? lastName;

    if (trimmedName.isNotEmpty) {
      final parts = trimmedName.split(RegExp(r'\s+'));
      if (parts.length == 1) {
        firstName = parts[0];
      } else {
        firstName = parts.first;
        lastName = parts.sublist(1).join(' ');
      }
    } else if (company != null && company.trim().isNotEmpty) {
      firstName = company.trim();
    } else {
      firstName = 'Contact';
    }

    final name = Name(
      first: firstName,
      last: lastName,
    );

    // 2. Multiple Phones Mapping with labels
    final List<Phone> contactPhones = phones
        .where((p) => p.number.trim().isNotEmpty)
        .map((p) => Phone(
              number: p.number.trim(),
              label: _mapPhoneLabel(p.label),
            ))
        .toList();

    // 3. Multiple Emails Mapping with labels
    final List<Email> contactEmails = emails
        .where((e) => e.email.trim().isNotEmpty)
        .map((e) => Email(
              address: e.email.trim(),
              label: _mapEmailLabel(e.label),
            ))
        .toList();

    // 4. Company & Job Title Mapping
    final List<Organization> organizations = [];
    final hasCompany = company != null && company.trim().isNotEmpty;
    final hasJobTitle = jobTitle != null && jobTitle.trim().isNotEmpty;
    if (hasCompany || hasJobTitle) {
      organizations.add(
        Organization(
          name: hasCompany ? company : null,
          jobTitle: hasJobTitle ? jobTitle : null,
        ),
      );
    }

    // 5. Website Mapping
    final List<Website> websites = [];
    if (website != null && website.trim().isNotEmpty) {
      websites.add(
        Website(
          url: website.trim(),
          label: const Label(WebsiteLabel.homepage),
        ),
      );
    }

    // 6. Address Mapping
    final List<Address> addresses = [];
    if (address != null && address.trim().isNotEmpty) {
      addresses.add(
        Address(
          formatted: address.trim(),
          street: address.trim(),
          label: const Label(AddressLabel.work),
        ),
      );
    }

    return Contact(
      name: name,
      phones: contactPhones,
      emails: contactEmails,
      organizations: organizations,
      websites: websites,
      addresses: addresses,
    );
  }

  Label<PhoneLabel> _mapPhoneLabel(String? label) {
    final lower = (label ?? '').toLowerCase().trim();
    if (lower.contains('mobile') || lower.contains('cell')) {
      return const Label(PhoneLabel.mobile);
    } else if (lower.contains('work') || lower.contains('office')) {
      return const Label(PhoneLabel.work);
    } else if (lower.contains('home') || lower.contains('personal')) {
      return const Label(PhoneLabel.home);
    } else if (lower.contains('main')) {
      return const Label(PhoneLabel.main);
    }
    return const Label(PhoneLabel.other);
  }

  Label<EmailLabel> _mapEmailLabel(String? label) {
    final lower = (label ?? '').toLowerCase().trim();
    if (lower.contains('work') || lower.contains('office') || lower.contains('business')) {
      return const Label(EmailLabel.work);
    } else if (lower.contains('personal') || lower.contains('home')) {
      return const Label(EmailLabel.home);
    }
    return const Label(EmailLabel.other);
  }

  @override
  Future<ContactSaveResult> saveSharedProfileToPhone(SharedProfile profile) async {
    // Validate minimum contact info
    final hasName = (profile.fullName != null && profile.fullName!.trim().isNotEmpty);
    final hasPhone = (profile.phoneNumber != null && profile.phoneNumber!.trim().isNotEmpty);
    final hasEmail = profile.email.trim().isNotEmpty;

    if (!hasName && !hasPhone && !hasEmail) {
      return const ContactSaveResult(
        status: ContactSaveStatus.invalidContact,
        message: 'Profile does not contain valid contact information to save.',
      );
    }

    try {
      final status = await FlutterContacts.permissions.request(PermissionType.readWrite);
      if (status == PermissionStatus.permanentlyDenied || status == PermissionStatus.restricted) {
        return const ContactSaveResult(
          status: ContactSaveStatus.permissionPermanentlyDenied,
          message: 'Contacts permission is permanently restricted. Please allow access in device settings to save contacts.',
        );
      }

      if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
        return const ContactSaveResult(
          status: ContactSaveStatus.permissionDenied,
          message: 'Contacts permission was not granted. Please allow access in device settings to save contacts.',
        );
      }

      final contact = buildContactFromProfile(profile);
      await FlutterContacts.create(contact);

      return const ContactSaveResult(
        status: ContactSaveStatus.success,
        message: 'Contact saved to your phone.',
      );
    } catch (e) {
      return ContactSaveResult(
        status: ContactSaveStatus.failed,
        message: 'Failed to save contact to phone: ${e.toString()}',
      );
    }
  }

  @override
  Future<ContactSaveResult> saveBusinessCardToPhone({
    required String? fullName,
    required String? company,
    required String? jobTitle,
    required String? website,
    required String? address,
    required List<BusinessCardPhone> phones,
    required List<BusinessCardEmail> emails,
    bool force = false,
  }) async {
    final hasName = (fullName != null && fullName.trim().isNotEmpty);
    final hasCompany = (company != null && company.trim().isNotEmpty);
    final hasPhones = phones.any((p) => p.number.trim().isNotEmpty);
    final hasEmails = emails.any((e) => e.email.trim().isNotEmpty);

    if (!hasName && !hasCompany && !hasPhones && !hasEmails) {
      return const ContactSaveResult(
        status: ContactSaveStatus.invalidContact,
        message: 'Card does not contain valid contact information to save.',
      );
    }

    try {
      final status = await FlutterContacts.permissions.request(PermissionType.readWrite);
      if (status == PermissionStatus.permanentlyDenied || status == PermissionStatus.restricted) {
        return const ContactSaveResult(
          status: ContactSaveStatus.permissionPermanentlyDenied,
          message: 'Contacts permission is permanently restricted. Please allow access in device settings to save contacts.',
        );
      }

      if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
        return const ContactSaveResult(
          status: ContactSaveStatus.permissionDenied,
          message: 'Contacts permission was not granted. Please allow access in device settings to save contacts.',
        );
      }

      // Check phone duplicates before creating if force == false
      if (!force) {
        try {
          final existingContacts = await FlutterContacts.getAll(
            properties: {ContactProperty.phone, ContactProperty.email},
          );
          final candidatePhoneNumbers = phones
              .map((p) => p.number.replaceAll(RegExp(r'\D'), ''))
              .where((p) => p.isNotEmpty)
              .toSet();
          final candidateEmails = emails
              .map((e) => e.email.trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toSet();

          bool hasMatch = false;
          for (final existing in existingContacts) {
            for (final p in existing.phones) {
              final norm = p.number.replaceAll(RegExp(r'\D'), '');
              if (candidatePhoneNumbers.contains(norm) ||
                  (norm.length >= 10 && candidatePhoneNumbers.any((c) => c.endsWith(norm) || norm.endsWith(c)))) {
                hasMatch = true;
                break;
              }
            }
            if (hasMatch) break;

            for (final e in existing.emails) {
              if (candidateEmails.contains(e.address.trim().toLowerCase())) {
                hasMatch = true;
                break;
              }
            }
            if (hasMatch) break;
          }

          if (hasMatch) {
            return const ContactSaveResult(
              status: ContactSaveStatus.duplicateFound,
              message: 'This contact may already exist on your phone.',
            );
          }
        } catch (_) {
          // If query fails, proceed gracefully
        }
      }

      final contact = buildContactFromBusinessCard(
        fullName: fullName,
        company: company,
        jobTitle: jobTitle,
        website: website,
        address: address,
        phones: phones,
        emails: emails,
      );

      await FlutterContacts.create(contact);

      return const ContactSaveResult(
        status: ContactSaveStatus.success,
        message: 'Contact added to your phone.',
      );
    } catch (e) {
      return ContactSaveResult(
        status: ContactSaveStatus.failed,
        message: 'Failed to add contact to phone: ${e.toString()}',
      );
    }
  }
}
