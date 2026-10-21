import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Categorization of image quality for business card OCR readability.
enum ImageQualityStatus {
  good,
  usableWithWarning,
  poorRetakeRecommended,
}

/// Centralized, configurable thresholds for image quality assessment.
class ImageQualityThresholds {
  /// Minimum recommended image width in pixels.
  final int minWidth;

  /// Minimum recommended image height in pixels.
  final int minHeight;

  /// Laplacian variance threshold below which an image is considered severely blurred.
  final double minBlurScore;

  /// Mean luminance (0-255) below which an image is considered severely underexposed (too dark).
  final double minLuminance;

  /// Mean luminance (0-255) above which an image is considered severely overexposed (washed out).
  final double maxLuminance;

  /// Ratio of blown-out highlight pixels (>245) above which glare/overexposure is flagged.
  final double maxBlownOutRatio;

  const ImageQualityThresholds({
    this.minWidth = 500,
    this.minHeight = 350,
    this.minBlurScore = 60.0,
    this.minLuminance = 42.0,
    this.maxLuminance = 228.0,
    this.maxBlownOutRatio = 0.38,
  });

  static const ImageQualityThresholds standard = ImageQualityThresholds();
}

/// Measurable quality metrics extracted from a business card photograph.
class ImageQualityMetrics {
  final int width;
  final int height;
  final double blurScore;
  final double averageLuminance;
  final double blownOutRatio;

  const ImageQualityMetrics({
    required this.width,
    required this.height,
    required this.blurScore,
    required this.averageLuminance,
    required this.blownOutRatio,
  });

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'blurScore': double.parse(blurScore.toStringAsFixed(2)),
        'averageLuminance': double.parse(averageLuminance.toStringAsFixed(2)),
        'blownOutRatio': double.parse(blownOutRatio.toStringAsFixed(3)),
      };
}

/// Comprehensive outcome of image quality evaluation.
class ImageQualityResult {
  final ImageQualityStatus status;
  final List<String> warnings;
  final ImageQualityMetrics metrics;

  const ImageQualityResult({
    required this.status,
    required this.warnings,
    required this.metrics,
  });

  bool get isGood => status == ImageQualityStatus.good;
  bool get isUsable => status != ImageQualityStatus.poorRetakeRecommended;
  bool get isPoor => status == ImageQualityStatus.poorRetakeRecommended;

  bool get isBlurry => warnings.any((w) => w.toLowerCase().contains('blur'));
  bool get isUnderexposed =>
      warnings.any((w) => w.toLowerCase().contains('dark') || w.toLowerCase().contains('underexposed'));
  bool get isOverexposed =>
      warnings.any((w) => w.toLowerCase().contains('glare') || w.toLowerCase().contains('overexposed'));
  bool get isTooSmall => warnings.any((w) => w.toLowerCase().contains('resolution'));

  factory ImageQualityResult.good({
    int width = 1200,
    int height = 800,
    double blurScore = 150.0,
    double averageLuminance = 135.0,
    double blownOutRatio = 0.05,
  }) {
    return ImageQualityResult(
      status: ImageQualityStatus.good,
      warnings: const [],
      metrics: ImageQualityMetrics(
        width: width,
        height: height,
        blurScore: blurScore,
        averageLuminance: averageLuminance,
        blownOutRatio: blownOutRatio,
      ),
    );
  }
}

/// Lightweight, cross-platform service evaluating photographic quality of business cards
/// prior to OCR, detecting blur, underexposure, glare/overexposure, and resolution limits.
class ImageQualityService {
  final ImageQualityThresholds thresholds;

  const ImageQualityService({
    this.thresholds = ImageQualityThresholds.standard,
  });

  /// Evaluates an image file at [imagePath].
  /// Returns [ImageQualityResult] with objective classification and warnings.
  Future<ImageQualityResult> evaluateImagePath(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!file.existsSync()) {
        return _fallbackResult('Image file does not exist on disk.');
      }
      final bytes = await file.readAsBytes();
      return evaluateBytes(bytes);
    } catch (e) {
      if (kDebugMode) {
        print('ImageQualityService error evaluating $imagePath: $e');
      }
      return _fallbackResult('Unable to evaluate image file.');
    }
  }

  /// Evaluates raw image bytes synchronously or via decoded image.
  ImageQualityResult evaluateBytes(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return _fallbackResult('Unsupported image format.');
      }
      return evaluateImage(decoded);
    } catch (e) {
      return _fallbackResult('Failed to decode image data.');
    }
  }

  /// Evaluates an in-memory [img.Image].
  ImageQualityResult evaluateImage(img.Image image) {
    final originalWidth = image.width;
    final originalHeight = image.height;
    final warnings = <String>[];

    // 1. Check dimensions
    final isTooSmall = originalWidth < thresholds.minWidth || originalHeight < thresholds.minHeight;
    if (isTooSmall) {
      warnings.add('Low resolution (${originalWidth}x$originalHeight). Small text may be difficult to read.');
    }

    // 2. Downsample thumbnail for fast metric analysis (<15ms)
    final evalThumb = img.copyResize(
      image,
      width: originalWidth > originalHeight ? 320 : 240,
      interpolation: img.Interpolation.nearest,
    );

    // 3. Compute luminance statistics
    double totalLum = 0.0;
    int blownOutPixels = 0;
    final pixelCount = evalThumb.width * evalThumb.height;

    for (int y = 0; y < evalThumb.height; y++) {
      for (int x = 0; x < evalThumb.width; x++) {
        final pixel = evalThumb.getPixel(x, y);
        // Standard Rec. 601 luma: 0.299 R + 0.587 G + 0.114 B
        final lum = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        totalLum += lum;
        if (lum > 245) {
          blownOutPixels++;
        }
      }
    }

    final avgLum = pixelCount > 0 ? (totalLum / pixelCount) : 128.0;
    final blownOutRatio = pixelCount > 0 ? (blownOutPixels / pixelCount) : 0.0;

    final isUnderexposed = avgLum < thresholds.minLuminance;
    final isOverexposed = avgLum > thresholds.maxLuminance || blownOutRatio > thresholds.maxBlownOutRatio;

    if (isUnderexposed) {
      warnings.add('Photo is dark / underexposed. Text may lack contrast.');
    }
    if (isOverexposed) {
      warnings.add('Severe glare / overexposure detected. Highlights may wash out text.');
    }

    // 4. Compute blur metric via Laplacian variance on downsampled grayscale
    final gray = img.grayscale(evalThumb);
    final blurScore = _computeLaplacianVariance(gray);
    final isBlurry = blurScore < thresholds.minBlurScore;

    if (isBlurry) {
      warnings.add('Photo appears blurry. Hold phone steady and focus on text.');
    }

    // 5. Determine overall classification
    ImageQualityStatus status;
    // If severely blurry, or both severely dark/overexposed and small, recommend retake
    if (blurScore < (thresholds.minBlurScore * 0.75) ||
        (isBlurry && (isUnderexposed || isOverexposed)) ||
        (isUnderexposed && avgLum < 25.0) ||
        (blownOutRatio > 0.55)) {
      status = ImageQualityStatus.poorRetakeRecommended;
    } else if (warnings.isNotEmpty) {
      status = ImageQualityStatus.usableWithWarning;
    } else {
      status = ImageQualityStatus.good;
    }

    final metrics = ImageQualityMetrics(
      width: originalWidth,
      height: originalHeight,
      blurScore: blurScore,
      averageLuminance: avgLum,
      blownOutRatio: blownOutRatio,
    );

    return ImageQualityResult(
      status: status,
      warnings: warnings,
      metrics: metrics,
    );
  }

  /// Calculates variance of 3x3 discrete Laplacian operator:
  /// [ 0,  1, 0 ]
  /// [ 1, -4, 1 ]
  /// [ 0,  1, 0 ]
  double _computeLaplacianVariance(img.Image grayImage) {
    final w = grayImage.width;
    final h = grayImage.height;
    if (w < 3 || h < 3) return 100.0;

    double sum = 0.0;
    double sumSq = 0.0;
    int count = 0;

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final c = grayImage.getPixel(x, y).r;
        final top = grayImage.getPixel(x, y - 1).r;
        final bottom = grayImage.getPixel(x, y + 1).r;
        final left = grayImage.getPixel(x - 1, y).r;
        final right = grayImage.getPixel(x + 1, y).r;

        final lap = (top + bottom + left + right) - (4.0 * c);
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }

    if (count == 0) return 100.0;
    final mean = sum / count;
    final variance = (sumSq / count) - (mean * mean);
    return max(0.0, variance);
  }

  ImageQualityResult _fallbackResult(String warning) {
    return ImageQualityResult(
      status: ImageQualityStatus.usableWithWarning,
      warnings: [warning],
      metrics: const ImageQualityMetrics(
        width: 0,
        height: 0,
        blurScore: 100.0,
        averageLuminance: 128.0,
        blownOutRatio: 0.0,
      ),
    );
  }
}
