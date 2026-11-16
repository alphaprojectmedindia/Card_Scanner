import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../../models/ocr_side_result.dart';
import '../../models/recovered_ocr_observation.dart';

/// Persistent & in-memory cache for targeted high-resolution OCR results (Part 22).
///
/// Ensures idempotent, ultra-fast re-evaluations while preventing redundant on-device
/// inferences.
///
/// Cache keys are strictly bound to:
/// 1. Original image SHA-256 content hash (never filename or path).
/// 2. Card side (front vs back).
/// 3. Crop coordinates (left, top, width, height in original pixel space).
/// 4. OCR engine name and model version.
/// 5. Image preprocessing pipeline version.
/// 6. Reprocessing / parser version.
///
/// Critical security & isolation guarantee:
/// Cache entries are never shared across contacts or company templates.
class TargetedReOcrCache {
  static const String defaultPreprocessingVersion = '2.1.0';
  static const String defaultReprocessingVersion = '3.0.0';

  final Directory? cacheDirectory;
  final Map<String, List<RecoveredOcrObservation>> _memoryCache = {};

  TargetedReOcrCache({this.cacheDirectory});

  /// Computes a canonical, cryptographically isolated cache key.
  static String computeCacheKey({
    required String imageHash,
    required CardSide side,
    required Rect cropRect,
    required String engine,
    String? engineVersion,
    String preprocessingVersion = defaultPreprocessingVersion,
    String reprocessingVersion = defaultReprocessingVersion,
  }) {
    final l = cropRect.left.round();
    final t = cropRect.top.round();
    final w = cropRect.width.round();
    final h = cropRect.height.round();
    final engVer = engineVersion ?? 'v1';

    final rawKey =
        '$imageHash:${side.name}:$l,$t,$w,$h:$engine:$engVer:$preprocessingVersion:$reprocessingVersion';
    return sha256.convert(utf8.encode(rawKey)).toString();
  }

  /// Retrieves cached recovered observations for the given parameters, or null if missed.
  Future<List<RecoveredOcrObservation>?> get({
    required String imageHash,
    required CardSide side,
    required Rect cropRect,
    required String engine,
    String? engineVersion,
    String preprocessingVersion = defaultPreprocessingVersion,
    String reprocessingVersion = defaultReprocessingVersion,
  }) async {
    if (imageHash.trim().isEmpty) return null;

    final key = computeCacheKey(
      imageHash: imageHash,
      side: side,
      cropRect: cropRect,
      engine: engine,
      engineVersion: engineVersion,
      preprocessingVersion: preprocessingVersion,
      reprocessingVersion: reprocessingVersion,
    );

    // 1. Check in-memory cache
    if (_memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }

    // 2. Check disk cache if available
    if (cacheDirectory != null) {
      final file = File('${cacheDirectory!.path}/$key.json');
      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          final list = jsonDecode(content) as List<dynamic>;
          final observations = list
              .map((e) =>
                  RecoveredOcrObservation.fromJson(e as Map<String, dynamic>))
              .toList();
          _memoryCache[key] = observations;
          return observations;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[TargetedReOcrCache] Error reading cache file: $e');
          }
        }
      }
    }

    return null;
  }

  /// Stores recovered observations in both memory and disk cache.
  Future<void> put({
    required String imageHash,
    required CardSide side,
    required Rect cropRect,
    required String engine,
    String? engineVersion,
    String preprocessingVersion = defaultPreprocessingVersion,
    String reprocessingVersion = defaultReprocessingVersion,
    required List<RecoveredOcrObservation> observations,
  }) async {
    if (imageHash.trim().isEmpty) return;

    final key = computeCacheKey(
      imageHash: imageHash,
      side: side,
      cropRect: cropRect,
      engine: engine,
      engineVersion: engineVersion,
      preprocessingVersion: preprocessingVersion,
      reprocessingVersion: reprocessingVersion,
    );

    _memoryCache[key] = List.unmodifiable(observations);

    if (cacheDirectory != null) {
      try {
        if (!await cacheDirectory!.exists()) {
          await cacheDirectory!.create(recursive: true);
        }
        final file = File('${cacheDirectory!.path}/$key.json');
        final jsonStr =
            jsonEncode(observations.map((o) => o.toJson()).toList());
        await file.writeAsString(jsonStr, flush: true);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[TargetedReOcrCache] Error writing cache file: $e');
        }
      }
    }
  }

  /// Invalidates all cached entries associated with an image hash.
  Future<void> invalidateImage(String imageHash) async {
    if (imageHash.trim().isEmpty) return;

    _memoryCache.clear();

    if (cacheDirectory != null && await cacheDirectory!.exists()) {
      try {
        final files = cacheDirectory!.listSync().whereType<File>();
        for (final f in files) {
          try {
            await f.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  /// Clears all in-memory and disk cached entries.
  Future<void> clear() async {
    _memoryCache.clear();
    if (cacheDirectory != null && await cacheDirectory!.exists()) {
      try {
        final files = cacheDirectory!.listSync().whereType<File>();
        for (final f in files) {
          try {
            await f.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }
  }
}

