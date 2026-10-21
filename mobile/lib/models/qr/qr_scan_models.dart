import 'qr_content_type.dart';

/// Top-level result representing a parsed QR scan.
class QrScanResult {
  final QrContentType type;
  final String rawValue;
  final Object parsedData;

  const QrScanResult({
    required this.type,
    required this.rawValue,
    required this.parsedData,
  });

  /// Type-safe helper cast.
  T dataAs<T>() => parsedData as T;
}

/// Parsed data for a Digital Share profile QR.
class DigitalShareQrData {
  final String shareId;
  final String canonicalUrl;

  const DigitalShareQrData({
    required this.shareId,
    required this.canonicalUrl,
  });
}

/// Parsed data for an HTTP or HTTPS website URL.
class UrlQrData {
  final String url;
  final String displayHost;
  final bool isSecure;

  const UrlQrData({
    required this.url,
    required this.displayHost,
    required this.isSecure,
  });
}

/// Parsed data for a WhatsApp contact or direct-chat link.
class WhatsAppQrData {
  final String phone;
  final String message;
  final String linkUrl;

  const WhatsAppQrData({
    required this.phone,
    required this.message,
    required this.linkUrl,
  });

  bool get hasPhone => phone.trim().isNotEmpty;
  bool get hasMessage => message.trim().isNotEmpty;
  bool get isNativeScheme => linkUrl.trim().toLowerCase().startsWith('whatsapp://');
}

/// Parsed data for a standard Wi-Fi network configuration.
class WifiQrData {
  final String ssid;
  final String security;
  final String password;
  final bool isHidden;

  const WifiQrData({
    required this.ssid,
    required this.security,
    required this.password,
    this.isHidden = false,
  });
}

/// Parsed data for a geographic location or map link.
class GeoQrData {
  final double? latitude;
  final double? longitude;
  final String? query;
  final String rawUri;

  const GeoQrData({
    this.latitude,
    this.longitude,
    this.query,
    required this.rawUri,
  });
}

/// Parsed data for a direct telephone link.
class PhoneQrData {
  final String phoneNumber;
  final String rawTelUri;

  const PhoneQrData({
    required this.phoneNumber,
    required this.rawTelUri,
  });
}

/// Parsed data for a direct email composition link.
class EmailQrData {
  final String email;
  final String subject;
  final String body;
  final String? cc;
  final String? bcc;

  const EmailQrData({
    required this.email,
    required this.subject,
    required this.body,
    this.cc,
    this.bcc,
  });
}

/// Parsed data for a direct SMS link.
class SmsQrData {
  final String phoneNumber;
  final String message;

  const SmsQrData({
    required this.phoneNumber,
    required this.message,
  });
}

/// Unified parsed data for a Contact card (vCard or MECARD).
class ContactQrData {
  final String fullName;
  final String? givenName;
  final String? familyName;
  final List<String> phones;
  final List<String> emails;
  final String? organization;
  final String? title;
  final String? website;
  final String? address;
  final String? notes;
  final bool isVCard;

  const ContactQrData({
    required this.fullName,
    this.givenName,
    this.familyName,
    required this.phones,
    required this.emails,
    this.organization,
    this.title,
    this.website,
    this.address,
    this.notes,
    required this.isVCard,
  });
}

/// Parsed data for an iCalendar / VEVENT calendar event.
class CalendarEventQrData {
  final String summary;
  final String? description;
  final String? location;
  final DateTime? dtStart;
  final DateTime? dtEnd;
  final String? rawDtStart;
  final String? rawDtEnd;

  const CalendarEventQrData({
    required this.summary,
    this.description,
    this.location,
    this.dtStart,
    this.dtEnd,
    this.rawDtStart,
    this.rawDtEnd,
  });
}

/// Parsed data for a recognized application or custom deep link.
class AppLinkQrData {
  final String uri;
  final String scheme;
  final bool isSafeToOpen;

  const AppLinkQrData({
    required this.uri,
    required this.scheme,
    this.isSafeToOpen = false,
  });
}

/// Parsed data for plain text content.
class TextQrData {
  final String text;

  const TextQrData({required this.text});
}

/// Parsed data for unknown, unsupported, or proprietary QR formats.
class UnknownQrData {
  final String rawContent;
  final String message;

  const UnknownQrData({
    required this.rawContent,
    this.message = "We don't recognize this QR format.",
  });
}

/// A privacy-safe record of a recently scanned QR code for local history.
///
/// NOTE: Passwords and sensitive session tokens are strictly EXCLUDED.
class RecentQrScan {
  final String id;
  final QrContentType type;
  final String displayTitle;
  final String displaySubtitle;
  final String safePayload;
  final DateTime scannedAt;

  const RecentQrScan({
    required this.id,
    required this.type,
    required this.displayTitle,
    required this.displaySubtitle,
    required this.safePayload,
    required this.scannedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'displayTitle': displayTitle,
        'displaySubtitle': displaySubtitle,
        'safePayload': safePayload,
        'scannedAt': scannedAt.toIso8601String(),
      };

  factory RecentQrScan.fromJson(Map<String, dynamic> json) {
    return RecentQrScan(
      id: json['id'] as String? ?? '',
      type: QrContentType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => QrContentType.unknown,
      ),
      displayTitle: json['displayTitle'] as String? ?? '',
      displaySubtitle: json['displaySubtitle'] as String? ?? '',
      safePayload: json['safePayload'] as String? ?? '',
      scannedAt: json['scannedAt'] != null
          ? DateTime.tryParse(json['scannedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
