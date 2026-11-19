import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Official hosted legal URLs for Medindia / Digital Share.
class LegalUrls {
  LegalUrls._();

  /// Official hosted Privacy Centre URL
  static const String privacyCentre =
      'https://alphaprojectmedindia.github.io/Privacy_Policy_URL_Medindia/';

  /// Official hosted Terms and Conditions HTML page
  static const String termsAndConditions =
      'https://alphaprojectmedindia.github.io/Privacy_Policy_URL_Medindia/terms-and-conditions.html';

  /// Official hosted Privacy Policy HTML page
  static const String privacyPolicy =
      'https://alphaprojectmedindia.github.io/Privacy_Policy_URL_Medindia/privacy-policy.html';

  /// Launches a legal URL safely with inAppBrowserView fallback to externalApplication.
  static Future<bool> launchLegalUrl(String urlStr) async {
    try {
      final uri = Uri.parse(urlStr);
      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) {
        debugPrint('[LegalUrls] Cannot launch URI: $urlStr');
        return false;
      }
      return await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      );
    } catch (e) {
      debugPrint('[LegalUrls] Error launching in-app browser, trying external: $e');
      try {
        final uri = Uri.parse(urlStr);
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } catch (err) {
        debugPrint('[LegalUrls] Error launching external browser: $err');
        return false;
      }
    }
  }

  /// Opens the official Terms and Conditions hosted page.
  static Future<bool> openTermsAndConditions() =>
      launchLegalUrl(termsAndConditions);

  /// Opens the official Privacy Policy hosted page.
  static Future<bool> openPrivacyPolicy() =>
      launchLegalUrl(privacyPolicy);

  /// Opens the official Privacy Centre hosted page.
  static Future<bool> openPrivacyCentre() =>
      launchLegalUrl(privacyCentre);
}
