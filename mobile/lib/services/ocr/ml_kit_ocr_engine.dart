import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'ocr_engine.dart';

/// Google ML Kit OCR engine implementation.
/// Wraps on-device Google ML Kit Text Recognition behind the [OcrEngine] abstraction.
class MlKitOcrEngine implements OcrEngine {
  final TextRecognitionScript script;

  const MlKitOcrEngine({
    this.script = TextRecognitionScript.latin,
  });

  @override
  String get name => 'Google ML Kit';

  @override
  Future<OcrEngineResult> recognize(String imagePath) async {
    final stopwatch = Stopwatch()..start();

    // 1. Validate file existence
    final file = File(imagePath);
    if (!file.existsSync()) {
      stopwatch.stop();
      return OcrEngineResult.failure(
        engineName: name,
        error: 'Image file does not exist at path: $imagePath',
        processingTime: stopwatch.elapsed,
      );
    }

    TextRecognizer? textRecognizer;
    try {
      textRecognizer = TextRecognizer(script: script);
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);

      stopwatch.stop();

      final lines = <String>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final trimmed = line.text.trim();
          if (trimmed.isNotEmpty) {
            lines.add(trimmed);
          }
        }
      }

      final rawText = recognizedText.text.trim();
      final charCount = OcrEngineResult.countCharacters(rawText);

      return OcrEngineResult(
        engineName: name,
        rawText: rawText,
        lineCount: lines.length,
        characterCount: charCount,
        processingTime: stopwatch.elapsed,
        isSuccess: true,
        detectedLines: lines,
        metadata: {
          'script': script.name,
          'blockCount': recognizedText.blocks.length,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return OcrEngineResult.failure(
        engineName: name,
        error: 'Google ML Kit error: $e',
        processingTime: stopwatch.elapsed,
      );
    } finally {
      try {
        await textRecognizer?.close();
      } catch (_) {}
    }
  }

  @override
  Future<void> dispose() async {
    // Ephemeral instances close per recognize call.
  }
}
