import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect, Offset, Size;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Dedicated state machine tracking the business card lifecycle from search to capture and perspective correction.
enum CardDetectionState {
  searching,
  detected,
  tracking,
  stabilizing,
  capturing,
  processing,
  completed,
}

/// Bidirectional coordinate mapper between camera sensor / preview coordinates [0.0, 1.0]
/// and screen pixel coordinates, compensating for [BoxFit.cover] aspect ratio scaling and centering offsets.
class CameraCoordinateMapper {
  final Size screenSize;
  final double previewAspect; // width / height of upright portrait preview (e.g. 9/16 = 0.5625)

  const CameraCoordinateMapper({
    required this.screenSize,
    required this.previewAspect,
  });

  double get _screenAspect =>
      screenSize.width / (screenSize.height > 0 ? screenSize.height : 1.0);

  /// Converts a point in normalized camera preview space [0.0, 1.0] to screen pixel space.
  Offset cameraToScreen(Offset camNormalized) {
    if (screenSize.width <= 0 || screenSize.height <= 0 || previewAspect <= 0) {
      return Offset(
        camNormalized.dx * screenSize.width,
        camNormalized.dy * screenSize.height,
      );
    }
    double scaledW, scaledH, offsetX = 0.0, offsetY = 0.0;
    if (_screenAspect > previewAspect) {
      scaledW = screenSize.width;
      scaledH = screenSize.width / previewAspect;
      offsetY = (scaledH - screenSize.height) / 2.0;
    } else {
      scaledH = screenSize.height;
      scaledW = screenSize.height * previewAspect;
      offsetX = (scaledW - screenSize.width) / 2.0;
    }
    final sx = camNormalized.dx * scaledW - offsetX;
    final sy = camNormalized.dy * scaledH - offsetY;
    return Offset(sx, sy);
  }

  /// Converts a point in screen pixel space to normalized camera preview space [0.0, 1.0].
  Offset screenToCamera(Offset screenPixel) {
    if (screenSize.width <= 0 || screenSize.height <= 0 || previewAspect <= 0) {
      return Offset(
        (screenPixel.dx / screenSize.width).clamp(0.0, 1.0),
        (screenPixel.dy / screenSize.height).clamp(0.0, 1.0),
      );
    }
    double scaledW, scaledH, offsetX = 0.0, offsetY = 0.0;
    if (_screenAspect > previewAspect) {
      scaledW = screenSize.width;
      scaledH = screenSize.width / previewAspect;
      offsetY = (scaledH - screenSize.height) / 2.0;
    } else {
      scaledH = screenSize.height;
      scaledW = screenSize.height * previewAspect;
      offsetX = (scaledW - screenSize.width) / 2.0;
    }
    final cx = (screenPixel.dx + offsetX) / scaledW;
    final cy = (screenPixel.dy + offsetY) / scaledH;
    return Offset(cx.clamp(0.0, 1.0), cy.clamp(0.0, 1.0));
  }
}

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

  /// Returns 4 polygon points ordered clockwise: [topLeft, topRight, bottomRight, bottomLeft].
  List<Point<int>> toPolygonPoints() => [topLeft, topRight, bottomRight, bottomLeft];

  /// Returns 4 normalized polygon vertices [Offset(x, y)] in 0.0 to 1.0 coordinate space.
  List<Offset> toNormalizedPolygon(int width, int height) {
    final w = max(1, width).toDouble();
    final h = max(1, height).toDouble();
    return [
      Offset((topLeft.x / w).clamp(0.0, 1.0), (topLeft.y / h).clamp(0.0, 1.0)),
      Offset((topRight.x / w).clamp(0.0, 1.0), (topRight.y / h).clamp(0.0, 1.0)),
      Offset((bottomRight.x / w).clamp(0.0, 1.0), (bottomRight.y / h).clamp(0.0, 1.0)),
      Offset((bottomLeft.x / w).clamp(0.0, 1.0), (bottomLeft.y / h).clamp(0.0, 1.0)),
    ];
  }

  static double _dist(Point<int> p1, Point<int> p2) {
    return CardGeometryService.getDistance(p1, p2);
  }

  double get widthTop => _dist(topLeft, topRight);
  double get widthBottom => _dist(bottomLeft, bottomRight);
  double get heightLeft => _dist(topLeft, bottomLeft);
  double get heightRight => _dist(topRight, bottomRight);

  double get avgWidth => (widthTop + widthBottom) / 2.0;
  double get avgHeight => (heightLeft + heightRight) / 2.0;
  double get aspectRatio => avgHeight > 0 ? (avgWidth / avgHeight) : 1.0;

  bool get isSquare => aspectRatio >= 0.82 && aspectRatio <= 1.20;
  bool get isLandscape => aspectRatio >= 1.20 && aspectRatio <= 2.30;
  bool get isPortrait => aspectRatio >= 0.40 && aspectRatio < 0.82;

  /// Area calculated using Shoelace formula for quadrilateral
  double get area {
    final x0 = topLeft.x.toDouble(), y0 = topLeft.y.toDouble();
    final x1 = topRight.x.toDouble(), y1 = topRight.y.toDouble();
    final x2 = bottomRight.x.toDouble(), y2 = bottomRight.y.toDouble();
    final x3 = bottomLeft.x.toDouble(), y3 = bottomLeft.y.toDouble();
    return 0.5 *
        ((x0 * y1 + x1 * y2 + x2 * y3 + x3 * y0) -
                (y0 * x1 + y1 * x2 + y2 * x3 + y3 * x0))
            .abs();
  }

  /// Verifies that the quadrilateral is strictly convex (non-self-intersecting).
  bool get isConvex {
    final pts = [topLeft, topRight, bottomRight, bottomLeft];
    bool? sign;
    for (int i = 0; i < 4; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % 4];
      final p3 = pts[(i + 2) % 4];
      final dx1 = p2.x - p1.x;
      final dy1 = p2.y - p1.y;
      final dx2 = p3.x - p2.x;
      final dy2 = p3.y - p2.y;
      final cross = dx1 * dy2 - dy1 * dx2;
      if (cross == 0) return false;
      if (sign == null) {
        sign = cross > 0;
      } else if ((cross > 0) != sign) {
        return false;
      }
    }
    return true;
  }

  /// Returns internal angle in degrees at corner index: 0 = TL, 1 = TR, 2 = BR, 3 = BL.
  double cornerAngle(int cornerIndex) {
    Point<int> pCenter;
    Point<int> pA;
    Point<int> pB;

    switch (cornerIndex % 4) {
      case 0: // Top-Left
        pCenter = topLeft;
        pA = topRight;
        pB = bottomLeft;
        break;
      case 1: // Top-Right
        pCenter = topRight;
        pA = bottomRight;
        pB = topLeft;
        break;
      case 2: // Bottom-Right
        pCenter = bottomRight;
        pA = bottomLeft;
        pB = topRight;
        break;
      case 3: // Bottom-Left
      default:
        pCenter = bottomLeft;
        pA = topLeft;
        pB = bottomRight;
        break;
    }

    final v1x = (pA.x - pCenter.x).toDouble();
    final v1y = (pA.y - pCenter.y).toDouble();
    final v2x = (pB.x - pCenter.x).toDouble();
    final v2y = (pB.y - pCenter.y).toDouble();

    final mag1 = sqrt(v1x * v1x + v1y * v1y);
    final mag2 = sqrt(v2x * v2x + v2y * v2y);
    if (mag1 == 0 || mag2 == 0) return 90.0;

    final dot = (v1x * v2x + v1y * v2y) / (mag1 * mag2);
    final rad = acos(dot.clamp(-1.0, 1.0));
    return rad * 180.0 / pi;
  }

  /// Verifies all four interior angles are within document perspective range [minAngleDeg, maxAngleDeg].
  bool hasValidCornerAngles({double minAngleDeg = 55.0, double maxAngleDeg = 125.0}) {
    for (int i = 0; i < 4; i++) {
      final a = cornerAngle(i);
      if (a < minAngleDeg || a > maxAngleDeg) return false;
    }
    return true;
  }

  /// Angle quality score (1.0 = ideal 90° corners, degrades as quadrilateral skews).
  double get angularScore {
    double totalDev = 0.0;
    for (int i = 0; i < 4; i++) {
      totalDev += (cornerAngle(i) - 90.0).abs();
    }
    final meanDev = totalDev / 4.0;
    return max(0.0, 1.0 - (meanDev / 45.0));
  }

  /// Edge parallelism / consistency ratio between opposite pairs of sides (0.0 to 1.0).
  double get edgeConsistency {
    final wMax = max(widthTop, widthBottom);
    final wRatio = wMax > 0 ? (min(widthTop, widthBottom) / wMax) : 0.0;
    final hMax = max(heightLeft, heightRight);
    final hRatio = hMax > 0 ? (min(heightLeft, heightRight) / hMax) : 0.0;
    return (wRatio + hRatio) / 2.0;
  }

  /// Rectangularity score: card quadrilateral area compared to average width * height.
  double get rectangularityScore {
    final expectedArea = avgWidth * avgHeight;
    if (expectedArea <= 0) return 0.0;
    return (min(area, expectedArea) / max(area, expectedArea)).clamp(0.0, 1.0);
  }

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

/// Structured real-time business card detection result from camera frame analysis.
class BusinessCardDetectionResult {
  /// True if an actual business card with valid boundaries, aspect ratio,
  /// edge contrast, and interior content was detected.
  final bool isDetected;

  /// Detection state machine status.
  final CardDetectionState state;

  /// Quadrilateral corners in coordinate space of the analyzed image.
  final CardCorners? corners;

  /// Normalized 4-corner polygon [Offset(x, y)] in 0.0 to 1.0 coordinate space for live overlay.
  final List<Offset>? normalizedPolygon;

  /// Normalized bounding box (0.0 to 1.0) of the detected card relative to the preview frame.
  final Rect? normalizedBoundingBox;

  /// Geometric confidence score (0.0 to 1.0).
  final double confidence;

  /// Aspect ratio (width / height).
  final double aspectRatio;

  /// True if card is oriented in landscape format.
  final bool isLandscape;

  /// True if card has square or near-square proportions.
  final bool isSquare;

  /// True if card is oriented in vertical/portrait format.
  bool get isPortrait => !isLandscape && !isSquare;

  /// Measured contrast gradient across the card perimeter against background.
  final double edgeContrast;

  /// Interior texture/glyph variance (distinguishes printed cards from blank paper or monotone objects).
  final double interiorTextureVariance;

  /// True if the interior of the detected shape contains text, typography, or high-frequency details.
  final bool hasCardContent;

  /// Ratio of card quadrilateral area to total camera frame area (0.0 to 1.0).
  final double cardAreaRatio;

  /// Internal angular quality score (1.0 = ideal 90° corners).
  final double angularScore;

  /// Rectangularity score (0.0 to 1.0).
  final double rectangularityScore;

  /// Capture quality indicators (brightness, blur, clipping).
  final CaptureQualityAssessment quality;

  const BusinessCardDetectionResult({
    required this.isDetected,
    this.state = CardDetectionState.searching,
    this.corners,
    this.normalizedPolygon,
    this.normalizedBoundingBox,
    this.confidence = 0.0,
    this.aspectRatio = 0.0,
    this.isLandscape = true,
    this.isSquare = false,
    this.edgeContrast = 0.0,
    this.interiorTextureVariance = 0.0,
    this.hasCardContent = false,
    this.cardAreaRatio = 0.0,
    this.angularScore = 0.0,
    this.rectangularityScore = 0.0,
    required this.quality,
  });

  factory BusinessCardDetectionResult.none({
    CaptureQualityAssessment? quality,
    CardDetectionState state = CardDetectionState.searching,
  }) =>
      BusinessCardDetectionResult(
        isDetected: false,
        state: state,
        quality: quality ??
            const CaptureQualityAssessment(
              brightness: 128.0,
              isExtremelyDark: false,
              isExtremelyOverexposed: false,
              blurScore: 100.0,
              isBlurry: false,
              cardAreaRatio: 0.0,
              isTooSmall: false,
              isTooClose: false,
              isClipping: false,
              isSeverePerspective: false,
              isUsableResolution: true,
              guidanceMessage: 'Position card inside the frame',
            ),
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
  /// Maps detected corners to exact destination dimensions without distortion or background.
  /// Never mutates the original image file.
  Future<CardGeometryResult> correctPerspectiveIfReliable(
    String imagePath, [
    ViewfinderNormalizedRect? viewfinderRoi,
    List<Offset>? detectedNormalizedPolygon,
  ]) async {
    try {
      final file = File(imagePath);
      if (!file.existsSync()) {
        return CardGeometryResult.original(imagePath);
      }

      final bytes = file.readAsBytesSync();
      final original = img.decodeImage(bytes);
      if (original == null) {
        return CardGeometryResult.original(imagePath);
      }

      // 1. Bake EXIF orientation so pixels match visual top/bottom
      final int orientation = original.exif.imageIfd.orientation ?? 1;
      final bool hadExifOrientation = orientation != 1;
      final uprightImage = img.bakeOrientation(original);

      // 2. Map corners or detect on uprightImage
      CardCorners? corners;
      double cornerConfidence = 0.0;

      // 2a. If high-res edge detection finds prominent card corners, prioritize them
      final detection = detectCorners(uprightImage, viewfinderRoi: viewfinderRoi, allowSquare: true);
      if (detection.corners != null && detection.confidence >= 0.65) {
        corners = detection.corners;
        cornerConfidence = detection.confidence;
      }

      // 2b. If not detected at full-res, use mapped corners from real-time live preview
      if (corners == null && detectedNormalizedPolygon != null && detectedNormalizedPolygon.length == 4) {
        final p0 = detectedNormalizedPolygon[0];
        final p1 = detectedNormalizedPolygon[1];
        final p2 = detectedNormalizedPolygon[2];
        final p3 = detectedNormalizedPolygon[3];
        corners = CardCorners(
          topLeft: Point<int>((p0.dx * uprightImage.width).round().clamp(0, uprightImage.width - 1), (p0.dy * uprightImage.height).round().clamp(0, uprightImage.height - 1)),
          topRight: Point<int>((p1.dx * uprightImage.width).round().clamp(0, uprightImage.width - 1), (p1.dy * uprightImage.height).round().clamp(0, uprightImage.height - 1)),
          bottomRight: Point<int>((p2.dx * uprightImage.width).round().clamp(0, uprightImage.width - 1), (p2.dy * uprightImage.height).round().clamp(0, uprightImage.height - 1)),
          bottomLeft: Point<int>((p3.dx * uprightImage.width).round().clamp(0, uprightImage.width - 1), (p3.dy * uprightImage.height).round().clamp(0, uprightImage.height - 1)),
        );
        cornerConfidence = 0.82;
      }

      // 2c. Fallback to detection corners if available
      if (corners == null && detection.corners != null) {
        corners = detection.corners;
        cornerConfidence = detection.confidence;
      }

      final quality = assessCaptureQuality(
        uprightImage,
        corners: corners,
        confidence: cornerConfidence,
      );

      if (cornerConfidence < minConfidenceThreshold || corners == null) {
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
              confidence: cornerConfidence,
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
            confidence: cornerConfidence,
            temporaryFilePath: tempFile.path,
            quality: quality,
          );
        }
        return CardGeometryResult(
          imagePath: imagePath,
          wasCorrected: false,
          wasRoiCropped: false,
          confidence: cornerConfidence,
          quality: quality,
        );
      }

      // 3. Perform perspective rectification mapped to exact card dimensions
      final orderedCorners = [corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft];
      final destDims = findDest(orderedCorners);

      final targetW = destDims.width.clamp(350, 3600);
      final targetH = destDims.height.clamp(250, 3600);

      // Radial outward expansion (~1.8%) around quadrilateral centroid
      // to preserve rounded corners, bleed edges, and outer border artwork
      final centroidX = (corners.topLeft.x + corners.topRight.x + corners.bottomLeft.x + corners.bottomRight.x) / 4.0;
      final centroidY = (corners.topLeft.y + corners.topRight.y + corners.bottomLeft.y + corners.bottomRight.y) / 4.0;
      const expandFactor = 1.018;

      int expX(int x) => (centroidX + (x - centroidX) * expandFactor).round().clamp(0, uprightImage.width - 1);
      int expY(int y) => (centroidY + (y - centroidY) * expandFactor).round().clamp(0, uprightImage.height - 1);

      final expandedCorners = CardCorners(
        topLeft: Point<int>(expX(corners.topLeft.x), expY(corners.topLeft.y)),
        topRight: Point<int>(expX(corners.topRight.x), expY(corners.topRight.y)),
        bottomLeft: Point<int>(expX(corners.bottomLeft.x), expY(corners.bottomLeft.y)),
        bottomRight: Point<int>(expX(corners.bottomRight.x), expY(corners.bottomRight.y)),
      );

      var rectified = warpPerspective(uprightImage, expandedCorners, targetW, targetH);

      // Controlled upscale if rectified card is small for crisp OCR reading
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

      // Requirement 4: Image enhancement & lighting correction without color distortion
      rectified = _applyGentleLightingCorrection(rectified);

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
        confidence: cornerConfidence,
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
    // Overexposure / glare occurs when average luminance is extreme (>238) or over 65% of frame is saturated white
    final isExtremelyOverexposed =
        avgBrightness > 238.0 || (saturatedCount / totalPixels > 0.65);

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
  /// Supports both rectangular (landscape & portrait) and square-shaped business cards.
  ({CardCorners? corners, double confidence}) detectCorners(
    img.Image image, {
    ViewfinderNormalizedRect? viewfinderRoi,
    bool allowSquare = true,
  }) {
    final origW = image.width;
    final origH = image.height;

    // Operate on a downsampled thumbnail for fast edge detection (<20ms)
    final scaleW = 320;
    final scaleH = (origH * (320 / origW)).round();
    final thumb = img.copyResize(image, width: scaleW, height: scaleH);
    final gray = img.grayscale(thumb);

    // 1. Gaussian Blur (5x5 kernel) to eliminate high frequency noise
    final blur = applyGaussianBlur(gray, kernelSize: 5);

    // 2. Canny Edge Detection with gradient magnitude, NMS, and adaptive hysteresis
    final canny = applyCannyEdgeDetection(blur, adaptive: true);

    // 3. Morphological Dilation (3x3 kernel) to close small gaps in card boundary
    final edgeImage = applyMorphologicalDilation(canny, iterations: 1);

    // Filter candidate points: discard edge points touching the camera frame boundary (outer 2.5%)
    // to reject table edges, wood grain running off-screen, and background artifacts.
    final borderX = max(2, (scaleW * 0.025).round());
    final borderY = max(2, (scaleH * 0.025).round());

    final points = <Point<int>>[];
    for (int y = borderY; y < edgeImage.height - borderY; y++) {
      for (int x = borderX; x < edgeImage.width - borderX; x++) {
        if (edgeImage.getPixel(x, y).r > 0) {
          points.add(Point(x, y));
        }
      }
    }

    if (points.length < 50) {
      // Fallback: collect points from canny or sobel gradients if dilation was sparse
      final sobel = _computeSobelEdges(gray);
      for (int y = borderY; y < sobel.height - borderY; y++) {
        for (int x = borderX; x < sobel.width - borderX; x++) {
          if (sobel.getPixel(x, y).r > 30) {
            points.add(Point(x, y));
          }
        }
      }
      if (points.length < 50) {
        return (corners: null, confidence: 0.1);
      }
    }

    // Candidate 1: Contour extraction and Ramer-Douglas-Peucker (RDP) polygon approximation
    CardCorners? bestContourCorners;
    double bestContourScore = 0.0;

    final candidateContours = findContours(edgeImage, minPoints: 20, borderX: borderX, borderY: borderY);
    for (final contour in candidateContours) {
      if (contour.length < 24) continue;
      final perim = calculatePerimeter(contour);
      final eps = perim * 0.025;
      var approx = approximatePolygonRdp(contour, eps);
      if (approx.length == 5 && approx.first == approx.last) {
        approx = approx.sublist(0, 4);
      }
      if (approx.length == 4) {
        final ordered = orderPoints(approx);
        final factorX = origW / scaleW;
        final factorY = origH / scaleH;
        final marginX = (origW * 0.02).round();
        final marginY = (origH * 0.02).round();

        final cTL = Point<int>(
          max(0, (ordered[0].x * factorX).round() - marginX),
          max(0, (ordered[0].y * factorY).round() - marginY),
        );
        final cTR = Point<int>(
          min(origW - 1, (ordered[1].x * factorX).round() + marginX),
          max(0, (ordered[1].y * factorY).round() - marginY),
        );
        final cBR = Point<int>(
          min(origW - 1, (ordered[2].x * factorX).round() + marginX),
          min(origH - 1, (ordered[2].y * factorY).round() + marginY),
        );
        final cBL = Point<int>(
          max(0, (ordered[3].x * factorX).round() - marginX),
          min(origH - 1, (ordered[3].y * factorY).round() + marginY),
        );

        final cand = CardCorners(
          topLeft: cTL,
          topRight: cTR,
          bottomLeft: cBL,
          bottomRight: cBR,
        );

        if (cand.isConvex && cand.hasValidCornerAngles(minAngleDeg: 55.0, maxAngleDeg: 125.0)) {
          final candArea = cand.area;
          final totalArea = origW * origH;
          final areaRatio = candArea / totalArea;
          if (areaRatio >= 0.05 && areaRatio <= 0.98) {
            final asp = cand.aspectRatio;
            final isLandscape = asp >= 1.15 && asp <= 2.35;
            final isPortrait = asp >= 0.40 && asp <= 0.88;
            final isSquare = allowSquare && asp >= 0.82 && asp <= 1.20;
            if (isLandscape || isPortrait || isSquare) {
              final score = (cand.angularScore * 0.35) +
                  (cand.edgeConsistency * 0.30) +
                  (cand.rectangularityScore * 0.20) +
                  (min(1.0, areaRatio / 0.5) * 0.15);
              if (score > bestContourScore) {
                bestContourScore = score;
                bestContourCorners = cand;
              }
            }
          }
        }
      }
    }

    // Candidate 2: Extremal corner approximation
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

    // Aspect ratio check (supports landscape, portrait, and square-shaped cards)
    final aspectRatio = avgWidth / avgHeight;
    final isLandscapeCard = aspectRatio >= 1.15 && aspectRatio <= 2.35;
    final isPortraitCard = aspectRatio >= 0.42 && aspectRatio <= 0.88;
    final isSquareCard = allowSquare && aspectRatio >= 0.82 && aspectRatio <= 1.20;

    if (!isLandscapeCard && !isPortraitCard && !isSquareCard) {
      return (corners: null, confidence: 0.4);
    }

    // Opposite sides parallelism check:
    final widthRatio = min(widthTop, widthBottom) / max(widthTop, widthBottom);
    final heightRatio = min(heightLeft, heightRight) / max(heightLeft, heightRight);

    if (widthRatio < 0.65 || heightRatio < 0.65) {
      return (corners: null, confidence: 0.5);
    }

    final candidateCorners = CardCorners(
      topLeft: origTL,
      topRight: origTR,
      bottomLeft: origBL,
      bottomRight: origBR,
    );

    // Requirement 1: Verify convex quadrilateral geometry (rejects self-intersecting or bow-tie contours)
    if (!candidateCorners.isConvex) {
      if (bestContourCorners != null) {
        return (corners: bestContourCorners, confidence: bestContourScore.clamp(0.0, 1.0));
      }
      return (corners: null, confidence: 0.3);
    }

    // High confidence detected
    final confidence = (widthRatio * 0.4) + (heightRatio * 0.4) + (min(1.0, areaRatio / 0.5) * 0.2);

    if (bestContourCorners != null && bestContourScore >= 0.65) {
      return (
        corners: bestContourCorners,
        confidence: max(confidence, bestContourScore).clamp(0.0, 1.0),
      );
    }

    return (
      corners: candidateCorners,
      confidence: confidence.clamp(0.0, 1.0),
    );
  }

  /// Requirement 4: Lighting correction & tone enhancement.
  /// Analyzes average luminance and gently balances exposure without color distortion or excessive sharpening.
  img.Image _applyGentleLightingCorrection(img.Image cardImage) {
    double totalLum = 0.0;
    int pixelCount = 0;
    for (int y = 0; y < cardImage.height; y += 4) {
      for (int x = 0; x < cardImage.width; x += 4) {
        final p = cardImage.getPixel(x, y);
        totalLum += (0.299 * p.r + 0.587 * p.g + 0.114 * p.b);
        pixelCount++;
      }
    }
    final avgLum = pixelCount > 0 ? (totalLum / pixelCount) : 128.0;

    // In low-light / underexposed conditions (< 110 lum), gently brighten and boost contrast
    if (avgLum < 110.0) {
      final boost = avgLum < 75.0 ? 1.20 : 1.12;
      return img.adjustColor(
        cardImage,
        brightness: boost,
        contrast: 1.05,
      );
    }
    // In harsh highlight / overexposed conditions (> 215 lum), compress highlights gently
    if (avgLum > 215.0) {
      return img.adjustColor(
        cardImage,
        brightness: 0.95,
        contrast: 1.04,
      );
    }
    // Balanced lighting: apply gentle contrast enhancement to crisp text edges and logos
    return img.adjustColor(
      cardImage,
      contrast: 1.03,
    );
  }

  /// =========================================================================
  /// OPENCV CARD SCANNER PORT & ADAPTIVE ENHANCEMENTS
  /// Reference implementation: https://github.com/thumbdev/OpenCV-Card-Scanner (main.py)
  /// Ported to native Flutter / Dart without requiring Python runtime.
  /// Enhancements: multi-orientation support (landscape, portrait, square, rotated),
  /// Canny non-maximum suppression, adaptive hysteresis thresholding, morphological dilation,
  /// 8-connected contour extraction, Ramer-Douglas-Peucker approximation, and bilinear perspective warp.
  /// =========================================================================

  /// Euclidean distance between two points: sqrt((p1.x - p2.x)^2 + (p1.y - p2.y)^2).
  /// Mirrors `get_distance()` from thumbdev/OpenCV-Card-Scanner.
  static double getDistance(Point<num> p1, Point<num> p2) {
    final dx = (p1.x - p2.x).toDouble();
    final dy = (p1.y - p2.y).toDouble();
    return sqrt(dx * dx + dy * dy);
  }

  /// Orders an arbitrary 4-point quadrilateral into clockwise [topLeft, topRight, bottomRight, bottomLeft].
  /// Mirrors and enhances `order_points()` from thumbdev/OpenCV-Card-Scanner with centroid
  /// angular sorting and bounding-box anchor alignment, ensuring orientation-invariance for
  /// landscape, portrait, square, and rotated business cards.
  static List<Point<int>> orderPoints(List<Point<int>> pts) {
    return _orderVerticesClockwise(pts);
  }

  /// Calculates destination dimensions and coordinates for perspective correction.
  /// Mirrors `find_dest()` from thumbdev/OpenCV-Card-Scanner:
  /// maxWidth = max(dist(bl, br), dist(tl, tr))
  /// maxHeight = max(dist(tr, br), dist(tl, bl))
  static ({int width, int height, List<Point<int>> destPoints}) findDest(List<Point<int>> ordered) {
    if (ordered.length < 4) {
      return (width: 100, height: 100, destPoints: const []);
    }
    final tl = ordered[0];
    final tr = ordered[1];
    final br = ordered[2];
    final bl = ordered[3];

    final widthA = getDistance(bl, br);
    final widthB = getDistance(tl, tr);
    final maxWidth = max(widthA, widthB).round();

    final heightA = getDistance(tr, br);
    final heightB = getDistance(tl, bl);
    final maxHeight = max(heightA, heightB).round();

    final destPoints = [
      const Point<int>(0, 0),
      Point<int>(max(0, maxWidth - 1), 0),
      Point<int>(max(0, maxWidth - 1), max(0, maxHeight - 1)),
      Point<int>(0, max(0, maxHeight - 1)),
    ];

    return (width: maxWidth, height: maxHeight, destPoints: destPoints);
  }

  /// 5x5 separable Gaussian blur smoothing to eliminate sensor noise, table grains, and reflections.
  /// Equivalent to `cv2.GaussianBlur(gray, (5, 5), 0)` in OpenCV.
  static img.Image applyGaussianBlur(img.Image gray, {int kernelSize = 5}) {
    final w = gray.width;
    final h = gray.height;
    final tmp = List<int>.filled(w * h, 0);
    final out = img.Image(width: w, height: h);

    // 1D Gaussian kernel: [1, 4, 6, 4, 1] / 16 (separable 5x5 equivalent)
    for (int y = 0; y < h; y++) {
      final rowOffset = y * w;
      for (int x = 0; x < w; x++) {
        if (x < 2 || x >= w - 2) {
          tmp[rowOffset + x] = gray.getPixel(x, y).r.toInt();
          continue;
        }
        final val = (gray.getPixel(x - 2, y).r.toInt() +
                (gray.getPixel(x - 1, y).r.toInt() << 2) +
                gray.getPixel(x, y).r.toInt() * 6 +
                (gray.getPixel(x + 1, y).r.toInt() << 2) +
                gray.getPixel(x + 2, y).r.toInt()) >>
            4;
        tmp[rowOffset + x] = val;
      }
    }

    for (int x = 0; x < w; x++) {
      for (int y = 0; y < h; y++) {
        if (y < 2 || y >= h - 2) {
          final val = tmp[y * w + x];
          out.setPixelRgb(x, y, val, val, val);
          continue;
        }
        final val = (tmp[(y - 2) * w + x] +
                (tmp[(y - 1) * w + x] << 2) +
                tmp[y * w + x] * 6 +
                (tmp[(y + 1) * w + x] << 2) +
                tmp[(y + 2) * w + x]) >>
            4;
        out.setPixelRgb(x, y, val, val, val);
      }
    }

    return out;
  }

  /// Canny edge detection with Sobel gradient operators, Non-Maximum Suppression (NMS),
  /// and adaptive hysteresis thresholding.
  /// Equivalent to `cv2.Canny(blur, lowThreshold, highThreshold)` in OpenCV.
  static img.Image applyCannyEdgeDetection(
    img.Image blur, {
    int lowThreshold = 30,
    int highThreshold = 80,
    bool adaptive = true,
  }) {
    final w = blur.width;
    final h = blur.height;

    final mag = List<int>.filled(w * h, 0);
    final angle = List<int>.filled(w * h, 0);
    int peakMag = 0;

    for (int y = 1; y < h - 1; y++) {
      final rowCurr = y * w;

      for (int x = 1; x < w - 1; x++) {
        final p00 = blur.getPixel(x - 1, y - 1).r.toInt();
        final p01 = blur.getPixel(x, y - 1).r.toInt();
        final p02 = blur.getPixel(x + 1, y - 1).r.toInt();
        final p10 = blur.getPixel(x - 1, y).r.toInt();
        final p12 = blur.getPixel(x + 1, y).r.toInt();
        final p20 = blur.getPixel(x - 1, y + 1).r.toInt();
        final p21 = blur.getPixel(x, y + 1).r.toInt();
        final p22 = blur.getPixel(x + 1, y + 1).r.toInt();

        final gx = (p02 + (p12 << 1) + p22) - (p00 + (p10 << 1) + p20);
        final gy = (p20 + (p21 << 1) + p22) - (p00 + (p01 << 1) + p02);

        final m = min(255, sqrt(gx * gx + gy * gy).round());
        final idx = rowCurr + x;
        mag[idx] = m;
        if (m > peakMag) peakMag = m;

        // Direction quantization to 0, 45, 90, 135 degrees
        double theta = atan2(gy.toDouble(), gx.toDouble()) * (180.0 / pi);
        if (theta < 0) theta += 180.0;

        if ((theta >= 0 && theta < 22.5) || (theta >= 157.5 && theta <= 180.0)) {
          angle[idx] = 0; // horizontal gradient
        } else if (theta >= 22.5 && theta < 67.5) {
          angle[idx] = 45; // diagonal
        } else if (theta >= 67.5 && theta < 112.5) {
          angle[idx] = 90; // vertical gradient
        } else {
          angle[idx] = 135; // anti-diagonal
        }
      }
    }

    int tHigh = highThreshold;
    int tLow = lowThreshold;
    if (adaptive && peakMag > 20) {
      tHigh = max(24, min(180, (peakMag * 0.38).round()));
      tLow = max(12, (tHigh * 0.40).round());
    }

    // Non-Maximum Suppression (NMS)
    final nms = List<int>.filled(w * h, 0);
    for (int y = 1; y < h - 1; y++) {
      final rowPrev = (y - 1) * w;
      final rowCurr = y * w;
      final rowNext = (y + 1) * w;

      for (int x = 1; x < w - 1; x++) {
        final idx = rowCurr + x;
        final m = mag[idx];
        if (m < tLow) continue;

        int q = 0;
        int r = 0;
        final dir = angle[idx];
        if (dir == 0) {
          q = mag[idx + 1];
          r = mag[idx - 1];
        } else if (dir == 45) {
          q = mag[rowPrev + x + 1];
          r = mag[rowNext + x - 1];
        } else if (dir == 90) {
          q = mag[rowPrev + x];
          r = mag[rowNext + x];
        } else if (dir == 135) {
          q = mag[rowPrev + x - 1];
          r = mag[rowNext + x + 1];
        }

        if (m >= q && m >= r) {
          nms[idx] = m;
        }
      }
    }

    // Hysteresis thresholding & edge tracking
    final edgeImage = img.Image(width: w, height: h);
    final strongIndices = <int>[];

    for (int i = 0; i < w * h; i++) {
      final v = nms[i];
      if (v >= tHigh) {
        nms[i] = 255;
        strongIndices.add(i);
      } else if (v >= tLow) {
        nms[i] = 50; // weak edge candidate
      } else {
        nms[i] = 0;
      }
    }

    while (strongIndices.isNotEmpty) {
      final idx = strongIndices.removeLast();
      final x = idx % w;
      final y = idx ~/ w;

      for (int dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= h) continue;
        final rowOffset = ny * w;
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          if (nx < 0 || nx >= w) continue;
          final nIdx = rowOffset + nx;
          if (nms[nIdx] == 50) {
            nms[nIdx] = 255;
            strongIndices.add(nIdx);
          }
        }
      }
    }

    for (int y = 0; y < h; y++) {
      final rowOffset = y * w;
      for (int x = 0; x < w; x++) {
        final val = nms[rowOffset + x] == 255 ? 255 : 0;
        edgeImage.setPixelRgb(x, y, val, val, val);
      }
    }

    return edgeImage;
  }

  /// Morphological dilation using a 3x3 structuring element.
  /// Equivalent to `cv2.dilate(edges, kernel, iterations=1)` in OpenCV.
  /// Bridges small gaps and connects broken perimeter lines into continuous contours.
  static img.Image applyMorphologicalDilation(img.Image edges, {int iterations = 1}) {
    img.Image current = edges;
    final w = edges.width;
    final h = edges.height;

    for (int iter = 0; iter < iterations; iter++) {
      final dilated = img.Image(width: w, height: h);
      for (int y = 0; y < h; y++) {
        final rowPrev = max(0, y - 1);
        final rowNext = min(h - 1, y + 1);
        for (int x = 0; x < w; x++) {
          if (current.getPixel(x, y).r > 0) {
            dilated.setPixelRgb(x, y, 255, 255, 255);
            continue;
          }
          final colPrev = max(0, x - 1);
          final colNext = min(w - 1, x + 1);

          final hasEdge = current.getPixel(colPrev, rowPrev).r > 0 ||
              current.getPixel(x, rowPrev).r > 0 ||
              current.getPixel(colNext, rowPrev).r > 0 ||
              current.getPixel(colPrev, y).r > 0 ||
              current.getPixel(colNext, y).r > 0 ||
              current.getPixel(colPrev, rowNext).r > 0 ||
              current.getPixel(x, rowNext).r > 0 ||
              current.getPixel(colNext, rowNext).r > 0;

          final val = hasEdge ? 255 : 0;
          dilated.setPixelRgb(x, y, val, val, val);
        }
      }
      current = dilated;
    }
    return current;
  }

  /// 8-connected contour extraction from binary edge image.
  /// Equivalent to `cv2.findContours(dilated, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)` in OpenCV.
  static List<List<Point<int>>> findContours(
    img.Image dilated, {
    int minPoints = 20,
    int borderX = 2,
    int borderY = 2,
  }) {
    return _findCandidateContours(dilated, 100, borderX, borderY, minPoints: minPoints);
  }

  /// Ramer-Douglas-Peucker polygon approximation.
  /// Equivalent to `cv2.approxPolyDP(contour, epsilon, True)` in OpenCV.
  /// For closed contours returning 5 vertices where the first and last points coincide or close the loop,
  /// returns the 4 distinct quadrilateral vertices.
  static List<Point<int>> approximatePolygonRdp(List<Point<int>> contour, double epsilon) {
    var approx = _approximatePolygonRDP(contour, epsilon);
    if (approx.length == 5) {
      if (approx.first == approx.last || getDistance(approx.first, approx.last) <= max(4.0, epsilon)) {
        approx = approx.sublist(0, 4);
      }
    }
    return approx;
  }

  /// Calculates perimeter of a closed polygonal contour.
  /// Equivalent to `cv2.arcLength(contour, True)` in OpenCV.
  static double calculatePerimeter(List<Point<int>> pts) {
    return _calculatePerimeter(pts);
  }

  /// Perspective transformation mapping 4 quadrilateral corners to rectangular output.
  /// Equivalent to `cv2.warpPerspective(image, M, (maxWidth, maxHeight))` in OpenCV.
  static img.Image warpPerspective(
    img.Image image,
    CardCorners corners,
    int destWidth,
    int destHeight,
  ) {
    final destImage = img.Image(
      width: destWidth,
      height: destHeight,
      numChannels: image.numChannels,
    );

    return img.copyRectify(
      image,
      topLeft: img.Point(corners.topLeft.x, corners.topLeft.y),
      topRight: img.Point(corners.topRight.x, corners.topRight.y),
      bottomLeft: img.Point(corners.bottomLeft.x, corners.bottomLeft.y),
      bottomRight: img.Point(corners.bottomRight.x, corners.bottomRight.y),
      interpolation: img.Interpolation.linear,
      toImage: destImage,
    );
  }

  /// Complete card scanning detection combining Canny, Dilation, Contours, and Quad evaluation.
  /// Mirrors `scan()` from thumbdev/OpenCV-Card-Scanner with multi-aspect-ratio enhancements.
  CardCorners? scanCard(
    img.Image image, {
    bool allowSquare = true,
    ViewfinderNormalizedRect? viewfinderRoi,
  }) {
    final res = detectCorners(image, viewfinderRoi: viewfinderRoi, allowSquare: allowSquare);
    return res.corners;
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

  /// Detects presence of an actual physical business card in [image].
  /// Supports rectangular business cards (landscape and portrait) and square cards.
  /// Enforces boundary edge contrast against surface, interior text/glyph variance (rejecting blank surfaces),
  /// non-clipping margins, and adequate capture lighting/sharpness.
  BusinessCardDetectionResult detectBusinessCardPresence(
    img.Image image, {
    ViewfinderNormalizedRect? viewfinderRoi,
    bool allowSquare = true,
  }) {
    if (image.width < 50 || image.height < 40) {
      return BusinessCardDetectionResult.none();
    }

    // 1. Lighting and blur assessment
    final baseQuality = assessCaptureQuality(image);
    if (baseQuality.isExtremelyDark ||
        baseQuality.isExtremelyOverexposed ||
        baseQuality.isBlurry) {
      return BusinessCardDetectionResult(
        isDetected: false,
        quality: baseQuality,
      );
    }

    // 2. Corner and boundary detection
    final cornerDetection = detectCorners(image, viewfinderRoi: viewfinderRoi, allowSquare: allowSquare);
    final corners = cornerDetection.corners;
    if (corners == null || cornerDetection.confidence < 0.40) {
      return BusinessCardDetectionResult(
        isDetected: false,
        confidence: cornerDetection.confidence,
        quality: baseQuality,
      );
    }

    // 3. Aspect ratio validation
    final widthTop = _distance(corners.topLeft, corners.topRight);
    final widthBottom = _distance(corners.bottomLeft, corners.bottomRight);
    final heightLeft = _distance(corners.topLeft, corners.bottomLeft);
    final heightRight = _distance(corners.topRight, corners.bottomRight);

    final avgWidth = (widthTop + widthBottom) / 2.0;
    final avgHeight = (heightLeft + heightRight) / 2.0;
    if (avgWidth <= 30 || avgHeight <= 20) {
      return BusinessCardDetectionResult(
        isDetected: false,
        confidence: 0.2,
        quality: baseQuality,
      );
    }

    final aspectRatio = avgWidth / avgHeight;
    final isLandscape = aspectRatio >= 1.20 && aspectRatio <= 2.25;
    final isPortrait = aspectRatio >= 0.42 && aspectRatio <= 0.82;
    final isSquare = allowSquare && aspectRatio >= 0.82 && aspectRatio <= 1.20;

    if (!isLandscape && !isPortrait && !isSquare) {
      return BusinessCardDetectionResult(
        isDetected: false,
        aspectRatio: aspectRatio,
        confidence: 0.35,
        quality: baseQuality,
      );
    }

    // 4. Clipping check against frame edges
    final marginX = (image.width * 0.025).round();
    final marginY = (image.height * 0.025).round();
    bool isClipping = false;
    for (final p in [
      corners.topLeft,
      corners.topRight,
      corners.bottomLeft,
      corners.bottomRight,
    ]) {
      if (p.x <= marginX ||
          p.x >= (image.width - marginX) ||
          p.y <= marginY ||
          p.y >= (image.height - marginY)) {
        isClipping = true;
        break;
      }
    }

    if (isClipping) {
      return BusinessCardDetectionResult(
        isDetected: false,
        corners: corners,
        aspectRatio: aspectRatio,
        quality: CaptureQualityAssessment(
          brightness: baseQuality.brightness,
          isExtremelyDark: false,
          isExtremelyOverexposed: false,
          blurScore: baseQuality.blurScore,
          isBlurry: false,
          cardAreaRatio: baseQuality.cardAreaRatio,
          isTooSmall: false,
          isTooClose: false,
          isClipping: true,
          isSeverePerspective: false,
          isUsableResolution: true,
          guidanceMessage: 'Keep the full card inside the frame',
        ),
      );
    }

    // 5. Interior Texture & Content Variance (Distinguish from Blank Paper or Monotone Rectangles)
    final interiorStats = _measureInteriorTextureAndContrast(image, corners);
    if (!interiorStats.hasTextOrContent) {
      return BusinessCardDetectionResult(
        isDetected: false,
        corners: corners,
        aspectRatio: aspectRatio,
        edgeContrast: interiorStats.edgeContrast,
        interiorTextureVariance: interiorStats.variance,
        hasCardContent: false,
        quality: CaptureQualityAssessment(
          brightness: baseQuality.brightness,
          isExtremelyDark: false,
          isExtremelyOverexposed: false,
          blurScore: baseQuality.blurScore,
          isBlurry: false,
          cardAreaRatio: baseQuality.cardAreaRatio,
          isTooSmall: false,
          isTooClose: false,
          isClipping: false,
          isSeverePerspective: false,
          isUsableResolution: true,
          guidanceMessage: 'Position card inside the frame',
        ),
      );
    }

    // 6. Valid genuine business card identified
    final minX = [corners.topLeft.x, corners.topRight.x, corners.bottomLeft.x, corners.bottomRight.x].reduce(min);
    final maxX = [corners.topLeft.x, corners.topRight.x, corners.bottomLeft.x, corners.bottomRight.x].reduce(max);
    final minY = [corners.topLeft.y, corners.topRight.y, corners.bottomLeft.y, corners.bottomRight.y].reduce(min);
    final maxY = [corners.topLeft.y, corners.topRight.y, corners.bottomLeft.y, corners.bottomRight.y].reduce(max);

    final normBox = Rect.fromLTRB(
      (minX / image.width).clamp(0.0, 1.0),
      (minY / image.height).clamp(0.0, 1.0),
      (maxX / image.width).clamp(0.0, 1.0),
      (maxY / image.height).clamp(0.0, 1.0),
    );

    final normPolygon = corners.toNormalizedPolygon(image.width, image.height);

    final finalQuality = assessCaptureQuality(
      image,
      corners: corners,
      confidence: cornerDetection.confidence,
    );

    final cardArea = corners.area;
    final totalArea = image.width * image.height;
    final cardAreaRatio = (cardArea / totalArea).clamp(0.0, 1.0);

    return BusinessCardDetectionResult(
      isDetected: true,
      state: CardDetectionState.detected,
      corners: corners,
      normalizedPolygon: normPolygon,
      normalizedBoundingBox: normBox,
      confidence: cornerDetection.confidence,
      aspectRatio: aspectRatio,
      isLandscape: isLandscape,
      isSquare: isSquare,
      edgeContrast: interiorStats.edgeContrast,
      interiorTextureVariance: interiorStats.variance,
      hasCardContent: true,
      cardAreaRatio: cardAreaRatio,
      angularScore: corners.angularScore,
      rectangularityScore: corners.rectangularityScore,
      quality: finalQuality,
    );
  }

  /// Real-time frame analysis from camera luminance byte array.
  /// Accounts for row strides, pixel strides, sensor orientation, and lens direction.
  BusinessCardDetectionResult detectCardInLumaBytes({
    required List<int> lumaBytes,
    required int width,
    required int height,
    int bytesPerRow = 0,
    int bytesPerPixel = 1,
    int sensorOrientation = 0,
    bool isFrontFacing = false,
    ViewfinderNormalizedRect? viewfinderRoi,
    bool allowSquare = true,
  }) {
    if (width < 60 || height < 40 || lumaBytes.isEmpty) {
      return BusinessCardDetectionResult.none();
    }

    final rowStride = bytesPerRow > 0 ? bytesPerRow : width;

    img.Image thumb;
    if (sensorOrientation != 0) {
      thumb = convertYuvToUprightLuma(
        lumaBytes: lumaBytes,
        rawWidth: width,
        rawHeight: height,
        bytesPerRow: rowStride,
        bytesPerPixel: bytesPerPixel,
        sensorOrientation: sensorOrientation,
        isFrontFacing: isFrontFacing,
        targetWidth: 200,
      );
    } else {
      // Fast downsampled thumbnail (~180px width)
      const targetW = 180;
      final stepX = max(1, width ~/ targetW);
      final targetH = (height / stepX).round();
      final stepY = stepX;

      thumb = img.Image(width: targetW, height: targetH);
      for (int ty = 0; ty < targetH; ty++) {
        final srcY = min(height - 1, ty * stepY);
        final rowOffset = srcY * rowStride;
        for (int tx = 0; tx < targetW; tx++) {
          final srcX = min(width - 1, tx * stepX);
          final pixelIndex = rowOffset + srcX * bytesPerPixel;
          final lum = pixelIndex < lumaBytes.length ? lumaBytes[pixelIndex] : 0;
          thumb.setPixelRgb(tx, ty, lum, lum, lum);
        }
      }
    }

    return detectBusinessCardPresence(
      thumb,
      viewfinderRoi: viewfinderRoi,
      allowSquare: allowSquare,
    );
  }

  /// Evaluates boundary edge contrast and interior texture/text variance.
  ({double variance, double edgeContrast, bool hasTextOrContent})
      _measureInteriorTextureAndContrast(img.Image image, CardCorners corners) {
    final int minX = [corners.topLeft.x, corners.topRight.x, corners.bottomLeft.x, corners.bottomRight.x].reduce(min);
    final int maxX = [corners.topLeft.x, corners.topRight.x, corners.bottomLeft.x, corners.bottomRight.x].reduce(max);
    final int minY = [corners.topLeft.y, corners.topRight.y, corners.bottomLeft.y, corners.bottomRight.y].reduce(min);
    final int maxY = [corners.topLeft.y, corners.topRight.y, corners.bottomLeft.y, corners.bottomRight.y].reduce(max);

    final cardW = maxX - minX;
    final cardH = maxY - minY;
    if (cardW < 30 || cardH < 20) {
      return (variance: 0.0, edgeContrast: 0.0, hasTextOrContent: false);
    }

    final cx = (minX + maxX) / 2.0;
    final cy = (minY + maxY) / 2.0;

    // 1. Measure boundary edge contrast by sampling points towards center (card interior)
    // and away from center (background surface).
    double edgeDiffSum = 0.0;
    int edgeSampleCount = 0;

    final stepX = max(1, cardW ~/ 16);
    for (int x = minX + 8; x < maxX - 8; x += stepX) {
      final inY = (minY + (cy - minY) * 0.15).round().clamp(0, image.height - 1);
      final outY = max(0, minY - 8);
      final inL = image.getPixel(x, inY).r;
      final outL = image.getPixel(x, outY).r;
      edgeDiffSum += (inL - outL).abs();
      edgeSampleCount++;

      final inYBot = (maxY - (maxY - cy) * 0.15).round().clamp(0, image.height - 1);
      final outYBot = min(image.height - 1, maxY + 8);
      final inLBot = image.getPixel(x, inYBot).r;
      final outLBot = image.getPixel(x, outYBot).r;
      edgeDiffSum += (inLBot - outLBot).abs();
      edgeSampleCount++;
    }

    final stepY = max(1, cardH ~/ 16);
    for (int y = minY + 8; y < maxY - 8; y += stepY) {
      final inX = (minX + (cx - minX) * 0.15).round().clamp(0, image.width - 1);
      final outX = max(0, minX - 8);
      final inL = image.getPixel(inX, y).r;
      final outL = image.getPixel(outX, y).r;
      edgeDiffSum += (inL - outL).abs();
      edgeSampleCount++;

      final inXRight = (maxX - (maxX - cx) * 0.15).round().clamp(0, image.width - 1);
      final outXRight = min(image.width - 1, maxX + 8);
      final inLRight = image.getPixel(inXRight, y).r;
      final outLRight = image.getPixel(outXRight, y).r;
      edgeDiffSum += (inLRight - outLRight).abs();
      edgeSampleCount++;
    }

    final avgEdgeContrast = edgeSampleCount > 0 ? (edgeDiffSum / edgeSampleCount) : 0.0;

    // 2. Interior texture variance & high-frequency edge counts
    final int innerX1 = minX + (cardW * 0.15).round();
    final int innerX2 = maxX - (cardW * 0.15).round();
    final int innerY1 = minY + (cardW * 0.15).round();
    final int innerY2 = maxY - (cardW * 0.15).round();

    double lumaSum = 0.0;
    double lumaSqSum = 0.0;
    int sampleCount = 0;
    int highFreqEdges = 0;

    final int step = max(1, min(cardW, cardH) ~/ 30);

    int prevLuma = -1;
    for (int y = innerY1; y < innerY2; y += step) {
      for (int x = innerX1; x < innerX2; x += step) {
        final p = image.getPixel(x, y);
        final luma = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        lumaSum += luma;
        lumaSqSum += luma * luma;
        sampleCount++;

        if (prevLuma >= 0) {
          final diff = (luma - prevLuma).abs();
          if (diff > 25) {
            highFreqEdges++;
          }
        }
        prevLuma = luma;
      }
    }

    if (sampleCount < 10) {
      return (variance: 0.0, edgeContrast: avgEdgeContrast, hasTextOrContent: false);
    }

    final mean = lumaSum / sampleCount;
    final variance = sqrt(max(0.0, (lumaSqSum / sampleCount) - (mean * mean)));

    // A real business card has printed text characters and lines:
    // Blank surfaces (sheets of plain paper, monotone tables, solid color cards) have very low variance (< 12) or few edges (< 5).
    // An actual business card with text lines has variance >= 12 or highFreqEdges >= 5, AND edgeContrast >= 9.0.
    final bool hasTextOrContent = (variance >= 12.0 || highFreqEdges >= 5) && avgEdgeContrast >= 9.0;

    return (
      variance: variance,
      edgeContrast: avgEdgeContrast,
      hasTextOrContent: hasTextOrContent,
    );
  }

  double _distance(Point<int> p1, Point<int> p2) {
    final dx = (p1.x - p2.x).toDouble();
    final dy = (p1.y - p2.y).toDouble();
    return sqrt(dx * dx + dy * dy);
  }

  /// Converts raw YUV420 Y-plane bytes into an upright grayscale [img.Image],
  /// correctly accounting for row strides, pixel strides, sensor orientation, and lens direction.
  static img.Image convertYuvToUprightLuma({
    required List<int> lumaBytes,
    required int rawWidth,
    required int rawHeight,
    required int bytesPerRow,
    int bytesPerPixel = 1,
    required int sensorOrientation,
    bool isFrontFacing = false,
    int targetWidth = 200,
  }) {
    if (rawWidth <= 0 || rawHeight <= 0 || lumaBytes.isEmpty) {
      return img.Image(width: 1, height: 1);
    }

    // Determine target dimensions based on orientation
    final bool isRotated = (sensorOrientation == 90 || sensorOrientation == 270);
    final int outW = isRotated ? targetWidth : (targetWidth * rawWidth ~/ rawHeight);
    final int outH = isRotated ? (targetWidth * rawWidth ~/ rawHeight) : (targetWidth * rawHeight ~/ rawWidth);

    final result = img.Image(width: max(1, outW), height: max(1, outH));

    final int maxRawX = rawWidth - 1;
    final int maxRawY = rawHeight - 1;
    final int maxOutX = max(1, outW - 1);
    final int maxOutY = max(1, outH - 1);

    for (int uy = 0; uy < outH; uy++) {
      for (int ux = 0; ux < outW; ux++) {
        int sx = 0;
        int sy = 0;

        switch (sensorOrientation) {
          case 90:
            // Android back camera: 90 deg clockwise
            sx = (uy * maxRawX ~/ maxOutY).clamp(0, maxRawX);
            sy = ((maxOutX - ux) * maxRawY ~/ maxOutX).clamp(0, maxRawY);
            break;
          case 270:
            // Android front camera / 270 deg
            sx = ((maxOutY - uy) * maxRawX ~/ maxOutY).clamp(0, maxRawX);
            sy = (ux * maxRawY ~/ maxOutX).clamp(0, maxRawY);
            break;
          case 180:
            sx = ((maxOutX - ux) * maxRawX ~/ maxOutX).clamp(0, maxRawX);
            sy = ((maxOutY - uy) * maxRawY ~/ maxOutY).clamp(0, maxRawY);
            break;
          case 0:
          default:
            sx = (ux * maxRawX ~/ maxOutX).clamp(0, maxRawX);
            sy = (uy * maxRawY ~/ maxOutY).clamp(0, maxRawY);
            break;
        }

        if (isFrontFacing && (sensorOrientation == 90 || sensorOrientation == 270)) {
          // Mirror horizontally for front camera
          sy = maxRawY - sy;
        }

        final int offset = sy * bytesPerRow + sx * bytesPerPixel;
        final int lum = (offset >= 0 && offset < lumaBytes.length) ? lumaBytes[offset] : 0;
        result.setPixelRgb(ux, uy, lum, lum, lum);
      }
    }

    return result;
  }

  static double _perpendicularDistance(Point<int> p, Point<int> lineStart, Point<int> lineEnd) {
    final dx = (lineEnd.x - lineStart.x).toDouble();
    final dy = (lineEnd.y - lineStart.y).toDouble();
    final lineLenSq = dx * dx + dy * dy;
    if (lineLenSq == 0) {
      final dpx = (p.x - lineStart.x).toDouble();
      final dpy = (p.y - lineStart.y).toDouble();
      return sqrt(dpx * dpx + dpy * dpy);
    }
    final num = ((p.x - lineStart.x) * dy - (p.y - lineStart.y) * dx).abs();
    return num / sqrt(lineLenSq);
  }

  static List<Point<int>> _approximatePolygonRDP(List<Point<int>> points, double epsilon) {
    if (points.length < 3) return points;

    double maxDist = 0.0;
    int index = 0;
    final start = points.first;
    final end = points.last;

    for (int i = 1; i < points.length - 1; i++) {
      final d = _perpendicularDistance(points[i], start, end);
      if (d > maxDist) {
        maxDist = d;
        index = i;
      }
    }

    if (maxDist > epsilon) {
      final left = _approximatePolygonRDP(points.sublist(0, index + 1), epsilon);
      final right = _approximatePolygonRDP(points.sublist(index), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [start, end];
    }
  }

  static List<Point<int>> _orderVerticesClockwise(List<Point<int>> pts) {
    if (pts.length != 4) return pts;
    final cx = (pts[0].x + pts[1].x + pts[2].x + pts[3].x) / 4.0;
    final cy = (pts[0].y + pts[1].y + pts[2].y + pts[3].y) / 4.0;

    final sorted = List<Point<int>>.from(pts)
      ..sort((a, b) {
        final angleA = atan2(a.y - cy, a.x - cx);
        final angleB = atan2(b.y - cy, b.x - cx);
        return angleA.compareTo(angleB);
      });

    // Find vertex closest to Top-Left (minimizing x + y)
    int tlIdx = 0;
    int minSum = sorted[0].x + sorted[0].y;
    for (int i = 1; i < 4; i++) {
      final sum = sorted[i].x + sorted[i].y;
      if (sum < minSum) {
        minSum = sum;
        tlIdx = i;
      }
    }

    return [
      sorted[tlIdx],
      sorted[(tlIdx + 1) % 4],
      sorted[(tlIdx + 2) % 4],
      sorted[(tlIdx + 3) % 4],
    ];
  }

  static double _calculatePerimeter(List<Point<int>> pts) {
    double perim = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % pts.length];
      final dx = (p1.x - p2.x).toDouble();
      final dy = (p1.y - p2.y).toDouble();
      perim += sqrt(dx * dx + dy * dy);
    }
    return perim;
  }

  static List<List<Point<int>>> _findCandidateContours(
    img.Image edgeImage,
    int threshold,
    int borderX,
    int borderY, {
    int minPoints = 20,
  }) {
    final w = edgeImage.width;
    final h = edgeImage.height;
    final visited = List<bool>.filled(w * h, false);
    final contours = <List<Point<int>>>[];

    // 8-connected neighbors
    const dx = [-1, 0, 1, 1, 1, 0, -1, -1];
    const dy = [-1, -1, -1, 0, 1, 1, 1, 0];

    for (int y = borderY; y < h - borderY; y += 2) {
      for (int x = borderX; x < w - borderX; x += 2) {
        final idx = y * w + x;
        if (visited[idx]) continue;
        if (edgeImage.getPixel(x, y).r <= threshold) continue;

        // Trace component
        final contour = <Point<int>>[];
        final queue = <Point<int>>[Point(x, y)];
        visited[idx] = true;

        while (queue.isNotEmpty && contour.length < 1200) {
          final curr = queue.removeLast();
          contour.add(curr);

          for (int k = 0; k < 8; k++) {
            final nx = curr.x + dx[k];
            final ny = curr.y + dy[k];
            if (nx < borderX || nx >= w - borderX || ny < borderY || ny >= h - borderY) {
              continue;
            }
            final nIdx = ny * w + nx;
            if (!visited[nIdx] && edgeImage.getPixel(nx, ny).r > threshold) {
              visited[nIdx] = true;
              queue.add(Point(nx, ny));
            }
          }
        }

        if (contour.length >= minPoints) {
          contours.add(contour);
          if (contours.length >= 25) break;
        }
      }
      if (contours.length >= 25) break;
    }

    contours.sort((a, b) => b.length.compareTo(a.length));
    return contours;
  }
}
