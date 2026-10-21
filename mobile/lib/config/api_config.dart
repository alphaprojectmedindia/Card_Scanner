class ApiConfig {
  ApiConfig._();

  /// Reads base URL from `--dart-define=API_BASE_URL=...` at compile/run time.
  /// Falls back to `http://10.0.2.2:5000` for Android emulator compatibility or `http://localhost:5000`.
  static const String _defaultBaseUrl = 'http://10.0.2.2:5000';

  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) {
      return fromEnv.endsWith('/')
          ? fromEnv.substring(0, fromEnv.length - 1)
          : fromEnv;
    }
    return _defaultBaseUrl;
  }

  // Auth endpoints
  static String get registerEndpoint => '$baseUrl/api/auth/register';
  static String get loginEndpoint => '$baseUrl/api/auth/login';
  static String get refreshEndpoint => '$baseUrl/api/auth/refresh';
  static String get logoutEndpoint => '$baseUrl/api/auth/logout';
  static String get logoutAllEndpoint => '$baseUrl/api/auth/logout-all';

  // Profile endpoints
  static String get profileMeEndpoint => '$baseUrl/api/profile/me';
  static String get uploadProfilePhotoEndpoint => '$baseUrl/api/profile/photo';

  /// Resolves an image path or URL. If the image is stored locally on the server
  /// with a relative path (e.g. `/uploads/profile-photos/...`), it resolves it against [baseUrl].
  /// If it is already an absolute HTTP/HTTPS URL, returns it unchanged.
  static String? resolveImageUrl(String? pathOrUrl) {
    if (pathOrUrl == null || pathOrUrl.trim().isEmpty) {
      return null;
    }
    final trimmed = pathOrUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final base = baseUrl;
    if (trimmed.startsWith('/')) {
      return '$base$trimmed';
    }
    return '$base/$trimmed';
  }

  // Public Share endpoints
  static String getShareEndpoint(String shareId) => '$baseUrl/api/share/$shareId';

  // Connections endpoints
  static String get connectionsEndpoint => '$baseUrl/api/connections';
  static String deleteConnectionEndpoint(String shareId) => '$baseUrl/api/connections/$shareId';

  // Imported Contacts endpoints
  static String get importedContactsEndpoint => '$baseUrl/api/imported-contacts';
  static String get checkDuplicateImportedContactEndpoint => '$baseUrl/api/imported-contacts/check-duplicate';
  static String importedContactByIdEndpoint(String id) => '$baseUrl/api/imported-contacts/$id';

  // Availability endpoints
  static String get availabilityMeEndpoint => '$baseUrl/api/availability/me';
  static String availabilityUserEndpoint(String userId) => '$baseUrl/api/availability/$userId';

  // Meetings endpoints
  static String get meetingsEndpoint => '$baseUrl/api/meetings';
  static String meetingByIdEndpoint(String id) => '$baseUrl/api/meetings/$id';
  static String acceptMeetingEndpoint(String id) => '$baseUrl/api/meetings/$id/accept';
  static String rejectMeetingEndpoint(String id) => '$baseUrl/api/meetings/$id/reject';
  static String cancelMeetingEndpoint(String id) => '$baseUrl/api/meetings/$id/cancel';

  // Canonical QR code URL scheme
  static const String shareUrlPrefix = 'https://digitalshare.app/s/';

  /// Generates the canonical URL encoded inside the user's QR code.
  static String buildShareUrl(String shareId) {
    return '$shareUrlPrefix$shareId';
  }

  /// Strictly validates and extracts a ShareId from scanned QR text.
  /// Rejects arbitrary websites, malformed URLs, and non-conforming formats.
  static String? extractShareId(String? rawContent) {
    if (rawContent == null || rawContent.trim().isEmpty) {
      return null;
    }

    final trimmed = rawContent.trim();

    String potentialShareId = '';

    // Check canonical URL format: https://digitalshare.app/s/<shareId>
    if (trimmed.startsWith('https://digitalshare.app/s/')) {
      potentialShareId = trimmed.substring('https://digitalshare.app/s/'.length);
    } else if (trimmed.startsWith('http://digitalshare.app/s/')) {
      potentialShareId = trimmed.substring('http://digitalshare.app/s/'.length);
    } else if (trimmed.startsWith('digitalshare.app/s/')) {
      potentialShareId = trimmed.substring('digitalshare.app/s/'.length);
    } else if (!trimmed.contains('://') && !trimmed.contains('/')) {
      // Allow direct shareId scan if formatted as pure identifier
      potentialShareId = trimmed;
    } else {
      // External / arbitrary website or invalid scheme
      return null;
    }

    // Clean any trailing slashes or query parameters
    if (potentialShareId.contains('?')) {
      potentialShareId = potentialShareId.split('?').first;
    }
    if (potentialShareId.endsWith('/')) {
      potentialShareId = potentialShareId.substring(0, potentialShareId.length - 1);
    }

    // Validate alphanumeric and URL-safe characters with reasonable length bounds (16 to 50 chars)
    final validShareIdRegex = RegExp(r'^[a-zA-Z0-9_-]{16,50}$');
    if (validShareIdRegex.hasMatch(potentialShareId)) {
      return potentialShareId;
    }

    return null;
  }
}
