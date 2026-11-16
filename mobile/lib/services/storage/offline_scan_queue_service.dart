import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../models/business_card_data.dart';

/// Represents a business card scan awaiting Gemini visual verification when back online.
class PendingScanQueueEntry {
  final String id;
  final String? contactId;
  final String userId;
  final String frontImagePath;
  final String? backImagePath;
  final String? frontImageSha256;
  final String? backImageSha256;
  final DateTime scannedAt;
  final Map<String, dynamic> localCardData;
  final String status; // 'pending', 'processing', 'completed', 'failed'
  final String? error;
  final int retryCount;

  const PendingScanQueueEntry({
    required this.id,
    this.contactId,
    required this.userId,
    required this.frontImagePath,
    this.backImagePath,
    this.frontImageSha256,
    this.backImageSha256,
    required this.scannedAt,
    required this.localCardData,
    this.status = 'pending',
    this.error,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'contactId': contactId,
        'userId': userId,
        'frontImagePath': frontImagePath,
        'backImagePath': backImagePath,
        'frontImageSha256': frontImageSha256,
        'backImageSha256': backImageSha256,
        'scannedAt': scannedAt.toIso8601String(),
        'localCardData': localCardData,
        'status': status,
        'error': error,
        'retryCount': retryCount,
      };

  factory PendingScanQueueEntry.fromJson(Map<String, dynamic> json) =>
      PendingScanQueueEntry(
        id: json['id'] as String,
        contactId: json['contactId'] as String?,
        userId: json['userId'] as String? ?? 'default_user',
        frontImagePath: json['frontImagePath'] as String,
        backImagePath: json['backImagePath'] as String?,
        frontImageSha256: json['frontImageSha256'] as String?,
        backImageSha256: json['backImageSha256'] as String?,
        scannedAt: json['scannedAt'] != null
            ? DateTime.tryParse(json['scannedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        localCardData: (json['localCardData'] as Map<String, dynamic>?) ?? {},
        status: json['status'] as String? ?? 'pending',
        error: json['error'] as String?,
        retryCount: json['retryCount'] as int? ?? 0,
      );

  PendingScanQueueEntry copyWith({
    String? status,
    String? error,
    int? retryCount,
  }) =>
      PendingScanQueueEntry(
        id: id,
        contactId: contactId,
        userId: userId,
        frontImagePath: frontImagePath,
        backImagePath: backImagePath,
        frontImageSha256: frontImageSha256,
        backImageSha256: backImageSha256,
        scannedAt: scannedAt,
        localCardData: localCardData,
        status: status ?? this.status,
        error: error ?? this.error,
        retryCount: retryCount ?? this.retryCount,
      );
}

/// Offline Scan Queue Service.
/// Stores business card scans completed while offline so they can receive full
/// Gemini multimodal visual extraction once network connectivity is re-established.
class OfflineScanQueueService {
  final FlutterSecureStorage _storage;
  static const String _storageKey = 'digital_share_offline_scan_queue';

  /// In-memory queue cache for fast synchronous checks.
  List<PendingScanQueueEntry> _inMemoryQueue = [];
  bool _isLoaded = false;

  OfflineScanQueueService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> _ensureLoaded() async {
    if (_isLoaded) return;
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _inMemoryQueue = list
            .map((item) =>
                PendingScanQueueEntry.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OfflineScanQueue] Failed to read queue: $e');
      }
    }
    _isLoaded = true;
  }

  Future<void> _persist() async {
    try {
      final raw = jsonEncode(_inMemoryQueue.map((e) => e.toJson()).toList());
      await _storage.write(key: _storageKey, value: raw);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OfflineScanQueue] Failed to persist queue: $e');
      }
    }
  }

  /// Enqueues an offline business card scan for subsequent Gemini processing.
  Future<void> enqueueScan({
    required String scanId,
    String? contactId,
    required String userId,
    required String frontImagePath,
    String? backImagePath,
    String? frontSha256,
    String? backSha256,
    required BusinessCardData cardData,
  }) async {
    await _ensureLoaded();
    final entry = PendingScanQueueEntry(
      id: scanId,
      contactId: contactId,
      userId: userId,
      frontImagePath: frontImagePath,
      backImagePath: backImagePath,
      frontImageSha256: frontSha256,
      backImageSha256: backSha256,
      scannedAt: DateTime.now().toUtc(),
      localCardData: cardData.toJson(),
    );
    _inMemoryQueue.removeWhere((e) => e.id == scanId);
    _inMemoryQueue.add(entry);
    await _persist();
    if (kDebugMode) {
      debugPrint('[OfflineScanQueue] Enqueued scan $scanId for user $userId (Total: ${_inMemoryQueue.length})');
    }
  }

  /// Retrieves all pending scans eligible for background Gemini extraction.
  Future<List<PendingScanQueueEntry>> getPendingScans({String? userId}) async {
    await _ensureLoaded();
    return _inMemoryQueue.where((e) {
      if (e.status != 'pending' && e.status != 'failed') return false;
      if (userId != null && e.userId != userId) return false;
      return true;
    }).toList();
  }

  /// Marks a scan entry as completed and removes it from the queue.
  Future<void> markCompleted(String scanId) async {
    await _ensureLoaded();
    _inMemoryQueue.removeWhere((e) => e.id == scanId);
    await _persist();
  }

  /// Marks a scan entry as failed with an error message and increments retry count.
  Future<void> markFailed(String scanId, String error) async {
    await _ensureLoaded();
    final idx = _inMemoryQueue.indexWhere((e) => e.id == scanId);
    if (idx != -1) {
      final item = _inMemoryQueue[idx];
      _inMemoryQueue[idx] = item.copyWith(
        status: 'failed',
        error: error,
        retryCount: item.retryCount + 1,
      );
      await _persist();
    }
  }

  /// Clears all queue items (for test isolation).
  @visibleForTesting
  Future<void> clearQueue() async {
    _inMemoryQueue.clear();
    _isLoaded = true;
    try {
      await _storage.delete(key: _storageKey);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OfflineScanQueue] delete error: $e');
      }
    }
  }
}
