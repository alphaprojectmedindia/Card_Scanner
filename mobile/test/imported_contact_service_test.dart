import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:digital_share/services/api_client.dart';
import 'package:digital_share/services/imported_contact_service.dart';
import 'package:digital_share/services/secure_storage_service.dart';

class FakeSecureStorageService extends SecureStorageService {
  @override
  Future<String?> getAuthToken() async => 'fake_test_jwt_token';
}

void main() {
  group('ImportedContactService Unit Tests', () {
    test('checkDuplicate calls endpoint and returns parsed result', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/api/imported-contacts/check-duplicate'));
        expect(request.headers['Authorization'], 'Bearer fake_test_jwt_token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['phoneNumbers'], contains('9876543210'));
        expect(body['emailAddresses'], contains('rahul@example.com'));

        return http.Response(
          jsonEncode({
            'isDuplicate': true,
            'existingContact': {
              'id': 'f7d2f932-b7b2-4d1a-a63d-4c31671970d1',
              'fullName': 'Rahul Kumar',
              'company': 'ABC Technologies',
              'phoneNumbers': [
                {'number': '+91 98765 43210', 'label': 'Mobile'}
              ],
              'emailAddresses': [
                {'email': 'rahul@example.com', 'label': 'Work'}
              ]
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        storageService: FakeSecureStorageService(),
      );
      final service = ImportedContactService(apiClient: apiClient);

      final result = await service.checkDuplicate(
        phoneNumbers: ['9876543210'],
        emailAddresses: ['rahul@example.com'],
      );

      expect(result.isDuplicate, isTrue);
      expect(result.existingContact, isNotNull);
      expect(result.existingContact!.fullName, 'Rahul Kumar');
      expect(result.existingContact!.primaryPhone, '+91 98765 43210');
    });

    test('saveContact creates and returns ImportedContact', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, contains('/api/imported-contacts'));
        expect(request.headers['Authorization'], 'Bearer fake_test_jwt_token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['fullName'], 'Rahul Kumar');

        return http.Response(
          jsonEncode({
            'id': 'a1b2c3d4-0000-0000-0000-000000000001',
            'fullName': 'Rahul Kumar',
            'company': 'ABC Technologies',
            'jobTitle': 'Senior Developer',
            'phoneNumbers': [
              {'id': 'p1', 'number': '+91 98765 43210', 'label': 'Mobile'}
            ],
            'emailAddresses': [
              {'id': 'e1', 'email': 'rahul@example.com', 'label': 'Work'}
            ]
          }),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        storageService: FakeSecureStorageService(),
      );
      final service = ImportedContactService(apiClient: apiClient);

      final saved = await service.saveContact({
        'fullName': 'Rahul Kumar',
        'company': 'ABC Technologies',
        'jobTitle': 'Senior Developer',
      });

      expect(saved.id, 'a1b2c3d4-0000-0000-0000-000000000001');
      expect(saved.fullName, 'Rahul Kumar');
      expect(saved.phoneNumbers.length, 1);
      expect(saved.emailAddresses.length, 1);
    });

    test('getContacts retrieves list of saved business cards', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer fake_test_jwt_token');
        return http.Response(
          jsonEncode([
            {
              'id': 'card-1',
              'fullName': 'Rahul Kumar',
              'company': 'ABC Corp',
              'phoneNumbers': [{'number': '9876543210', 'label': 'Mobile'}],
              'emailAddresses': []
            },
            {
              'id': 'card-2',
              'fullName': 'Priya Sharma',
              'company': 'XYZ Corp',
              'phoneNumbers': [],
              'emailAddresses': [{'email': 'priya@xyz.com', 'label': 'Work'}]
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
      final service = ImportedContactService(apiClient: apiClient);

      final contacts = await service.getContacts();

      expect(contacts.length, 2);
      expect(contacts[0].fullName, 'Rahul Kumar');
      expect(contacts[1].fullName, 'Priya Sharma');
    });

    test('updateContact puts payload and returns updated contact', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, contains('/api/imported-contacts/card-1'));
        expect(request.headers['Authorization'], 'Bearer fake_test_jwt_token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['fullName'], 'Rahul Updated');

        return http.Response(
          jsonEncode({
            'id': 'card-1',
            'fullName': 'Rahul Updated',
            'company': 'ABC Corp',
            'phoneNumbers': [],
            'emailAddresses': []
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        storageService: FakeSecureStorageService(),
      );
      final service = ImportedContactService(apiClient: apiClient);

      final updated = await service.updateContact('card-1', {'fullName': 'Rahul Updated'});
      expect(updated.fullName, 'Rahul Updated');
    });

    test('deleteContact sends DELETE request successfully', () async {
      bool deleteCalled = false;
      final mockClient = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, contains('/api/imported-contacts/card-1'));
        expect(request.headers['Authorization'], 'Bearer fake_test_jwt_token');
        deleteCalled = true;
        return http.Response('', 204);
      });

      final apiClient = ApiClient(
        httpClient: mockClient,
        storageService: FakeSecureStorageService(),
      );
      final service = ImportedContactService(apiClient: apiClient);

      await service.deleteContact('card-1');
      expect(deleteCalled, isTrue);
    });
  });
}
