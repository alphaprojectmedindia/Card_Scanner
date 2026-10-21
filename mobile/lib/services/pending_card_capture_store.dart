import 'dart:convert';
import 'dart:io';
import '../models/ocr_side_result.dart';

/// Lightweight local store to track pending camera capture intent (front vs back)
/// and recover staged paths if Android destroys the Activity while the external
/// camera application is running.
class PendingCardCaptureStore {
  static CardSide? inMemorySide;
  static String? inMemoryFrontPath;
  static String? inMemoryBackPath;

  static File get _storeFile {
    final tempDir = Directory.systemTemp.path;
    return File('$tempDir/digital_share_pending_capture.json');
  }

  /// Persists the intent and existing staged images before opening the camera.
  static Future<void> savePendingCapture({
    required CardSide side,
    String? frontPath,
    String? backPath,
  }) async {
    inMemorySide = side;
    inMemoryFrontPath = frontPath;
    inMemoryBackPath = backPath;

    try {
      final file = _storeFile;
      final payload = jsonEncode({
        'side': side.name,
        'frontPath': frontPath,
        'backPath': backPath,
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
          if (timestamp != null &&
              DateTime.now().millisecondsSinceEpoch - timestamp > 15 * 60 * 1000) {
            await clear();
            return null;
          }
          // Update in-memory state as well
          final sideName = data['side'] as String?;
          if (sideName != null) {
            inMemorySide = sideName == CardSide.back.name ? CardSide.back : CardSide.front;
          }
          inMemoryFrontPath = data['frontPath'] as String?;
          inMemoryBackPath = data['backPath'] as String?;
          return data;
        }
      }
    } catch (_) {}

    if (inMemorySide != null) {
      return {
        'side': inMemorySide!.name,
        'frontPath': inMemoryFrontPath,
        'backPath': inMemoryBackPath,
      };
    }

    return null;
  }

  /// Clears the store after successful image recovery, normal return, or cancellation.
  static Future<void> clear() async {
    inMemorySide = null;
    inMemoryFrontPath = null;
    inMemoryBackPath = null;

    try {
      final file = _storeFile;
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  /// Cleans up state synchronously for test isolation.
  static void resetForTesting() {
    inMemorySide = null;
    inMemoryFrontPath = null;
    inMemoryBackPath = null;
    try {
      final file = _storeFile;
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
