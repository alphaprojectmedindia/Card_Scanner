import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

abstract class IBusinessCardOcrService {
  Future<String> recognizeTextFromPath(String imagePath);
}

/// On-device OCR service utilizing Google ML Kit Text Recognition.
/// Runs 100% locally on the device without uploading image data to any backend.
class BusinessCardOcrService implements IBusinessCardOcrService {
  final TextRecognitionScript script;

  const BusinessCardOcrService({this.script = TextRecognitionScript.latin});

  @override
  Future<String> recognizeTextFromPath(String imagePath) async {
    final textRecognizer = TextRecognizer(script: script);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);
      return recognizedText.text;
    } finally {
      await textRecognizer.close();
    }
  }
}
