import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../models/qr/qr_content_type.dart';
import '../../models/qr/qr_scan_models.dart';

/// Privacy-safe, on-device local storage for recent QR scans.
///
/// Strictly guarantees:
/// 1. Wi-Fi passwords are NEVER stored in recent scan history.
/// 2. No cloud sync, no tracking, no backend involvement.
/// 3. Maximum of 20 items stored (FIFO eviction).
/// 4. Provides instant Clear History.
class QrRecentScansService {
  static const String _storageKey = 'digital_share_recent_qr_scans_v1';
  static const int _maxScans = 20;

  final FlutterSecureStorage _storage;

  QrRecentScansService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  /// Retrieves list of recent scans, newest first.
  Future<List<RecentQrScan>> getRecentScans() async {
    try {
      final jsonString = await _storage.read(key: _storageKey);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded
          .map((item) => RecentQrScan.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Adds a new scan result to history with privacy sanitization.
  Future<void> addScan(QrScanResult scanResult) async {
    try {
      // 1. Build privacy-sanitized display and payload info
      String displayTitle = '';
      String displaySubtitle = '';
      String safePayload = '';

      switch (scanResult.type) {
        case QrContentType.digitalShare:
          final data = scanResult.dataAs<DigitalShareQrData>();
          displayTitle = 'Digital Share Profile';
          displaySubtitle = 'ID: ${data.shareId}';
          safePayload = data.canonicalUrl;
          break;

        case QrContentType.url:
          final data = scanResult.dataAs<UrlQrData>();
          displayTitle = 'Website';
          displaySubtitle = data.displayHost;
          safePayload = data.url;
          break;

        case QrContentType.whatsapp:
          final data = scanResult.dataAs<WhatsAppQrData>();
          displayTitle = data.hasPhone ? 'WhatsApp Chat' : 'WhatsApp';
          displaySubtitle = data.hasPhone
              ? data.phone
              : (data.hasMessage ? data.message : 'WhatsApp Link');
          safePayload = data.linkUrl;
          break;

        case QrContentType.wifi:
          final data = scanResult.dataAs<WifiQrData>();
          displayTitle = 'Wi-Fi Network';
          displaySubtitle = '${data.ssid} (${data.security})';
          // PRIVACY GUARANTEE: Password is NEVER saved to history
          safePayload = 'WIFI:S:${data.ssid};T:${data.security};;';
          break;

        case QrContentType.geo:
          final data = scanResult.dataAs<GeoQrData>();
          displayTitle = 'Location';
          if (data.latitude != null && data.longitude != null) {
            displaySubtitle = '${data.latitude!.toStringAsFixed(4)}, ${data.longitude!.toStringAsFixed(4)}';
          } else {
            displaySubtitle = data.query ?? 'Map';
          }
          safePayload = data.rawUri;
          break;

        case QrContentType.phone:
          final data = scanResult.dataAs<PhoneQrData>();
          displayTitle = 'Phone Call';
          displaySubtitle = data.phoneNumber;
          safePayload = data.rawTelUri;
          break;

        case QrContentType.email:
          final data = scanResult.dataAs<EmailQrData>();
          displayTitle = 'Email';
          displaySubtitle = data.email;
          safePayload = 'mailto:${data.email}';
          break;

        case QrContentType.sms:
          final data = scanResult.dataAs<SmsQrData>();
          displayTitle = 'SMS Message';
          displaySubtitle = data.phoneNumber;
          safePayload = 'sms:${data.phoneNumber}';
          break;

        case QrContentType.vcard:
        case QrContentType.mecard:
          final data = scanResult.dataAs<ContactQrData>();
          displayTitle = 'Contact';
          displaySubtitle = data.fullName;
          safePayload = data.phones.isNotEmpty ? data.phones.first : data.fullName;
          break;

        case QrContentType.event:
          final data = scanResult.dataAs<CalendarEventQrData>();
          displayTitle = 'Calendar Event';
          displaySubtitle = data.summary;
          safePayload = data.summary;
          break;

        case QrContentType.appLink:
          final data = scanResult.dataAs<AppLinkQrData>();
          displayTitle = 'App Link';
          displaySubtitle = '${data.scheme}://...';
          safePayload = data.uri;
          break;

        case QrContentType.text:
          final data = scanResult.dataAs<TextQrData>();
          displayTitle = 'Plain Text';
          final singleLine = data.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          displaySubtitle = singleLine.length > 40
              ? '${singleLine.substring(0, 40)}...'
              : singleLine;
          safePayload = data.text;
          break;

        case QrContentType.unknown:
          displayTitle = 'QR Code';
          displaySubtitle = 'Unrecognized content';
          safePayload = scanResult.rawValue.length > 50
              ? '${scanResult.rawValue.substring(0, 50)}...'
              : scanResult.rawValue;
          break;
      }

      final newScan = RecentQrScan(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: scanResult.type,
        displayTitle: displayTitle,
        displaySubtitle: displaySubtitle,
        safePayload: safePayload,
        scannedAt: DateTime.now(),
      );

      final current = await getRecentScans();
      // Add to front, remove duplicates of same safePayload
      current.removeWhere((item) => item.safePayload == safePayload);
      current.insert(0, newScan);

      // Keep up to max items
      final trimmedList = current.length > _maxScans
          ? current.sublist(0, _maxScans)
          : current;

      final encoded = jsonEncode(trimmedList.map((e) => e.toJson()).toList());
      await _storage.write(key: _storageKey, value: encoded);
    } catch (_) {
      // Storage operations handle errors gracefully without crashing scanner
    }
  }

  /// Clears all stored scan history.
  Future<void> clearHistory() async {
    try {
      await _storage.delete(key: _storageKey);
    } catch (_) {}
  }
}
