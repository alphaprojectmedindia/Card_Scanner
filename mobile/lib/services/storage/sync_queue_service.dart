import 'dart:convert';
import 'dart:io';
import '../api_client.dart';
import '../imported_contact_service.dart';
import 'local_contact_repository.dart';

enum SyncOperationType {
  create,
  update,
  delete,
}

class SyncOperation {
  final String id;
  final String contactLocalId;
  final String? contactRemoteId;
  final SyncOperationType type;
  final Map<String, dynamic>? payload;
  final DateTime createdAt;
  final int retryCount;

  const SyncOperation({
    required this.id,
    required this.contactLocalId,
    this.contactRemoteId,
    required this.type,
    this.payload,
    required this.createdAt,
    this.retryCount = 0,
  });

  SyncOperation copyWith({
    int? retryCount,
  }) {
    return SyncOperation(
      id: id,
      contactLocalId: contactLocalId,
      contactRemoteId: contactRemoteId,
      type: type,
      payload: payload,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contactLocalId': contactLocalId,
      if (contactRemoteId != null) 'contactRemoteId': contactRemoteId,
      'type': type.name,
      if (payload != null) 'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
    };
  }

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    return SyncOperation(
      id: json['id'] as String? ?? '',
      contactLocalId: json['contactLocalId'] as String? ?? '',
      contactRemoteId: json['contactRemoteId'] as String?,
      type: SyncOperationType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => SyncOperationType.create,
      ),
      payload: json['payload'] as Map<String, dynamic>?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Outbox synchronization queue to replay offline mutations when connectivity is restored.
class SyncQueueService {
  final Directory storageDirectory;
  final List<SyncOperation> _queue = [];
  bool _isLoaded = false;
  bool _isSyncing = false;

  SyncQueueService({Directory? storageDirectory})
      : storageDirectory = storageDirectory ?? Directory.systemTemp;

  File get _file => File('${storageDirectory.path}/digital_share_sync_queue.json');

  Future<void> ensureLoaded() async {
    if (_isLoaded) return;
    try {
      if (_file.existsSync()) {
        final content = _file.readAsStringSync();
        if (content.trim().isNotEmpty) {
          final List<dynamic> list = jsonDecode(content) as List<dynamic>;
          _queue.clear();
          for (final item in list) {
            _queue.add(SyncOperation.fromJson(item as Map<String, dynamic>));
          }
        }
      }
    } catch (_) {
    } finally {
      _isLoaded = true;
    }
  }

  Future<void> _persist() async {
    try {
      if (!storageDirectory.existsSync()) {
        storageDirectory.createSync(recursive: true);
      }
      final temp = File('${_file.path}.tmp');
      temp.writeAsStringSync(jsonEncode(_queue.map((o) => o.toJson()).toList()), flush: true);
      if (_file.existsSync()) {
        _file.deleteSync();
      }
      temp.renameSync(_file.path);
    } catch (_) {}
  }

  /// Enqueues an operation to be synced.
  Future<void> enqueue(SyncOperation operation) async {
    await ensureLoaded();
    _queue.add(operation);
    await _persist();
  }

  /// Returns uncompleted sync operations.
  Future<List<SyncOperation>> getPendingOperations() async {
    await ensureLoaded();
    return List.unmodifiable(_queue);
  }

  /// Attempts to process pending sync operations against the remote backend.
  /// Stops processing on connection/network failures and preserves remaining operations.
  Future<int> processPendingSync({
    required ImportedContactService remoteService,
    required LocalContactRepository localRepo,
  }) async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    await ensureLoaded();

    int successCount = 0;
    final operations = List<SyncOperation>.from(_queue);

    for (final op in operations) {
      try {
        switch (op.type) {
          case SyncOperationType.create:
            if (op.payload != null) {
              final remoteContact = await remoteService.saveContact(op.payload!);
              await localRepo.markSynced(op.contactLocalId, remoteContact.id);
            }
            break;

          case SyncOperationType.update:
            final targetId = op.contactRemoteId ?? op.contactLocalId;
            if (op.payload != null) {
              final updated = await remoteService.updateContact(targetId, op.payload!);
              await localRepo.markSynced(op.contactLocalId, updated.id);
            }
            break;

          case SyncOperationType.delete:
            final targetId = op.contactRemoteId ?? op.contactLocalId;
            await remoteService.deleteContact(targetId);
            await localRepo.deleteContact(op.contactLocalId, markPendingSync: false);
            break;
        }

        _queue.removeWhere((item) => item.id == op.id);
        successCount++;
        await _persist();
      } on ApiException catch (_) {
        // Network or auth error: pause sync and retry later
        break;
      } catch (_) {
        // Unexpected error: pause sync
        break;
      }
    }

    _isSyncing = false;
    return successCount;
  }

  /// Clears the queue (primarily for testing).
  Future<void> clear() async {
    _queue.clear();
    try {
      if (await _file.exists()) {
        await _file.delete();
      }
    } catch (_) {}
  }
}
