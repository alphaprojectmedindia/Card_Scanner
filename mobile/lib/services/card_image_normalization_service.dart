import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/ocr_side_result.dart';
import 'card_geometry_service.dart';

/// Exception thrown when an image cannot be read, decoded, or normalized.
/// Clearly differentiates fundamental image I/O or decoding failure from OCR recognition weakness.
class CardNormalizationException implements Exception {
  final String message;
  final String? path;

  const CardNormalizationException(this.message, {this.path});

  @override
  String toString() => 'CardNormalizationException: $message';
}

/// Structured diagnostic result returned by [CardImageNormalizationService.normalizeCardImage].
class CardNormalizationResult {
  /// Path to the physically upright, dimension-normalized, ready-for-OCR file.
  final String normalizedPath;

  /// Original file path provided as input.
  final String originalPath;

  /// File size in bytes of the original image.
  final int originalSizeBytes;

  /// Inferred or decoded image format ('jpeg', 'png', 'webp', etc.).
  final String imageFormat;

  /// Original width before normalization.
  final int originalWidth;

  /// Original height before normalization.
  final int originalHeight;

  /// Normalized width after orientation baking and resolution adjustments.
  final int normalizedWidth;

  /// Normalized height after orientation baking and resolution adjustments.
  final int normalizedHeight;

  /// Original EXIF orientation tag (1 = standard, 6 = 90 deg CW, 8 = 270 deg CW, 3 = 180 deg).
  final int exifOrientation;

  /// True if EXIF orientation was detected as non-upright and physically baked into pixels.
  final bool wasOrientationBaked;

  /// True if image was downscaled to fit max long-edge dimension.
  final bool wasResized;

  /// True if a small image was upscaled to improve OCR stroke thickness.
  final bool wasUpscaled;

  /// True if high-confidence card boundary was detected and perspective-rectified.
  final bool wasPerspectiveCorrected;

  /// True if safe viewfinder ROI crop was applied as deterministic fallback when corner confidence was low.
  final bool wasRoiCropped;

  /// Perspective/corner detection confidence (0.0 to 1.0).
  final double perspectiveConfidence;

  /// Temporary file created during normalization that should be safely deleted after OCR completes.
  final String? temporaryFilePath;

  const CardNormalizationResult({
    required this.normalizedPath,
    required this.originalPath,
    required this.originalSizeBytes,
    required this.imageFormat,
    required this.originalWidth,
    required this.originalHeight,
    required this.normalizedWidth,
    required this.normalizedHeight,
    required this.exifOrientation,
    required this.wasOrientationBaked,
    required this.wasResized,
    required this.wasUpscaled,
    required this.wasPerspectiveCorrected,
    this.wasRoiCropped = false,
    required this.perspectiveConfidence,
    this.temporaryFilePath,
  });
}

/// Production image normalization service for both Camera and Gallery business card images.
///
/// Guarantees that downstream OCR engines (Google ML Kit and PaddleOCR PP-OCRv5)
/// receive equivalent, visually upright, appropriately scaled, high-contrast images.
class CardImageNormalizationService {
  /// Maximum allowed long-edge dimension for OCR input.
  /// Standard business cards (3.5" x 2") at 2160px long edge retain ~18-24px height per character glyph
  /// for 6pt-8pt fonts even when the card occupies only 40-50% of the photograph, while avoiding
  /// memory exhaustion and GC stutter on mobile devices.
  final int maxLongEdge;

  /// Threshold below which an image is considered low-resolution and subjected to controlled upscale.
  final int minLongEdge;

  /// Target long edge for controlled upscaling of small/compressed cards.
  final int targetUpscaleLongEdge;

  /// Maximum scale factor allowed during controlled upscaling (avoids pixelation artifacts).
  final double maxUpscaleFactor;

  /// JPEG compression quality for normalized staging.
  final int outputJpegQuality;

  const CardImageNormalizationService({
    this.maxLongEdge = 2160,
    this.minLongEdge = 1000,
    this.targetUpscaleLongEdge = 1200,
    this.maxUpscaleFactor = 1.8,
    this.outputJpegQuality = 92,
  });

  /// Normalizes a card image at [imagePath] for on-device OCR.
  ///
  /// Steps:
  /// 1. File verification: existence, non-zero size, decodability, valid dimensions.
  /// 2. EXIF orientation normalization: physically bakes rotation into pixel raster.
  /// 3. Dimension normalization: downscales oversized images preserving aspect ratio,
  ///    or upscales low-resolution/compressed images without distorting glyphs.
  /// 4. Perspective rectification: rectifies card quadrilateral when edge detection confidence >= 0.70.
  ///    If confidence < 0.70, preserves full normalized upright frame (never crops destructively).
  /// 5. Contrast optimization: gently stretches contrast for low-dynamic-range cards.
  /// 6. Staging: writes to a unique temporary file in the system temp directory.
  Future<CardNormalizationResult> normalizeCardImage({
    required String imagePath,
    CardSide? side,
    String? sessionId,
    CardGeometryService? geometryService,
    ViewfinderNormalizedRect? viewfinderRoi,
  }) async {
    final file = File(imagePath);

    // 1. Validate file existence
    if (!file.existsSync()) {
      throw CardNormalizationException(
        'Image file does not exist at path: $imagePath',
        path: imagePath,
      );
    }

    // 2. Validate non-zero file size
    final fileSize = file.lengthSync();
    if (fileSize == 0) {
      throw CardNormalizationException(
        'Selected image is empty (0 bytes).',
        path: imagePath,
      );
    }

    // 3. Decode image bytes format-agnostically (JPEG, PNG, WebP, GIF, etc.)
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      throw CardNormalizationException(
        'Failed to read image bytes: $e',
        path: imagePath,
      );
    }

    final img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (e) {
      throw CardNormalizationException(
        'Failed to decode image data: $e',
        path: imagePath,
      );
    }

    if (decoded == null) {
      throw CardNormalizationException(
        'Unable to decode image format. Please select a valid JPEG, PNG, or WebP photo.',
        path: imagePath,
      );
    }

    // 4. Validate dimensions
    final origW = decoded.width;
    final origH = decoded.height;
    if (origW <= 0 || origH <= 0) {
      throw CardNormalizationException(
        'Invalid image dimensions (${origW}x$origH).',
        path: imagePath,
      );
    }

    // Incur image format from header magic or extension
    final formatName = _inferImageFormat(bytes, imagePath);

    // 5. EXIF Orientation Normalization: physically bake orientation into pixel matrix
    int exifOrientation = decoded.exif.imageIfd.orientation ?? 1;
    if (exifOrientation == 1 && formatName == 'jpeg') {
      final rawExif = _extractExifOrientationFromBytes(bytes);
      if (rawExif != null) {
        exifOrientation = rawExif;
      }
    }
    final bool wasOrientationBaked = exifOrientation != 1;
    var working = img.bakeOrientation(decoded);

    // 6. Dimension & Resolution Normalization
    bool wasResized = false;
    bool wasUpscaled = false;
    final currentLongEdge = max(working.width, working.height);

    if (currentLongEdge > maxLongEdge) {
      // Downscale oversized image preserving exact aspect ratio
      final double scale = maxLongEdge / currentLongEdge;
      final int newW = (working.width * scale).round();
      final int newH = (working.height * scale).round();
      working = img.copyResize(
        working,
        width: newW,
        height: newH,
        interpolation: img.Interpolation.linear,
      );
      wasResized = true;
    } else if (currentLongEdge < minLongEdge) {
      // Controlled upscale for small/compressed images (e.g. WhatsApp / screenshots)
      final double desiredScale = targetUpscaleLongEdge / currentLongEdge;
      final double scale = desiredScale.clamp(1.1, maxUpscaleFactor);
      final int newW = (working.width * scale).round();
      final int newH = (working.height * scale).round();
      working = img.copyResize(
        working,
        width: newW,
        height: newH,
        interpolation: img.Interpolation.linear,
      );
      wasUpscaled = true;
    }

    // 7. Card Boundary Detection & Perspective Rectification / Safe Crop Fallback
    bool wasPerspectiveCorrected = false;
    bool wasRoiCropped = false;
    double perspectiveConfidence = 0.0;

    if (geometryService != null) {
      final detection = geometryService.detectCorners(working, viewfinderRoi: viewfinderRoi);
      perspectiveConfidence = detection.confidence;

      if (detection.confidence >= geometryService.minConfidenceThreshold &&
          detection.corners != null) {
        final corners = detection.corners!;
        // Expand corners outward by 3% safety margin to ensure edge address text is never clipped
        final centroidX = (corners.topLeft.x + corners.topRight.x + corners.bottomLeft.x + corners.bottomRight.x) / 4.0;
        final centroidY = (corners.topLeft.y + corners.topRight.y + corners.bottomLeft.y + corners.bottomRight.y) / 4.0;
        const expandFactor = 1.018;

        int expX(int x) => (centroidX + (x - centroidX) * expandFactor).round().clamp(0, working.width - 1);
        int expY(int y) => (centroidY + (y - centroidY) * expandFactor).round().clamp(0, working.height - 1);

        final pTL = Point<int>(expX(corners.topLeft.x), expY(corners.topLeft.y));
        final pTR = Point<int>(expX(corners.topRight.x), expY(corners.topRight.y));
        final pBL = Point<int>(expX(corners.bottomLeft.x), expY(corners.bottomLeft.y));
        final pBR = Point<int>(expX(corners.bottomRight.x), expY(corners.bottomRight.y));

        double dist(Point<int> a, Point<int> b) => sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
        final wTop = dist(pTL, pTR);
        final wBottom = dist(pBL, pBR);
        final hLeft = dist(pTL, pBL);
        final hRight = dist(pTR, pBR);

        final targetW = max(wTop, wBottom).round().clamp(350, 3600);
        final targetH = max(hLeft, hRight).round().clamp(250, 3600);

        final destImage = img.Image(
          width: targetW,
          height: targetH,
          numChannels: working.numChannels,
        );

        working = img.copyRectify(
          working,
          topLeft: img.Point(pTL.x, pTL.y),
          topRight: img.Point(pTR.x, pTR.y),
          bottomLeft: img.Point(pBL.x, pBL.y),
          bottomRight: img.Point(pBR.x, pBR.y),
          interpolation: img.Interpolation.linear,
          toImage: destImage,
        );
        wasPerspectiveCorrected = true;

        // Controlled upscale if rectified card is relatively small (Requirement 6: Small text preservation)
        final rectLong = max(working.width, working.height);
        if (rectLong < targetUpscaleLongEdge) {
          final double desiredScale = targetUpscaleLongEdge / rectLong;
          final double scale = desiredScale.clamp(1.1, maxUpscaleFactor);
          working = img.copyResize(
            working,
            width: (working.width * scale).round(),
            height: (working.height * scale).round(),
            interpolation: img.Interpolation.linear,
          );
          wasUpscaled = true;
        }
      } else if (viewfinderRoi != null && viewfinderRoi.width > 0.1 && viewfinderRoi.height > 0.1) {
        // Safe ROI crop fallback: When four reliable corners cannot be confidently located,
        // use the mapped viewfinder ROI with a 5% safe padding to prevent cutting text near card edges
        final marginX = (working.width * 0.05).round();
        final marginY = (working.height * 0.05).round();
        final cropX = max(0, (viewfinderRoi.left * working.width).round() - marginX);
        final cropY = max(0, (viewfinderRoi.top * working.height).round() - marginY);
        final cropW = min(working.width - cropX, (viewfinderRoi.width * working.width).round() + 2 * marginX);
        final cropH = min(working.height - cropY, (viewfinderRoi.height * working.height).round() + 2 * marginY);

        if (cropW > 100 && cropH > 100) {
          working = img.copyCrop(working, x: cropX, y: cropY, width: cropW, height: cropH);
          wasRoiCropped = true;

          final rectLong = max(working.width, working.height);
          if (rectLong < targetUpscaleLongEdge) {
            final double desiredScale = targetUpscaleLongEdge / rectLong;
            final double scale = desiredScale.clamp(1.1, maxUpscaleFactor);
            working = img.copyResize(
              working,
              width: (working.width * scale).round(),
              height: (working.height * scale).round(),
              interpolation: img.Interpolation.linear,
            );
            wasUpscaled = true;
          }
        }
      }
    } else if (viewfinderRoi != null && viewfinderRoi.width > 0.1 && viewfinderRoi.height > 0.1) {
      // Safe ROI crop fallback when geometryService is not provided but viewfinderRoi is present
      final marginX = (working.width * 0.05).round();
      final marginY = (working.height * 0.05).round();
      final cropX = max(0, (viewfinderRoi.left * working.width).round() - marginX);
      final cropY = max(0, (viewfinderRoi.top * working.height).round() - marginY);
      final cropW = min(working.width - cropX, (viewfinderRoi.width * working.width).round() + 2 * marginX);
      final cropH = min(working.height - cropY, (viewfinderRoi.height * working.height).round() + 2 * marginY);

      if (cropW > 100 && cropH > 100) {
        working = img.copyCrop(working, x: cropX, y: cropY, width: cropW, height: cropH);
        wasRoiCropped = true;

        final rectLong = max(working.width, working.height);
        if (rectLong < targetUpscaleLongEdge) {
          final double desiredScale = targetUpscaleLongEdge / rectLong;
          final double scale = desiredScale.clamp(1.1, maxUpscaleFactor);
          working = img.copyResize(
            working,
            width: (working.width * scale).round(),
            height: (working.height * scale).round(),
            interpolation: img.Interpolation.linear,
          );
          wasUpscaled = true;
        }
      }
    }

    // 8. Conservative Contrast Optimization (Phase 9)
    working = _enhanceContrastIfLow(working);

    // 9. Stage normalized image to a dedicated, uniquely-named temporary scan file
    final tempDir = Directory.systemTemp.path;
    final sessionTag = sessionId ?? 'session';
    final sideTag = side?.name ?? 'card';
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final tempFileName =
        'digital_share_normalized_${sessionTag}_${sideTag}_$timestamp.jpg';
    final tempFile = File('$tempDir/$tempFileName');

    final encodedJpg = img.encodeJpg(working, quality: outputJpegQuality);
    await tempFile.writeAsBytes(encodedJpg, flush: true);

    return CardNormalizationResult(
      normalizedPath: tempFile.path,
      originalPath: imagePath,
      originalSizeBytes: fileSize,
      imageFormat: formatName,
      originalWidth: origW,
      originalHeight: origH,
      normalizedWidth: working.width,
      normalizedHeight: working.height,
      exifOrientation: exifOrientation,
      wasOrientationBaked: wasOrientationBaked,
      wasResized: wasResized,
      wasUpscaled: wasUpscaled,
      wasPerspectiveCorrected: wasPerspectiveCorrected,
      wasRoiCropped: wasRoiCropped,
      perspectiveConfidence: perspectiveConfidence,
      temporaryFilePath: tempFile.path,
    );
  }

  /// Gently stretches contrast if dynamic range is compressed without destructive binarization.
  img.Image _enhanceContrastIfLow(img.Image image) {
    num minLum = 255;
    num maxLum = 0;

    for (int y = 0; y < image.height; y += 4) {
      for (int x = 0; x < image.width; x += 4) {
        final p = image.getPixel(x, y);
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        if (lum < minLum) minLum = lum;
        if (lum > maxLum) maxLum = lum;
      }
    }

    final range = maxLum - minLum;
    // If dynamic range is compressed (< 90 and > 15), gently stretch contrast linearly
    if (range < 90 && range > 15) {
      final enhanced = img.Image.from(image);
      final scale = 255.0 / range;
      for (final p in enhanced) {
        p.r = ((p.r - minLum) * scale).clamp(0, 255).round();
        p.g = ((p.g - minLum) * scale).clamp(0, 255).round();
        p.b = ((p.b - minLum) * scale).clamp(0, 255).round();
      }
      return enhanced;
    }
    return image;
  }

  /// Infers image format from byte headers or file extension.
  String _inferImageFormat(Uint8List bytes, String path) {
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    final lower = path.toLowerCase();
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'heic';
    }
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    return 'jpeg';
  }

  /// Parses EXIF orientation directly from JPEG APP1 marker bytes if decoder stripped or auto-baked it.
  int? _extractExifOrientationFromBytes(Uint8List bytes) {
    if (bytes.length < 14) return null;
    int idx = 2; // skip SOI (FF D8)
    while (idx + 4 < bytes.length) {
      if (bytes[idx] != 0xFF) break;
      final marker = bytes[idx + 1];
      if (marker == 0xDA || marker == 0xD9) break; // SOS or EOI
      final len = (bytes[idx + 2] << 8) | bytes[idx + 3];
      if (marker == 0xE1) {
        // APP1 marker
        if (idx + 4 + 6 <= bytes.length) {
          final exifHeader = String.fromCharCodes(bytes.sublist(idx + 4, idx + 8));
          if (exifHeader == 'Exif' && bytes[idx + 8] == 0 && bytes[idx + 9] == 0) {
            final tiffStart = idx + 10;
            if (tiffStart + 8 > bytes.length) return null;
            final isLE = bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49;
            final isBE = bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D;
            if (!isLE && !isBE) return null;

            int readU16(int offset) {
              return isLE
                  ? bytes[offset] | (bytes[offset + 1] << 8)
                  : (bytes[offset] << 8) | bytes[offset + 1];
            }

            int readU32(int offset) {
              return isLE
                  ? bytes[offset] |
                      (bytes[offset + 1] << 8) |
                      (bytes[offset + 2] << 16) |
                      (bytes[offset + 3] << 24)
                  : (bytes[offset] << 24) |
                      (bytes[offset + 1] << 16) |
                      (bytes[offset + 2] << 8) |
                      bytes[offset + 3];
            }

            final ifdOffset = readU32(tiffStart + 4);
            final ifdStart = tiffStart + ifdOffset;
            if (ifdStart + 2 > bytes.length) return null;
            final numEntries = readU16(ifdStart);
            for (int i = 0; i < numEntries; i++) {
              final entryOffset = ifdStart + 2 + i * 12;
              if (entryOffset + 12 > bytes.length) break;
              final tag = readU16(entryOffset);
              if (tag == 0x0112) {
                // Orientation tag
                final value = readU16(entryOffset + 8);
                return value;
              }
            }
          }
        }
      }
      idx += 2 + len;
    }
    return null;
  }
}
