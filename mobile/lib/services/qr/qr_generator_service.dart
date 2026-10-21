import '../../config/api_config.dart';

/// Pure, deterministic service for generating standards-compliant, interoperable
/// QR payload strings readable by any standard QR reader.
class QrGeneratorService {
  const QrGeneratorService();

  /// 1. Digital Share Profile QR
  static String buildDigitalSharePayload(String shareId) {
    return ApiConfig.buildShareUrl(shareId.trim());
  }

  /// 2. Website URL QR
  /// Ensures valid http or https scheme.
  static String buildWebsitePayload(String url) {
    final trimmed = url.trim();
    if (!trimmed.toLowerCase().startsWith('http://') &&
        !trimmed.toLowerCase().startsWith('https://')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  /// 3. Wi-Fi Configuration QR
  /// Generates standard format: WIFI:T:WPA;S:MySSID;P:myPassword;H:false;;
  static String buildWifiPayload({
    required String ssid,
    required String security, // 'WPA', 'WEP', or 'nopass'
    required String password,
    bool isHidden = false,
  }) {
    final cleanSsid = _escapeWifi(ssid.trim());
    final cleanSec = security.trim().toUpperCase();
    final cleanPassword = _escapeWifi(password);
    final hiddenStr = isHidden ? 'true' : 'false';

    if (cleanSec == 'NOPASS' || cleanSec == 'NONE') {
      return 'WIFI:T:nopass;S:$cleanSsid;;';
    }

    return 'WIFI:T:$cleanSec;S:$cleanSsid;P:$cleanPassword;H:$hiddenStr;;';
  }

  /// 4. WhatsApp Direct Chat QR
  /// Generates: `https://wa.me/<digits>?text=<encodedMessage>`
  static String buildWhatsAppPayload({
    required String phone,
    String? message,
  }) {
    // Strip non-digits except preserve country code
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final cleanMessage = message?.trim() ?? '';

    if (cleanMessage.isNotEmpty) {
      final encoded = Uri.encodeComponent(cleanMessage);
      return 'https://wa.me/$digits?text=$encoded';
    }
    return 'https://wa.me/$digits';
  }

  /// 5. Phone Number QR
  /// Generates: tel:+919876543210
  static String buildPhonePayload(String phone) {
    final trimmed = phone.trim();
    return 'tel:$trimmed';
  }

  /// 6. Email QR
  /// Generates: mailto:user@example.com?subject=...&body=...
  static String buildEmailPayload({
    required String email,
    String? subject,
    String? body,
  }) {
    final cleanEmail = email.trim();
    final queryParams = <String>[];

    if (subject != null && subject.trim().isNotEmpty) {
      queryParams.add('subject=${Uri.encodeComponent(subject.trim())}');
    }
    if (body != null && body.trim().isNotEmpty) {
      queryParams.add('body=${Uri.encodeComponent(body.trim())}');
    }

    final query = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    return 'mailto:$cleanEmail$query';
  }

  /// 7. SMS QR
  /// Generates standard SMSTO: format
  static String buildSmsPayload({
    required String phone,
    String? message,
  }) {
    final cleanPhone = phone.trim();
    final cleanMessage = message?.trim() ?? '';
    if (cleanMessage.isNotEmpty) {
      return 'SMSTO:$cleanPhone:$cleanMessage';
    }
    return 'sms:$cleanPhone';
  }

  /// 8. Contact (vCard 3.0) QR
  /// Generates interoperable standard vCard format
  static String buildContactVCardPayload({
    required String name,
    List<String>? phones,
    List<String>? emails,
    String? company,
    String? title,
    String? website,
    String? address,
    String? notes,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCARD');
    buffer.writeln('VERSION:3.0');

    final cleanName = name.trim();
    buffer.writeln('FN:$cleanName');

    // Split first and last name if possible
    final parts = cleanName.split(' ');
    if (parts.length > 1) {
      final last = parts.last;
      final first = parts.sublist(0, parts.length - 1).join(' ');
      buffer.writeln('N:$last;$first;;;');
    } else {
      buffer.writeln('N:$cleanName;;;;');
    }

    if (company != null && company.trim().isNotEmpty) {
      buffer.writeln('ORG:${company.trim()}');
    }
    if (title != null && title.trim().isNotEmpty) {
      buffer.writeln('TITLE:${title.trim()}');
    }

    if (phones != null) {
      for (final p in phones) {
        final cp = p.trim();
        if (cp.isNotEmpty) {
          buffer.writeln('TEL;TYPE=CELL:$cp');
        }
      }
    }

    if (emails != null) {
      for (final e in emails) {
        final ce = e.trim();
        if (ce.isNotEmpty) {
          buffer.writeln('EMAIL;TYPE=WORK:$ce');
        }
      }
    }

    if (website != null && website.trim().isNotEmpty) {
      buffer.writeln('URL:${website.trim()}');
    }

    if (address != null && address.trim().isNotEmpty) {
      buffer.writeln('ADR;TYPE=WORK:;;${_escapeVCard(address.trim())};;;;');
    }

    if (notes != null && notes.trim().isNotEmpty) {
      buffer.writeln('NOTE:${_escapeVCard(notes.trim())}');
    }

    buffer.write('END:VCARD');
    return buffer.toString();
  }

  /// 9. Geographic Location QR
  /// Generates: geo:13.0827,80.2707 or geo:lat,lng?q=lat,lng(Label)
  static String buildLocationPayload({
    required double latitude,
    required double longitude,
    String? label,
  }) {
    if (latitude < -90.0 || latitude > 90.0) {
      throw ArgumentError('Latitude must be between -90 and +90.');
    }
    if (longitude < -180.0 || longitude > 180.0) {
      throw ArgumentError('Longitude must be between -180 and +180.');
    }

    final latStr = latitude.toStringAsFixed(6);
    final lngStr = longitude.toStringAsFixed(6);

    final cleanLabel = label?.trim() ?? '';
    if (cleanLabel.isNotEmpty) {
      return 'geo:$latStr,$lngStr?q=$latStr,$lngStr(${Uri.encodeComponent(cleanLabel)})';
    }
    return 'geo:$latStr,$lngStr';
  }

  /// 10. Plain Text QR
  static String buildPlainTextPayload(String text) {
    return text;
  }

  // ---------------------------------------------------------------------------
  // Escape Helpers
  // ---------------------------------------------------------------------------
  static String _escapeWifi(String val) {
    return val
        .replaceAll(r'\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll(':', r'\:');
  }

  static String _escapeVCard(String val) {
    return val
        .replaceAll(r'\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll('\n', r'\n');
  }
}
