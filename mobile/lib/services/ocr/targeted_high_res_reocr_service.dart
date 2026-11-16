import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../../models/recovered_ocr_observation.dart';
import 'image_hash_service.dart';
import 'ocr_engine.dart';
import 'ocr_observation.dart';
import 'targeted_reocr_cache.dart';
import 'targeted_reocr_uncertainty_detector.dart';

/// Structured result of targeted high-resolution re-OCR on an uncertain card region (Legacy Part 18).
class TargetedReOcrResult {
  final String originalText;
  final String recoveredText;
  final double confidence;
  final bool wasImproved;
  final String engine;
  final Rect targetRegion;

  const TargetedReOcrResult({
    required this.originalText,
    required this.recoveredText,
    required this.confidence,
    required this.wasImproved,
    required this.engine,
    required this.targetRegion,
  });
}

/// Structured response of full targeted region re-OCR execution (Part 22 Stage 3).
class TargetedRegionRecoveryResult {
  final TargetedReOcrRequest request;
  final List<RecoveredOcrObservation> recoveredObservations;
  final CropTransformationMetadata transformationMetadata;
  final bool isFromCache;
  final bool isSuccess;
  final String? errorMessage;

  const TargetedRegionRecoveryResult({
    required this.request,
    this.recoveredObservations = const [],
    required this.transformationMetadata,
    this.isFromCache = false,
    this.isSuccess = true,
    this.errorMessage,
  });
}

/// Service that executes targeted high-resolution re-OCR on uncertain business card regions (Parts 18 & 22).
///
/// Features:
/// 1. Crops directly from the ORIGINAL high-resolution card image (never repeatedly re-OCRs compressed thumbnails).
/// 2. Expands bounding box with safe padding (25% width, 35% height) to prevent clipping ascenders/descenders/plus signs.
/// 3. Upscales conservatively if font glyph height is smaller than 36px.
/// 4. Re-runs PaddleOCR recognition and ML Kit recovery on the isolated region.
/// 5. Restores bounding boxes back into original image coordinate space.
/// 6. Integrates with TargetedReOcrCache for idempotent execution and zero duplicate work.
/// 7. Strictly bounded execution (max 3-4 recovery attempts per card side).
class TargetedHighResReOcrService {
  static const int maxRecoveryAttempts = 3;
  static const String pipelineVersion = '3.0.0';

  final ImageHashService hashService;

  const TargetedHighResReOcrService({
    this.hashService = const ImageHashService(),
  });

  /// Executes full Stage 3 targeted region recovery with coordinate restoration and multi-engine collection.
  Future<TargetedRegionRecoveryResult> reprocessTargetedRegion({
    required String originalImagePath,
    required TargetedReOcrRequest request,
    required OcrEngine primaryEngine,
    OcrEngine? secondaryEngine,
    TargetedReOcrCache? cache,
    String? imageHash,
  }) async {
    final file = File(originalImagePath);
    if (!file.existsSync()) {
      return TargetedRegionRecoveryResult(
        request: request,
        recoveredObservations: const [],
        transformationMetadata: CropTransformationMetadata(
          cropLeft: 0,
          cropTop: 0,
          cropWidth: 0,
          cropHeight: 0,
          originalWidth: 0,
          originalHeight: 0,
        ),
        isSuccess: false,
        errorMessage: 'Original image does not exist at path: $originalImagePath',
      );
    }

    final box = request.targetBoundingBox;

    // 1. Check cache first if available
    final hash = imageHash ?? await hashService.computeFileSha256(originalImagePath);
    if (cache != null && hash.isNotEmpty) {
      final cachedObs = await cache.get(
        imageHash: hash,
        side: request.side,
        cropRect: box,
        engine: '${primaryEngine.name}+${secondaryEngine?.name ?? "none"}',
        reprocessingVersion: pipelineVersion,
      );
      if (cachedObs != null && cachedObs.isNotEmpty) {
        return TargetedRegionRecoveryResult(
          request: request,
          recoveredObservations: cachedObs,
          transformationMetadata: cachedObs.first.transformationMetadata,
          isFromCache: true,
          isSuccess: true,
        );
      }
    }

    String? tempCropPath;
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return TargetedRegionRecoveryResult(
          request: request,
          recoveredObservations: const [],
          transformationMetadata: CropTransformationMetadata(
            cropLeft: 0,
            cropTop: 0,
            cropWidth: 0,
            cropHeight: 0,
            originalWidth: 0,
            originalHeight: 0,
          ),
          isSuccess: false,
          errorMessage: 'Failed to decode original image bytes',
        );
      }

      final upright = img.bakeOrientation(decoded);
      final origW = upright.width;
      final origH = upright.height;

      // Safe contextual padding (25% width, 35% height, minimum 6px)
      final padX = max(6, (box.width * 0.25).round());
      final padY = max(6, (box.height * 0.35).round());

      final cropLeft = max(0, box.left.round() - padX);
      final cropTop = max(0, box.top.round() - padY);
      final cropRight = min(origW - 1, box.right.round() + padX);
      final cropBottom = min(origH - 1, box.bottom.round() + padY);

      final cropW = cropRight - cropLeft + 1;
      final cropH = cropBottom - cropTop + 1;

      if (cropW < 6 || cropH < 6) {
        return TargetedRegionRecoveryResult(
          request: request,
          recoveredObservations: const [],
          transformationMetadata: CropTransformationMetadata(
            cropLeft: cropLeft,
            cropTop: cropTop,
            cropWidth: cropW,
            cropHeight: cropH,
            originalWidth: origW,
            originalHeight: origH,
          ),
          isSuccess: false,
          errorMessage: 'Crop region is too small (< 6px)',
        );
      }

      var cropped = img.copyCrop(
        upright,
        x: cropLeft,
        y: cropTop,
        width: cropW,
        height: cropH,
      );

      // Conservative upscale if glyph height is smaller than 36px
      double scale = 1.0;
      if (cropped.height < 36) {
        scale = (36.0 / cropped.height).clamp(1.0, 3.0);
        cropped = img.copyResize(
          cropped,
          width: (cropped.width * scale).round(),
          height: (cropped.height * scale).round(),
          interpolation: img.Interpolation.linear,
        );
      }

      final transform = CropTransformationMetadata(
        cropLeft: cropLeft,
        cropTop: cropTop,
        cropWidth: cropW,
        cropHeight: cropH,
        padX: padX,
        padY: padY,
        scale: scale,
        originalWidth: origW,
        originalHeight: origH,
      );

      // Save high-resolution crop to temporary file
      final tempDir = Directory.systemTemp.path;
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      tempCropPath = '$tempDir/stage3_target_crop_${request.side.name}_$timestamp.png';
      final tempFile = File(tempCropPath);
      await tempFile.writeAsBytes(img.encodePng(cropped), flush: true);

      final recoveredObservations = <RecoveredOcrObservation>[];

      // Step 1: Run Primary Engine (PaddleOCR) on pristine crop
      try {
        final paddleResult = await primaryEngine.recognize(tempCropPath);
        if (paddleResult.isSuccess) {
          for (int idx = 0; idx < paddleResult.detectedLines.length; idx++) {
            final lineText = paddleResult.detectedLines[idx].trim();
            if (lineText.isEmpty) continue;

            final matchingObs = paddleResult.observations.cast<OcrObservation?>().firstWhere(
                  (o) => o != null && o.text.trim() == lineText,
                  orElse: () => null,
                );

            final cropBox = matchingObs?.boundingBox ??
                Rect.fromLTWH(0, 0, cropped.width.toDouble(), cropped.height.toDouble());

            final mappedBox = transform.mapCropRectToOriginal(cropBox);
            final isUncertain = mappedBox == Rect.zero;

            recoveredObservations.add(RecoveredOcrObservation(
              id: 'rec_${request.side.name}_paddle_${idx}_$timestamp',
              text: lineText,
              sourceEngine: '${primaryEngine.name} (Targeted)',
              side: request.side,
              originalCoordinates: isUncertain ? box : mappedBox,
              cropCoordinates: cropBox,
              transformationMetadata: transform,
              ocrConfidence: matchingObs?.confidence ?? 0.90,
              processingVersion: pipelineVersion,
              reprocessingReason: request.triggerReason,
              isSpatialMappingUncertain: isUncertain,
              createdAt: DateTime.now(),
            ));
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[TargetedReOCR] Primary engine exception: $e');
        }
      }

      // Step 2: Run Secondary Engine (Google ML Kit) on pristine crop if available
      if (secondaryEngine != null) {
        try {
          final secondaryResult = await secondaryEngine.recognize(tempCropPath);
          if (secondaryResult.isSuccess) {
            for (int idx = 0; idx < secondaryResult.detectedLines.length; idx++) {
              final lineText = secondaryResult.detectedLines[idx].trim();
              if (lineText.isEmpty) continue;

              final matchingObs = secondaryResult.observations.cast<OcrObservation?>().firstWhere(
                    (o) => o != null && o.text.trim() == lineText,
                    orElse: () => null,
                  );

              final cropBox = matchingObs?.boundingBox ??
                  Rect.fromLTWH(0, 0, cropped.width.toDouble(), cropped.height.toDouble());

              final mappedBox = transform.mapCropRectToOriginal(cropBox);
              final isUncertain = mappedBox == Rect.zero;

              recoveredObservations.add(RecoveredOcrObservation(
                id: 'rec_${request.side.name}_mlkit_${idx}_$timestamp',
                text: lineText,
                sourceEngine: '${secondaryEngine.name} (Targeted)',
                side: request.side,
                originalCoordinates: isUncertain ? box : mappedBox,
                cropCoordinates: cropBox,
                transformationMetadata: transform,
                ocrConfidence: matchingObs?.confidence ?? 0.90,
                processingVersion: pipelineVersion,
                reprocessingReason: request.triggerReason,
                isSpatialMappingUncertain: isUncertain,
                createdAt: DateTime.now(),
              ));
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[TargetedReOCR] Secondary engine exception: $e');
          }
        }
      }

      // Cache successful recovery results
      if (cache != null && hash.isNotEmpty && recoveredObservations.isNotEmpty) {
        await cache.put(
          imageHash: hash,
          side: request.side,
          cropRect: box,
          engine: '${primaryEngine.name}+${secondaryEngine?.name ?? "none"}',
          reprocessingVersion: pipelineVersion,
          observations: recoveredObservations,
        );
      }

      return TargetedRegionRecoveryResult(
        request: request,
        recoveredObservations: recoveredObservations,
        transformationMetadata: transform,
        isFromCache: false,
        isSuccess: true,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TargetedReOCR] Exception during targeted region re-OCR: $e');
      }
      return TargetedRegionRecoveryResult(
        request: request,
        recoveredObservations: const [],
        transformationMetadata: CropTransformationMetadata(
          cropLeft: 0,
          cropTop: 0,
          cropWidth: 0,
          cropHeight: 0,
          originalWidth: 0,
          originalHeight: 0,
        ),
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      if (tempCropPath != null) {
        try {
          final f = File(tempCropPath);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Legacy observation-level recovery (preserves 100% backward compatibility for Part 18 callers).
  Future<TargetedReOcrResult> recoverRegion({
    required String highResImagePath,
    required OcrObservation observation,
    required OcrEngine primaryEngine,
    OcrEngine? recoveryEngine,
  }) async {
    final file = File(highResImagePath);
    if (!file.existsSync()) {
      return TargetedReOcrResult(
        originalText: observation.text,
        recoveredText: observation.text,
        confidence: observation.confidence,
        wasImproved: false,
        engine: observation.engine,
        targetRegion: observation.boundingBox,
      );
    }

    String? tempCropPath;
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return TargetedReOcrResult(
          originalText: observation.text,
          recoveredText: observation.text,
          confidence: observation.confidence,
          wasImproved: false,
          engine: observation.engine,
          targetRegion: observation.boundingBox,
        );
      }

      final upright = img.bakeOrientation(decoded);
      final box = observation.boundingBox;

      final padX = max(6, (box.width * 0.25).round());
      final padY = max(6, (box.height * 0.35).round());

      final cropLeft = max(0, (box.left - padX).round());
      final cropTop = max(0, (box.top - padY).round());
      final cropRight = min(upright.width - 1, (box.right + padX).round());
      final cropBottom = min(upright.height - 1, (box.bottom + padY).round());

      final cropW = cropRight - cropLeft + 1;
      final cropH = cropBottom - cropTop + 1;

      if (cropW < 8 || cropH < 8) {
        return TargetedReOcrResult(
          originalText: observation.text,
          recoveredText: observation.text,
          confidence: observation.confidence,
          wasImproved: false,
          engine: observation.engine,
          targetRegion: box,
        );
      }

      var cropped = img.copyCrop(
        upright,
        x: cropLeft,
        y: cropTop,
        width: cropW,
        height: cropH,
      );

      if (cropped.height < 36) {
        final scale = (36.0 / cropped.height).clamp(1.0, 3.0);
        cropped = img.copyResize(
          cropped,
          width: (cropped.width * scale).round(),
          height: 36,
          interpolation: img.Interpolation.linear,
        );
      }

      final tempDir = Directory.systemTemp.path;
      tempCropPath =
          '$tempDir/target_reocr_${DateTime.now().microsecondsSinceEpoch}.png';
      final tempFile = File(tempCropPath);
      await tempFile.writeAsBytes(img.encodePng(cropped), flush: true);

      final paddleResult = await primaryEngine.recognize(tempCropPath);
      String bestCandidate = observation.text;
      double bestConfidence = observation.confidence;
      String winningEngine = observation.engine;
      bool improved = false;

      if (paddleResult.isSuccess && paddleResult.detectedLines.isNotEmpty) {
        final paddleText = paddleResult.detectedLines.join(' ').trim();
        final paddleConf = paddleResult.observations.isNotEmpty
            ? paddleResult.observations.map((o) => o.confidence).reduce(min)
            : 0.90;

        if (_isQualityImprovement(observation.text, paddleText, paddleConf, observation.confidence)) {
          bestCandidate = paddleText;
          bestConfidence = paddleConf;
          winningEngine = primaryEngine.name;
          improved = true;
        }
      }

      if ((!improved || bestConfidence < 0.70) && recoveryEngine != null) {
        final recoveryResult = await recoveryEngine.recognize(tempCropPath);
        if (recoveryResult.isSuccess && recoveryResult.detectedLines.isNotEmpty) {
          final recoveryText = recoveryResult.detectedLines.join(' ').trim();
          final recoveryConf = recoveryResult.observations.isNotEmpty
              ? recoveryResult.observations.map((o) => o.confidence).reduce(min)
              : 0.88;

          if (_isQualityImprovement(bestCandidate, recoveryText, recoveryConf, bestConfidence)) {
            bestCandidate = recoveryText;
            bestConfidence = recoveryConf;
            winningEngine = recoveryEngine.name;
            improved = true;
          }
        }
      }

      return TargetedReOcrResult(
        originalText: observation.text,
        recoveredText: bestCandidate,
        confidence: bestConfidence,
        wasImproved: improved,
        engine: winningEngine,
        targetRegion: Rect.fromLTRB(
          cropLeft.toDouble(),
          cropTop.toDouble(),
          cropRight.toDouble(),
          cropBottom.toDouble(),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TargetedReOCR] Exception during region recovery: $e');
      }
      return TargetedReOcrResult(
        originalText: observation.text,
        recoveredText: observation.text,
        confidence: observation.confidence,
        wasImproved: false,
        engine: observation.engine,
        targetRegion: observation.boundingBox,
      );
    } finally {
      if (tempCropPath != null) {
        try {
          final f = File(tempCropPath);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
  }

  bool _isQualityImprovement(
    String original,
    String candidate,
    double candidateConf,
    double originalConf,
  ) {
    if (candidate.trim().isEmpty) return false;
    final origTrim = original.trim();
    final candTrim = candidate.trim();

    if (origTrim == candTrim) return false;

    final emailRegex = RegExp(r'\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b');
    final origHasEmail = emailRegex.hasMatch(origTrim);
    final candHasEmail = emailRegex.hasMatch(candTrim);
    if (!origHasEmail && candHasEmail) return true;

    final origDigits = origTrim.replaceAll(RegExp(r'\D'), '');
    final candDigits = candTrim.replaceAll(RegExp(r'\D'), '');
    if (origDigits.length < 10 && candDigits.length >= 10 && candDigits.length <= 13) {
      return true;
    }

    if (candidateConf > originalConf + 0.15 && candTrim.length >= origTrim.length) {
      return true;
    }

    return false;
  }
}
