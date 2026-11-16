import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'ocr_side_result.dart';

/// Metadata preserving the spatial geometry and scaling parameters of an image crop
/// used for targeted high-resolution re-OCR.
@immutable
class CropTransformationMetadata {
  /// Left offset in original image pixel space.
  final int cropLeft;

  /// Top offset in original image pixel space.
  final int cropTop;

  /// Width of the crop in original image pixel space before upscaling.
  final int cropWidth;

  /// Height of the crop in original image pixel space before upscaling.
  final int cropHeight;

  /// Horizontal padding added to the target region.
  final int padX;

  /// Vertical padding added to the target region.
  final int padY;

  /// Scale multiplier applied to the crop for OCR legibility.
  final double scale;

  /// Dimensions of the original card image.
  final int originalWidth;
  final int originalHeight;

  const CropTransformationMetadata({
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
    this.padX = 0,
    this.padY = 0,
    this.scale = 1.0,
    required this.originalWidth,
    required this.originalHeight,
  });

  /// Maps a bounding box detected within the crop back to original image pixel coordinates.
  /// If the transformation is mathematically invalid or degenerate, returns [Rect.zero].
  Rect mapCropRectToOriginal(Rect cropRect) {
    if (scale <= 0 || cropWidth <= 0 || cropHeight <= 0) {
      return Rect.zero;
    }

    final origLeft = cropLeft + (cropRect.left / scale);
    final origTop = cropTop + (cropRect.top / scale);
    final origWidth = cropRect.width / scale;
    final origHeight = cropRect.height / scale;

    final maxW = originalWidth > 0 ? originalWidth.toDouble() : double.infinity;
    final maxH = originalHeight > 0 ? originalHeight.toDouble() : double.infinity;

    final clampLeft = origLeft.clamp(0.0, maxW);
    final clampTop = origTop.clamp(0.0, maxH);
    final clampRight = (origLeft + origWidth).clamp(0.0, maxW);
    final clampBottom = (origTop + origHeight).clamp(0.0, maxH);

    final w = clampRight - clampLeft;
    final h = clampBottom - clampTop;
    if (w <= 0 || h <= 0) return Rect.zero;

    return Rect.fromLTWH(clampLeft, clampTop, w, h);
  }

  Map<String, dynamic> toJson() => {
        'cropLeft': cropLeft,
        'cropTop': cropTop,
        'cropWidth': cropWidth,
        'cropHeight': cropHeight,
        'padX': padX,
        'padY': padY,
        'scale': scale,
        'originalWidth': originalWidth,
        'originalHeight': originalHeight,
      };

  factory CropTransformationMetadata.fromJson(Map<String, dynamic> json) {
    return CropTransformationMetadata(
      cropLeft: (json['cropLeft'] as num?)?.toInt() ?? 0,
      cropTop: (json['cropTop'] as num?)?.toInt() ?? 0,
      cropWidth: (json['cropWidth'] as num?)?.toInt() ?? 0,
      cropHeight: (json['cropHeight'] as num?)?.toInt() ?? 0,
      padX: (json['padX'] as num?)?.toInt() ?? 0,
      padY: (json['padY'] as num?)?.toInt() ?? 0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      originalWidth: (json['originalWidth'] as num?)?.toInt() ?? 0,
      originalHeight: (json['originalHeight'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Structured record of an OCR observation recovered through targeted high-resolution re-OCR.
/// Retained separately from baseline observations to maintain complete auditability and traceability.
@immutable
class RecoveredOcrObservation {
  /// Unique identifier for this recovered observation (e.g. 'rec_front_paddle_1730000000').
  final String id;

  /// Recovered recognized text string.
  final String text;

  /// Engine that produced this recovered observation (e.g. 'PaddleOCR (Targeted)', 'Google ML Kit (Targeted)').
  final String sourceEngine;

  /// Card side where the target region resides.
  final CardSide side;

  /// Restored bounding box in original source image pixel coordinates.
  final Rect originalCoordinates;

  /// Bounding box within the isolated crop image.
  final Rect cropCoordinates;

  /// Complete transformation metadata used to map crop coordinates back to original coordinates.
  final CropTransformationMetadata transformationMetadata;

  /// Token recognition confidence score (0.0 to 1.0).
  final double ocrConfidence;

  /// Engine and re-OCR pipeline processing version (e.g. '3.0.0').
  final String processingVersion;

  /// Diagnostic reason triggering the targeted re-OCR for this region.
  final String reprocessingReason;

  /// True if spatial mapping back to original image space could not be established with high fidelity.
  final bool isSpatialMappingUncertain;

  /// Creation timestamp.
  final DateTime createdAt;

  const RecoveredOcrObservation({
    required this.id,
    required this.text,
    required this.sourceEngine,
    required this.side,
    required this.originalCoordinates,
    required this.cropCoordinates,
    required this.transformationMetadata,
    required this.ocrConfidence,
    this.processingVersion = '3.0.0',
    required this.reprocessingReason,
    this.isSpatialMappingUncertain = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'sourceEngine': sourceEngine,
        'side': side.name,
        'originalCoordinates': {
          'left': originalCoordinates.left,
          'top': originalCoordinates.top,
          'width': originalCoordinates.width,
          'height': originalCoordinates.height,
        },
        'cropCoordinates': {
          'left': cropCoordinates.left,
          'top': cropCoordinates.top,
          'width': cropCoordinates.width,
          'height': cropCoordinates.height,
        },
        'transformationMetadata': transformationMetadata.toJson(),
        'ocrConfidence': double.parse(ocrConfidence.toStringAsFixed(3)),
        'processingVersion': processingVersion,
        'reprocessingReason': reprocessingReason,
        'isSpatialMappingUncertain': isSpatialMappingUncertain,
        'createdAt': createdAt.toIso8601String(),
      };

  factory RecoveredOcrObservation.fromJson(Map<String, dynamic> json) {
    final origMap = json['originalCoordinates'] as Map<String, dynamic>?;
    final cropMap = json['cropCoordinates'] as Map<String, dynamic>?;
    final transMap = json['transformationMetadata'] as Map<String, dynamic>?;

    final sideStr = json['side'] as String? ?? 'front';
    final cardSide = CardSide.values.firstWhere(
      (s) => s.name == sideStr,
      orElse: () => CardSide.front,
    );

    return RecoveredOcrObservation(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      sourceEngine: json['sourceEngine'] as String? ?? '',
      side: cardSide,
      originalCoordinates: origMap != null
          ? Rect.fromLTWH(
              (origMap['left'] as num?)?.toDouble() ?? 0.0,
              (origMap['top'] as num?)?.toDouble() ?? 0.0,
              (origMap['width'] as num?)?.toDouble() ?? 0.0,
              (origMap['height'] as num?)?.toDouble() ?? 0.0,
            )
          : Rect.zero,
      cropCoordinates: cropMap != null
          ? Rect.fromLTWH(
              (cropMap['left'] as num?)?.toDouble() ?? 0.0,
              (cropMap['top'] as num?)?.toDouble() ?? 0.0,
              (cropMap['width'] as num?)?.toDouble() ?? 0.0,
              (cropMap['height'] as num?)?.toDouble() ?? 0.0,
            )
          : Rect.zero,
      transformationMetadata: transMap != null
          ? CropTransformationMetadata.fromJson(transMap)
          : const CropTransformationMetadata(
              cropLeft: 0,
              cropTop: 0,
              cropWidth: 0,
              cropHeight: 0,
              originalWidth: 0,
              originalHeight: 0,
            ),
      ocrConfidence: (json['ocrConfidence'] as num?)?.toDouble() ?? 0.90,
      processingVersion: json['processingVersion'] as String? ?? '3.0.0',
      reprocessingReason: json['reprocessingReason'] as String? ?? '',
      isSpatialMappingUncertain:
          json['isSpatialMappingUncertain'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

