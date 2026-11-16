import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';
import 'secure_storage_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? details;

  ApiException(this.message, {this.statusCode, this.details});

  @override
  String toString() => message;
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(
      [super.message = 'Session expired. Please log in again.'])
      : super(statusCode: 401);
}

class ConflictException extends ApiException {
  ConflictException([super.message = 'This item already exists.'])
      : super(statusCode: 409);
}

class ApiClient {
  final http.Client _httpClient;
  final SecureStorageService _storageService;

  // Single-flight refresh coordinator
  Completer<bool>? _refreshCompleter;

  ApiClient({
    http.Client? httpClient,
    SecureStorageService? storageService,
  })  : _httpClient = httpClient ?? http.Client(),
        _storageService = storageService ?? SecureStorageService();

  Future<Map<String, String>> _buildHeaders({bool requiresAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };

    if (requiresAuth) {
      final token = await _storageService.getAuthToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  static const Duration defaultTimeout = Duration(seconds: 15);

  /// Single-flight refresh coordinator:
  /// Ensures multiple concurrent 401 requests trigger only ONE refresh operation.
  Future<bool> _coordinateRefresh() async {
    if (_refreshCompleter != null) {
      return await _refreshCompleter!.future;
    }

    final completer = Completer<bool>();
    _refreshCompleter = completer;

    try {
      final success = await _performTokenRefresh();
      completer.complete(success);
      return success;
    } catch (e) {
      completer.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  /// Performs the actual token refresh call to POST /api/auth/refresh.
  Future<bool> _performTokenRefresh() async {
    final refreshToken = await _storageService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    try {
      final response = await _httpClient
          .post(
            Uri.parse(ApiConfig.refreshEndpoint),
            headers: {
              'Content-Type': 'application/json; charset=UTF-8',
              'Accept': 'application/json',
            },
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(defaultTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final newAccessToken =
              (decoded['accessToken'] ?? decoded['token']) as String? ?? '';
          final newRefreshToken =
              (decoded['refreshToken'] ?? '') as String? ?? '';

          final accessExpiry = decoded['accessTokenExpiresAt'] != null
              ? DateTime.tryParse(decoded['accessTokenExpiresAt'] as String)
              : (decoded['expirationUtc'] != null
                  ? DateTime.tryParse(decoded['expirationUtc'] as String)
                  : null);

          final refreshExpiry = decoded['refreshTokenExpiresAt'] != null
              ? DateTime.tryParse(decoded['refreshTokenExpiresAt'] as String)
              : null;

          if (newAccessToken.isNotEmpty && newRefreshToken.isNotEmpty) {
            try {
              // Crash-safe storage update: writes new refresh token first
              await _storageService.saveAuthTokens(
                accessToken: newAccessToken,
                refreshToken: newRefreshToken,
                accessTokenExpiresAt: accessExpiry,
                refreshTokenExpiresAt: refreshExpiry,
              );
              return true;
            } catch (_) {
              return false;
            }
          }
        }
        return false;
      }

      // If server explicitly confirmed invalid / expired / revoked refresh token:
      if (response.statusCode == 400 || response.statusCode == 401) {
        await _storageService.clearAuth();
        return false;
      }

      // 5xx server errors or transient issues: DO NOT clear auth
      return false;
    } on SocketException {
      // Offline / network failure: DO NOT delete stored credentials
      return false;
    } on TimeoutException {
      // Timeout: DO NOT delete stored credentials
      return false;
    } catch (_) {
      // Other network / IO errors: DO NOT delete stored credentials
      return false;
    }
  }

  /// Executes request with single-flight token refresh on genuine 401 and retries once.
  Future<dynamic> _executeWithAuthRetry({
    required String url,
    required Future<http.Response> Function(Map<String, String> headers)
        sendRequest,
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    final headers = await _buildHeaders(requiresAuth: requiresAuth);
    final response = await _sendWithTimeout(sendRequest(headers), timeout: timeout);

    // When access token expires on an authenticated request:
    // (Ensure refresh endpoint itself never triggers automatic refresh)
    if (response.statusCode == 401 &&
        requiresAuth &&
        !url.contains('/api/auth/refresh')) {
      final refreshSuccess = await _coordinateRefresh();
      if (refreshSuccess) {
        // Re-generate headers with the newly rotated access token
        final retriedHeaders = await _buildHeaders(requiresAuth: true);
        // Retry original request ONCE. If retry returns 401 again, _processResponse throws
        // UnauthorizedException without looping.
        final retryResponse =
            await _sendWithTimeout(sendRequest(retriedHeaders), timeout: timeout);
        return _processResponse(retryResponse);
      } else {
        return _processResponse(response);
      }
    }

    return _processResponse(response);
  }

  Future<http.Response> _sendWithTimeout(Future<http.Response> future,
      {Duration? timeout}) async {
    try {
      return await future.timeout(timeout ?? defaultTimeout);
    } on TimeoutException {
      throw ApiException(
          'Connection timed out. Please check your network connection and try again.');
    } on SocketException {
      throw ApiException(
          'Unable to connect to the server. Please check your network connection.');
    } on HttpException {
      throw ApiException('Service temporarily unavailable. Please try again.');
    } on FormatException {
      throw ApiException('Unexpected server response format.');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('An unexpected network error occurred.');
    }
  }

  Future<dynamic> get(String url,
      {bool requiresAuth = true, Duration? timeout}) async {
    return _executeWithAuthRetry(
      url: url,
      requiresAuth: requiresAuth,
      timeout: timeout,
      sendRequest: (headers) =>
          _httpClient.get(Uri.parse(url), headers: headers),
    );
  }

  Future<dynamic> post(String url,
      {dynamic body, bool requiresAuth = false, Duration? timeout}) async {
    return _executeWithAuthRetry(
      url: url,
      requiresAuth: requiresAuth,
      timeout: timeout,
      sendRequest: (headers) => _httpClient.post(
        Uri.parse(url),
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      ),
    );
  }

  Future<dynamic> put(String url,
      {dynamic body, bool requiresAuth = true, Duration? timeout}) async {
    return _executeWithAuthRetry(
      url: url,
      requiresAuth: requiresAuth,
      timeout: timeout,
      sendRequest: (headers) => _httpClient.put(
        Uri.parse(url),
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      ),
    );
  }

  Future<dynamic> delete(String url,
      {bool requiresAuth = true, Duration? timeout}) async {
    return _executeWithAuthRetry(
      url: url,
      requiresAuth: requiresAuth,
      timeout: timeout,
      sendRequest: (headers) =>
          _httpClient.delete(Uri.parse(url), headers: headers),
    );
  }

  Future<dynamic> postMultipart(
    String url, {
    required String fieldName,
    String? filePath,
    List<int>? fileBytes,
    String? filename,
    String? contentType,
    Map<String, String>? fields,
    bool requiresAuth = true,
  }) async {
    Future<http.Response> sendMultipart(String? token) async {
      final request = http.MultipartRequest('POST', Uri.parse(url));

      if (fields != null && fields.isNotEmpty) {
        request.fields.addAll(fields);
      }

      if (requiresAuth && token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.headers['Accept'] = 'application/json';

      MediaType mediaType;
      if (contentType != null && contentType.contains('/')) {
        final parts = contentType.split('/');
        mediaType = MediaType(parts[0], parts[1]);
      } else {
        mediaType = MediaType('image', 'jpeg');
      }

      if (filePath != null) {
        request.files.add(await http.MultipartFile.fromPath(
          fieldName,
          filePath,
          filename: filename,
          contentType: mediaType,
        ));
      } else if (fileBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          fieldName,
          fileBytes,
          filename: filename ?? 'photo.jpg',
          contentType: mediaType,
        ));
      } else {
        throw ApiException('No file provided for upload.');
      }

      final streamedResponse = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 45));
      return await http.Response.fromStream(streamedResponse);
    }

    try {
      final initialToken =
          requiresAuth ? await _storageService.getAuthToken() : null;
      final response = await sendMultipart(initialToken);

      if (response.statusCode == 401 && requiresAuth) {
        final refreshSuccess = await _coordinateRefresh();
        if (refreshSuccess) {
          final newToken = await _storageService.getAuthToken();
          final retryResponse = await sendMultipart(newToken);
          return _processResponse(retryResponse);
        }
      }

      return _processResponse(response);
    } on TimeoutException {
      throw ApiException(
          'Upload timed out. Please check your network connection and try again.');
    } on SocketException {
      throw ApiException(
          'Unable to connect to the server. Please check your network connection.');
    } on HttpException {
      throw ApiException('Service temporarily unavailable. Please try again.');
    } on FormatException {
      throw ApiException('Unexpected server response format.');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
          'An unexpected network error occurred while uploading.');
    }
  }

  /// Manually triggers token refresh if needed.
  Future<bool> refreshTokens() => _coordinateRefresh();

  dynamic _processResponse(http.Response response) {
    dynamic jsonBody;
    if (response.body.isNotEmpty) {
      try {
        jsonBody = jsonDecode(response.body);
      } catch (_) {
        jsonBody = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonBody;
    }

    if (response.statusCode == 401) {
      throw UnauthorizedException(
        jsonBody is Map<String, dynamic> && jsonBody['message'] != null
            ? jsonBody['message'].toString()
            : 'Invalid credentials or session expired.',
      );
    }

    if (response.statusCode == 403) {
      throw ApiException(
        jsonBody is Map<String, dynamic> && jsonBody['message'] != null
            ? jsonBody['message'].toString()
            : 'You do not have permission to perform this action.',
        statusCode: 403,
      );
    }

    if (response.statusCode == 409) {
      throw ConflictException(
        jsonBody is Map<String, dynamic> && jsonBody['message'] != null
            ? jsonBody['message'].toString()
            : 'This profile is already saved.',
      );
    }

    if (response.statusCode == 404) {
      throw ApiException(
        jsonBody is Map<String, dynamic> && jsonBody['message'] != null
            ? jsonBody['message'].toString()
            : 'Requested resource was not found.',
        statusCode: 404,
      );
    }

    if (response.statusCode == 413) {
      throw ApiException(
        jsonBody is Map<String, dynamic> && jsonBody['message'] != null
            ? jsonBody['message'].toString()
            : 'The uploaded file is too large. Maximum allowed size is 5 MB.',
        statusCode: 413,
      );
    }

    if (response.statusCode == 415) {
      throw ApiException(
        jsonBody is Map<String, dynamic> && jsonBody['message'] != null
            ? jsonBody['message'].toString()
            : 'Unsupported file format. Please upload a JPEG, PNG, WebP, or GIF image.',
        statusCode: 415,
      );
    }

    if (response.statusCode == 400) {
      String errorMessage = 'Bad request.';
      if (jsonBody is Map<String, dynamic>) {
        if (jsonBody['message'] != null) {
          errorMessage = jsonBody['message'].toString();
        }

        // Check if there are validation error dictionaries
        if (jsonBody['errors'] is Map) {
          final errorsMap = jsonBody['errors'] as Map;
          final List<String> errorMessages = [];
          for (final entry in errorsMap.entries) {
            if (entry.value is List) {
              errorMessages
                  .addAll((entry.value as List).map((e) => e.toString()));
            } else {
              errorMessages.add(entry.value.toString());
            }
          }
          if (errorMessages.isNotEmpty) {
            errorMessage = errorMessages.join('\n');
          }
        }
      }
      throw ApiException(errorMessage,
          statusCode: 400,
          details: jsonBody is Map<String, dynamic> ? jsonBody : null);
    }

    throw ApiException(
      jsonBody is Map<String, dynamic> && jsonBody['message'] != null
          ? jsonBody['message'].toString()
          : 'Server error (${response.statusCode}). Please try again.',
      statusCode: response.statusCode,
    );
  }
}
