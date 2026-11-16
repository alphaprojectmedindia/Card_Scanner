import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Representation of 4 detected quadrilateral corners on a card image.
class CardCorners {
  final Point<int> topLeft;
  final Point<int> topRight;
  final Point<int> bottomLeft;
  final Point<int> bottomRight;

  const CardCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  Map<String, dynamic> toJson() => {
        'topLeft': {'x': topLeft.x, 'y': topLeft.y},
        'topRight': {'x': topRight.x, 'y': topRight.y},
        'bottomLeft': {'x': bottomLeft.x, 'y': bottomLeft.y},
        'bottomRight': {'x': bottomRight.x, 'y': bottomRight.y},
      };

  /// Tests whether point (x, y) is inside the bounding rectangle formed by the corners.
  bool containsPoint(num x, num y) {
    final minX = [topLeft.x, topRight.x, bottomLeft.x, bottomRight.x].reduce(min);
    final maxX = [topLeft.x, topRight.x, bottomLeft.x, bottomRight.x].reduce(max);
    final minY = [topLeft.y, topRight.y, bottomLeft.y, bottomRight.y].reduce(min);
    final maxY = [topLeft.y, topRight.y, bottomLeft.y, bottomRight.y].reduce(max);
    return x >= minX && x <= maxX && y >= minY && y <= maxY;
  }
}

/// Normalized rectangle coordinates (0.0 to 1.0) of the camera viewfinder guide.
class ViewfinderNormalizedRect {
  final double left;
  final double top;
  final double width;
  final double height;

  const ViewfinderNormalizedRect({
    this.left = 0.07,
    this.top = 0.22,
    this.width = 0.86,
    this.height = 0.49,
  });

  double get right => left + width;
  double get bottom => top + height;

  /// Checks if a normalized point (0.0 to 1.0) is inside or close to the viewfinder bounds.
  bool containsNormalizedPoint(double nx, double ny, {double margin = 0.08}) {
    return nx >= (left - margin) &&
        nx <= (right + margin) &&
        ny >= (top - margin) &&
        ny <= (bottom + margin);
  }
}

/// Lightweight capture quality report calculated from pixel metrics and card geometry.
class CaptureQualityAssessment {
  final double brightness; // 0.0 to 255.0
  final bool isExtremelyDark;
  final bool isExtremelyOverexposed;
  final double blurScore; // higher is sharper; < 50 indicates motion/defocus blur
  final bool isBlurry;
  final double cardAreaRatio;
  final bool isTooSmall;
  final bool isTooClose;
  final bool isClipping;
  final bool isSeverePerspective;
  final bool isUsableResolution;
  final String guidanceMessage;

  const CaptureQualityAssessment({
    required this.brightness,
    required this.isExtremelyDark,
    required this.isExtremelyOverexposed,
    required this.blurScore,
    required this.isBlurry,
    required this.cardAreaRatio,
    required this.isTooSmall,
    required this.isTooClose,
    required this.isClipping,
    required this.isSeverePerspective,
    required this.isUsableResolution,
    required this.guidanceMessage,
  });

  bool get isHighQuality =>
      !isExtremelyDark &&
      !isExtremelyOverexposed &&
      !isBlurry &&
      !isTooSmall &&
      !isTooClose &&
      !isClipping &&
      !isSeverePerspective &&
      isUsableResolution;

  Map<String, dynamic> toJson() => {
        'brightness': double.parse(brightness.toStringAsFixed(1)),
        'isExtremelyDark': isExtremelyDark,
        'isExtremelyOverexposed': isExtremelyOverexposed,
        'blurScore': double.parse(blurScore.toStringAsFixed(1)),
        'isBlurry': isBlurry,
        'cardAreaRatio': double.parse(cardAreaRatio.toStringAsFixed(3)),
        'isTooSmall': isTooSmall,
        'isTooClose': isTooClose,
        'isClipping': isClipping,
        'isSeverePerspective': isSeverePerspective,
        'isUsableResolution': isUsableResolution,
        'guidanceMessage': guidanceMessage,
      };

  @override
  String toString() =>
      'CaptureQualityAssessment(brightness: ${brightness.toStringAsFixed(0)}, blur: ${blurScore.toStringAsFixed(0)}, msg: "$guidanceMessage")';
}

/// Result of card edge detection and perspective correction.
class CardGeometryResult {
  /// The image file path to be used for OCR (corrected image if successful, else original).
  final String imagePath;

  /// True if perspective correction was reliably applied.
  final bool wasCorrected;

  /// Geometric confidence score (0.0 to 1.0).
  final double confidence;

  /// Detected corners if confidence met the threshold.
  final CardCorners? corners;

  /// Any temporary derived file created during correction that should be cleaned up later.
  final String? temporaryFilePath;

  /// Capture quality assessment evaluated before OCR.
  final CaptureQualityAssessment? quality;

  /// True if fallback to viewfinder safe ROI crop was applied instead of full image.
  final bool wasRoiCropped;

  const CardGeometryResult({
    required this.imagePath,
    required this.wasCorrected,
    this.wasRoiCropped = false,
    this.confidence = 0.0,
    this.corners,
    this.temporaryFilePath,
    this.quality,
  });

  factory CardGeometryResult.original(String path, {CaptureQualityAssessment? quality}) =>
      CardGeometryResult(
        imagePath: path,
        wasCorrected: false,
        wasRoiCropped: false,
        confidence: 0.0,
        quality: quality,
      );
}

/// Service that safely detects business card boundaries and performs perspective
/// correction before OCR when geometric confidence is high.
/// Falls back to the viewfinder safe ROI crop (or upright image) whenever confidence is insufficient.
class CardGeometryService {
  /// Minimum confidence (0.0 - 1.0) required before applying perspective transformation.
  final double minConfidenceThreshold;

  const CardGeometryService({
    this.minConfidenceThreshold = 0.70,
  });

  /// Evaluates and corrects perspective for an image at [imagePath].
  /// Never mutates the original image file.
  Future<CardGeometryResult> correctPerspectiveIfReliable(
    String imagePath, [
    ViewfinderNormalizedRect? viewfinderRoi,
  ]) async {
    try {
      final file = File(imagePath);
      if (!file.existsSync()) {
        return CardGeometryResult.original(imagePath);
      }

      final bytes = await file.readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) {
        return CardGeometryResult.original(imagePath);
      }

      // 1. Bake EXIF orientation so pixels match visual top/bottom
      final int orientation = original.exif.imageIfd.orientation ?? 1;
      final bool hadExifOrientation = orientation != 1;
      final uprightImage = img.bakeOrientation(original);

      // 2. Detect 4 card corners
      final detection = detectCorners(uprightImage, viewfinderRoi: viewfinderRoi);
      final quality = assessCaptureQuality(
        uprightImage,
        corners: detection.corners,
        confidence: detection.confidence,
      );

      if (detection.confidence < minConfidenceThreshold || detection.corners == null) {
        // Edge detection confidence is insufficient -> use safe viewfinder ROI crop if available
        if (viewfinderRoi != null && viewfinderRoi.width > 0.1 && viewfinderRoi.height > 0.1) {
          final marginX = (uprightImage.width * 0.03).round();
          final marginY = (uprightImage.height * 0.03).round();
          final cropX = max(0, (viewfinderRoi.left * uprightImage.width).round() - marginX);
          final cropY = max(0, (viewfinderRoi.top * uprightImage.height).round() - marginY);
          final cropW = min(uprightImage.width - cropX, (viewfinderRoi.width * uprightImage.width).round() + 2 * marginX);
          final cropH = min(uprightImage.height - cropY, (viewfinderRoi.height * uprightImage.height).round() + 2 * marginY);

          if (cropW > 100 && cropH > 100) {
            var cropped = img.copyCrop(uprightImage, x: cropX, y: cropY, width: cropW, height: cropH);
            final cropLongEdge = max(cropped.width, cropped.height);
            if (cropLongEdge < 1200) {
              final double scale = (1200 / cropLongEdge).clamp(1.1, 1.8);
              cropped = img.copyResize(
                cropped,
                width: (cropped.width * scale).round(),
                height: (cropped.height * scale).round(),
                interpolation: img.Interpolation.linear,
              );
            }

            final tempDir = Directory.systemTemp.path;
            final tempFileName =
                'digital_share_roi_crop_${DateTime.now().microsecondsSinceEpoch}.jpg';
            final tempFile = File('$tempDir/$tempFileName');
            await tempFile.writeAsBytes(img.encodeJpg(cropped, quality: 92), flush: true);
            return CardGeometryResult(
              imagePath: tempFile.path,
              wasCorrected: false,
              wasRoiCropped: true,
              confidence: detection.confidence,
              temporaryFilePath: tempFile.path,
              quality: quality,
            );
          }
        }

        if (hadExifOrientation) {
          final tempDir = Directory.systemTemp.path;
          final tempFileName =
              'digital_share_upright_${DateTime.now().microsecondsSinceEpoch}.jpg';
          final tempFile = File('$tempDir/$tempFileName');
          await tempFile.writeAsBytes(img.encodeJpg(uprightImage, quality: 92), flush: true);
          return CardGeometryResult(
            imagePath: tempFile.path,
            wasCorrected: false,
            wasRoiCropped: false,
            confidence: detection.confidence,
            temporaryFilePath: tempFile.path,
            quality: quality,
          );
        }
        return CardGeometryResult(
          imagePath: imagePath,
          wasCorrected: false,
          wasRoiCropped: false,
          confidence: detection.confidence,
          quality: quality,
        );
      }

      final corners = detection.corners!;

      // 3. Perform rectification via copyRectify
      var rectified = img.copyRectify(
        uprightImage,
        topLeft: img.Point(corners.topLeft.x, corners.topLeft.y),
        topRight: img.Point(corners.topRight.x, corners.topRight.y),
        bottomLeft: img.Point(corners.bottomLeft.x, corners.bottomLeft.y),
        bottomRight: img.Point(corners.bottomRight.x, corners.bottomRight.y),
      );

      // Controlled upscale if rectified card is small (Requirement 6: Small text preservation)
      final rectLongEdge = max(rectified.width, rectified.height);
      if (rectLongEdge < 1200) {
        final double scale = (1200 / rectLongEdge).clamp(1.1, 1.8);
        rectified = img.copyResize(
          rectified,
          width: (rectified.width * scale).round(),
          height: (rectified.height * scale).round(),
          interpolation: img.Interpolation.linear,
        );
      }

      // 4. Save corrected image to temporary cache file
      final tempDir = Directory.systemTemp.path;
      final tempFileName =
          'digital_share_rectified_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final tempFile = File('$tempDir/$tempFileName');
      final encodedJpg = img.encodeJpg(rectified, quality: 92);
      await tempFile.writeAsBytes(encodedJpg, flush: true);

      return CardGeometryResult(
        imagePath: tempFile.path,
        wasCorrected: true,
        wasRoiCropped: false,
        confidence: detection.confidence,
        corners: corners,
        temporaryFilePath: tempFile.path,
        quality: quality,
      );
    } catch (e) {
      if (kDebugMode) {
        print('CardGeometryService perspective correction fallback: $e');
      }
      return CardGeometryResult.original(imagePath);
    }
  }

  /// Calculates lightweight capture quality indicators before OCR.
  CaptureQualityAssessment assessCaptureQuality(
    img.Image image, {
    CardCorners? corners,
    double? confidence,
  }) {
    final origW = image.width;
    final origH = image.height;

    // Fast evaluation on downsampled thumbnail
    final thumbW = 160;
    final thumbH = (origH * (160 / origW)).round();
    final thumb = img.copyResize(image, width: thumbW, height: thumbH);

    double totalLum = 0.0;
    int saturatedCount = 0;
    final totalPixels = thumbW * thumbH;

    for (int y = 0; y < thumbH; y++) {
      for (int x = 0; x < thumbW; x++) {
        final p = thumb.getPixel(x, y);
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        totalLum += lum;
        if (p.r > 245 && p.g > 245 && p.b > 245) {
          saturatedCount++;
        }
      }
    }

    final avgBrightness = totalLum / totalPixels;
    final isExtremelyDark = avgBrightness < 45.0;
    final isExtremelyOverexposed =
        avgBrightness > 220.0 || (saturatedCount / totalPixels > 0.25);

    // Compute blur via Laplacian variance on central region at native resolution
    final cropW = min(400, origW);
    final cropH = min(300, origH);
    final startX = (origW - cropW) ~/ 2;
    final startY = (origH - cropH) ~/ 2;

    double laplacianSum = 0.0;
    double laplacianSqSum = 0.0;
    int laplacianCount = 0;

    for (int y = startY + 1; y < startY + cropH - 1; y += 2) {
      for (int x = startX + 1; x < startX + cropW - 1; x += 2) {
        final center = image.getPixel(x, y).r;
        final up = image.getPixel(x, y - 1).r;
        final down = image.getPixel(x, y + 1).r;
        final left = image.getPixel(x - 1, y).r;
        final right = image.getPixel(x + 1, y).r;

        final val = (up + down + left + right - 4 * center).toDouble();
        laplacianSum += val;
        laplacianSqSum += val * val;
        laplacianCount++;
      }
    }

    final meanL = laplacianSum / max(1, laplacianCount);
    final blurVariance = (laplacianSqSum / max(1, laplacianCount)) - (meanL * meanL);
    final isBlurry = blurVariance < 50.0;

    // Card geometry signals
    double cardAreaRatio = 0.0;
    bool isTooSmall = false;
    bool isTooClose = false;
    bool isClipping = false;
    bool isSeverePerspective = false;

    if (corners != null && (confidence == null || confidence >= 0.30)) {
      final widthTop = _distance(corners.topLeft, corners.topRight);
      final widthBottom = _distance(corners.bottomLeft, corners.bottomRight);
      final heightLeft = _distance(corners.topLeft, corners.bottomLeft);
      final heightRight = _distance(corners.topRight, corners.bottomRight);

      final avgW = (widthTop + widthBottom) / 2.0;
      final avgH = (heightLeft + heightRight) / 2.0;
      final cardArea = avgW * avgH;
      final totalArea = origW * origH;
      cardAreaRatio = (cardArea / totalArea).clamp(0.0, 1.0);

      isTooSmall = cardAreaRatio < 0.20;
      isTooClose = cardAreaRatio > 0.88;

      // Check clipping against image margins (within 2% of frame edge)
      final marginX = origW * 0.02;
      final marginY = origH * 0.02;
      for (final p in [
        corners.topLeft,
        corners.topRight,
        corners.bottomLeft,
        corners.bottomRight,
      ]) {
        if (p.x <= marginX ||
            p.x >= (origW - marginX) ||
            p.y <= marginY ||
            p.y >= (origH - marginY)) {
          isClipping = true;
          break;
        }
      }

      final widthRatio = min(widthTop, widthBottom) / max(1, max(widthTop, widthBottom));
      final heightRatio = min(heightLeft, heightRight) / max(1, max(heightLeft, heightRight));
      isSeverePerspective = widthRatio < 0.65 || heightRatio < 0.65;
    }

    final isUsableResolution = origW >= 700 && origH >= 400;

    // Compute guidance message matching prompt requirements exactly
    String guidance;
    if (isExtremelyDark) {
      guidance = 'Move to better lighting';
    } else if (isExtremelyOverexposed) {
      guidance = 'Reduce glare';
    } else if (isClipping) {
      guidance = 'Keep the full card inside the frame';
    } else if (isTooSmall) {
      guidance = 'Move closer to the card';
    } else if (isTooClose) {
      guidance = 'Move card farther away';
    } else if (isBlurry) {
      guidance = 'Hold the card steady';
    } else if (corners != null && (confidence ?? 0.0) >= 0.70) {
      guidance = 'Card aligned';
    } else {
      guidance = 'Position card inside the frame';
    }

    return CaptureQualityAssessment(
      brightness: avgBrightness,
      isExtremelyDark: isExtremelyDark,
      isExtremelyOverexposed: isExtremelyOverexposed,
      blurScore: blurVariance,
      isBlurry: isBlurry,
      cardAreaRatio: cardAreaRatio,
      isTooSmall: isTooSmall,
      isTooClose: isTooClose,
      isClipping: isClipping,
      isSeverePerspective: isSeverePerspective,
      isUsableResolution: isUsableResolution,
      guidanceMessage: guidance,
    );
  }

  /// Detects 4 corner candidates on an in-memory [img.Image] and evaluates geometric confidence.
  ({CardCorners? corners, double confidence}) detectCorners(
    img.Image image, {
    ViewfinderNormalizedRect? viewfinderRoi,
  }) {
    final origW = image.width;
    final origH = image.height;

    // Operate on a downsampled thumbnail for fast edge detection (<20ms)
    final scaleW = 320;
    final scaleH = (origH * (320 / origW)).round();
    final thumb = img.copyResize(image, width: scaleW, height: scaleH);
    final gray = img.grayscale(thumb);

    // Compute Sobel edges
    final edgeImage = _computeSobelEdges(gray);

    // Find bounding contour / extremal points of significant edges
    final points = <Point<int>>[];
    final threshold = 45; // gradient threshold

    for (int y = 0; y < edgeImage.height; y++) {
      for (int x = 0; x < edgeImage.width; x++) {
        if (edgeImage.getPixel(x, y).r > threshold) {
          points.add(Point(x, y));
        }
      }
    }

    if (points.length < 50) {
      return (corners: null, confidence: 0.1);
    }

    // If viewfinder ROI is provided, prioritize edge points within/near the guide frame
    List<Point<int>> candidatePoints = points;
    if (viewfinderRoi != null) {
      final roiPoints = points.where((p) {
        final nx = p.x / scaleW;
        final ny = p.y / scaleH;
        return viewfinderRoi.containsNormalizedPoint(nx, ny, margin: 0.10);
      }).toList();
      if (roiPoints.length >= 50) {
        candidatePoints = roiPoints;
      }
    }

    // Extremal corner approximation:
    // Top-Left: minimizes (x + y)
    // Top-Right: maximizes (x - y)
    // Bottom-Left: minimizes (x - y)
    // Bottom-Right: maximizes (x + y)
    Point<int> tl = candidatePoints.first;
    Point<int> tr = candidatePoints.first;
    Point<int> bl = candidatePoints.first;
    Point<int> br = candidatePoints.first;

    int minSum = tl.x + tl.y;
    int maxSum = br.x + br.y;
    int minDiff = bl.x - bl.y;
    int maxDiff = tr.x - tr.y;

    for (final p in candidatePoints) {
      final sum = p.x + p.y;
      final diff = p.x - p.y;

      if (sum < minSum) {
        minSum = sum;
        tl = p;
      }
      if (sum > maxSum) {
        maxSum = sum;
        br = p;
      }
      if (diff < minDiff) {
        minDiff = diff;
        bl = p;
      }
      if (diff > maxDiff) {
        maxDiff = diff;
        tr = p;
      }
    }

    // Scale corners back to original image coordinate space
    final factorX = origW / scaleW;
    final factorY = origH / scaleH;

    // Add safe margin (padding 2%) so text touching the boundary is never cropped
    final marginX = (origW * 0.02).round();
    final marginY = (origH * 0.02).round();

    final origTL = Point<int>(
      max(0, (tl.x * factorX).round() - marginX),
      max(0, (tl.y * factorY).round() - marginY),
    );
    final origTR = Point<int>(
      min(origW - 1, (tr.x * factorX).round() + marginX),
      max(0, (tr.y * factorY).round() - marginY),
    );
    final origBL = Point<int>(
      max(0, (bl.x * factorX).round() - marginX),
      min(origH - 1, (bl.y * factorY).round() + marginY),
    );
    final origBR = Point<int>(
      min(origW - 1, (br.x * factorX).round() + marginX),
      min(origH - 1, (br.y * factorY).round() + marginY),
    );

    // Verify geometric invariants of a business card quadrilateral
    final widthTop = _distance(origTL, origTR);
    final widthBottom = _distance(origBL, origBR);
    final heightLeft = _distance(origTL, origBL);
    final heightRight = _distance(origTR, origBR);

    final avgWidth = (widthTop + widthBottom) / 2.0;
    final avgHeight = (heightLeft + heightRight) / 2.0;

    if (avgWidth <= 50 || avgHeight <= 50) {
      return (corners: null, confidence: 0.2);
    }

    final cardArea = avgWidth * avgHeight;
    final totalArea = origW * origH;
    final areaRatio = cardArea / totalArea;

    // Card must occupy reasonable area of the image (between 5% and 98%)
    if (areaRatio < 0.05 || areaRatio > 0.98) {
      return (corners: null, confidence: 0.2);
    }

    // Aspect ratio check:
    // Standard business card is ~1.5 to 1.8 (or 0.55 to 0.67 if vertical)
    final aspectRatio = avgWidth / avgHeight;
    final isLandscapeCard = aspectRatio >= 1.15 && aspectRatio <= 2.35;
    final isPortraitCard = aspectRatio >= 0.42 && aspectRatio <= 0.88;

    if (!isLandscapeCard && !isPortraitCard) {
      return (corners: null, confidence: 0.4);
    }

    // Opposite sides parallelism check:
    // Top and bottom widths should not differ by more than 35%
    final widthRatio = min(widthTop, widthBottom) / max(widthTop, widthBottom);
    final heightRatio = min(heightLeft, heightRight) / max(heightLeft, heightRight);

    if (widthRatio < 0.65 || heightRatio < 0.65) {
      return (corners: null, confidence: 0.5);
    }

    // High confidence detected
    final confidence = (widthRatio * 0.4) + (heightRatio * 0.4) + (min(1.0, areaRatio / 0.5) * 0.2);

    return (
      corners: CardCorners(
        topLeft: origTL,
        topRight: origTR,
        bottomLeft: origBL,
        bottomRight: origBR,
      ),
      confidence: confidence.clamp(0.0, 1.0),
    );
  }

  img.Image _computeSobelEdges(img.Image gray) {
    final w = gray.width;
    final h = gray.height;
    final edges = img.Image(width: w, height: h);

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final p00 = gray.getPixel(x - 1, y - 1).r;
        final p01 = gray.getPixel(x, y - 1).r;
        final p02 = gray.getPixel(x + 1, y - 1).r;

        final p10 = gray.getPixel(x - 1, y).r;
        final p12 = gray.getPixel(x + 1, y).r;

        final p20 = gray.getPixel(x - 1, y + 1).r;
        final p21 = gray.getPixel(x, y + 1).r;
        final p22 = gray.getPixel(x + 1, y + 1).r;

        final gx = (p02 + 2 * p12 + p22) - (p00 + 2 * p10 + p20);
        final gy = (p20 + 2 * p21 + p22) - (p00 + 2 * p01 + p02);
        final mag = min(255, sqrt(gx * gx + gy * gy).round());

        edges.setPixelRgb(x, y, mag, mag, mag);
      }
    }

    return edges;
  }

  double _distance(Point<int> p1, Point<int> p2) {
    final dx = (p1.x - p2.x).toDouble();
    final dy = (p1.y - p2.y).toDouble();
    return sqrt(dx * dx + dy * dy);
  }
}
