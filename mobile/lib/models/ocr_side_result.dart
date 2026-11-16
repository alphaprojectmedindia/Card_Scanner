import 'dart:ui';
import 'recovered_ocr_observation.dart';

/// Represents the physical side of a business card.
enum CardSide {
  front,
  back,
  both,
}

/// A 2D point representing coordinates within an OCR image.
class OcrPoint {
  final int x;
  final int y;

  const OcrPoint(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory OcrPoint.fromJson(Map<String, dynamic> json) =>
      OcrPoint(json['x'] as int, json['y'] as int);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OcrPoint &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'OcrPoint($x, $y)';
}

/// Metadata for a single recognized text element (word/token).
class OcrElementMetadata {
  final String text;
  final Rect boundingBox;
  final List<OcrPoint> cornerPoints;
  final double? confidence;
  final List<String> recognizedLanguages;

  const OcrElementMetadata({
    required this.text,
    required this.boundingBox,
    this.cornerPoints = const [],
    this.confidence,
    this.recognizedLanguages = const [],
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'boundingBox': {
          'left': boundingBox.left,
          'top': boundingBox.top,
          'width': boundingBox.width,
          'height': boundingBox.height,
        },
        'cornerPoints': cornerPoints.map((p) => p.toJson()).toList(),
        if (confidence != null) 'confidence': confidence,
        'recognizedLanguages': recognizedLanguages,
      };
}

/// Metadata for a single recognized line of text.
class OcrLineMetadata {
  final String text;
  final CardSide side;
  final int lineIndex;
  final int blockIndex;
  final Rect boundingBox;
  final List<OcrPoint> cornerPoints;
  final double? confidence;
  final List<String> recognizedLanguages;
  final List<OcrElementMetadata> elements;

  const OcrLineMetadata({
    required this.text,
    required this.side,
    required this.lineIndex,
    required this.blockIndex,
    required this.boundingBox,
    this.cornerPoints = const [],
    this.confidence,
    this.recognizedLanguages = const [],
    this.elements = const [],
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'side': side.name,
        'lineIndex': lineIndex,
        'blockIndex': blockIndex,
        'boundingBox': {
          'left': boundingBox.left,
          'top': boundingBox.top,
          'width': boundingBox.width,
          'height': boundingBox.height,
        },
        'cornerPoints': cornerPoints.map((p) => p.toJson()).toList(),
        if (confidence != null) 'confidence': confidence,
        'recognizedLanguages': recognizedLanguages,
        'elements': elements.map((e) => e.toJson()).toList(),
      };
}

/// Metadata for a grouped block of text lines.
class OcrBlockMetadata {
  final String text;
  final CardSide side;
  final int blockIndex;
  final Rect boundingBox;
  final List<OcrPoint> cornerPoints;
  final List<String> recognizedLanguages;
  final List<OcrLineMetadata> lines;

  const OcrBlockMetadata({
    required this.text,
    required this.side,
    required this.blockIndex,
    required this.boundingBox,
    this.cornerPoints = const [],
    this.recognizedLanguages = const [],
    this.lines = const [],
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'side': side.name,
        'blockIndex': blockIndex,
        'boundingBox': {
          'left': boundingBox.left,
          'top': boundingBox.top,
          'width': boundingBox.width,
          'height': boundingBox.height,
        },
        'cornerPoints': cornerPoints.map((p) => p.toJson()).toList(),
        'recognizedLanguages': recognizedLanguages,
        'lines': lines.map((l) => l.toJson()).toList(),
      };
}

/// Strongly typed result of on-device OCR for one side of a business card.
class OcrSideResult {
  final CardSide side;
  final String imagePath;
  final String rawText;
  final List<OcrBlockMetadata> blocks;
  final List<OcrLineMetadata> lines;
  final DateTime processedAt;
  final Map<String, dynamic> metadata;
  final List<RecoveredOcrObservation> recoveredObservations;

  OcrSideResult({
    required this.side,
    required this.imagePath,
    required this.rawText,
    this.blocks = const [],
    List<OcrLineMetadata> lines = const [],
    DateTime? processedAt,
    this.metadata = const {},
    this.recoveredObservations = const [],
  })  : lines = lines.isNotEmpty
            ? lines
            : blocks.expand((b) => b.lines).toList(),
        processedAt = processedAt ?? DateTime.now().toUtc();

  bool get isEmpty => rawText.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;
  bool get fallbackInvoked => metadata['fallbackInvoked'] == true;
  String get engineName => (metadata['selectedEngine'] as String?) ?? '';

  OcrSideResult copyWith({
    CardSide? side,
    String? imagePath,
    String? rawText,
    List<OcrBlockMetadata>? blocks,
    List<OcrLineMetadata>? lines,
    DateTime? processedAt,
    Map<String, dynamic>? metadata,
    List<RecoveredOcrObservation>? recoveredObservations,
  }) {
    return OcrSideResult(
      side: side ?? this.side,
      imagePath: imagePath ?? this.imagePath,
      rawText: rawText ?? this.rawText,
      blocks: blocks ?? this.blocks,
      lines: lines ?? this.lines,
      processedAt: processedAt ?? this.processedAt,
      metadata: metadata ?? this.metadata,
      recoveredObservations:
          recoveredObservations ?? this.recoveredObservations,
    );
  }

  /// Serialized OCR observation dictionaries preserving text, coordinates and confidence.
  List<Map<String, dynamic>> get observations {
    if (lines.isEmpty) return const [];
    return lines.asMap().entries.map((entry) {
      final idx = entry.key;
      final l = entry.value;
      return {
        'id': '${side.name}_$idx',
        'text': l.text,
        'confidence': l.confidence ?? 1.0,
        'side': side.name,
        'engine': engineName,
        'lineIndex': l.lineIndex,
        'boundingBox': {
          'left': l.boundingBox.left,
          'top': l.boundingBox.top,
          'width': l.boundingBox.width,
          'height': l.boundingBox.height,
        },
      };
    }).toList();
  }

  factory OcrSideResult.empty(CardSide side, {String imagePath = ''}) {
    return OcrSideResult(
      side: side,
      imagePath: imagePath,
      rawText: '',
      blocks: const [],
      lines: const [],
      processedAt: DateTime.now().toUtc(),
      metadata: const {},
    );
  }

  /// Convenience constructor building a normalized side result from plain text.
  factory OcrSideResult.fromText({
    required CardSide side,
    required String imagePath,
    required String rawText,
    Map<String, dynamic> metadata = const {},
  }) {
    final rawLines = rawText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final lineMetas = <OcrLineMetadata>[];
    for (int i = 0; i < rawLines.length; i++) {
      lineMetas.add(OcrLineMetadata(
        text: rawLines[i],
        side: side,
        lineIndex: i,
        blockIndex: 0,
        boundingBox: Rect.zero,
      ));
    }

    return OcrSideResult(
      side: side,
      imagePath: imagePath,
      rawText: rawText,
      blocks: [
        OcrBlockMetadata(
          text: rawText,
          side: side,
          blockIndex: 0,
          boundingBox: Rect.zero,
          lines: lineMetas,
        ),
      ],
      lines: lineMetas,
      processedAt: DateTime.now().toUtc(),
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'side': side.name,
        'imagePath': imagePath,
        'rawText': rawText,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'lines': lines.map((l) => l.toJson()).toList(),
        'processedAt': processedAt.toIso8601String(),
        if (metadata.isNotEmpty) 'metadata': metadata,
        if (recoveredObservations.isNotEmpty)
          'recoveredObservations':
              recoveredObservations.map((r) => r.toJson()).toList(),
      };
}

/// Strongly typed encapsulation of front and optional back OCR side results.
class DualSidedOcrResult {
  final OcrSideResult front;
  final OcrSideResult? back;

  const DualSidedOcrResult({
    required this.front,
    this.back,
  });

  bool get isDualSided => back != null && back!.isNotEmpty;
}
