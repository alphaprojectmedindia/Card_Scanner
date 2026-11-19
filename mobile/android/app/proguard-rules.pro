# ML Kit Text Recognition: Suppress warnings for optional language scripts
# Digital Share only uses Latin script (TextRecognitionScript.latin).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Flutter Deferred Components & Google Play Core optional dependencies
-dontwarn com.google.android.play.core.**

# Flutter framework & plugins core rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google ML Kit Text Recognition & Vision Core
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google.android.gms.tasks.** { *; }

# Barcode Scanning (Mobile Scanner / Barhopper)
-keep class com.google.mlkit.vision.barcode.** { *; }
-keep class dev.steenbakker.mobile_scanner.** { *; }

# ONNX Runtime (PaddleOCR PP-OCRv5 Mobile Benchmark)
-keep class ai.onnxruntime.** { *; }
-keep class ai.onnxruntime.internal.** { *; }

# Camera Plugin & AndroidX Camera
-keep class io.flutter.plugins.camera.** { *; }
-keep class androidx.camera.** { *; }

# Image Picker & Contacts
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class co.quis.flutter_contacts.** { *; }

# Flutter Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Geolocator
-keep class com.baseflow.geolocator.** { *; }

# URL Launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Preserve critical runtime reflection & serialization attributes
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes SourceFile,LineNumberTable
