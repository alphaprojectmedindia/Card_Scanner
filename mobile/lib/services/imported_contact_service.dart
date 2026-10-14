import '../config/api_config.dart';
import '../models/check_duplicate_result.dart';
import '../models/imported_contact.dart';
import 'api_client.dart';

class ImportedContactService {
  final ApiClient _apiClient;

  ImportedContactService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// Checks if any phone number or email address matches an existing imported business card
  /// for the currently authenticated user.
  Future<CheckDuplicateResult> checkDuplicate({
    required List<String> phoneNumbers,
    required List<String> emailAddresses,
  }) async {
    final body = {
      'phoneNumbers': phoneNumbers,
      'emailAddresses': emailAddresses,
    };

    final response = await _apiClient.post(
      ApiConfig.checkDuplicateImportedContactEndpoint,
      body: body,
      requiresAuth: true,
    );

    return CheckDuplicateResult.fromJson(response as Map<String, dynamic>);
  }

  /// Saves a new imported physical business card for the authenticated user.
  Future<ImportedContact> saveContact(Map<String, dynamic> contactData) async {
    final response = await _apiClient.post(
      ApiConfig.importedContactsEndpoint,
      body: contactData,
      requiresAuth: true,
    );

    return ImportedContact.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieves all imported business cards owned by the authenticated user, newest first.
  Future<List<ImportedContact>> getContacts() async {
    final response = await _apiClient.get(
      ApiConfig.importedContactsEndpoint,
      requiresAuth: true,
    );

    if (response is List) {
      return response
          .map((item) => ImportedContact.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return [];
  }

  /// Retrieves a specific saved imported business card by ID.
  Future<ImportedContact> getContactById(String id) async {
    final response = await _apiClient.get(
      ApiConfig.importedContactByIdEndpoint(id),
      requiresAuth: true,
    );

    return ImportedContact.fromJson(response as Map<String, dynamic>);
  }

  /// Updates an existing saved imported business card.
  Future<ImportedContact> updateContact(
    String id,
    Map<String, dynamic> updatedData,
  ) async {
    final response = await _apiClient.put(
      ApiConfig.importedContactByIdEndpoint(id),
      body: updatedData,
      requiresAuth: true,
    );

    return ImportedContact.fromJson(response as Map<String, dynamic>);
  }

  /// Deletes a saved imported business card.
  Future<void> deleteContact(String id) async {
    await _apiClient.delete(
      ApiConfig.importedContactByIdEndpoint(id),
      requiresAuth: true,
    );
  }
}
