/// Represents the recognized content type of a scanned QR code.
enum QrContentType {
  /// Digital Share user profile QR (canonical shareId URL or direct shareId).
  digitalShare,

  /// Safe HTTP or HTTPS website URL.
  url,

  /// WhatsApp direct-chat or contact link (wa.me, api.whatsapp.com).
  whatsapp,

  /// Standard Wi-Fi configuration (WIFI:T:...;S:...;P:...;;).
  wifi,

  /// Geographic coordinates or map link (geo:lat,lng or Google Maps).
  geo,

  /// Direct telephone number link (tel:...).
  phone,

  /// Direct email composition link (mailto:...).
  email,

  /// Direct SMS composition link (sms:... or SMSTO:...).
  sms,

  /// Contact card in vCard format (BEGIN:VCARD ... END:VCARD).
  vcard,

  /// Contact card in MECARD format (MECARD:N:...;TEL:...;;).
  mecard,

  /// Calendar event in iCalendar format (BEGIN:VEVENT ... END:VEVENT).
  event,

  /// Recognized application or deep link.
  appLink,

  /// Plain Unicode text.
  text,

  /// Unrecognized or proprietary format (safely displayed without executing).
  unknown,
}
