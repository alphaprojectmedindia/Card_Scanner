# ML Kit Text Recognition: Suppress warnings for optional language scripts
# Digital Share only uses Latin script (TextRecognitionScript.latin).
# The other language modules (Chinese, Devanagari, Japanese, Korean) are compileOnly
# in google_mlkit_text_recognition and not included at runtime.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# ONNX Runtime (PaddleOCR PP-OCRv5 Mobile Benchmark)
-keep class ai.onnxruntime.** { *; }
