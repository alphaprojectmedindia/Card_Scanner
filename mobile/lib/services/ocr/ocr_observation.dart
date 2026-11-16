import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../../models/ocr_side_result.dart';

/// Structured observation model preserving text geometry, engine attribution,
/// confidence, and line/block relationships for physical business-card OCR.
@immutable
class OcrObservation {
  /// Unique identifier for this observation (e.g. 'paddle_0', 'mlkit_1').
  final String id;

  /// Complete recognized text content.
  final String text;

  /// Absolute bounding box in source image pixel coordinates.
  final Rect boundingBox;

  /// Normalized bounding box coordinates (0.0 to 1.0) relative to image width/height.
  final Rect normalizedBoundingBox;

  /// Character/token recognition confidence (0.0 to 1.0).
  final double confidence;

  /// Engine that produced this observation (e.g. 'PaddleOCR (PP-OCRv5 Mobile)', 'Google ML Kit').
  final String engine;

  /// Sequential reading-order line index.
  final int lineIndex;

  final String? _explicitRegion;

  /// Spatial card region ('top', 'middle', 'bottom', 'left', 'right', 'center').
  String get region {
    if (_explicitRegion != null) return _explicitRegion;
    final midY = (normalizedBoundingBox.top + normalizedBoundingBox.bottom) / 2.0;
    if (midY < 0.33) return 'top';
    if (midY > 0.67) return 'bottom';
    final midX = (normalizedBoundingBox.left + normalizedBoundingBox.right) / 2.0;
    if (midX < 0.33) return 'left';
    if (midX > 0.67) return 'right';
    return 'middle';
  }

  /// Optional sub-element/word-level observations if available.
  final List<OcrObservation> elements;

  const OcrObservation({
    required this.id,
    required this.text,
    required this.boundingBox,
    required this.normalizedBoundingBox,
    this.confidence = 1.0,
    required this.engine,
    this.lineIndex = 0,
    String? region,
    this.elements = const [],
  }) : _explicitRegion = region;

  /// Factory helper constructing an observation from an [OcrLineMetadata].
  factory OcrObservation.fromLineMetadata(
    OcrLineMetadata meta, {
    required double imageWidth,
    required double imageHeight,
    required String engine,
  }) {
    final box = meta.boundingBox;
    final w = imageWidth > 0 ? imageWidth : 1.0;
    final h = imageHeight > 0 ? imageHeight : 1.0;

    final normBox = Rect.fromLTRB(
      (box.left / w).clamp(0.0, 1.0),
      (box.top / h).clamp(0.0, 1.0),
      (box.right / w).clamp(0.0, 1.0),
      (box.bottom / h).clamp(0.0, 1.0),
    );

    final midY = (normBox.top + normBox.bottom) / 2.0;
    final midX = (normBox.left + normBox.right) / 2.0;

    String reg = 'middle';
    if (midY < 0.33) {
      reg = 'top';
    } else if (midY > 0.66) {
      reg = 'bottom';
    }

    if (midX < 0.35) {
      reg = '$reg-left';
    } else if (midX > 0.65) {
      reg = '$reg-right';
    }

    return OcrObservation(
      id: '${engine.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_${meta.lineIndex}',
      text: meta.text,
      boundingBox: box,
      normalizedBoundingBox: normBox,
      confidence: meta.confidence ?? 0.90,
      engine: engine,
      lineIndex: meta.lineIndex,
      region: reg,
    );
  }

  /// Converts this observation back into strongly typed [OcrLineMetadata].
  OcrLineMetadata toLineMetadata(CardSide side) {
    return OcrLineMetadata(
      text: text,
      side: side,
      lineIndex: lineIndex,
      blockIndex: 0,
      boundingBox: boundingBox,
      confidence: confidence,
    );
  }

  /// PII-safe representation omitting extracted text strings.
  Map<String, dynamic> toSafeDiagnosticJson() => {
        'id': id,
        'engine': engine,
        'lineIndex': lineIndex,
        'region': region,
        'confidence': double.parse(confidence.toStringAsFixed(2)),
        'normalizedBox': {
          'l': double.parse(normalizedBoundingBox.left.toStringAsFixed(3)),
          't': double.parse(normalizedBoundingBox.top.toStringAsFixed(3)),
          'w': double.parse(normalizedBoundingBox.width.toStringAsFixed(3)),
          'h': double.parse(normalizedBoundingBox.height.toStringAsFixed(3)),
        },
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'engine': engine,
        'lineIndex': lineIndex,
        'region': region,
        'confidence': double.parse(confidence.toStringAsFixed(2)),
        'boundingBox': {
          'left': boundingBox.left,
          'top': boundingBox.top,
          'width': boundingBox.width,
          'height': boundingBox.height,
        },
        'normalizedBoundingBox': {
          'left': normalizedBoundingBox.left,
          'top': normalizedBoundingBox.top,
          'width': normalizedBoundingBox.width,
          'height': normalizedBoundingBox.height,
        },
        if (elements.isNotEmpty)
          'elements': elements.map((e) => e.toJson()).toList(),
      };

  factory OcrObservation.fromJson(Map<String, dynamic> json) {
    final boxMap = json['boundingBox'] as Map<String, dynamic>?;
    final normMap = json['normalizedBoundingBox'] as Map<String, dynamic>?;
    return OcrObservation(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      engine: json['engine'] as String? ?? '',
      lineIndex: json['lineIndex'] as int? ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      region: json['region'] as String?,
      boundingBox: boxMap != null
          ? Rect.fromLTWH(
              (boxMap['left'] as num?)?.toDouble() ?? 0.0,
              (boxMap['top'] as num?)?.toDouble() ?? 0.0,
              (boxMap['width'] as num?)?.toDouble() ?? 0.0,
              (boxMap['height'] as num?)?.toDouble() ?? 0.0,
            )
          : Rect.zero,
      normalizedBoundingBox: normMap != null
          ? Rect.fromLTWH(
              (normMap['left'] as num?)?.toDouble() ?? 0.0,
              (normMap['top'] as num?)?.toDouble() ?? 0.0,
              (normMap['width'] as num?)?.toDouble() ?? 0.0,
              (normMap['height'] as num?)?.toDouble() ?? 0.0,
            )
          : Rect.zero,
    );
  }

  @override
  String toString() =>
      'OcrObservation($id, "$text", engine: $engine, conf: ${(confidence * 100).toStringAsFixed(0)}%, region: $region)';
}
