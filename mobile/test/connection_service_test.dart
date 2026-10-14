import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:digital_share/services/api_client.dart';
import 'package:digital_share/services/connection_service.dart';
import 'package:digital_share/services/secure_storage_service.dart';

class FakeSecureStorageService extends SecureStorageService {
  @override
  Future<String?> getAuthToken() async => 'fake_test_jwt_token';
}

void main() {
  group('ConnectionService Unit Tests', () {
    test('saveConnection posts shareId and parses SavedConnection', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/connections');
        expect(request.headers['Authorization'], 'Bearer fake_test_jwt_token');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['shareId'], 'target-share-id-123');

        return http.Response(
          jsonEncode({
            'shareId': 'target-share-id-123',
            'fullName': 'Alice Wonderland',
            'email': 'alice@wonderland.com',
            'jobTitle': 'Chief Architect',
            'company': 'Fantasy Tech',
            'savedAtUtc': '2026-10-08T12:00:00.000Z',
          }),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        storageService: FakeSecureStorageService(),
      );
      final connectionService = ConnectionService(apiClient: apiClient);

      final result = await connectionService.saveConnection('target-share-id-123');

      expect(result.shareId, 'target-share-id-123');
      expect(result.fullName, 'Alice Wonderland');
      expect(result.email, 'alice@wonderland.com');
      expect(result.jobTitle, 'Chief Architect');
      expect(result.company, 'Fantasy Tech');
    });

    test('saveConnection throws ConflictException when profile is already saved (409)', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'This profile is already saved.'}),
          409,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        storageService: FakeSecureStorageService(),
      );
      final connectionService = ConnectionService(apiClient: apiClient);

      expect(
        () async => await connectionService.saveConnection('already-saved-id'),
        throwsA(isA<ConflictException>()),
      );
    });

    test('getConnections fetches and parses list of saved connections', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/connections');

        return http.Response(
          jsonEncode([
            {
              'shareId': 'share-1',
              'fullName': 'User One',
              'email': 'one@example.com',
              'savedAtUtc': '2026-10-08T10:00:00.000Z',
            },
            {
              'shareId': 'share-2',
              'fullName': 'User Two',
              'email': 'two@example.com',
              'savedAtUtc': '2026-10-08T11:00:00.000Z',
            }
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        storageService: FakeSecureStorageService(),
      );
      final connectionService = ConnectionService(apiClient: apiClient);

      final list = await connectionService.getConnections();

      expect(list.length, 2);
      expect(list[0].shareId, 'share-1');
      expect(list[1].shareId, 'share-2');
    });
  });
}
