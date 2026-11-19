import 'dart:convert';
import 'dart:io';
import '../../models/field_evidence.dart';
import '../../models/imported_contact.dart';
import '../../models/recovered_ocr_observation.dart';
import 'card_image_storage_service.dart';
import 'local_contact_record.dart';
import 'local_scan_cache_manager.dart';
import '../ocr/local_correction_learning_service.dart';

/// Permanent local repository for saved business cards and contacts.
/// Operates 100% offline with crash-safe atomic disk persistence.
class LocalContactRepository {
  final Directory storageDirectory;
  final String fileName;
  final CardImageStorageService imageStorageService;
  final LocalScanCacheManager? scanCacheManager;
  final LocalCorrectionLearningService? learningService;

  final Map<String, LocalContactRecord> _cache = {};
  bool _isLoaded = false;

  static Directory _resolveDefaultStorageDirectory() {
    try {
      if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'] ??
            Platform.environment['LOCALAPPDATA'];
        if (appData != null && appData.isNotEmpty) {
          return Directory('$appData/digital_share/storage');
        }
      } else if (Platform.isLinux || Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        if (home != null && home.isNotEmpty) {
          return Directory('$home/.digital_share/storage');
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        final parent = Directory.systemTemp.parent;
        return Directory('${parent.path}/app_flutter/storage');
      }
    } catch (_) {}
    return Directory.systemTemp;
  }

  LocalContactRepository({
    Directory? storageDirectory,
    this.fileName = 'digital_share_contacts.json',
    CardImageStorageService? imageStorageService,
    this.scanCacheManager,
    this.learningService,
    this.defaultUserId,
  })  : storageDirectory = storageDirectory ?? _resolveDefaultStorageDirectory(),
        imageStorageService = imageStorageService ??
            CardImageStorageService(
              baseDirectory: storageDirectory?.parent,
            );

  String? defaultUserId;

  File get _storeFile => File('${storageDirectory.path}/$fileName');
  File get _tempStoreFile => File('${storageDirectory.path}/$fileName.tmp');

  Future<void> _writeQueue = Future.value();

  /// Ensures data is loaded from disk into memory.
  /// Automatically recovers from an interrupted write if .tmp file exists.
  Future<void> ensureLoaded() async {
    if (_isLoaded) return;
    try {
      final file = _storeFile;
      final temp = _tempStoreFile;
      final backup = File('${file.path}.bak');

      // Migration from legacy temporary storage if new default storage file does not exist
      final defaultDir = _resolveDefaultStorageDirectory();
      if (storageDirectory.path == defaultDir.path && storageDirectory.path != Directory.systemTemp.path) {
        final legacyFile = File('${Directory.systemTemp.path}/$fileName');
        if (!file.existsSync() && legacyFile.existsSync()) {
          try {
            storageDirectory.createSync(recursive: true);
            legacyFile.copySync(file.path);
          } catch (_) {}
        }
      }

      // Safe recovery: if storeFile is missing or empty, recover from backup or temp
      if (!file.existsSync() || file.lengthSync() == 0) {
        if (backup.existsSync() && backup.lengthSync() > 0) {
          try {
            if (file.existsSync()) file.deleteSync();
            backup.renameSync(file.path);
          } catch (_) {}
        } else if (temp.existsSync() && temp.lengthSync() > 0) {
          try {
            if (file.existsSync()) file.deleteSync();
            temp.renameSync(file.path);
          } catch (_) {}
        }
      }

      if (file.existsSync()) {
        final content = file.readAsStringSync();
        if (content.trim().isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(content) as List<dynamic>;
          _cache.clear();
          for (final item in decoded) {
            final record = LocalContactRecord.fromJson(item as Map<String, dynamic>);
            _cache[record.id] = record;
          }
        }
      }
    } catch (_) {
      // Fallback: keep existing in-memory cache if file corrupted
    } finally {
      _isLoaded = true;
    }
  }

  /// Atomically flushes in-memory cache to disk.
  /// Serializes concurrent calls to eliminate race conditions.
  Future<void> _persistToDisk() {
    _writeQueue = _writeQueue.then((_) => _performDiskWrite()).catchError((_) {});
    return _writeQueue;
  }

  Future<void> _performDiskWrite() async {
    try {
      if (!await storageDirectory.exists()) {
        await storageDirectory.create(recursive: true);
      }
      final recordsList = _cache.values.map((r) => r.toJson()).toList();
      final jsonString = jsonEncode(recordsList);

      final tempFile = _tempStoreFile;
      await tempFile.writeAsString(jsonString, flush: true);

      final storeFile = _storeFile;
      final backupFile = File('${storeFile.path}.bak');

      // Safe atomic swap: retain storeFile in backup until replacement verified
      if (await storeFile.exists()) {
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
        await storeFile.rename(backupFile.path);
      }

      try {
        await tempFile.rename(storeFile.path);
        // Successful rename: safely purge previous backup
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
      } catch (e) {
        // Rollback: restore previous valid storeFile if rename encountered an error
        if (await backupFile.exists()) {
          await backupFile.rename(storeFile.path);
        }
      }
    } catch (_) {
      // Disk write failure must not crash in-memory operations
    }
  }

  /// Saves a new contact or creates a local record for a scanned business card.
  Future<ImportedContact> saveContact(
    Map<String, dynamic> contactData, {
    String userId = 'default_user',
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
    List<RecoveredOcrObservation> recoveredObservations = const [],
    bool isSynced = false,
  }) async {
    await ensureLoaded();

    final now = DateTime.now();
    final localId = contactData['id'] as String? ?? 'loc_${now.millisecondsSinceEpoch}_${_cache.length + 1}';
    final resolvedUserId = (contactData['userId'] as String?) ??
        (userId != 'default_user' ? userId : (defaultUserId ?? 'default_user'));

    final phones = (contactData['phoneNumbers'] as List<dynamic>?)
            ?.map((p) {
              if (p is Map<String, dynamic>) {
                return ImportedContactPhone(
                  id: p['id'] as String?,
                  number: p['number'] as String? ?? '',
                  normalizedNumber: p['normalizedNumber'] as String?,
                  label: p['label'] as String?,
                );
              }
              return ImportedContactPhone(number: p.toString());
            })
            .where((p) => p.number.trim().isNotEmpty)
            .toList() ??
        const [];

    final emails = (contactData['emailAddresses'] as List<dynamic>?)
            ?.map((e) {
              if (e is Map<String, dynamic>) {
                return ImportedContactEmail(
                  id: e['id'] as String?,
                  email: e['email'] as String? ?? '',
                  normalizedEmail: e['normalizedEmail'] as String?,
                  label: e['label'] as String?,
                );
              }
              return ImportedContactEmail(email: e.toString());
            })
            .where((e) => e.email.trim().isNotEmpty)
            .toList() ??
        const [];

    // Store original card images in permanent application storage with verification
    String? permFront = frontImagePath;
    String? permBack = backImagePath;

    if (frontImagePath != null || backImagePath != null) {
      final imgResult = await imageStorageService.storeCardImages(
        contactId: localId,
        tempFrontPath: frontImagePath,
        tempBackPath: backImagePath,
        cleanupTempOnSuccess: true,
      );
      if (imgResult.frontStoredSuccessfully && imgResult.permanentFrontPath != null) {
        permFront = imgResult.permanentFrontPath;
      }
      if (imgResult.backStoredSuccessfully && imgResult.permanentBackPath != null) {
        permBack = imgResult.permanentBackPath;
      }
    }

    final record = LocalContactRecord(
      id: localId,
      userId: resolvedUserId,
      remoteId: isSynced ? localId : (contactData['remoteId'] as String?),
      fullName: contactData['fullName'] as String?,
      company: contactData['company'] as String?,
      jobTitle: contactData['jobTitle'] as String?,
      website: contactData['website'] as String?,
      address: contactData['address'] as String?,
      personalRemark: (contactData['rememberThisContact'] as String?) ?? (contactData['personalRemark'] as String?),
      rememberThisContact: (contactData['rememberThisContact'] as String?) ?? (contactData['personalRemark'] as String?),
      phoneNumbers: phones,
      emailAddresses: emails,
      syncStatus: isSynced ? ContactSyncStatus.synced : ContactSyncStatus.pendingCreate,
      createdAt: now,
      updatedAt: now,
      imageFingerprint: imageFingerprint,
      imageDHash: imageDHash,
      frontImagePath: permFront,
      backImagePath: permBack,
      rawRecognizedText: rawRecognizedText,
      frontRawText: frontRawText ?? rawRecognizedText,
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
      recoveredObservations: recoveredObservations,
    );

    _cache[record.id] = record;
    await _persistToDisk();

    return record.toImportedContact();
  }

  /// Retrieves all non-deleted contacts sorted newest first.
  Future<List<ImportedContact>> getContacts() async {
    return getContactsForUser(defaultUserId);
  }

  /// User-scoped variant of [getContacts].
  Future<List<ImportedContact>> getContactsForUser(String? userId) async {
    await ensureLoaded();
    final effectiveUserId = userId ?? defaultUserId;
    final validRecords = _cache.values
        .where((r) => r.syncStatus != ContactSyncStatus.pendingDelete)
        .where((r) => effectiveUserId == null || r.userId == effectiveUserId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return validRecords.map((r) => r.toImportedContact()).toList();
  }

  /// Retrieves a contact by ID.
  Future<ImportedContact?> getContactById(String id, {String? userId}) async {
    await ensureLoaded();
    final record = _cache[id];
    if (record == null || record.syncStatus == ContactSyncStatus.pendingDelete) {
      return null;
    }
    if (userId != null && record.userId != userId) {
      return null;
    }
    return record.toImportedContact();
  }

  /// Retrieves the complete internal record by ID (including hashes & sync status).
  Future<LocalContactRecord?> getRecordById(String id, {String? userId}) async {
    await ensureLoaded();
    final record = _cache[id];
    if (record == null) return null;
    if (userId != null && record.userId != userId) return null;
    return record;
  }

  /// Retrieves all records including pending ones.
  Future<List<LocalContactRecord>> getAllRecords({String? userId}) async {
    await ensureLoaded();
    if (userId == null) return _cache.values.toList();
    return _cache.values.where((r) => r.userId == userId).toList();
  }

  /// Updates an existing contact.
  Future<ImportedContact> updateContact(
    String id,
    Map<String, dynamic> updatedData, {
    bool markPendingSync = true,
  }) async {
    await ensureLoaded();
    final existing = _cache[id];
    if (existing == null) {
      throw StateError('Contact with ID "$id" does not exist locally.');
    }

    final phones = updatedData.containsKey('phoneNumbers')
        ? (updatedData['phoneNumbers'] as List<dynamic>?)
                ?.map((p) {
                  if (p is Map<String, dynamic>) {
                    return ImportedContactPhone(
                      id: p['id'] as String?,
                      number: p['number'] as String? ?? '',
                      normalizedNumber: p['normalizedNumber'] as String?,
                      label: p['label'] as String?,
                    );
                  }
                  return ImportedContactPhone(number: p.toString());
                })
                .where((p) => p.number.trim().isNotEmpty)
                .toList() ??
            const <ImportedContactPhone>[]
        : existing.phoneNumbers;

    final emails = updatedData.containsKey('emailAddresses')
        ? (updatedData['emailAddresses'] as List<dynamic>?)
                ?.map((e) {
                  if (e is Map<String, dynamic>) {
                    return ImportedContactEmail(
                      id: e['id'] as String?,
                      email: e['email'] as String? ?? '',
                      normalizedEmail: e['normalizedEmail'] as String?,
                      label: e['label'] as String?,
                    );
                  }
                  return ImportedContactEmail(email: e.toString());
                })
                .where((e) => e.email.trim().isNotEmpty)
                .toList() ??
            const <ImportedContactEmail>[]
        : existing.emailAddresses;

    final updatedEvidence = Map<String, FieldEvidence>.from(existing.fieldEvidence);
    void applyCorrection(String fieldKey, String? newValue) {
      if (newValue == null) return;
      final existingEv = updatedEvidence[fieldKey];
      if (existingEv != null) {
        if (existingEv.normalizedValue != newValue || existingEv.userApprovedValue != newValue) {
          updatedEvidence[fieldKey] = existingEv.withUserCorrection(
            newValue,
            verificationSource: 'userManualEdit',
          );
        }
      } else {
        updatedEvidence[fieldKey] = FieldEvidence(
          fieldName: fieldKey,
          originalOcrText: '',
          normalizedValue: newValue,
          userApprovedValue: newValue,
          sourceEngine: 'Manual Input',
          sourceObservationIds: const [],
          boundingBoxes: const [],
          ocrConfidence: 1.0,
          parserConfidence: 1.0,
          verificationStatus: FieldVerificationStatus.verified,
          verificationSource: 'userManualEdit',
          verifiedAt: DateTime.now().toUtc(),
        );
      }
    }

    if (updatedData.containsKey('fullName')) {
      applyCorrection('fullName', updatedData['fullName'] as String?);
    }
    if (updatedData.containsKey('company')) {
      applyCorrection('company', updatedData['company'] as String?);
    }
    if (updatedData.containsKey('jobTitle')) {
      applyCorrection('jobTitle', updatedData['jobTitle'] as String?);
    }
    if (updatedData.containsKey('website')) {
      applyCorrection('website', updatedData['website'] as String?);
    }
    if (updatedData.containsKey('address')) {
      applyCorrection('address', updatedData['address'] as String?);
    }
    if (updatedData.containsKey('phoneNumbers') && phones.isNotEmpty) {
      applyCorrection('phone', phones.map((p) => p.number).join(', '));
    }
    if (updatedData.containsKey('emailAddresses') && emails.isNotEmpty) {
      applyCorrection('email', emails.map((e) => e.email).join(', '));
    }

    final hasMemoryKey = updatedData.containsKey('rememberThisContact') || updatedData.containsKey('personalRemark');
    final memoryVal = updatedData.containsKey('rememberThisContact')
        ? updatedData['rememberThisContact'] as String?
        : (updatedData.containsKey('personalRemark')
            ? updatedData['personalRemark'] as String?
            : (existing.rememberThisContact ?? existing.personalRemark));
    final clearMemory = hasMemoryKey && memoryVal == null;

    final updated = existing.copyWith(
      fullName: updatedData.containsKey('fullName') ? updatedData['fullName'] as String? : existing.fullName,
      company: updatedData.containsKey('company') ? updatedData['company'] as String? : existing.company,
      jobTitle: updatedData.containsKey('jobTitle') ? updatedData['jobTitle'] as String? : existing.jobTitle,
      website: updatedData.containsKey('website') ? updatedData['website'] as String? : existing.website,
      address: updatedData.containsKey('address') ? updatedData['address'] as String? : existing.address,
      personalRemark: memoryVal,
      rememberThisContact: memoryVal,
      clearPersonalRemark: clearMemory,
      clearRememberThisContact: clearMemory,
      phoneNumbers: phones,
      emailAddresses: emails,
      fieldEvidence: updatedEvidence,
      syncStatus: markPendingSync
          ? (existing.syncStatus == ContactSyncStatus.pendingCreate
              ? ContactSyncStatus.pendingCreate
              : ContactSyncStatus.pendingUpdate)
          : existing.syncStatus,
      updatedAt: DateTime.now(),
    );

    _cache[id] = updated;
    await _persistToDisk();
    return updated.toImportedContact();
  }

  /// Updates a [LocalContactRecord] directly and persists changes to disk.
  Future<void> updateLocalRecord(LocalContactRecord record) async {
    await ensureLoaded();
    _cache[record.id] = record;
    await _persistToDisk();
  }

  /// Deletes a contact locally, flagging for sync deletion if previously synced.
  Future<void> deleteContact(String id, {bool markPendingSync = true}) async {
    await ensureLoaded();
    final existing = _cache[id];
    if (existing == null) return;

    if (existing.syncStatus == ContactSyncStatus.pendingCreate || !markPendingSync) {
      _cache.remove(id);
      await imageStorageService.deleteContactImages(id);

      // Clean associated cache entries & learned exact-image rules when contact is deleted (Stage 5)
      if (scanCacheManager != null) {
        await scanCacheManager!.evictByContactId(id);
        if (existing.imageFingerprint != null && existing.imageFingerprint!.isNotEmpty) {
          await scanCacheManager!.evictByImageFingerprint(existing.imageFingerprint!);
        }
      }
      if (learningService != null && existing.imageFingerprint != null && existing.imageFingerprint!.isNotEmpty) {
        await learningService!.evictForImageHash(existing.imageFingerprint!);
      }
    } else {
      _cache[id] = existing.copyWith(
        syncStatus: ContactSyncStatus.pendingDelete,
        updatedAt: DateTime.now(),
      );
    }
    await _persistToDisk();
  }

  /// Clears all local contacts and cached images completely from disk and memory.
  Future<void> clearAllLocalContacts() async {
    await ensureLoaded();
    final ids = _cache.keys.toList();
    for (final id in ids) {
      try {
        await imageStorageService.deleteContactImages(id);
      } catch (_) {}
    }
    _cache.clear();
    await _persistToDisk();
  }

  /// Searches contacts for an exact normalized image SHA-256 fingerprint match.
  Future<LocalContactRecord?> findByImageFingerprint(String fingerprint, {String? userId}) async {
    if (fingerprint.isEmpty) return null;
    await ensureLoaded();
    for (final record in _cache.values) {
      if (record.syncStatus != ContactSyncStatus.pendingDelete &&
          record.imageFingerprint == fingerprint) {
        if (userId != null && record.userId != userId) continue;
        return record;
      }
    }
    return null;
  }

  /// Searches contacts by normalized phone number or email address.
  Future<List<LocalContactRecord>> findMatchingContactsByPhoneOrEmail({
    List<String> phoneNumbers = const [],
    List<String> emailAddresses = const [],
    String? userId,
  }) async {
    await ensureLoaded();
    final matches = <LocalContactRecord>[];

    final targetPhones = phoneNumbers
        .map((p) => p.replaceAll(RegExp(r'\D'), ''))
        .where((p) => p.length >= 7)
        .toSet();

    final targetEmails = emailAddresses
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();

    for (final record in _cache.values) {
      if (record.syncStatus == ContactSyncStatus.pendingDelete) continue;
      if (userId != null && record.userId != userId) continue;

      bool matched = false;
      for (final p in record.phoneNumbers) {
        final clean = p.number.replaceAll(RegExp(r'\D'), '');
        for (final tp in targetPhones) {
          if (clean.endsWith(tp) || tp.endsWith(clean)) {
            matches.add(record);
            matched = true;
            break;
          }
        }
        if (matched) break;
      }

      if (!matched) {
        for (final e in record.emailAddresses) {
          if (targetEmails.contains(e.email.trim().toLowerCase())) {
            matches.add(record);
            break;
          }
        }
      }
    }

    return matches;
  }

  /// Updates record when synced successfully with remote backend.
  Future<void> markSynced(String localId, String remoteId) async {
    await ensureLoaded();
    final record = _cache[localId];
    if (record == null) return;

    if (record.syncStatus == ContactSyncStatus.pendingDelete) {
      _cache.remove(localId);
    } else {
      _cache[localId] = record.copyWith(
        remoteId: remoteId,
        syncStatus: ContactSyncStatus.synced,
      );
    }
    await _persistToDisk();
  }

  /// Clears records and images belonging exclusively to [userId].
  Future<void> clearUserData(String userId) async {
    await ensureLoaded();
    final toRemove = _cache.values
        .where((r) => r.userId == userId)
        .map((r) => r.id)
        .toList();
    for (final id in toRemove) {
      final rec = _cache.remove(id);
      if (rec != null) {
        await imageStorageService.deleteContactImages(id);
        if (rec.imageFingerprint != null && rec.imageFingerprint!.isNotEmpty) {
          if (scanCacheManager != null) {
            await scanCacheManager!.evictByImageFingerprint(rec.imageFingerprint!);
          }
          if (learningService != null) {
            await learningService!.evictForImageHash(rec.imageFingerprint!);
          }
        }
      }
    }
    if (toRemove.isNotEmpty) {
      await _persistToDisk();
    }
  }

  /// Clears in-memory cache and deletes file (useful for test isolation).
  Future<void> resetForTesting() async {
    _cache.clear();
    _isLoaded = false;
    final file = _storeFile;
    if (await file.exists()) {
      await file.delete();
    }
    final tmp = _tempStoreFile;
    if (await tmp.exists()) {
      await tmp.delete();
    }
  }
}

