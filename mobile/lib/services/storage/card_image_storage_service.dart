import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../models/ocr_side_result.dart';
import 'local_contact_repository.dart';

/// Result of storing front and/or back card images permanently.
class PermanentImageResult {
  final String? permanentFrontPath;
  final String? permanentBackPath;
  final bool frontStoredSuccessfully;
  final bool backStoredSuccessfully;
  final List<String> warnings;

  const PermanentImageResult({
    this.permanentFrontPath,
    this.permanentBackPath,
    this.frontStoredSuccessfully = false,
    this.backStoredSuccessfully = false,
    this.warnings = const [],
  });

  bool get hasAnyPermanentImage =>
      (permanentFrontPath != null && frontStoredSuccessfully) ||
      (permanentBackPath != null && backStoredSuccessfully);

  bool get isDualSidePermanent =>
      frontStoredSuccessfully && backStoredSuccessfully;
}

/// Diagnostic report summarizing migration of existing contact records.
class ImageMigrationReport {
  final int totalRecordsChecked;
  final int frontImagesMigrated;
  final int backImagesMigrated;
  final int alreadyPermanentCount;
  final int missingImagesCount;
  final List<String> unrecoverableRecordIds;

  const ImageMigrationReport({
    required this.totalRecordsChecked,
    required this.frontImagesMigrated,
    required this.backImagesMigrated,
    required this.alreadyPermanentCount,
    required this.missingImagesCount,
    required this.unrecoverableRecordIds,
  });

  @override
  String toString() =>
      'ImageMigrationReport(checked: $totalRecordsChecked, frontMigrated: $frontImagesMigrated, '
      'backMigrated: $backImagesMigrated, alreadyPermanent: $alreadyPermanentCount, '
      'missing: $missingImagesCount, unrecoverable: ${unrecoverableRecordIds.length})';
}

/// Service that manages the complete lifecycle of business-card images.
///
/// Guarantees:
/// 1. Original front and back card images are copied to persistent application storage before temp files are deleted.
/// 2. Stable naming: `{contactId}_front.{ext}` and `{contactId}_back.{ext}`.
/// 3. Verification: checks file existence, non-zero length, and header readability.
/// 4. Immutability: original image bytes are preserved intact; enhanced crops are stored in separate files.
/// 5. Crash safety & temp cleanup: temporary files are only deleted after verified permanent persistence.
/// 6. Honest migration: records whose temp files were already destroyed are reported as missing, never falsely claimed.
class CardImageStorageService {
  final Directory baseDirectory;

  CardImageStorageService({Directory? baseDirectory})
      : baseDirectory = baseDirectory ?? _resolveDefaultBaseDirectory();

  static Directory _resolveDefaultBaseDirectory() {
    try {
      if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'] ??
            Platform.environment['LOCALAPPDATA'];
        if (appData != null && appData.isNotEmpty) {
          return Directory('$appData/digital_share');
        }
      } else if (Platform.isLinux || Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        if (home != null && home.isNotEmpty) {
          return Directory('$home/.digital_share');
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        final parent = Directory.systemTemp.parent;
        return Directory('${parent.path}/app_flutter');
      }
    } catch (_) {}
    return Directory.systemTemp;
  }

  /// Directory dedicated to permanent original card images.
  Directory get imageDirectory =>
      Directory('${baseDirectory.path}/cards/images');

  /// Directory dedicated to derived/enhanced images (kept separate from originals).
  Directory get enhancedImageDirectory =>
      Directory('${baseDirectory.path}/cards/enhanced');

  /// Ensures storage directories exist on disk.
  Future<void> ensureDirectoriesExist() async {
    if (!await imageDirectory.exists()) {
      await imageDirectory.create(recursive: true);
    }
    if (!await enhancedImageDirectory.exists()) {
      await enhancedImageDirectory.create(recursive: true);
    }
  }

  /// Verifies whether an image file exists, has a non-zero byte size, and is readable.
  Future<bool> verifyImageFile(String? filePath) async {
    if (filePath == null || filePath.trim().isEmpty) return false;
    final file = File(filePath);
    try {
      if (!await file.exists()) return false;
      final length = await file.length();
      if (length <= 0) return false;

      // Verify that initial bytes can be read without I/O failure
      final raf = await file.open(mode: FileMode.read);
      try {
        final sample = await raf.read(min(32, length));
        if (sample.isEmpty) return false;
      } finally {
        await raf.close();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Synchronous verification helper.
  bool verifyImageFileSync(String? filePath) {
    if (filePath == null || filePath.trim().isEmpty) return false;
    final file = File(filePath);
    try {
      if (!file.existsSync()) return false;
      final length = file.lengthSync();
      if (length <= 0) return false;

      final raf = file.openSync(mode: FileMode.read);
      try {
        final sample = raf.readSync(min(32, length));
        if (sample.isEmpty) return false;
      } finally {
        raf.closeSync();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Checks if a file path is already located inside the permanent image directory.
  bool isPermanentPath(String? filePath) {
    if (filePath == null || filePath.isEmpty) return false;
    final normDir = imageDirectory.path.replaceAll('\\', '/').toLowerCase();
    final normPath = filePath.replaceAll('\\', '/').toLowerCase();
    return normPath.startsWith(normDir);
  }

  /// Stores original front and/or back card images into persistent storage.
  ///
  /// Temporary files are safely cleaned up ONLY after successful verification of the target permanent file.
  Future<PermanentImageResult> storeCardImages({
    required String contactId,
    String? tempFrontPath,
    String? tempBackPath,
    bool cleanupTempOnSuccess = true,
  }) async {
    await ensureDirectoriesExist();

    final warnings = <String>[];
    String? finalFrontPath;
    String? finalBackPath;
    bool frontSuccess = false;
    bool backSuccess = false;

    // 1. Process Front Image
    if (tempFrontPath != null && tempFrontPath.trim().isNotEmpty) {
      if (isPermanentPath(tempFrontPath)) {
        if (await verifyImageFile(tempFrontPath)) {
          finalFrontPath = tempFrontPath;
          frontSuccess = true;
        } else {
          warnings.add('Existing front permanent file corrupted or empty: $tempFrontPath');
        }
      } else {
        final sourceFile = File(tempFrontPath);
        if (await sourceFile.exists() && await sourceFile.length() > 0) {
          final ext = _extractExtension(tempFrontPath);
          final sanitizedId = _sanitizeFilename(contactId);
          final destFile = File('${imageDirectory.path}/${sanitizedId}_front$ext');
          final tempDestFile = File('${destFile.path}.tmp');

          try {
            // Atomic copy: write to .tmp, verify, then rename with safe backup rollback
            await sourceFile.copy(tempDestFile.path);
            if (await verifyImageFile(tempDestFile.path)) {
              final backupDestFile = File('${destFile.path}.bak');
              if (await destFile.exists()) {
                if (await backupDestFile.exists()) await backupDestFile.delete();
                await destFile.rename(backupDestFile.path);
              }

              try {
                await tempDestFile.rename(destFile.path);
                if (await verifyImageFile(destFile.path)) {
                  if (await backupDestFile.exists()) await backupDestFile.delete();
                  finalFrontPath = destFile.path;
                  frontSuccess = true;

                  if (cleanupTempOnSuccess) {
                    await _safeDeleteTempFile(tempFrontPath);
                  }
                } else {
                  // Rollback if verification failed
                  if (await backupDestFile.exists()) await backupDestFile.rename(destFile.path);
                  warnings.add('Front image rename verification failed: ${destFile.path}');
                }
              } catch (e) {
                if (await backupDestFile.exists()) await backupDestFile.rename(destFile.path);
                rethrow;
              }
            } else {
              warnings.add('Front image copy verification failed: ${tempDestFile.path}');
              if (await tempDestFile.exists()) await tempDestFile.delete();
            }
          } catch (e) {
            warnings.add('Exception copying front image: $e');
            if (await tempDestFile.exists()) await tempDestFile.delete();
          }
        } else {
          warnings.add('Source front image does not exist or is empty: $tempFrontPath');
        }
      }
    }

    // 2. Process Back Image
    if (tempBackPath != null && tempBackPath.trim().isNotEmpty) {
      if (isPermanentPath(tempBackPath)) {
        if (await verifyImageFile(tempBackPath)) {
          finalBackPath = tempBackPath;
          backSuccess = true;
        } else {
          warnings.add('Existing back permanent file corrupted or empty: $tempBackPath');
        }
      } else {
        final sourceFile = File(tempBackPath);
        if (await sourceFile.exists() && await sourceFile.length() > 0) {
          final ext = _extractExtension(tempBackPath);
          final sanitizedId = _sanitizeFilename(contactId);
          final destFile = File('${imageDirectory.path}/${sanitizedId}_back$ext');
          final tempDestFile = File('${destFile.path}.tmp');

          try {
            await sourceFile.copy(tempDestFile.path);
            if (await verifyImageFile(tempDestFile.path)) {
              final backupDestFile = File('${destFile.path}.bak');
              if (await destFile.exists()) {
                if (await backupDestFile.exists()) await backupDestFile.delete();
                await destFile.rename(backupDestFile.path);
              }

              try {
                await tempDestFile.rename(destFile.path);
                if (await verifyImageFile(destFile.path)) {
                  if (await backupDestFile.exists()) await backupDestFile.delete();
                  finalBackPath = destFile.path;
                  backSuccess = true;

                  if (cleanupTempOnSuccess) {
                    await _safeDeleteTempFile(tempBackPath);
                  }
                } else {
                  if (await backupDestFile.exists()) await backupDestFile.rename(destFile.path);
                  warnings.add('Back image rename verification failed: ${destFile.path}');
                }
              } catch (e) {
                if (await backupDestFile.exists()) await backupDestFile.rename(destFile.path);
                rethrow;
              }
            } else {
              warnings.add('Back image copy verification failed: ${tempDestFile.path}');
              if (await tempDestFile.exists()) await tempDestFile.delete();
            }
          } catch (e) {
            warnings.add('Exception copying back image: $e');
            if (await tempDestFile.exists()) await tempDestFile.delete();
          }
        } else {
          warnings.add('Source back image does not exist or is empty: $tempBackPath');
        }
      }
    }

    return PermanentImageResult(
      permanentFrontPath: finalFrontPath,
      permanentBackPath: finalBackPath,
      frontStoredSuccessfully: frontSuccess,
      backStoredSuccessfully: backSuccess,
      warnings: warnings,
    );
  }

  /// Stores derived enhanced image separately, strictly preserving original image bytes.
  Future<String?> storeEnhancedImage({
    required String contactId,
    required CardSide side,
    required Uint8List enhancedBytes,
  }) async {
    if (enhancedBytes.isEmpty) return null;
    await ensureDirectoriesExist();

    final sanitizedId = _sanitizeFilename(contactId);
    final destFile = File('${enhancedImageDirectory.path}/${sanitizedId}_${side.name}_enhanced.jpg');
    final tempDest = File('${destFile.path}.tmp');

    try {
      await tempDest.writeAsBytes(enhancedBytes, flush: true);
      if (await verifyImageFile(tempDest.path)) {
        if (await destFile.exists()) await destFile.delete();
        await tempDest.rename(destFile.path);
        return destFile.path;
      }
      if (await tempDest.exists()) await tempDest.delete();
      return null;
    } catch (_) {
      if (await tempDest.exists()) await tempDest.delete();
      return null;
    }
  }

  /// Safely cleans up temporary images, ensuring permanent directory files are NEVER deleted.
  Future<void> _safeDeleteTempFile(String filePath) async {
    try {
      if (isPermanentPath(filePath)) return; // Strict guard: never delete permanent image
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Deletes permanent images when a contact is permanently removed.
  Future<void> deleteContactImages(String contactId) async {
    final sanitizedId = _sanitizeFilename(contactId);
    try {
      if (await imageDirectory.exists()) {
        final list = await imageDirectory.list().toList();
        for (final entity in list) {
          if (entity is File && entity.path.contains('${sanitizedId}_')) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
      if (await enhancedImageDirectory.exists()) {
        final list = await enhancedImageDirectory.list().toList();
        for (final entity in list) {
          if (entity is File && entity.path.contains('${sanitizedId}_')) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// Scans existing [LocalContactRepository] records and migrates any remaining temporary images
  /// into permanent storage.
  ///
  /// Truthful accounting: If an image was already deleted by OS temp cleanup, it is honestly
  /// counted as missing rather than falsely claimed as recovered.
  Future<ImageMigrationReport> migrateExistingRecords(
    LocalContactRepository repository,
  ) async {
    await ensureDirectoriesExist();
    await repository.ensureLoaded();

    int totalChecked = 0;
    int frontMigrated = 0;
    int backMigrated = 0;
    int alreadyPermanent = 0;
    int missingCount = 0;
    final unrecoverableIds = <String>[];

    final records = await repository.getAllRecords();
    totalChecked = records.length;

    for (final record in records) {
      bool recordNeedsUpdate = false;
      String? newFront = record.frontImagePath;
      String? newBack = record.backImagePath;

      // Front image check
      if (record.frontImagePath != null && record.frontImagePath!.isNotEmpty) {
        if (isPermanentPath(record.frontImagePath)) {
          if (await verifyImageFile(record.frontImagePath)) {
            alreadyPermanent++;
          } else {
            missingCount++;
            unrecoverableIds.add(record.id);
          }
        } else {
          final res = await storeCardImages(
            contactId: record.id,
            tempFrontPath: record.frontImagePath,
            cleanupTempOnSuccess: false, // Keep source during migration
          );
          if (res.frontStoredSuccessfully && res.permanentFrontPath != null) {
            newFront = res.permanentFrontPath;
            frontMigrated++;
            recordNeedsUpdate = true;
          } else {
            missingCount++;
            unrecoverableIds.add(record.id);
          }
        }
      }

      // Back image check
      if (record.backImagePath != null && record.backImagePath!.isNotEmpty) {
        if (isPermanentPath(record.backImagePath)) {
          if (await verifyImageFile(record.backImagePath)) {
            alreadyPermanent++;
          } else {
            missingCount++;
            if (!unrecoverableIds.contains(record.id)) {
              unrecoverableIds.add(record.id);
            }
          }
        } else {
          final res = await storeCardImages(
            contactId: record.id,
            tempBackPath: record.backImagePath,
            cleanupTempOnSuccess: false,
          );
          if (res.backStoredSuccessfully && res.permanentBackPath != null) {
            newBack = res.permanentBackPath;
            backMigrated++;
            recordNeedsUpdate = true;
          } else {
            missingCount++;
            if (!unrecoverableIds.contains(record.id)) {
              unrecoverableIds.add(record.id);
            }
          }
        }
      }

      if (recordNeedsUpdate) {
        final updatedRecord = record.copyWith(
          frontImagePath: newFront,
          backImagePath: newBack,
        );
        await repository.updateLocalRecord(updatedRecord);
      }
    }

    return ImageMigrationReport(
      totalRecordsChecked: totalChecked,
      frontImagesMigrated: frontMigrated,
      backImagesMigrated: backMigrated,
      alreadyPermanentCount: alreadyPermanent,
      missingImagesCount: missingCount,
      unrecoverableRecordIds: unrecoverableIds.toSet().toList(),
    );
  }

  String _extractExtension(String path) {
    final idx = path.lastIndexOf('.');
    if (idx != -1 && idx > path.lastIndexOf(Platform.pathSeparator)) {
      final ext = path.substring(idx).toLowerCase();
      if (['.jpg', '.jpeg', '.png', '.webp'].contains(ext)) {
        return ext == '.jpeg' ? '.jpg' : ext;
      }
    }
    return '.jpg';
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }

  int min(int a, int b) => a < b ? a : b;
}

