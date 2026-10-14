import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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
  UnauthorizedException([super.message = 'Session expired. Please log in again.'])
      : super(statusCode: 401);
}

class ConflictException extends ApiException {
  ConflictException([super.message = 'This item already exists.'])
      : super(statusCode: 409);
}

class ApiClient {
  final http.Client _httpClient;
  final SecureStorageService _storageService;

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

  Future<dynamic> get(String url, {bool requiresAuth = true}) async {
    try {
      final headers = await _buildHeaders(requiresAuth: requiresAuth);
      final response = await _httpClient.get(Uri.parse(url), headers: headers);
      return _processResponse(response);
    } on SocketException {
      throw ApiException('Unable to connect to the server. Please check your network connection.');
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

  Future<dynamic> post(String url, {dynamic body, bool requiresAuth = false}) async {
    try {
      final headers = await _buildHeaders(requiresAuth: requiresAuth);
      final response = await _httpClient.post(
        Uri.parse(url),
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
      return _processResponse(response);
    } on SocketException {
      throw ApiException('Unable to connect to the server. Please check your network connection.');
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

  Future<dynamic> put(String url, {dynamic body, bool requiresAuth = true}) async {
    try {
      final headers = await _buildHeaders(requiresAuth: requiresAuth);
      final response = await _httpClient.put(
        Uri.parse(url),
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
      return _processResponse(response);
    } on SocketException {
      throw ApiException('Unable to connect to the server. Please check your network connection.');
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

  Future<dynamic> delete(String url, {bool requiresAuth = true}) async {
    try {
      final headers = await _buildHeaders(requiresAuth: requiresAuth);
      final response = await _httpClient.delete(
        Uri.parse(url),
        headers: headers,
      );
      return _processResponse(response);
    } on SocketException {
      throw ApiException('Unable to connect to the server. Please check your network connection.');
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

  Future<dynamic> postMultipart(
    String url, {
    required String fieldName,
    String? filePath,
    List<int>? fileBytes,
    String? filename,
    String? contentType,
    bool requiresAuth = true,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(url));

      if (requiresAuth) {
        final token = await _storageService.getAuthToken();
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }
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

      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      return _processResponse(response);
    } on SocketException {
      throw ApiException('Unable to connect to the server. Please check your network connection.');
    } on HttpException {
      throw ApiException('Service temporarily unavailable. Please try again.');
    } on FormatException {
      throw ApiException('Unexpected server response format.');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('An unexpected network error occurred while uploading.');
    }
  }

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
              errorMessages.addAll((entry.value as List).map((e) => e.toString()));
            } else {
              errorMessages.add(entry.value.toString());
            }
          }
          if (errorMessages.isNotEmpty) {
            errorMessage = errorMessages.join('\n');
          }
        }
      }
      throw ApiException(errorMessage, statusCode: 400, details: jsonBody is Map<String, dynamic> ? jsonBody : null);
    }

    throw ApiException(
      jsonBody is Map<String, dynamic> && jsonBody['message'] != null
          ? jsonBody['message'].toString()
          : 'Server error (${response.statusCode}). Please try again.',
      statusCode: response.statusCode,
    );
  }
}
