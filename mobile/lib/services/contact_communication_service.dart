import 'package:url_launcher/url_launcher.dart';

abstract class IContactCommunicationService {
  Future<bool> openWhatsApp({
    required String phone,
    required String message,
  });

  Future<bool> openEmail({
    required String email,
    required String subject,
    required String body,
  });
}

class ContactCommunicationService implements IContactCommunicationService {
  const ContactCommunicationService();

  /// Generates a polite, personalized default follow-up message.
  static String getDefaultMessage(String? fullName) {
    final trimmed = fullName?.trim() ?? '';
    if (trimmed.isEmpty) {
      return "Hi, it was great meeting you. Let's stay connected.";
    }
    final firstName = trimmed.split(RegExp(r'\s+')).first;
    return "Hi $firstName, it was great meeting you. Let's stay connected.";
  }

  /// Sanitizes a phone number for the WhatsApp universal link (`wa.me/<digits>`).
  ///
  /// Preserves international country codes when present, strips formatting/symbols (+, -, (), spaces).
  static String sanitizeForWhatsApp(String phone) {
    final trimmed = phone.trim();
    if (trimmed.startsWith('00')) {
      return trimmed.substring(2).replaceAll(RegExp(r'\D'), '');
    }
    // Remove all non-digit characters. If it had a '+', the leading '+' is stripped leaving country code digits.
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return digits;
  }

  /// Checks if the phone number includes an explicit international country code prefix (+ or 00).
  static bool hasCountryCode(String phone) {
    final trimmed = phone.trim();
    if (trimmed.startsWith('+') || trimmed.startsWith('00')) {
      return true;
    }
    return false;
  }

  /// Combines a country code and a local phone number into an international E.164-style display string.
  ///
  /// Examples:
  /// - `countryCode`: `+91`, `phoneNumber`: `8078709703` -> `+91 8078709703`
  /// - `countryCode`: `+44`, `phoneNumber`: `07700 900123` -> `+44 7700 900123`
  /// - `countryCode`: `44`, `phoneNumber`: `7700900123` -> `+44 7700900123`
  static String formatWithCountryCode({
    required String countryCode,
    required String phoneNumber,
  }) {
    final rawCodeDigits = countryCode.replaceAll(RegExp(r'\D'), '');
    final cleanCode = '+$rawCodeDigits';

    var cleanNumber = phoneNumber.trim();
    // Strip leading local trunk zero if present (e.g. 08078709703 -> 8078709703)
    if (cleanNumber.startsWith('0')) {
      cleanNumber = cleanNumber.replaceFirst(RegExp(r'^0+'), '');
    }
    return '$cleanCode $cleanNumber';
  }

  /// Constructs a RFC 6068 / RFC 3986 compliant `mailto:` URI string.
  ///
  /// Uses RFC 3986 percent-encoding (`Uri.encodeComponent`) so spaces become
  /// `%20` instead of `+`. This prevents email clients (such as Android Gmail)
  /// from rendering literal '+' characters in the subject or body.
  static String buildMailtoUriString({
    required String email,
    required String subject,
    required String body,
  }) {
    final cleanEmail = email.trim();
    final queryParts = <String>[];
    if (subject.isNotEmpty) {
      queryParts.add('subject=${Uri.encodeComponent(subject)}');
    }
    if (body.isNotEmpty) {
      queryParts.add('body=${Uri.encodeComponent(body)}');
    }
    final queryString = queryParts.isNotEmpty ? '?${queryParts.join('&')}' : '';
    return 'mailto:$cleanEmail$queryString';
  }

  /// Constructs a native WhatsApp direct-chat URI string (`whatsapp://send?phone=...&text=...`).
  static String buildWhatsAppNativeUriString({
    required String phone,
    required String message,
  }) {
    final sanitizedPhone = sanitizeForWhatsApp(phone);
    final encodedMessage = Uri.encodeComponent(message);
    return 'whatsapp://send?phone=$sanitizedPhone&text=$encodedMessage';
  }

  /// Constructs a universal WhatsApp direct-chat link (`https://wa.me/.../?text=...`).
  static String buildWhatsAppUniversalUriString({
    required String phone,
    required String message,
  }) {
    final sanitizedPhone = sanitizeForWhatsApp(phone);
    final encodedMessage = Uri.encodeComponent(message);
    return 'https://wa.me/$sanitizedPhone?text=$encodedMessage';
  }

  @override
  Future<bool> openWhatsApp({
    required String phone,
    required String message,
  }) async {
    try {
      final sanitizedPhone = sanitizeForWhatsApp(phone);
      if (sanitizedPhone.isEmpty) return false;

      // 1. Attempt native WhatsApp direct chat scheme if supported
      final nativeUri = Uri.parse(
        buildWhatsAppNativeUriString(phone: phone, message: message),
      );
      if (await canLaunchUrl(nativeUri)) {
        final launched = await launchUrl(
          nativeUri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      }

      // 2. Direct universal link wa.me/<recipient>?text=<message>
      final universalUri = Uri.parse(
        buildWhatsAppUniversalUriString(phone: phone, message: message),
      );
      if (await canLaunchUrl(universalUri)) {
        return await launchUrl(
          universalUri,
          mode: LaunchMode.externalApplication,
        );
      }

      // Fallback: direct external application launch attempt on universal URL
      return await launchUrl(
        universalUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openEmail({
    required String email,
    required String subject,
    required String body,
  }) async {
    try {
      final trimmedEmail = email.trim();
      if (trimmedEmail.isEmpty) return false;

      final uriString = buildMailtoUriString(
        email: trimmedEmail,
        subject: subject,
        body: body,
      );
      final uri = Uri.parse(uriString);

      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }
}
