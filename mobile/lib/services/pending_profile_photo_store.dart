import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Lightweight persistent store to track pending profile photo camera capture intent
/// and recover lost data if Android destroys MainActivity while the external
/// camera application is running.
class PendingProfilePhotoStore {
  static bool inMemoryPending = false;
  static String? inMemorySource;
  static bool isUploading = false;
  static String? lastUploadedPath;

  static File get _storeFile {
    final tempDir = Directory.systemTemp.path;
    return File('$tempDir/digital_share_pending_profile_photo.json');
  }

  /// Persists the intent before opening the camera.
  static Future<void> savePendingCapture({required String source}) async {
    inMemoryPending = true;
    inMemorySource = source;

    if (kDebugMode) {
      debugPrint('[ProfilePhotoFlow] pending profile-photo operation saved (source: $source)');
    }

    try {
      final file = _storeFile;
      final payload = jsonEncode({
        'action': 'profile_photo_capture',
        'source': source,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      file.writeAsStringSync(payload, flush: true);
    } catch (_) {
      // In-memory fallback remains intact
    }
  }

  /// Reads pending capture data if an Android process restart occurred.
  static Future<Map<String, dynamic>?> loadPendingCapture() async {
    try {
      final file = _storeFile;
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;
          final timestamp = data['timestamp'] as int?;
          // 15-minute expiration
          if (timestamp != null &&
              DateTime.now().millisecondsSinceEpoch - timestamp > 15 * 60 * 1000) {
            await clear();
            return null;
          }
          inMemoryPending = true;
          inMemorySource = data['source'] as String?;
          if (kDebugMode) {
            debugPrint('[ProfilePhotoFlow] pending profile-photo operation found on disk: $data');
          }
          return data;
        }
      }
    } catch (_) {}

    if (inMemoryPending) {
      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] pending profile-photo operation found in-memory (source: $inMemorySource)');
      }
      return {
        'action': 'profile_photo_capture',
        'source': inMemorySource ?? 'camera',
      };
    }

    return null;
  }

  /// Clears the store after successful image recovery, normal return, or cancellation.
  static Future<void> clear() async {
    inMemoryPending = false;
    inMemorySource = null;
    isUploading = false;

    if (kDebugMode) {
      debugPrint('[ProfilePhotoFlow] pending profile-photo operation cleared');
    }

    try {
      final file = _storeFile;
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  /// Marks upload as in-progress to prevent concurrent/duplicate uploads.
  static void markUploadInProgress(bool inProgress) {
    isUploading = inProgress;
  }

  static bool get isUploadInProgress => isUploading;

  /// Cleans up state synchronously for test isolation.
  static void resetForTesting() {
    inMemoryPending = false;
    inMemorySource = null;
    isUploading = false;
    lastUploadedPath = null;
    try {
      final file = _storeFile;
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
