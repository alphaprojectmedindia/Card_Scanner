import 'dart:io';
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'ocr_engine.dart';
import 'ocr_observation.dart';

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
      // Decode source image dimensions to normalize coordinates accurately
      double imageWidth = 1000.0;
      double imageHeight = 1000.0;
      try {
        final bytes = await file.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded != null && decoded.width > 0 && decoded.height > 0) {
          imageWidth = decoded.width.toDouble();
          imageHeight = decoded.height.toDouble();
        }
      } catch (_) {
        // Safe fallback maintains execution on unusual formats
      }

      textRecognizer = TextRecognizer(script: script);
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);

      stopwatch.stop();

      final lines = <String>[];
      final observations = <OcrObservation>[];

      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final trimmed = line.text.trim();
          if (trimmed.isNotEmpty) {
            lines.add(trimmed);
            final box = line.boundingBox;

            final normBox = Rect.fromLTRB(
              (box.left / imageWidth).clamp(0.0, 1.0),
              (box.top / imageHeight).clamp(0.0, 1.0),
              (box.right / imageWidth).clamp(0.0, 1.0),
              (box.bottom / imageHeight).clamp(0.0, 1.0),
            );

            final midYNorm = (normBox.top + normBox.bottom) / 2.0;
            final midXNorm = (normBox.left + normBox.right) / 2.0;
            String reg = 'middle';
            if (midYNorm < 0.33) {
              reg = 'top';
            } else if (midYNorm > 0.67) {
              reg = 'bottom';
            }
            if (midXNorm < 0.33) {
              reg = '$reg-left';
            } else if (midXNorm > 0.67) {
              reg = '$reg-right';
            }

            // Extract word-level elements and bounding boxes where supported
            final wordElements = <OcrObservation>[];
            for (int eIdx = 0; eIdx < line.elements.length; eIdx++) {
              final elem = line.elements[eIdx];
              final elemText = elem.text.trim();
              if (elemText.isEmpty) continue;
              final elemBox = elem.boundingBox;
              final elemNormBox = Rect.fromLTRB(
                (elemBox.left / imageWidth).clamp(0.0, 1.0),
                (elemBox.top / imageHeight).clamp(0.0, 1.0),
                (elemBox.right / imageWidth).clamp(0.0, 1.0),
                (elemBox.bottom / imageHeight).clamp(0.0, 1.0),
              );
              wordElements.add(OcrObservation(
                id: 'mlkit_${observations.length}_word_$eIdx',
                text: elemText,
                boundingBox: elemBox,
                normalizedBoundingBox: elemNormBox,
                confidence: elem.confidence ?? line.confidence ?? 0.90,
                engine: name,
                lineIndex: observations.length,
                region: reg,
              ));
            }

            observations.add(OcrObservation(
              id: 'mlkit_${observations.length}',
              text: trimmed,
              boundingBox: box,
              normalizedBoundingBox: normBox,
              confidence: line.confidence ?? 0.90,
              engine: name,
              lineIndex: observations.length,
              region: reg,
              elements: wordElements,
            ));
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
        observations: observations,
        metadata: {
          'script': script.name,
          'blockCount': recognizedText.blocks.length,
          'observationsCount': observations.length,
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
