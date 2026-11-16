import 'ocr_observation.dart';

/// Unified result model representing output from any OCR engine.
class OcrEngineResult {
  /// Identifying name of the OCR engine (e.g., 'Google ML Kit', 'PaddleOCR (PP-OCRv5 Mobile)').
  final String engineName;

  /// Complete raw recognized text output.
  final String rawText;

  /// Total count of recognized text lines.
  final int lineCount;

  /// Total count of recognized characters (excluding newline formatting if desired).
  final int characterCount;

  /// Total end-to-end processing latency.
  final Duration processingTime;

  /// Error message if recognition failed or engine was unavailable.
  final String? error;

  /// Indicates whether the engine completed recognition successfully.
  final bool isSuccess;

  /// Ordered individual lines recognized by the engine.
  final List<String> detectedLines;

  /// Structured geometry and confidence observations for each recognized line/token.
  final List<OcrObservation> observations;

  /// Optional engine-specific diagnostic metadata (e.g. model version, detection box count).
  final Map<String, dynamic> metadata;

  const OcrEngineResult({
    required this.engineName,
    this.rawText = '',
    this.lineCount = 0,
    this.characterCount = 0,
    required this.processingTime,
    this.error,
    this.isSuccess = true,
    this.detectedLines = const [],
    this.observations = const [],
    this.metadata = const {},
  });

  /// Factory helper for creating an error or unavailable result safely.
  factory OcrEngineResult.failure({
    required String engineName,
    required String error,
    Duration processingTime = Duration.zero,
    Map<String, dynamic> metadata = const {},
  }) {
    return OcrEngineResult(
      engineName: engineName,
      rawText: '',
      lineCount: 0,
      characterCount: 0,
      processingTime: processingTime,
      error: error,
      isSuccess: false,
      detectedLines: const [],
      observations: const [],
      metadata: metadata,
    );
  }

  /// Helper to calculate character count reliably.
  static int countCharacters(String text) {
    return text.replaceAll(RegExp(r'\r\n|\r|\n'), '').length;
  }
}

/// Abstract contract for OCR engines.
/// Enables clean side-by-side benchmarking and testing without coupling
/// or destabilizing existing production scanner implementations.
abstract class OcrEngine {
  /// Human-readable display name of the engine.
  String get name;

  /// Performs raw text recognition on the given image path on-device.
  /// Must return an [OcrEngineResult] and must never throw an uncaught exception.
  Future<OcrEngineResult> recognize(String imagePath);

  /// Disposes any open sessions, runtime tensors, or native memory resources.
  Future<void> dispose();
}
