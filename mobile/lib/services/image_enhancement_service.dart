import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Types of targeted image enhancement for difficult business cards.
enum EnhancementStrategy {
  none,
  inverted,
  contrastBoost,
  scriptEnhanced,
}

/// Service that creates conservative, targeted image enhancements for difficult business cards
/// (e.g., dark cards with light text, washed-out low contrast cards).
class ImageEnhancementService {
  const ImageEnhancementService();

  /// Reads [imagePath], normalizes EXIF orientation to ensure pixels are upright,
  /// and writes to a normalized temporary file if EXIF transformation was needed.
  Future<String> normalizeExifOrientation(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!file.existsSync()) return imagePath;

      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return imagePath;

      // If EXIF orientation is present and not 1 (normal), bake orientation
      final orientation = decoded.exif.imageIfd.orientation;
      if (orientation != null && orientation != 1) {
        final upright = img.bakeOrientation(decoded);
        final tempDir = Directory.systemTemp.path;
        final tempFile = File(
          '$tempDir/digital_share_upright_${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        await tempFile.writeAsBytes(img.encodeJpg(upright, quality: 92), flush: true);
        return tempFile.path;
      }
      return imagePath;
    } catch (e) {
      if (kDebugMode) {
        print('ImageEnhancementService EXIF normalize fallback: $e');
      }
      return imagePath;
    }
  }

  /// Creates an inverted contrast candidate (inverts colors so white/gold text on
  /// dark/black cards becomes dark text on a light background for ML Kit).
  Future<String?> createInvertedCandidate(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!file.existsSync()) return null;

      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final inverted = img.invert(decoded);
      final tempDir = Directory.systemTemp.path;
      final tempFile = File(
        '$tempDir/digital_share_inverted_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(img.encodeJpg(inverted, quality: 90), flush: true);
      return tempFile.path;
    } catch (e) {
      if (kDebugMode) {
        print('ImageEnhancementService inverted candidate error: $e');
      }
      return null;
    }
  }

  /// Creates a contrast-boosted candidate for low-contrast, washed-out, or unevenly lit cards.
  Future<String?> createContrastCandidate(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!file.existsSync()) return null;

      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // Increase contrast by 25% and slightly adjust dynamic range
      final boosted = img.contrast(decoded, contrast: 125);
      final tempDir = Directory.systemTemp.path;
      final tempFile = File(
        '$tempDir/digital_share_contrast_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(img.encodeJpg(boosted, quality: 90), flush: true);
      return tempFile.path;
    } catch (e) {
      if (kDebugMode) {
        print('ImageEnhancementService contrast candidate error: $e');
      }
      return null;
    }
  }

  /// Evaluates whether an image appears to be a dark card with light text.
  Future<bool> isDarkCard(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!file.existsSync()) return false;

      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return false;

      final thumb = img.copyResize(decoded, width: 120, interpolation: img.Interpolation.nearest);
      double totalLum = 0.0;
      final totalPixels = thumb.width * thumb.height;

      for (int y = 0; y < thumb.height; y++) {
        for (int x = 0; x < thumb.width; x++) {
          final p = thumb.getPixel(x, y);
          final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
          totalLum += lum;
        }
      }

      final avgLum = totalPixels > 0 ? (totalLum / totalPixels) : 128.0;
      // If average luminance is low (< 95), card is predominantly dark background
      return avgLum < 95.0;
    } catch (_) {
      return false;
    }
  }

  /// Creates a targeted script/decorative font enhanced candidate:
  /// normalized orientation, moderate upscale if low resolution, grayscale,
  /// contrast normalization, and mild sharpening (without destructive thresholding).
  Future<String?> createScriptEnhancedCandidate(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!file.existsSync()) return null;

      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // 1. Bake EXIF orientation
      var working = img.bakeOrientation(decoded);

      // 2. Moderate upscale if resolution is small (width < 1200 or height < 700)
      if (working.width < 1200 && working.height < 1200) {
        final scale = (1200 / working.width).clamp(1.15, 1.8);
        working = img.copyResize(
          working,
          width: (working.width * scale).round(),
          interpolation: img.Interpolation.linear,
        );
      }

      // 3. Grayscale conversion
      var gray = img.grayscale(working);

      // 4. Contrast normalization: increase contrast by 25% without crushing strokes
      var contrastBoosted = img.contrast(gray, contrast: 125);

      // 5. Mild unsharp sharpening filter to accentuate thin script strokes
      final sharpened = img.convolution(contrastBoosted, filter: [
        0, -1, 0,
        -1, 5, -1,
        0, -1, 0,
      ], div: 1);

      final tempDir = Directory.systemTemp.path;
      final tempFile = File(
        '$tempDir/digital_share_script_enhanced_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(img.encodeJpg(sharpened, quality: 92), flush: true);
      return tempFile.path;
    } catch (e) {
      if (kDebugMode) {
        print('ImageEnhancementService script candidate error: $e');
      }
      return null;
    }
  }
}
