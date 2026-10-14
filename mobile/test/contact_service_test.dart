import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/shared_profile.dart';
import 'package:digital_share/services/contact_service.dart';

void main() {
  group('ContactService Mapping Tests', () {
    final contactService = ContactService();

    test('buildContactFromProfile maps full name, phone, email, organization, website, address correctly', () {
      final profile = SharedProfile(
        shareId: 'test-share-id-12345678',
        fullName: 'Johnathan Alexander Doe',
        phoneNumber: '+1-555-123-4567',
        email: 'johnathan.doe@company.org',
        jobTitle: 'Senior VP of Engineering',
        company: 'Global Technologies Inc.',
        website: 'https://johndoe.dev',
        address: '456 Innovation Way, Suite 700, San Francisco, CA',
        bio: 'Leading distributed platforms.',
      );

      final contact = contactService.buildContactFromProfile(profile);

      // 1. Name
      expect(contact.name?.first, 'Johnathan');
      expect(contact.name?.last, 'Alexander Doe');

      // 2. Phone
      expect(contact.phones.length, 1);
      expect(contact.phones.first.number, '+1-555-123-4567');

      // 3. Email
      expect(contact.emails.length, 1);
      expect(contact.emails.first.address, 'johnathan.doe@company.org');

      // 4. Organization & Job Title
      expect(contact.organizations.length, 1);
      expect(contact.organizations.first.name, 'Global Technologies Inc.');
      expect(contact.organizations.first.jobTitle, 'Senior VP of Engineering');

      // 5. Website
      expect(contact.websites.length, 1);
      expect(contact.websites.first.url, 'https://johndoe.dev');

      // 6. Address
      expect(contact.addresses.length, 1);
      expect(contact.addresses.first.formatted, '456 Innovation Way, Suite 700, San Francisco, CA');
    });

    test('buildContactFromProfile handles single-word name and minimal fields', () {
      final profile = SharedProfile(
        shareId: 'test-single-name',
        fullName: 'Madonna',
        email: 'madonna@music.com',
      );

      final contact = contactService.buildContactFromProfile(profile);

      expect(contact.name?.first, 'Madonna');
      expect(contact.name?.last, isNull);
      expect(contact.emails.first.address, 'madonna@music.com');
      expect(contact.phones, isEmpty);
      expect(contact.organizations, isEmpty);
    });
  });
}
