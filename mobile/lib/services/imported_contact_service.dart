import 'dart:async';
import '../config/api_config.dart';
import '../models/check_duplicate_result.dart';
import '../models/field_evidence.dart';
import '../models/imported_contact.dart';
import 'api_client.dart';
import 'ocr/local_correction_learning_service.dart';
import 'storage/card_image_storage_service.dart';
import 'storage/local_contact_repository.dart';
import 'storage/local_scan_cache_manager.dart';
import 'storage/sync_queue_service.dart';

/// Offline-first service managing imported business-card contacts.
/// Automatically persists contacts to local disk storage before attempting remote synchronization.
class ImportedContactService {
  final ApiClient _apiClient;
  final LocalContactRepository _localRepo;
  final SyncQueueService _syncQueue;
  String? defaultUserId;

  ImportedContactService({
    ApiClient? apiClient,
    LocalContactRepository? localRepo,
    SyncQueueService? syncQueue,
    LocalScanCacheManager? scanCacheManager,
    LocalCorrectionLearningService? learningService,
    this.defaultUserId,
  })  : _apiClient = apiClient ?? ApiClient(),
        _localRepo = localRepo ??
            LocalContactRepository(
              scanCacheManager: scanCacheManager,
              learningService: learningService,
            ),
        _syncQueue = syncQueue ?? SyncQueueService();

  LocalContactRepository get localRepository => _localRepo;
  SyncQueueService get syncQueue => _syncQueue;

  /// Migrates existing contact records whose image paths point to temporary storage into
  /// permanent application storage, reporting exact recovery and missing counts.
  Future<ImageMigrationReport> migrateExistingCardImages() async {
    return await _localRepo.imageStorageService.migrateExistingRecords(_localRepo);
  }

  /// Checks if any phone number or email address matches an existing imported business card,
  /// querying local persistent storage first, then querying remote backend if available.
  Future<CheckDuplicateResult> checkDuplicate({
    required List<String> phoneNumbers,
    required List<String> emailAddresses,
  }) async {
    return checkDuplicateForUser(
      phoneNumbers: phoneNumbers,
      emailAddresses: emailAddresses,
      userId: defaultUserId,
    );
  }

  /// User-scoped variant of [checkDuplicate].
  Future<CheckDuplicateResult> checkDuplicateForUser({
    required List<String> phoneNumbers,
    required List<String> emailAddresses,
    String? userId,
  }) async {
    // 1. Check local persistent storage first
    final localMatches = await _localRepo.findMatchingContactsByPhoneOrEmail(
      phoneNumbers: phoneNumbers,
      emailAddresses: emailAddresses,
      userId: userId ?? defaultUserId,
    );

    if (localMatches.isNotEmpty) {
      final first = localMatches.first;
      return CheckDuplicateResult(
        isDuplicate: true,
        existingContact: first.toImportedContact(),
        matchedBy: 'local_storage',
      );
    }

    // 2. If no local match, check remote API if online
    try {
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
    } catch (_) {
      // Offline fallback: if backend is unreachable, trust local check
      return const CheckDuplicateResult(isDuplicate: false);
    }
  }

  /// Saves a new imported physical business card.
  /// Guarantees immediate offline persistence to local storage before remote sync.
  Future<ImportedContact> saveContact(
    Map<String, dynamic> contactData, {
    String? imageFingerprint,
    String? imageDHash,
    String? frontImagePath,
    String? backImagePath,
    String? rawRecognizedText,
    String? frontRawText,
    String? backRawText,
    List<Map<String, dynamic>> frontObservations = const [],
    List<Map<String, dynamic>> backObservations = const [],
    String? ocrEngineName,
    String? ocrModelVersion,
    double? overallOcrConfidence,
    Map<String, FieldEvidence> fieldEvidence = const {},
    String? parserVersion,
    String? preprocessingVersion,
    String? notes,
  }) async {
    final effectiveUserId = (contactData['userId'] as String?) ?? defaultUserId ?? 'default_user';

    // 1. Immediately save to local persistent storage
    final localContact = await _localRepo.saveContact(
      contactData,
      userId: effectiveUserId,
      imageFingerprint: imageFingerprint,
      imageDHash: imageDHash,
      frontImagePath: frontImagePath,
      backImagePath: backImagePath,
      rawRecognizedText: rawRecognizedText,
      frontRawText: frontRawText,
      backRawText: backRawText,
      frontObservations: frontObservations,
      backObservations: backObservations,
      ocrEngineName: ocrEngineName,
      ocrModelVersion: ocrModelVersion,
      overallOcrConfidence: overallOcrConfidence,
      fieldEvidence: fieldEvidence,
      parserVersion: parserVersion,
      preprocessingVersion: preprocessingVersion,
      notes: notes,
      isSynced: false,
    );

    // 2. Attempt remote sync if online
    try {
      final response = await _apiClient.post(
        ApiConfig.importedContactsEndpoint,
        body: contactData,
        requiresAuth: true,
      );

      final remoteContact = ImportedContact.fromJson(response as Map<String, dynamic>);
      await _localRepo.markSynced(localContact.id, remoteContact.id);
      return remoteContact;
    } on ApiException catch (_) {
      // Offline / network failure: enqueue in sync queue for background retry
      await _syncQueue.enqueue(
        SyncOperation(
          id: 'sync_create_${DateTime.now().millisecondsSinceEpoch}',
          contactLocalId: localContact.id,
          type: SyncOperationType.create,
          payload: contactData,
          createdAt: DateTime.now(),
        ),
      );
      return localContact;
    } catch (_) {
      // Any other error: also enqueue and return local copy
      await _syncQueue.enqueue(
        SyncOperation(
          id: 'sync_create_${DateTime.now().millisecondsSinceEpoch}',
          contactLocalId: localContact.id,
          type: SyncOperationType.create,
          payload: contactData,
          createdAt: DateTime.now(),
        ),
      );
      return localContact;
    }
  }

  /// Retrieves all imported business cards owned by the authenticated user.
  /// Merges remote contacts with pending offline contacts.
  Future<List<ImportedContact>> getContacts() async {
    return getContactsForUser(defaultUserId);
  }

  /// User-scoped variant of [getContacts].
  Future<List<ImportedContact>> getContactsForUser(String? userId) async {
    final effectiveUserId = userId ?? defaultUserId;
    final localContacts = await _localRepo.getContactsForUser(effectiveUserId);

    try {
      final response = await _apiClient.get(
        ApiConfig.importedContactsEndpoint,
        requiresAuth: true,
      );

      if (response is List) {
        final remoteList = response
            .map((item) => ImportedContact.fromJson(item as Map<String, dynamic>))
            .toList();

        // Update local store with remote contacts
        for (final remote in remoteList) {
          final existing = await _localRepo.getRecordById(remote.id, userId: effectiveUserId);
          if (existing == null) {
            await _localRepo.saveContact(
              remote.toJson(),
              userId: effectiveUserId ?? 'default_user',
              isSynced: true,
            );
          }
        }

        // Return combined list (remote + pending offline)
        return await _localRepo.getContactsForUser(effectiveUserId);
      }
    } catch (_) {
      // Offline fallback: return existing local contacts
    }

    return localContacts;
  }

  /// Retrieves a specific saved imported business card by ID.
  Future<ImportedContact> getContactById(String id, {String? userId}) async {
    final local = await _localRepo.getContactById(id, userId: userId);
    if (local != null) return local;

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
    ImportedContact? updatedLocal;
    try {
      updatedLocal = await _localRepo.updateContact(id, updatedData);
    } catch (_) {
      // If contact is not yet cached locally, proceed to remote update
    }

    try {
      final targetId = (await _localRepo.getRecordById(id))?.remoteId ?? id;
      final response = await _apiClient.put(
        ApiConfig.importedContactByIdEndpoint(targetId),
        body: updatedData,
        requiresAuth: true,
      );

      final remote = ImportedContact.fromJson(response as Map<String, dynamic>);
      try {
        await _localRepo.markSynced(id, remote.id);
      } catch (_) {}
      return remote;
    } catch (_) {
      if (updatedLocal != null) {
        await _syncQueue.enqueue(
          SyncOperation(
            id: 'sync_update_${DateTime.now().millisecondsSinceEpoch}',
            contactLocalId: id,
            contactRemoteId: (await _localRepo.getRecordById(id))?.remoteId,
            type: SyncOperationType.update,
            payload: updatedData,
            createdAt: DateTime.now(),
          ),
        );
        return updatedLocal;
      }
      rethrow;
    }
  }

  /// Updates or sets the personal remark on a saved contact.
  Future<ImportedContact> updateRemark(String id, String? remark) async {
    ImportedContact? localUpdated;
    try {
      localUpdated = await _localRepo.updateContact(id, {'personalRemark': remark});
    } catch (_) {}

    try {
      final targetId = (await _localRepo.getRecordById(id))?.remoteId ?? id;
      final response = await _apiClient.put(
        ApiConfig.importedContactRemarkEndpoint(targetId),
        body: {'remark': remark},
        requiresAuth: true,
      );
      final remote = ImportedContact.fromJson(response as Map<String, dynamic>);
      try {
        await _localRepo.markSynced(id, remote.id);
      } catch (_) {}
      return remote;
    } catch (_) {
      if (localUpdated != null) {
        return localUpdated;
      }
      rethrow;
    }
  }

  /// Clears the personal remark from a saved contact.
  Future<ImportedContact> clearRemark(String id) async {
    ImportedContact? localUpdated;
    try {
      localUpdated = await _localRepo.updateContact(id, {'personalRemark': null});
    } catch (_) {}

    try {
      final targetId = (await _localRepo.getRecordById(id))?.remoteId ?? id;
      final response = await _apiClient.delete(
        ApiConfig.importedContactRemarkEndpoint(targetId),
        requiresAuth: true,
      );
      final remote = ImportedContact.fromJson(response as Map<String, dynamic>);
      try {
        await _localRepo.markSynced(id, remote.id);
      } catch (_) {}
      return remote;
    } catch (_) {
      if (localUpdated != null) {
        return localUpdated;
      }
      rethrow;
    }
  }

  /// Deletes a saved imported business card.
  Future<void> deleteContact(String id) async {
    final record = await _localRepo.getRecordById(id);
    final targetId = record?.remoteId ?? id;

    try {
      await _localRepo.deleteContact(id, markPendingSync: record?.remoteId != null);
    } catch (_) {}

    try {
      if (record == null || record.remoteId != null) {
        await _apiClient.delete(
          ApiConfig.importedContactByIdEndpoint(targetId),
          requiresAuth: true,
        );
        try {
          await _localRepo.deleteContact(id, markPendingSync: false);
        } catch (_) {}
      }
    } catch (_) {
      if (record?.remoteId != null) {
        await _syncQueue.enqueue(
          SyncOperation(
            id: 'sync_delete_${DateTime.now().millisecondsSinceEpoch}',
            contactLocalId: id,
            contactRemoteId: targetId,
            type: SyncOperationType.delete,
            createdAt: DateTime.now(),
          ),
        );
      }
    }
  }

  /// Triggers background queue synchronization.
  Future<int> syncPending() async {
    return _syncQueue.processPendingSync(
      remoteService: this,
      localRepo: _localRepo,
    );
  }
}
