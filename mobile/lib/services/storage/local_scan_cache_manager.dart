import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../../models/business_card_data.dart';
import '../../models/card_analysis_result.dart';
import '../ocr/ocr_observation.dart';

/// Entry stored in the image fingerprint scan cache.
/// Enhanced in Stage 5 with multi-dimensional cryptographic identity.
class CachedScanEntry {
  final String imageFingerprint;
  final String frontRawText;
  final String? backRawText;
  final BusinessCardData parsedData;
  final DateTime cachedAt;
  final String? associatedContactId;
  final List<Map<String, dynamic>> frontObservations;
  final List<Map<String, dynamic>> backObservations;
  final List<String> frontLines;
  final List<String> backLines;

  // Stage 5 multi-dimensional identity attributes
  final String userId;
  final String? cardSide;
  final String? ocrEngineName;
  final String? ocrModelVersion;
  final String? preprocessingVersion;
  final String? parserVersion;
  final String? reprocessingVersion;
  final String? geminiModelVersion;
  final String? observationFingerprint;

  const CachedScanEntry({
    required this.imageFingerprint,
    required this.frontRawText,
    this.backRawText,
    required this.parsedData,
    required this.cachedAt,
    this.associatedContactId,
    this.frontObservations = const [],
    this.backObservations = const [],
    this.frontLines = const [],
    this.backLines = const [],
    this.userId = 'default_user',
    this.cardSide,
    this.ocrEngineName,
    this.ocrModelVersion,
    this.preprocessingVersion = '1.0.0',
    this.parserVersion = '5.0.0',
    this.reprocessingVersion,
    this.geminiModelVersion,
    this.observationFingerprint,
  });

  Map<String, dynamic> toJson() {
    return {
      'imageFingerprint': imageFingerprint,
      'frontRawText': frontRawText,
      if (backRawText != null) 'backRawText': backRawText,
      'parsedData': parsedData.toJson(),
      'cachedAt': cachedAt.toIso8601String(),
      if (associatedContactId != null) 'associatedContactId': associatedContactId,
      if (frontObservations.isNotEmpty) 'frontObservations': frontObservations,
      if (backObservations.isNotEmpty) 'backObservations': backObservations,
      if (frontLines.isNotEmpty) 'frontLines': frontLines,
      if (backLines.isNotEmpty) 'backLines': backLines,
      'userId': userId,
      if (cardSide != null) 'cardSide': cardSide,
      if (ocrEngineName != null) 'ocrEngineName': ocrEngineName,
      if (ocrModelVersion != null) 'ocrModelVersion': ocrModelVersion,
      if (preprocessingVersion != null) 'preprocessingVersion': preprocessingVersion,
      if (parserVersion != null) 'parserVersion': parserVersion,
      if (reprocessingVersion != null) 'reprocessingVersion': reprocessingVersion,
      if (geminiModelVersion != null) 'geminiModelVersion': geminiModelVersion,
      if (observationFingerprint != null) 'observationFingerprint': observationFingerprint,
    };
  }

  factory CachedScanEntry.fromJson(Map<String, dynamic> json) {
    return CachedScanEntry(
      imageFingerprint: json['imageFingerprint'] as String? ?? '',
      frontRawText: json['frontRawText'] as String? ?? '',
      backRawText: json['backRawText'] as String?,
      parsedData: BusinessCardData.fromJson(json['parsedData'] as Map<String, dynamic>),
      cachedAt: json['cachedAt'] != null
          ? DateTime.tryParse(json['cachedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      associatedContactId: json['associatedContactId'] as String?,
      frontObservations: (json['frontObservations'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      backObservations: (json['backObservations'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      frontLines: (json['frontLines'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      backLines: (json['backLines'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      userId: json['userId'] as String? ?? 'default_user',
      cardSide: json['cardSide'] as String?,
      ocrEngineName: json['ocrEngineName'] as String?,
      ocrModelVersion: json['ocrModelVersion'] as String?,
      preprocessingVersion: json['preprocessingVersion'] as String? ?? '1.0.0',
      parserVersion: json['parserVersion'] as String? ?? '5.0.0',
      reprocessingVersion: json['reprocessingVersion'] as String?,
      geminiModelVersion: json['geminiModelVersion'] as String?,
      observationFingerprint: json['observationFingerprint'] as String?,
    );
  }
}

/// Persistent local cache manager for:
/// 1. Exact image fingerprint scan & OCR reuse.
/// 2. Gemini AI correction reuse across app restarts.
///
/// **Crucial Requirement**: Clearing this cache never touches permanent contacts.
class LocalScanCacheManager {
  final Directory cacheDirectory;

  final Map<String, CachedScanEntry> _fingerprintCache = {};
  final Map<String, Map<String, dynamic>> _geminiCorrectionCache = {};
  bool _isLoaded = false;

  static Directory _resolveDefaultCacheDirectory() {
    try {
      if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'] ??
            Platform.environment['LOCALAPPDATA'];
        if (appData != null && appData.isNotEmpty) {
          return Directory('$appData/digital_share/cache');
        }
      } else if (Platform.isLinux || Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        if (home != null && home.isNotEmpty) {
          return Directory('$home/.digital_share/cache');
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        final parent = Directory.systemTemp.parent;
        return Directory('${parent.path}/app_flutter/cache');
      }
    } catch (_) {}
    return Directory.systemTemp;
  }

  LocalScanCacheManager({Directory? cacheDirectory})
      : cacheDirectory = cacheDirectory ?? _resolveDefaultCacheDirectory();

  File get _fingerprintCacheFile =>
      File('${cacheDirectory.path}/digital_share_fingerprint_cache.json');
  File get _geminiCacheFile =>
      File('${cacheDirectory.path}/digital_share_gemini_cache.json');

  Future<void> _writeQueue = Future.value();

  Future<void> ensureLoaded() async {
    if (_isLoaded) return;
    try {
      // Migration from legacy temporary directory if new default persistent cache is empty
      final defaultDir = _resolveDefaultCacheDirectory();
      if (cacheDirectory.path == defaultDir.path && cacheDirectory.path != Directory.systemTemp.path) {
        final legacyFpFile = File('${Directory.systemTemp.path}/digital_share_fingerprint_cache.json');
        final legacyGemFile = File('${Directory.systemTemp.path}/digital_share_gemini_cache.json');

        if (!_fingerprintCacheFile.existsSync() && legacyFpFile.existsSync()) {
          try {
            cacheDirectory.createSync(recursive: true);
            legacyFpFile.copySync(_fingerprintCacheFile.path);
          } catch (_) {}
        }
        if (!_geminiCacheFile.existsSync() && legacyGemFile.existsSync()) {
          try {
            cacheDirectory.createSync(recursive: true);
            legacyGemFile.copySync(_geminiCacheFile.path);
          } catch (_) {}
        }
      }

      final fpTemp = File('${_fingerprintCacheFile.path}.tmp');
      if ((!_fingerprintCacheFile.existsSync() || _fingerprintCacheFile.lengthSync() == 0) &&
          fpTemp.existsSync()) {
        try {
          if (_fingerprintCacheFile.existsSync()) _fingerprintCacheFile.deleteSync();
          fpTemp.renameSync(_fingerprintCacheFile.path);
        } catch (_) {}
      }

      final gemTemp = File('${_geminiCacheFile.path}.tmp');
      if ((!_geminiCacheFile.existsSync() || _geminiCacheFile.lengthSync() == 0) &&
          gemTemp.existsSync()) {
        try {
          if (_geminiCacheFile.existsSync()) _geminiCacheFile.deleteSync();
          gemTemp.renameSync(_geminiCacheFile.path);
        } catch (_) {}
      }

      if (_fingerprintCacheFile.existsSync()) {
        final content = _fingerprintCacheFile.readAsStringSync();
        if (content.trim().isNotEmpty) {
          final List<dynamic> list = jsonDecode(content) as List<dynamic>;
          for (final item in list) {
            final entry = CachedScanEntry.fromJson(item as Map<String, dynamic>);
            _fingerprintCache[entry.imageFingerprint] = entry;
          }
        }
      }

      if (_geminiCacheFile.existsSync()) {
        final content = _geminiCacheFile.readAsStringSync();
        if (content.trim().isNotEmpty) {
          final Map<String, dynamic> map = jsonDecode(content) as Map<String, dynamic>;
          map.forEach((k, v) {
            if (v is Map<String, dynamic>) {
              _geminiCorrectionCache[k] = v;
            }
          });
        }
      }
    } catch (_) {
      // Safe fallback: in-memory state remains operational
    } finally {
      _isLoaded = true;
    }
  }

  Future<void> _persistFingerprints() {
    _writeQueue = _writeQueue.then((_) => _doPersistFingerprints()).catchError((_) {});
    return _writeQueue;
  }

  Future<void> _doPersistFingerprints() async {
    try {
      if (!await cacheDirectory.exists()) {
        await cacheDirectory.create(recursive: true);
      }
      final list = _fingerprintCache.values.map((e) => e.toJson()).toList();
      final temp = File('${_fingerprintCacheFile.path}.tmp');
      await temp.writeAsString(jsonEncode(list), flush: true);
      if (await _fingerprintCacheFile.exists()) {
        await _fingerprintCacheFile.delete();
      }
      await temp.rename(_fingerprintCacheFile.path);
    } catch (_) {}
  }

  Future<void> _persistGemini() {
    _writeQueue = _writeQueue.then((_) => _doPersistGemini()).catchError((_) {});
    return _writeQueue;
  }

  Future<void> _doPersistGemini() async {
    try {
      if (!await cacheDirectory.exists()) {
        await cacheDirectory.create(recursive: true);
      }
      final temp = File('${_geminiCacheFile.path}.tmp');
      await temp.writeAsString(jsonEncode(_geminiCorrectionCache), flush: true);
      if (await _geminiCacheFile.exists()) {
        await _geminiCacheFile.delete();
      }
      await temp.rename(_geminiCacheFile.path);
    } catch (_) {}
  }

  /// Computes a canonical, cryptographically isolated cache key for scan entries.
  static String computeCanonicalScanKey({
    required String imageFingerprint,
    String? cardSide,
    String? ocrEngineName,
    String? parserVersion,
    String? preprocessingVersion,
    String userId = 'default_user',
  }) {
    final rawKey = '$userId:$imageFingerprint:${cardSide ?? "front"}:${ocrEngineName ?? "hybrid"}:${parserVersion ?? "5.0.0"}:${preprocessingVersion ?? "1.0.0"}';
    return sha256.convert(utf8.encode(rawKey)).toString();
  }

  /// Caches a scan result keyed by the normalized image SHA-256 fingerprint with full identity.
  Future<void> putScanResult({
    required String imageFingerprint,
    required String frontRawText,
    String? backRawText,
    required BusinessCardData parsedData,
    String? contactId,
    List<dynamic>? frontObservations,
    List<dynamic>? backObservations,
    List<String>? frontLines,
    List<String>? backLines,
    String userId = 'default_user',
    String? cardSide,
    String? ocrEngineName,
    String? ocrModelVersion,
    String? preprocessingVersion = '1.0.0',
    String? parserVersion = '5.0.0',
    String? reprocessingVersion,
    String? geminiModelVersion,
    String? observationFingerprint,
  }) async {
    if (imageFingerprint.isEmpty) return;
    await ensureLoaded();

    List<Map<String, dynamic>> serializeObs(List<dynamic>? obs) {
      if (obs == null) return const [];
      final result = <Map<String, dynamic>>[];
      for (final item in obs) {
        if (item is OcrObservation) {
          result.add(item.toJson());
        } else if (item is Map) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
      return result;
    }

    final entry = CachedScanEntry(
      imageFingerprint: imageFingerprint,
      frontRawText: frontRawText,
      backRawText: backRawText,
      parsedData: parsedData,
      cachedAt: DateTime.now(),
      associatedContactId: contactId,
      frontObservations: serializeObs(frontObservations),
      backObservations: serializeObs(backObservations),
      frontLines: frontLines ?? const [],
      backLines: backLines ?? const [],
      userId: userId,
      cardSide: cardSide,
      ocrEngineName: ocrEngineName,
      ocrModelVersion: ocrModelVersion,
      preprocessingVersion: preprocessingVersion,
      parserVersion: parserVersion,
      reprocessingVersion: reprocessingVersion,
      geminiModelVersion: geminiModelVersion,
      observationFingerprint: observationFingerprint,
    );

    _fingerprintCache['$userId:$imageFingerprint'] = entry;
    _fingerprintCache[imageFingerprint] = entry;
    await _persistFingerprints();
  }

  /// Retrieves a previously cached scan by normalized image SHA-256 fingerprint,
  /// strictly validating cache identity against user, parserVersion, and preprocessingVersion.
  Future<CachedScanEntry?> getScanResult(
    String imageFingerprint, {
    String? parserVersion,
    String? preprocessingVersion,
    String userId = 'default_user',
  }) async {
    if (imageFingerprint.isEmpty) return null;
    await ensureLoaded();

    final entry = _fingerprintCache['$userId:$imageFingerprint'] ??
        _fingerprintCache[imageFingerprint];
    if (entry == null) return null;

    // Cross-user contamination check
    if (entry.userId != userId) {
      return null;
    }

    // Version mismatch checks: invalidate stale entries
    if (parserVersion != null && entry.parserVersion != null && entry.parserVersion != parserVersion) {
      return null;
    }
    if (preprocessingVersion != null &&
        entry.preprocessingVersion != null &&
        entry.preprocessingVersion != preprocessingVersion) {
      return null;
    }

    return entry;
  }

  /// Evicts any cached scan entries associated with a specific contact ID.
  Future<void> evictByContactId(String contactId) async {
    if (contactId.isEmpty) return;
    await ensureLoaded();

    final keysToRemove = _fingerprintCache.entries
        .where((e) => e.value.associatedContactId == contactId)
        .map((e) => e.key)
        .toList();

    for (final k in keysToRemove) {
      _fingerprintCache.remove(k);
    }

    if (keysToRemove.isNotEmpty) {
      await _persistFingerprints();
    }
  }

  /// Evicts cached entry by normalized image fingerprint.
  Future<void> evictByImageFingerprint(String imageFingerprint) async {
    if (imageFingerprint.isEmpty) return;
    await ensureLoaded();

    if (_fingerprintCache.containsKey(imageFingerprint)) {
      _fingerprintCache.remove(imageFingerprint);
      await _persistFingerprints();
    }
  }

  /// Caches a Gemini AI correction response.
  Future<void> putGeminiCorrection({
    required String cacheKey,
    required CardAnalysisResult result,
  }) async {
    if (cacheKey.isEmpty) return;
    await ensureLoaded();

    _geminiCorrectionCache[cacheKey] = {
      'data': result.toJson(),
      'cachedAt': DateTime.now().toIso8601String(),
    };
    await _persistGemini();
  }

  /// Retrieves a cached Gemini AI correction response by canonical cache key.
  Future<CardAnalysisResult?> getGeminiCorrection(String cacheKey) async {
    if (cacheKey.isEmpty) return null;
    await ensureLoaded();

    final entry = _geminiCorrectionCache[cacheKey];
    if (entry == null) return null;

    final data = entry['data'] as Map<String, dynamic>?;
    if (data == null) return null;

    try {
      return CardAnalysisResult.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// Clears cached scan entries belonging exclusively to [userId].
  Future<void> clearUserCache(String userId) async {
    await ensureLoaded();
    final keysToRemove = _fingerprintCache.entries
        .where((e) => e.value.userId == userId)
        .map((e) => e.key)
        .toList();
    for (final k in keysToRemove) {
      _fingerprintCache.remove(k);
    }
    if (keysToRemove.isNotEmpty) {
      await _persistFingerprints();
    }
  }

  /// Clears only the temporary scan/fingerprint and Gemini caches.
  /// Permanent contacts are strictly preserved.
  Future<void> clearScanCache() async {
    _fingerprintCache.clear();
    _geminiCorrectionCache.clear();
    try {
      if (await _fingerprintCacheFile.exists()) {
        await _fingerprintCacheFile.delete();
      }
      if (await _geminiCacheFile.exists()) {
        await _geminiCacheFile.delete();
      }
      // Also clean up legacy temporary directory cache if present
      final legacyFp = File('${Directory.systemTemp.path}/digital_share_fingerprint_cache.json');
      if (await legacyFp.exists()) {
        await legacyFp.delete();
      }
      final legacyGem = File('${Directory.systemTemp.path}/digital_share_gemini_cache.json');
      if (await legacyGem.exists()) {
        await legacyGem.delete();
      }
    } catch (_) {}
  }
}
