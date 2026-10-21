import '../../config/api_config.dart';
import '../../models/qr/qr_content_type.dart';
import '../../models/qr/qr_scan_models.dart';

/// Pure, deterministic on-device parser for classifying and extracting
/// structured QR code data according to international QR conventions.
class QrContentParser {
  const QrContentParser();

  /// Maximum characters allowed for QR content to prevent memory exhaustion
  /// or regex catastrophic backtracking.
  static const int maxContentLength = 8192;

  /// Parses [rawValue] into a strongly typed [QrScanResult].
  static QrScanResult parse(String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) {
      return const QrScanResult(
        type: QrContentType.unknown,
        rawValue: '',
        parsedData: UnknownQrData(
          rawContent: '',
          message: 'Empty QR code.',
        ),
      );
    }

    // Safety guard against oversized inputs
    final String sanitizedRaw = rawValue.length > maxContentLength
        ? rawValue.substring(0, maxContentLength)
        : rawValue;

    final trimmed = sanitizedRaw.trim();

    // 1. Digital Share Profile QR (Highest Priority)
    // Check canonical Digital Share URL format or direct ShareId format
    final shareId = ApiConfig.extractShareId(trimmed);
    if (shareId != null) {
      // Validate that it either starts with the digital share prefix or is a pure share identifier
      final isCanonicalUrl = trimmed.toLowerCase().startsWith('https://digitalshare.app/s/') ||
          trimmed.toLowerCase().startsWith('http://digitalshare.app/s/') ||
          trimmed.toLowerCase().startsWith('digitalshare.app/s/');

      // If it has a URL scheme that is NOT digitalshare.app, reject as digital share
      final hasOtherScheme = trimmed.contains('://') && !isCanonicalUrl;

      if (!hasOtherScheme) {
        return QrScanResult(
          type: QrContentType.digitalShare,
          rawValue: sanitizedRaw,
          parsedData: DigitalShareQrData(
            shareId: shareId,
            canonicalUrl: ApiConfig.buildShareUrl(shareId),
          ),
        );
      }
    }

    final lower = trimmed.toLowerCase();

    // 2. Wi-Fi Configuration (WIFI:T:...;S:...;P:...;;)
    if (lower.startsWith('wifi:')) {
      final wifi = _parseWifi(trimmed);
      if (wifi != null) {
        return QrScanResult(
          type: QrContentType.wifi,
          rawValue: sanitizedRaw,
          parsedData: wifi,
        );
      }
    }

    // 3. vCard Contact Card (BEGIN:VCARD ... END:VCARD)
    if (lower.contains('begin:vcard') && lower.contains('end:vcard')) {
      final vcard = _parseVCard(trimmed);
      if (vcard != null) {
        return QrScanResult(
          type: QrContentType.vcard,
          rawValue: sanitizedRaw,
          parsedData: vcard,
        );
      }
    }

    // 4. MECARD Contact Card (MECARD:N:...;TEL:...;;)
    if (lower.startsWith('mecard:')) {
      final mecard = _parseMeCard(trimmed);
      if (mecard != null) {
        return QrScanResult(
          type: QrContentType.mecard,
          rawValue: sanitizedRaw,
          parsedData: mecard,
        );
      }
    }

    // 5. Calendar Event (BEGIN:VEVENT ... END:VEVENT)
    if (lower.contains('begin:vevent') && lower.contains('end:vevent')) {
      final event = _parseCalendarEvent(trimmed);
      if (event != null) {
        return QrScanResult(
          type: QrContentType.event,
          rawValue: sanitizedRaw,
          parsedData: event,
        );
      }
    }

    // 6. WhatsApp Direct Chat Links
    // Matches wa.me/..., api.whatsapp.com/send, or whatsapp://send
    if (_isWhatsAppUri(lower)) {
      final wa = _parseWhatsApp(trimmed);
      if (wa != null) {
        return QrScanResult(
          type: QrContentType.whatsapp,
          rawValue: sanitizedRaw,
          parsedData: wa,
        );
      }
    }

    // 7. Geographic Location (geo:lat,lng or Google Maps links)
    if (lower.startsWith('geo:') || _isGoogleMapsUrl(lower)) {
      final geo = _parseGeo(trimmed);
      if (geo != null) {
        return QrScanResult(
          type: QrContentType.geo,
          rawValue: sanitizedRaw,
          parsedData: geo,
        );
      }
    }

    // 8. Telephone Links (tel:+...)
    if (lower.startsWith('tel:')) {
      final phone = _parsePhone(trimmed);
      if (phone != null) {
        return QrScanResult(
          type: QrContentType.phone,
          rawValue: sanitizedRaw,
          parsedData: phone,
        );
      }
    }

    // 9. Email Links (mailto:...)
    if (lower.startsWith('mailto:')) {
      final email = _parseEmail(trimmed);
      if (email != null) {
        return QrScanResult(
          type: QrContentType.email,
          rawValue: sanitizedRaw,
          parsedData: email,
        );
      }
    }

    // 10. SMS Links (sms:... or SMSTO:...)
    if (lower.startsWith('sms:') || lower.startsWith('smsto:')) {
      final sms = _parseSms(trimmed);
      if (sms != null) {
        return QrScanResult(
          type: QrContentType.sms,
          rawValue: sanitizedRaw,
          parsedData: sms,
        );
      }
    }

    // 11. Security Check: Reject dangerous URI schemes
    if (_isDangerousUriScheme(lower)) {
      return QrScanResult(
        type: QrContentType.unknown,
        rawValue: sanitizedRaw,
        parsedData: UnknownQrData(
          rawContent: sanitizedRaw,
          message: 'Unsupported or blocked URI scheme for security.',
        ),
      );
    }

    // 12. Standard HTTP/HTTPS Website URL
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      final urlData = _parseUrl(trimmed);
      if (urlData != null) {
        return QrScanResult(
          type: QrContentType.url,
          rawValue: sanitizedRaw,
          parsedData: urlData,
        );
      }
    }

    // 13. Custom App / Deep Links (scheme://path)
    if (_isCustomAppScheme(trimmed)) {
      final appLink = _parseAppLink(trimmed);
      if (appLink != null) {
        return QrScanResult(
          type: QrContentType.appLink,
          rawValue: sanitizedRaw,
          parsedData: appLink,
        );
      }
    }

    // 14. Default fallback: Plain Text
    return QrScanResult(
      type: QrContentType.text,
      rawValue: sanitizedRaw,
      parsedData: TextQrData(text: sanitizedRaw),
    );
  }

  // ---------------------------------------------------------------------------
  // Wi-Fi Parser
  // ---------------------------------------------------------------------------
  static WifiQrData? _parseWifi(String raw) {
    try {
      // Format: WIFI:T:WPA;S:MySSID;P:myPassword;H:false;;
      final content = raw.substring(raw.indexOf(':') + 1);
      final fields = _parseEscapedDelimitedFields(content, ';');

      String ssid = '';
      String security = 'nopass';
      String password = '';
      bool isHidden = false;

      for (final entry in fields) {
        final colonIdx = entry.indexOf(':');
        if (colonIdx <= 0) continue;

        final key = entry.substring(0, colonIdx).toUpperCase().trim();
        final val = entry.substring(colonIdx + 1);

        switch (key) {
          case 'S':
            ssid = val;
            break;
          case 'T':
            final secUpper = val.toUpperCase().trim();
            if (secUpper == 'WEP') {
              security = 'WEP';
            } else if (secUpper == 'NOPASS' || secUpper == 'NONE') {
              security = 'nopass';
            } else {
              security = val.trim().isNotEmpty ? val.trim() : 'WPA';
            }
            break;
          case 'P':
            password = val;
            break;
          case 'H':
            isHidden = val.toLowerCase().trim() == 'true';
            break;
        }
      }

      if (ssid.isEmpty && password.isEmpty) return null;

      return WifiQrData(
        ssid: ssid,
        security: security,
        password: password,
        isHidden: isHidden,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // vCard Parser (RFC 2426 / RFC 6350)
  // ---------------------------------------------------------------------------
  static ContactQrData? _parseVCard(String raw) {
    try {
      // 1. Unfold lines: RFC allows long lines to be folded with a leading space or tab
      final rawLines = raw.split(RegExp(r'\r?\n'));
      final unfoldedLines = <String>[];
      for (final line in rawLines) {
        if (line.startsWith(' ') || line.startsWith('\t')) {
          if (unfoldedLines.isNotEmpty) {
            unfoldedLines[unfoldedLines.length - 1] += line.substring(1);
          }
        } else if (line.trim().isNotEmpty) {
          unfoldedLines.add(line.trim());
        }
      }

      String fullName = '';
      String? familyName;
      String? givenName;
      final phones = <String>[];
      final emails = <String>[];
      String? organization;
      String? title;
      String? website;
      String? address;
      String? notes;

      for (final line in unfoldedLines) {
        final colonIdx = line.indexOf(':');
        if (colonIdx <= 0) continue;

        final header = line.substring(0, colonIdx).toUpperCase();
        final rawVal = line.substring(colonIdx + 1).trim();
        final val = _unescapeVCardValue(rawVal);

        if (header == 'FN') {
          fullName = val;
        } else if (header == 'N' || header.startsWith('N;')) {
          // Format: Family;Given;Additional;Prefix;Suffix
          final parts = val.split(';');
          if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
            familyName = parts[0].trim();
          }
          if (parts.length > 1 && parts[1].trim().isNotEmpty) {
            givenName = parts[1].trim();
          }
        } else if (header == 'TEL' || header.startsWith('TEL;') || header.startsWith('TEL:')) {
          final cleanPhone = val.trim();
          if (cleanPhone.isNotEmpty && !phones.contains(cleanPhone)) {
            phones.add(cleanPhone);
          }
        } else if (header == 'EMAIL' || header.startsWith('EMAIL;') || header.startsWith('EMAIL:')) {
          final cleanEmail = val.trim();
          if (cleanEmail.isNotEmpty && !emails.contains(cleanEmail)) {
            emails.add(cleanEmail);
          }
        } else if (header == 'ORG' || header.startsWith('ORG;')) {
          final orgParts = val.split(';');
          organization = orgParts.first.trim();
        } else if (header == 'TITLE' || header.startsWith('TITLE;')) {
          title = val;
        } else if (header == 'URL' || header.startsWith('URL;')) {
          website = val;
        } else if (header == 'ADR' || header.startsWith('ADR;')) {
          // Format: postOffice;extended;street;locality;region;postalCode;country
          final adrParts = val
              .split(';')
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toList();
          if (adrParts.isNotEmpty) {
            address = adrParts.join(', ');
          }
        } else if (header == 'NOTE' || header.startsWith('NOTE;')) {
          notes = val;
        }
      }

      // Fallback for full name if only N was provided
      if (fullName.isEmpty) {
        final nameParts = [givenName, familyName].where((n) => n != null && n.isNotEmpty).join(' ');
        fullName = nameParts.isNotEmpty ? nameParts : 'Unknown Contact';
      }

      return ContactQrData(
        fullName: fullName,
        givenName: givenName,
        familyName: familyName,
        phones: phones,
        emails: emails,
        organization: organization,
        title: title,
        website: website,
        address: address,
        notes: notes,
        isVCard: true,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // MECARD Parser
  // ---------------------------------------------------------------------------
  static ContactQrData? _parseMeCard(String raw) {
    try {
      final content = raw.substring(raw.indexOf(':') + 1);
      final fields = _parseEscapedDelimitedFields(content, ';');

      String fullName = '';
      String? familyName;
      String? givenName;
      final phones = <String>[];
      final emails = <String>[];
      String? organization;
      String? address;
      String? website;
      String? notes;

      for (final entry in fields) {
        final colonIdx = entry.indexOf(':');
        if (colonIdx <= 0) continue;

        final key = entry.substring(0, colonIdx).toUpperCase().trim();
        final val = entry.substring(colonIdx + 1).trim();

        switch (key) {
          case 'N':
            // Format: Last,First or Name
            final commaIdx = val.indexOf(',');
            if (commaIdx > 0) {
              familyName = val.substring(0, commaIdx).trim();
              givenName = val.substring(commaIdx + 1).trim();
              fullName = '$givenName $familyName'.trim();
            } else {
              fullName = val;
            }
            break;
          case 'TEL':
            if (val.isNotEmpty && !phones.contains(val)) {
              phones.add(val);
            }
            break;
          case 'EMAIL':
            if (val.isNotEmpty && !emails.contains(val)) {
              emails.add(val);
            }
            break;
          case 'ADR':
            address = val;
            break;
          case 'URL':
            website = val;
            break;
          case 'NOTE':
            notes = val;
            break;
          case 'ORG':
            organization = val;
            break;
        }
      }

      if (fullName.isEmpty && phones.isEmpty && emails.isEmpty) {
        return null;
      }

      return ContactQrData(
        fullName: fullName.isNotEmpty ? fullName : 'Contact',
        givenName: givenName,
        familyName: familyName,
        phones: phones,
        emails: emails,
        organization: organization,
        website: website,
        address: address,
        notes: notes,
        isVCard: false,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Calendar Event Parser (iCalendar / VEVENT)
  // ---------------------------------------------------------------------------
  static CalendarEventQrData? _parseCalendarEvent(String raw) {
    try {
      final rawLines = raw.split(RegExp(r'\r?\n'));
      String summary = '';
      String? description;
      String? location;
      String? rawDtStart;
      String? rawDtEnd;
      DateTime? dtStart;
      DateTime? dtEnd;

      for (final line in rawLines) {
        final colonIdx = line.indexOf(':');
        if (colonIdx <= 0) continue;

        final header = line.substring(0, colonIdx).toUpperCase().trim();
        final val = line.substring(colonIdx + 1).trim();

        if (header == 'SUMMARY' || header.startsWith('SUMMARY;')) {
          summary = val;
        } else if (header == 'DESCRIPTION' || header.startsWith('DESCRIPTION;')) {
          description = val;
        } else if (header == 'LOCATION' || header.startsWith('LOCATION;')) {
          location = val;
        } else if (header == 'DTSTART' || header.startsWith('DTSTART;')) {
          rawDtStart = val;
          dtStart = _parseICalDate(val);
        } else if (header == 'DTEND' || header.startsWith('DTEND;')) {
          rawDtEnd = val;
          dtEnd = _parseICalDate(val);
        }
      }

      if (summary.isEmpty && rawDtStart == null) return null;

      return CalendarEventQrData(
        summary: summary.isNotEmpty ? summary : 'Event',
        description: description,
        location: location,
        dtStart: dtStart,
        dtEnd: dtEnd,
        rawDtStart: rawDtStart,
        rawDtEnd: rawDtEnd,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // WhatsApp Link Parser
  // ---------------------------------------------------------------------------
  static bool _isWhatsAppUri(String lower) {
    if (lower.startsWith('whatsapp://send')) {
      return true;
    }

    String toCheck = lower;
    if (!toCheck.contains('://')) {
      if (toCheck.startsWith('wa.me') || toCheck.startsWith('api.whatsapp.com')) {
        toCheck = 'https://$toCheck';
      } else {
        return false;
      }
    }

    final uri = Uri.tryParse(toCheck);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;

    final host = uri.host.toLowerCase();
    if (host == 'wa.me' || host == 'www.wa.me') {
      return true;
    }
    if (host == 'api.whatsapp.com') {
      final path = uri.path.toLowerCase();
      return path == '/send' || path.startsWith('/send/') || path.isEmpty;
    }

    return false;
  }

  static WhatsAppQrData? _parseWhatsApp(String raw) {
    try {
      String phone = '';
      String message = '';
      String linkUrl = raw.trim();

      final lower = raw.toLowerCase().trim();

      if (lower.startsWith('whatsapp://')) {
        final uri = Uri.tryParse(linkUrl);
        if (uri == null) return null;
        if (uri.scheme.toLowerCase() != 'whatsapp') return null;
        final hostAndPath = '${uri.host}${uri.path}'.toLowerCase();
        if (!hostAndPath.contains('send')) return null;

        phone = uri.queryParameters['phone'] ?? '';
        message = uri.queryParameters['text'] ?? '';
      } else {
        if (!linkUrl.toLowerCase().startsWith('http://') &&
            !linkUrl.toLowerCase().startsWith('https://')) {
          linkUrl = 'https://$linkUrl';
        }

        final uri = Uri.tryParse(linkUrl);
        if (uri == null) return null;

        final host = uri.host.toLowerCase();
        if (host != 'wa.me' && host != 'www.wa.me' && host != 'api.whatsapp.com') {
          return null;
        }

        if (host == 'wa.me' || host == 'www.wa.me') {
          final segments = uri.pathSegments;
          if (segments.isNotEmpty) {
            final firstSegment = segments.first.trim();
            if (firstSegment.toLowerCase() == 'send') {
              phone = uri.queryParameters['phone'] ?? '';
            } else if (firstSegment.isNotEmpty) {
              phone = firstSegment;
            }
          }
          message = uri.queryParameters['text'] ?? '';
        } else if (host == 'api.whatsapp.com') {
          phone = uri.queryParameters['phone'] ?? '';
          message = uri.queryParameters['text'] ?? '';
        }
      }

      phone = phone.trim();
      if (phone.isNotEmpty) {
        final hasPlus = phone.startsWith('+');
        final digits = phone.replaceAll(RegExp(r'\D'), '');
        if (digits.isNotEmpty) {
          phone = hasPlus ? '+$digits' : digits;
        } else {
          phone = '';
        }
      }

      // At least a recipient phone or a non-empty pre-filled message must be present
      if (phone.isEmpty && message.trim().isEmpty) {
        return null;
      }

      return WhatsAppQrData(
        phone: phone,
        message: message,
        linkUrl: linkUrl,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Geographic / Maps Parser
  // ---------------------------------------------------------------------------
  static bool _isGoogleMapsUrl(String lower) {
    return lower.startsWith('https://maps.google.com') ||
        lower.startsWith('http://maps.google.com') ||
        lower.startsWith('https://www.google.com/maps') ||
        lower.startsWith('http://www.google.com/maps') ||
        lower.startsWith('https://maps.app.goo.gl') ||
        lower.startsWith('https://goo.gl/maps');
  }

  static GeoQrData? _parseGeo(String raw) {
    try {
      if (raw.toLowerCase().startsWith('geo:')) {
        // Format: geo:13.0827,80.2707 or geo:13.0827,80.2707?q=... or geo:0,0?q=Chennai
        final content = raw.substring(4);
        final parts = content.split('?');
        final coordsPart = parts.first;
        final queryPart = parts.length > 1 ? parts[1] : null;

        double? lat;
        double? lng;
        String? query;

        final coordSplit = coordsPart.split(',');
        if (coordSplit.length >= 2) {
          final parsedLat = double.tryParse(coordSplit[0].trim());
          final parsedLng = double.tryParse(coordSplit[1].trim());

          if (parsedLat != null && parsedLng != null) {
            // Coordinate validity validation
            if (parsedLat >= -90.0 && parsedLat <= 90.0 && parsedLng >= -180.0 && parsedLng <= 180.0) {
              lat = parsedLat;
              lng = parsedLng;
            }
          }
        }

        if (queryPart != null && queryPart.startsWith('q=')) {
          query = Uri.decodeComponent(queryPart.substring(2));
        }

        return GeoQrData(
          latitude: lat,
          longitude: lng,
          query: query,
          rawUri: raw,
        );
      } else {
        // Google Maps URL
        return GeoQrData(
          rawUri: raw,
          query: raw,
        );
      }
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Phone Parser
  // ---------------------------------------------------------------------------
  static PhoneQrData? _parsePhone(String raw) {
    try {
      final number = raw.substring(raw.indexOf(':') + 1).trim();
      if (number.isEmpty) return null;
      return PhoneQrData(
        phoneNumber: number,
        rawTelUri: raw,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Email Parser
  // ---------------------------------------------------------------------------
  static EmailQrData? _parseEmail(String raw) {
    try {
      final uri = Uri.tryParse(raw);
      if (uri == null) return null;

      final recipient = uri.path.trim();
      final subject = uri.queryParameters['subject'] ?? '';
      final body = uri.queryParameters['body'] ?? '';
      final cc = uri.queryParameters['cc'];
      final bcc = uri.queryParameters['bcc'];

      if (recipient.isEmpty && subject.isEmpty && body.isEmpty) return null;

      return EmailQrData(
        email: recipient,
        subject: subject,
        body: body,
        cc: cc,
        bcc: bcc,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // SMS Parser
  // ---------------------------------------------------------------------------
  static SmsQrData? _parseSms(String raw) {
    try {
      final lower = raw.toLowerCase();
      String phone = '';
      String message = '';

      if (lower.startsWith('smsto:')) {
        // Format: SMSTO:+919876543210:Hello message
        final afterPrefix = raw.substring(6);
        final colonIdx = afterPrefix.indexOf(':');
        if (colonIdx > 0) {
          phone = afterPrefix.substring(0, colonIdx).trim();
          message = afterPrefix.substring(colonIdx + 1).trim();
        } else {
          phone = afterPrefix.trim();
        }
      } else if (lower.startsWith('sms:')) {
        // Format: sms:+919876543210?body=Hello or sms:+919876543210:Hello
        final afterPrefix = raw.substring(4);
        if (afterPrefix.contains('?')) {
          final uri = Uri.tryParse(raw);
          if (uri != null) {
            phone = uri.path.trim();
            message = uri.queryParameters['body'] ?? '';
          }
        } else if (afterPrefix.contains(':')) {
          final colonIdx = afterPrefix.indexOf(':');
          phone = afterPrefix.substring(0, colonIdx).trim();
          message = afterPrefix.substring(colonIdx + 1).trim();
        } else {
          phone = afterPrefix.trim();
        }
      }

      if (phone.isEmpty && message.isEmpty) return null;

      return SmsQrData(
        phoneNumber: phone,
        message: message,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Website URL Parser
  // ---------------------------------------------------------------------------
  static UrlQrData? _parseUrl(String raw) {
    try {
      final uri = Uri.tryParse(raw);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

      final isSecure = uri.scheme.toLowerCase() == 'https';
      return UrlQrData(
        url: raw,
        displayHost: uri.host,
        isSecure: isSecure,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // App Link / Custom Scheme Parser
  // ---------------------------------------------------------------------------
  static bool _isCustomAppScheme(String raw) {
    final colonIdx = raw.indexOf('://');
    if (colonIdx <= 0) return false;
    final scheme = raw.substring(0, colonIdx).toLowerCase();
    return scheme.isNotEmpty &&
        RegExp(r'^[a-z0-9+.-]+$').hasMatch(scheme) &&
        scheme != 'http' &&
        scheme != 'https';
  }

  static AppLinkQrData? _parseAppLink(String raw) {
    try {
      final colonIdx = raw.indexOf('://');
      if (colonIdx <= 0) return null;
      final scheme = raw.substring(0, colonIdx).toLowerCase();

      return AppLinkQrData(
        uri: raw,
        scheme: scheme,
        isSafeToOpen: false, // Default safe policy: explicit confirmation required
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers & Security Guards
  // ---------------------------------------------------------------------------
  static bool _isDangerousUriScheme(String lower) {
    return lower.startsWith('javascript:') ||
        lower.startsWith('data:') ||
        lower.startsWith('file:') ||
        lower.startsWith('blob:') ||
        lower.startsWith('content:');
  }

  /// Parses fields delimited by [delimiter] while respecting backslash escaping (\;, \:, \\, \,).
  static List<String> _parseEscapedDelimitedFields(String input, String delimiter) {
    final results = <String>[];
    final buffer = StringBuffer();
    bool isEscaped = false;

    for (int i = 0; i < input.length; i++) {
      final char = input[i];

      if (isEscaped) {
        buffer.write(char);
        isEscaped = false;
      } else if (char == '\\') {
        isEscaped = true;
      } else if (char == delimiter) {
        final field = buffer.toString().trim();
        if (field.isNotEmpty) {
          results.add(field);
        }
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty) {
      results.add(remaining);
    }

    return results;
  }

  static String _unescapeVCardValue(String value) {
    return value
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';')
        .replaceAll(r'\\', r'\')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\N', '\n');
  }

  static DateTime? _parseICalDate(String raw) {
    try {
      // Formats: 20261025T090000Z or 20261025T090000 or 20261025
      final clean = raw.replaceAll(RegExp(r'[^0-9T]'), '');
      if (clean.length == 8) {
        // YYYYMMDD
        final year = int.parse(clean.substring(0, 4));
        final month = int.parse(clean.substring(4, 6));
        final day = int.parse(clean.substring(6, 8));
        return DateTime(year, month, day);
      } else if (clean.length >= 15 && clean.contains('T')) {
        // YYYYMMDDTHHMMSS
        final parts = clean.split('T');
        final d = parts[0];
        final t = parts[1];
        final year = int.parse(d.substring(0, 4));
        final month = int.parse(d.substring(4, 6));
        final day = int.parse(d.substring(6, 8));
        final hour = int.parse(t.substring(0, 2));
        final min = int.parse(t.substring(2, 4));
        final sec = int.parse(t.substring(4, 6));
        return DateTime(year, month, day, hour, min, sec);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
