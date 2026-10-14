import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/services/contact_communication_service.dart';
import 'package:digital_share/services/contact_service.dart';

void main() {
  group('ContactCommunicationService Unit Tests', () {
    test('1. Default message includes first name when full name provided', () {
      final msg = ContactCommunicationService.getDefaultMessage('Rahul Kumar');
      expect(msg, "Hi Rahul, it was great meeting you. Let's stay connected.");

      final singleNameMsg =
          ContactCommunicationService.getDefaultMessage('Priya');
      expect(singleNameMsg,
          "Hi Priya, it was great meeting you. Let's stay connected.");
    });

    test('2. Default message works without name (null, empty, or whitespace)', () {
      expect(ContactCommunicationService.getDefaultMessage(null),
          "Hi, it was great meeting you. Let's stay connected.");
      expect(ContactCommunicationService.getDefaultMessage(''),
          "Hi, it was great meeting you. Let's stay connected.");
      expect(ContactCommunicationService.getDefaultMessage('   '),
          "Hi, it was great meeting you. Let's stay connected.");
    });

    test('3. WhatsApp phone sanitization preserves international digits and strips formatting', () {
      expect(
        ContactCommunicationService.sanitizeForWhatsApp('+91 98765 43210'),
        '919876543210',
      );
      expect(
        ContactCommunicationService.sanitizeForWhatsApp('+1 (415) 555-2671'),
        '14155552671',
      );
      expect(
        ContactCommunicationService.sanitizeForWhatsApp('+44 20 7946 0958'),
        '442079460958',
      );
      expect(
        ContactCommunicationService.sanitizeForWhatsApp('00919876543210'),
        '919876543210',
      );
    });

    test('4. Country code detection differentiates international from local numbers', () {
      expect(
        ContactCommunicationService.hasCountryCode('+91 98765 43210'),
        isTrue,
      );
      expect(
        ContactCommunicationService.hasCountryCode('00442079460958'),
        isTrue,
      );
      expect(
        ContactCommunicationService.hasCountryCode('+1 555 123 4567'),
        isTrue,
      );
      expect(
        ContactCommunicationService.hasCountryCode('9876543210'),
        isFalse,
      );
      expect(
        ContactCommunicationService.hasCountryCode('044 23456789'),
        isFalse,
      );
      expect(
        ContactCommunicationService.hasCountryCode('8078709703'),
        isFalse,
      );
    });

    test('Email Bug 1: Subject spaces do NOT become literal + characters', () {
      final uriString = ContactCommunicationService.buildMailtoUriString(
        email: 'ansafofficial3@gmail.com',
        subject: 'Great meeting you',
        body: '',
      );

      // Must contain subject=Great%20meeting%20you
      expect(uriString, contains('subject=Great%20meeting%20you'));
      // Must NOT contain Great+meeting+you
      expect(uriString, isNot(contains('Great+meeting+you')));
      expect(uriString, isNot(contains('+')));
    });

    test('Email Bug 1: Body spaces do NOT contain inserted literal + characters', () {
      const originalBody =
          "Hi Ansaf, it was great meeting you. Let's stay connected.";
      final uriString = ContactCommunicationService.buildMailtoUriString(
        email: 'ansafofficial3@gmail.com',
        subject: '',
        body: originalBody,
      );

      // Must contain %20 for spaces
      expect(uriString, contains('%20'));
      // Must NOT contain literal +
      expect(uriString, isNot(contains('+')));
      expect(uriString, isNot(contains('Hi+Ansaf')));

      // Decoded body matches exactly
      final bodyParam = uriString.split('body=').last;
      expect(Uri.decodeComponent(bodyParam), originalBody);
    });

    test('Email: Special characters, &, ?, +, multiline, and emoji encode and decode correctly', () {
      // &
      final ampersandUri = ContactCommunicationService.buildMailtoUriString(
        email: 'test@example.com',
        subject: 'Hello & welcome',
        body: '',
      );
      expect(ampersandUri, contains('subject=Hello%20%26%20welcome'));
      final decodedAmpersand =
          Uri.decodeComponent(ampersandUri.split('subject=').last);
      expect(decodedAmpersand, 'Hello & welcome');

      // ?
      final questionUri = ContactCommunicationService.buildMailtoUriString(
        email: 'test@example.com',
        subject: 'Question?',
        body: '',
      );
      expect(questionUri, contains('subject=Question%3F'));
      final decodedQuestion =
          Uri.decodeComponent(questionUri.split('subject=').last);
      expect(decodedQuestion, 'Question?');

      // +
      final plusUri = ContactCommunicationService.buildMailtoUriString(
        email: 'test@example.com',
        subject: '+',
        body: '',
      );
      expect(plusUri, contains('subject=%2B'));
      final decodedPlus = Uri.decodeComponent(plusUri.split('subject=').last);
      expect(decodedPlus, '+');

      // Multiline
      final multilineUri = ContactCommunicationService.buildMailtoUriString(
        email: 'test@example.com',
        subject: 'Multiline',
        body: 'Line 1\nLine 2',
      );
      expect(multilineUri, contains('body=Line%201%0ALine%202'));
      final decodedMultiline =
          Uri.decodeComponent(multilineUri.split('body=').last);
      expect(decodedMultiline, 'Line 1\nLine 2');

      // Emoji
      final emojiUri = ContactCommunicationService.buildMailtoUriString(
        email: 'test@example.com',
        subject: '🎉 Meeting',
        body: 'Hello 😊',
      );
      expect(emojiUri, contains('%F0%9F%8E%89'));
      expect(emojiUri, contains('%F0%9F%98%8A'));
      final decodedEmojiSubject = Uri.decodeComponent(
          emojiUri.split('&').first.split('subject=').last);
      expect(decodedEmojiSubject, '🎉 Meeting');
      final decodedEmojiBody =
          Uri.decodeComponent(emojiUri.split('body=').last);
      expect(decodedEmojiBody, 'Hello 😊');
    });

    test('6, 7, 8, 9. WhatsApp international numbers (+91, +44, +1, +971)', () {
      // India +91
      expect(
        ContactCommunicationService.sanitizeForWhatsApp('+91 8078709703'),
        '918078709703',
      );
      expect(
        ContactCommunicationService.hasCountryCode('+91 8078709703'),
        isTrue,
      );

      // UK +44
      expect(
        ContactCommunicationService.sanitizeForWhatsApp('+44 7700 900123'),
        '447700900123',
      );
      expect(
        ContactCommunicationService.hasCountryCode('+44 7700 900123'),
        isTrue,
      );

      // US/Canada +1
      expect(
        ContactCommunicationService.sanitizeForWhatsApp('+1 (415) 555-2671'),
        '14155552671',
      );
      expect(
        ContactCommunicationService.hasCountryCode('+1 (415) 555-2671'),
        isTrue,
      );

      // UAE +971
      expect(
        ContactCommunicationService.sanitizeForWhatsApp('+971 50 123 4567'),
        '971501234567',
      );
      expect(
        ContactCommunicationService.hasCountryCode('+971 50 123 4567'),
        isTrue,
      );
    });

    test('10. WhatsApp URI strips formatting correctly from complex inputs', () {
      expect(
        ContactCommunicationService.sanitizeForWhatsApp('+91 (807) 870-9703'),
        '918078709703',
      );
      expect(
        ContactCommunicationService.sanitizeForWhatsApp('0044 7700 900123'),
        '447700900123',
      );
    });

    test('16. formatWithCountryCode combines country code and local number correctly', () {
      expect(
        ContactCommunicationService.formatWithCountryCode(
          countryCode: '+91',
          phoneNumber: '8078709703',
        ),
        '+91 8078709703',
      );
      expect(
        ContactCommunicationService.formatWithCountryCode(
          countryCode: '91',
          phoneNumber: '8078709703',
        ),
        '+91 8078709703',
      );
      expect(
        ContactCommunicationService.formatWithCountryCode(
          countryCode: '+44',
          phoneNumber: '07700 900123',
        ),
        '+44 7700 900123',
      );
      expect(
        ContactCommunicationService.formatWithCountryCode(
          countryCode: '+1',
          phoneNumber: '415 555 2671',
        ),
        '+1 415 555 2671',
      );
      expect(
        ContactCommunicationService.formatWithCountryCode(
          countryCode: '+971',
          phoneNumber: '50 123 4567',
        ),
        '+971 50 123 4567',
      );
    });

    test('20, 21. WhatsApp message encoding preserves spaces without literal + and encodes specials', () {
      const msg = "Hi Ansaf, it was great meeting you. Let's stay connected! 🎉 & ?";
      final uriString = ContactCommunicationService.buildWhatsAppUniversalUriString(
        phone: '+91 8078709703',
        message: msg,
      );

      // Verify recipient digits
      expect(uriString, startsWith('https://wa.me/918078709703?text='));

      // Spaces are %20, NOT +
      final textParam = uriString.split('text=').last;
      expect(textParam, contains('%20'));
      expect(textParam, isNot(contains('Hi+Ansaf')));

      // Decoded text matches exactly
      expect(Uri.decodeComponent(textParam), msg);
    });

    test('23. WhatsApp direct URIs always target recipient and do not use generic contact picker', () {
      final nativeUri = ContactCommunicationService.buildWhatsAppNativeUriString(
        phone: '+91 8078709703',
        message: 'Hello',
      );
      expect(nativeUri, contains('phone=918078709703'));

      final universalUri = ContactCommunicationService.buildWhatsAppUniversalUriString(
        phone: '+91 8078709703',
        message: 'Hello',
      );
      expect(universalUri, contains('wa.me/918078709703'));
    });
  });

  group('ContactService Business Card Mapping Tests', () {
    final contactService = ContactService();

    test('19, 20, 21, 22. buildContactFromBusinessCard maps all phones, emails, company, job title, website, and address', () {
      final contact = contactService.buildContactFromBusinessCard(
        fullName: 'Rahul Kumar',
        company: 'ABC Technologies',
        jobTitle: 'Senior Developer',
        website: 'https://abctech.com',
        address: 'Chennai, Tamil Nadu',
        phones: const [
          BusinessCardPhone(number: '+91 98765 43210', label: 'Mobile'),
          BusinessCardPhone(number: '+91 44 2345 6789', label: 'Office'),
        ],
        emails: const [
          BusinessCardEmail(email: 'rahul@abctech.com', label: 'Work'),
          BusinessCardEmail(email: 'rahul.personal@gmail.com', label: 'Personal'),
        ],
      );

      // Name
      expect(contact.name?.first, 'Rahul');
      expect(contact.name?.last, 'Kumar');

      // Phones (all phones preserved)
      expect(contact.phones.length, 2);
      expect(contact.phones[0].number, '+91 98765 43210');
      expect(contact.phones[1].number, '+91 44 2345 6789');

      // Emails (all emails preserved)
      expect(contact.emails.length, 2);
      expect(contact.emails[0].address, 'rahul@abctech.com');
      expect(contact.emails[1].address, 'rahul.personal@gmail.com');

      // Organizations (company & job title)
      expect(contact.organizations.length, 1);
      expect(contact.organizations.first.name, 'ABC Technologies');
      expect(contact.organizations.first.jobTitle, 'Senior Developer');

      // Websites
      expect(contact.websites.length, 1);
      expect(contact.websites.first.url, 'https://abctech.com');

      // Addresses
      expect(contact.addresses.length, 1);
      expect(contact.addresses.first.formatted, 'Chennai, Tamil Nadu');
    });
  });
}
