import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'ocr_engine.dart';
import 'ocr_observation.dart';

/// Decoded CTC recognition text and average character confidence score.
class DecodedCtcResult {
  final String text;
  final double confidence;

  const DecodedCtcResult({
    required this.text,
    required this.confidence,
  });
}

/// Representation of a detected text line bounding box in pixel coordinates.
class PaddleTextBox {
  final int minX;
  final int minY;
  final int maxX;
  final int maxY;
  final double score;

  const PaddleTextBox({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.score,
  });

  int get width => maxX - minX + 1;
  int get height => maxY - minY + 1;
  double get centerY => (minY + maxY) / 2.0;
  double get centerX => (minX + maxX) / 2.0;
}

/// Production-ready on-device PaddleOCR PP-OCRv5 mobile engine.
///
/// Features:
/// - Official PaddleOCR PP-OCRv5 Mobile ONNX models:
///   * Detection: PP-OCRv5_mobile_det_infer.onnx (~4.6 MB)
///   * Recognition: PP-OCRv5_mobile_rec_infer.onnx (~15.7 MB)
///   * Character dictionary: ppocrv5_dict.txt (~74 KB, 18,384 characters)
/// - Pure on-device processing via ONNX Runtime native mobile libraries.
/// - Memory-safe execution:
///   * Sequential pipeline with aggressive native tensor disposal.
///   * High-resolution crop preservation (crops from original up to 2160px; detection input at 960px).
///   * Aspect-ratio preserving width scaling up to 1600px for text line crops (prevents long email truncation).
///   * Native thread pooling (intraOpNumThreads = 2) for smooth UI.
///   * Bounded execution with a 25-second safety timeout.
///   * Fail-soft exception handling returning [OcrEngineResult.failure] without crashing.
class PaddleOcrEngine implements OcrEngine {
  static const String _detAssetPath =
      'assets/models/paddleocr/PP-OCRv5_mobile_det_infer.onnx';
  static const String _recAssetPath =
      'assets/models/paddleocr/PP-OCRv5_mobile_rec_infer.onnx';
  static const String _dictAssetPath =
      'assets/models/paddleocr/ppocrv5_dict.txt';

  static const int _vocabularySize = 18385;
  static const int _spaceTokenIndex = 18384;
  static const int _maxImageDimension = 2160;
  static const int _maxDetDimension = 960;
  static const int _recFixedCropHeight = 48;
  static const double _dbNetThreshold = 0.25;
  static const double _dbNetMinBoxScore = 0.40;

  final OnnxRuntime _onnxRuntime;
  OrtSession? _detSession;
  OrtSession? _recSession;
  List<String>? _dictionary;
  bool _isInitializing = false;

  PaddleOcrEngine({
    OnnxRuntime? onnxRuntime,
  }) : _onnxRuntime = onnxRuntime ?? OnnxRuntime();

  @override
  String get name => 'PaddleOCR (PP-OCRv5 Mobile)';

  /// Asynchronously pre-warms the detection and recognition ONNX sessions
  /// and dictionary ahead of time to eliminate cold-start latency on first scan.
  Future<void> prewarm() async {
    try {
      await initialize();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PaddleOCR] Pre-warming non-fatal notice: ');
      }
    }
  }

  /// Pre-loads models and dictionary into memory.
  /// Safe to call ahead of time or lazily on first recognition.
  Future<void> initialize() async {
    if (_detSession != null && _recSession != null && _dictionary != null) {
      return;
    }

    if (_isInitializing) {
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }

    _isInitializing = true;
    try {
      // 1. Load dictionary asset
      if (_dictionary == null) {
        final dictContent = await rootBundle.loadString(_dictAssetPath);
        final lines = dictContent.split(RegExp(r'\r\n|\r|\n'));
        // Standardize lines: ensure list has exact 18384 elements
        _dictionary = lines;
      }

      // 2. Initialize ONNX Runtime detection session
      _detSession ??= await _onnxRuntime.createSessionFromAsset(
        _detAssetPath,
        options: OrtSessionOptions(
          intraOpNumThreads: 2,
          useArena: true,
        ),
      );

      // 3. Initialize ONNX Runtime recognition session
      _recSession ??= await _onnxRuntime.createSessionFromAsset(
        _recAssetPath,
        options: OrtSessionOptions(
          intraOpNumThreads: 2,
          useArena: true,
        ),
      );
    } finally {
      _isInitializing = false;
    }
  }

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

    try {
      // Bounded execution with safety timeout
      return await _recognizeInternal(file, stopwatch).timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          stopwatch.stop();
          return OcrEngineResult.failure(
            engineName: name,
            error: 'PaddleOCR inference timed out after 25 seconds',
            processingTime: stopwatch.elapsed,
          );
        },
      );
    } catch (e, stack) {
      stopwatch.stop();
      if (kDebugMode) {
        debugPrint('PaddleOcrEngine exception: $e\n$stack');
      }
      return OcrEngineResult.failure(
        engineName: name,
        error: 'PaddleOCR engine error: $e',
        processingTime: stopwatch.elapsed,
      );
    }
  }

  Future<OcrEngineResult> _recognizeInternal(
    File file,
    Stopwatch stopwatch,
  ) async {
    // 2. Ensure models and dictionary are loaded
    await initialize();

    final dict = _dictionary;
    final detSession = _detSession;
    final recSession = _recSession;

    if (dict == null || detSession == null || recSession == null) {
      stopwatch.stop();
      return OcrEngineResult.failure(
        engineName: name,
        error: 'PaddleOCR models could not be loaded into memory',
        processingTime: stopwatch.elapsed,
      );
    }

    // 3. Decode image from file
    final bytes = await file.readAsBytes();
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) {
      stopwatch.stop();
      return OcrEngineResult.failure(
        engineName: name,
        error: 'Failed to decode image pixels from file',
        processingTime: stopwatch.elapsed,
      );
    }

    // Ensure pixels are physically upright according to EXIF metadata
    final uprightImage = img.bakeOrientation(decodedImage);

    // 4. Downscale image if larger than max dimension (2160px) to prevent OOM
    final originalImage = _normalizeAndDownscale(uprightImage);
    final enhancedImage = _enhanceContrastIfLow(originalImage);

    // 5. Prepare detection input (aspect-ratio preserved, multiple of 32, max dimension 960)
    final detDimensions = _computeDetDimensions(
      enhancedImage.width,
      enhancedImage.height,
    );
    final detWidth = detDimensions.width;
    final detHeight = detDimensions.height;

    final detResized = img.copyResize(
      enhancedImage,
      width: detWidth,
      height: detHeight,
      interpolation: img.Interpolation.linear,
    );

    // 6. DBNet input normalization (mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    final detTensorData = Float32List(1 * 3 * detHeight * detWidth);
    const meanR = 0.485, meanG = 0.456, meanB = 0.406;
    const stdR = 0.229, stdG = 0.224, stdB = 0.225;
    final channelStride = detHeight * detWidth;

    for (int y = 0; y < detHeight; y++) {
      for (int x = 0; x < detWidth; x++) {
        final pixel = detResized.getPixel(x, y);
        final r = (pixel.r / 255.0 - meanR) / stdR;
        final g = (pixel.g / 255.0 - meanG) / stdG;
        final b = (pixel.b / 255.0 - meanB) / stdB;

        final offset = y * detWidth + x;
        detTensorData[0 * channelStride + offset] = r;
        detTensorData[1 * channelStride + offset] = g;
        detTensorData[2 * channelStride + offset] = b;
      }
    }

    // 7. Run DBNet detection model
    OrtValue? detInput;
    Map<String, OrtValue>? detOutputs;
    List<dynamic>? flatProbMap;

    try {
      detInput = await OrtValue.fromList(
        detTensorData,
        [1, 3, detHeight, detWidth],
      );
      detOutputs = await detSession.run({'x': detInput});
      final outputTensor = detOutputs.values.first;
      flatProbMap = await outputTensor.asFlattenedList();
    } finally {
      await detInput?.dispose();
      if (detOutputs != null) {
        for (final t in detOutputs.values) {
          await t.dispose();
        }
      }
    }

    if (flatProbMap.isEmpty) {
      stopwatch.stop();
      return OcrEngineResult.failure(
        engineName: name,
        error: 'Detection model returned empty probability map',
        processingTime: stopwatch.elapsed,
      );
    }

    // 8. Extract text bounding boxes using connected components
    final detectedBoxes = _extractBoundingBoxes(
      probMap: flatProbMap,
      detWidth: detWidth,
      detHeight: detHeight,
      origWidth: enhancedImage.width,
      origHeight: enhancedImage.height,
    );

    // 9. If no boxes detected, fallback to strip scanning to avoid silent drops
    final boxesToProcess = detectedBoxes.isNotEmpty
        ? detectedBoxes
        : _generateFallbackBoxes(enhancedImage.width, enhancedImage.height);

    // 10. Sort boxes in natural reading order with column-awareness
    final sortedBoxes = _sortBoxesReadingOrder(boxesToProcess);

    // 11. Run recognition on each box crop sequentially
    final recognizedLines = <String>[];
    final observations = <OcrObservation>[];

    for (final box in sortedBoxes) {
      final cropW = box.width;
      final cropH = box.height;
      if (cropW < 4 || cropH < 4) continue;

      // Crop directly from high-resolution enhanced image to preserve character glyphs
      final crop = img.copyCrop(
        enhancedImage,
        x: box.minX,
        y: box.minY,
        width: cropW,
        height: cropH,
      );

      // Scale to fixed height 48 for PP-OCRv5 mobile rec (allow up to 1600px width for long emails/URLs)
      final recWidth = (48 * cropW / cropH).round().clamp(32, 1600);
      final recResized = img.copyResize(
        crop,
        width: recWidth,
        height: _recFixedCropHeight,
        interpolation: img.Interpolation.linear,
      );

      // Rec normalization: (pixel / 255.0 - 0.5) / 0.5
      final recData = Float32List(1 * 3 * _recFixedCropHeight * recWidth);
      final recChannelStride = _recFixedCropHeight * recWidth;

      for (int y = 0; y < _recFixedCropHeight; y++) {
        for (int x = 0; x < recWidth; x++) {
          final pixel = recResized.getPixel(x, y);
          final r = (pixel.r / 255.0 - 0.5) / 0.5;
          final g = (pixel.g / 255.0 - 0.5) / 0.5;
          final b = (pixel.b / 255.0 - 0.5) / 0.5;

          final offset = y * recWidth + x;
          recData[0 * recChannelStride + offset] = r;
          recData[1 * recChannelStride + offset] = g;
          recData[2 * recChannelStride + offset] = b;
        }
      }

      OrtValue? recInput;
      Map<String, OrtValue>? recOutputs;

      try {
        recInput = await OrtValue.fromList(
          recData,
          [1, 3, _recFixedCropHeight, recWidth],
        );
        recOutputs = await recSession.run({'x': recInput});
        final recOutputTensor = recOutputs.values.first;
        final flatLogits = await recOutputTensor.asFlattenedList();

        final decoded = _decodeCtcLogits(flatLogits, dict);
        final trimmed = decoded.text.trim();
        if (trimmed.isNotEmpty) {
          recognizedLines.add(trimmed);

          final normBox = Rect.fromLTRB(
            (box.minX / enhancedImage.width).clamp(0.0, 1.0),
            (box.minY / enhancedImage.height).clamp(0.0, 1.0),
            (box.maxX / enhancedImage.width).clamp(0.0, 1.0),
            (box.maxY / enhancedImage.height).clamp(0.0, 1.0),
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

          observations.add(OcrObservation(
            id: 'paddle_${observations.length}',
            text: trimmed,
            boundingBox: Rect.fromLTRB(
              box.minX.toDouble(),
              box.minY.toDouble(),
              box.maxX.toDouble(),
              box.maxY.toDouble(),
            ),
            normalizedBoundingBox: normBox,
            confidence: decoded.confidence,
            engine: name,
            lineIndex: observations.length,
            region: reg,
          ));
        }
      } finally {
        await recInput?.dispose();
        if (recOutputs != null) {
          for (final t in recOutputs.values) {
            await t.dispose();
          }
        }
      }
    }

    stopwatch.stop();

    final rawText = recognizedLines.join('\n');
    final charCount = OcrEngineResult.countCharacters(rawText);

    return OcrEngineResult(
      engineName: name,
      rawText: rawText,
      lineCount: recognizedLines.length,
      characterCount: charCount,
      processingTime: stopwatch.elapsed,
      isSuccess: true,
      detectedLines: recognizedLines,
      observations: observations,
      metadata: {
        'detDimensions': '${detWidth}x$detHeight',
        'detectedBoxesCount': detectedBoxes.length,
        'boxesProcessed': sortedBoxes.length,
        'observationsCount': observations.length,
        'imageWidth': enhancedImage.width,
        'imageHeight': enhancedImage.height,
      },
    );
  }

  /// Normalizes and downscales input images to prevent mobile memory pressure.
  img.Image _normalizeAndDownscale(img.Image input) {
    if (input.width <= _maxImageDimension &&
        input.height <= _maxImageDimension) {
      return input;
    }

    final scale = min(
      _maxImageDimension / input.width,
      _maxImageDimension / input.height,
    );

    final targetW = (input.width * scale).round();
    final targetH = (input.height * scale).round();

    return img.copyResize(
      input,
      width: targetW,
      height: targetH,
      interpolation: img.Interpolation.linear,
    );
  }

  /// Controlled contrast enhancement for low-contrast / metallic / gradient business cards.
  /// Preserves continuous tone strokes and cursive lines without destructive binarization.
  img.Image _enhanceContrastIfLow(img.Image image) {
    num minLum = 255;
    num maxLum = 0;

    for (int y = 0; y < image.height; y += 4) {
      for (int x = 0; x < image.width; x += 4) {
        final p = image.getPixel(x, y);
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        if (lum < minLum) minLum = lum;
        if (lum > maxLum) maxLum = lum;
      }
    }

    final range = maxLum - minLum;
    // If dynamic range is compressed (< 85), gently stretch contrast linearly
    if (range < 85 && range > 10) {
      final enhanced = img.Image.from(image);
      final scale = 255.0 / range;
      for (final p in enhanced) {
        p.r = ((p.r - minLum) * scale).clamp(0, 255).round();
        p.g = ((p.g - minLum) * scale).clamp(0, 255).round();
        p.b = ((p.b - minLum) * scale).clamp(0, 255).round();
      }
      return enhanced;
    }
    return image;
  }

  /// Calculates DBNet input dimensions ensuring they are multiples of 32.
  ({int width, int height}) _computeDetDimensions(int origW, int origH) {
    double scale = 1.0;
    final maxDim = max(origW, origH);
    if (maxDim > _maxDetDimension) {
      scale = _maxDetDimension / maxDim;
    }

    int targetW = (origW * scale).round();
    int targetH = (origH * scale).round();

    // Clamp and align to multiple of 32
    targetW = max(32, (targetW ~/ 32) * 32);
    targetH = max(32, (targetH ~/ 32) * 32);

    return (width: targetW, height: targetH);
  }

  /// Extracts text boxes from the 2D probability map using iterative BFS flood-fill.
  List<PaddleTextBox> _extractBoundingBoxes({
    required List<dynamic> probMap,
    required int detWidth,
    required int detHeight,
    required int origWidth,
    required int origHeight,
  }) {
    final boxes = <PaddleTextBox>[];
    final totalPixels = detWidth * detHeight;
    final visited = Uint8List(totalPixels);
    final queue = Int32List(totalPixels);

    final scaleX = origWidth / detWidth;
    final scaleY = origHeight / detHeight;

    for (int y = 0; y < detHeight; y++) {
      for (int x = 0; x < detWidth; x++) {
        final idx = y * detWidth + x;
        if (visited[idx] == 1) continue;

        final prob = (probMap[idx] as num).toDouble();
        if (prob < _dbNetThreshold) continue;

        // Start connected component BFS
        int head = 0;
        int tail = 0;
        queue[tail++] = idx;
        visited[idx] = 1;

        int bMinX = x, bMaxX = x;
        int bMinY = y, bMaxY = y;
        double sumScore = 0.0;
        int pixelCount = 0;

        while (head < tail) {
          final curr = queue[head++];
          final cy = curr ~/ detWidth;
          final cx = curr % detWidth;
          final currentProb = (probMap[curr] as num).toDouble();

          sumScore += currentProb;
          pixelCount++;

          if (cx < bMinX) bMinX = cx;
          if (cx > bMaxX) bMaxX = cx;
          if (cy < bMinY) bMinY = cy;
          if (cy > bMaxY) bMaxY = cy;

          // 4-connected neighbors
          // Left
          if (cx > 0) {
            final nIdx = curr - 1;
            if (visited[nIdx] == 0 &&
                (probMap[nIdx] as num).toDouble() >= _dbNetThreshold) {
              visited[nIdx] = 1;
              queue[tail++] = nIdx;
            }
          }
          // Right
          if (cx < detWidth - 1) {
            final nIdx = curr + 1;
            if (visited[nIdx] == 0 &&
                (probMap[nIdx] as num).toDouble() >= _dbNetThreshold) {
              visited[nIdx] = 1;
              queue[tail++] = nIdx;
            }
          }
          // Up
          if (cy > 0) {
            final nIdx = curr - detWidth;
            if (visited[nIdx] == 0 &&
                (probMap[nIdx] as num).toDouble() >= _dbNetThreshold) {
              visited[nIdx] = 1;
              queue[tail++] = nIdx;
            }
          }
          // Down
          if (cy < detHeight - 1) {
            final nIdx = curr + detWidth;
            if (visited[nIdx] == 0 &&
                (probMap[nIdx] as num).toDouble() >= _dbNetThreshold) {
              visited[nIdx] = 1;
              queue[tail++] = nIdx;
            }
          }
        }

        // Noise filtering: tuned to preserve small phone/email text boxes
        final boxW = bMaxX - bMinX + 1;
        final boxH = bMaxY - bMinY + 1;
        if (pixelCount >= 10 && boxW >= 3 && boxH >= 3) {
          final avgScore = sumScore / pixelCount;
          if (avgScore >= _dbNetMinBoxScore) {
            // DBNet unclip expansion (25% horizontal, 35% vertical with minimum 3px padding to protect edge glyphs)
            final padW = max(3, (boxW * 0.25).round());
            final padH = max(3, (boxH * 0.35).round());

            final clampedMinX = max(0, bMinX - padW);
            final clampedMinY = max(0, bMinY - padH);
            final clampedMaxX = min(detWidth - 1, bMaxX + padW);
            final clampedMaxY = min(detHeight - 1, bMaxY + padH);

            // Scale to original coordinate space
            final origMinX = (clampedMinX * scaleX).round().clamp(0, origWidth - 1);
            final origMinY = (clampedMinY * scaleY).round().clamp(0, origHeight - 1);
            final origMaxX = (clampedMaxX * scaleX).round().clamp(0, origWidth - 1);
            final origMaxY = (clampedMaxY * scaleY).round().clamp(0, origHeight - 1);

            if (origMaxX > origMinX && origMaxY > origMinY) {
              boxes.add(PaddleTextBox(
                minX: origMinX,
                minY: origMinY,
                maxX: origMaxX,
                maxY: origMaxY,
                score: avgScore,
              ));
            }
          }
        }
      }
    }

    return boxes;
  }

  /// Generates horizontal strip fallback boxes if DBNet detects 0 components.
  List<PaddleTextBox> _generateFallbackBoxes(int imgWidth, int imgHeight) {
    const strips = 5;
    final stripH = imgHeight ~/ strips;
    final boxes = <PaddleTextBox>[];

    for (int i = 0; i < strips; i++) {
      boxes.add(PaddleTextBox(
        minX: (imgWidth * 0.05).round(),
        minY: i * stripH,
        maxX: (imgWidth * 0.95).round(),
        maxY: min(imgHeight - 1, (i + 1) * stripH),
        score: 0.5,
      ));
    }
    return boxes;
  }

  /// Visible for testing reading-order layout algorithms.
  @visibleForTesting
  List<PaddleTextBox> sortBoxesReadingOrderForTesting(List<PaddleTextBox> boxes) =>
      _sortBoxesReadingOrder(boxes);

  /// Sorts text boxes into natural reading order (top-to-bottom lines, left-to-right within line).
  /// Preserves column independence so two-column cards or left/right blocks are not merged into single lines.
  List<PaddleTextBox> _sortBoxesReadingOrder(List<PaddleTextBox> boxes) {
    if (boxes.length <= 1) return boxes;

    final minLeft = boxes.map((b) => b.minX).reduce(min);
    final maxRight = boxes.map((b) => b.maxX).reduce(max);
    final cardW = maxRight - minLeft;

    // Check if card has a distinct two-column layout
    if (cardW > 200 && boxes.length >= 4) {
      final midX = minLeft + cardW / 2.0;

      // Identify header and footer boxes that span broadly across columns
      final headerBoxes = <PaddleTextBox>[];
      final footerBoxes = <PaddleTextBox>[];
      final leftBoxes = <PaddleTextBox>[];
      final rightBoxes = <PaddleTextBox>[];

      // Find vertical overlap zone of candidate columns
      final nonSpanning = boxes.where((b) => b.width < cardW * 0.65).toList();
      final candLeft = nonSpanning.where((b) => b.centerX < midX).toList();
      final candRight = nonSpanning.where((b) => b.centerX >= midX).toList();

      if (candLeft.length >= 2 && candRight.length >= 2) {
        final leftMaxX = candLeft.map((b) => b.maxX).reduce(max);
        final rightMinX = candRight.map((b) => b.minX).reduce(min);

        // Clear horizontal separation between columns
        if (rightMinX >= leftMaxX - (cardW * 0.08)) {
          final leftMinY = candLeft.map((b) => b.minY).reduce(min);
          final leftMaxY = candLeft.map((b) => b.maxY).reduce(max);
          final rightMinY = candRight.map((b) => b.minY).reduce(min);
          final rightMaxY = candRight.map((b) => b.maxY).reduce(max);

          final colTop = min(leftMinY, rightMinY);
          final colBottom = max(leftMaxY, rightMaxY);

          for (final box in boxes) {
            final isSpanning = box.width >= cardW * 0.65;
            if (isSpanning && box.maxY <= colTop + (colBottom - colTop) * 0.25) {
              headerBoxes.add(box);
            } else if (isSpanning && box.minY >= colBottom - (colBottom - colTop) * 0.25) {
              footerBoxes.add(box);
            } else if (box.centerX < midX) {
              leftBoxes.add(box);
            } else {
              rightBoxes.add(box);
            }
          }

          // Combine: Header -> Left Column -> Right Column -> Footer
          final result = <PaddleTextBox>[];
          result.addAll(_sortBoxesInBlock(headerBoxes));
          result.addAll(_sortBoxesInBlock(leftBoxes));
          result.addAll(_sortBoxesInBlock(rightBoxes));
          result.addAll(_sortBoxesInBlock(footerBoxes));
          return result;
        }
      }
    }

    // Default single-column / fallback reading order
    return _sortBoxesInBlock(boxes);
  }

  /// Sorts a set of boxes belonging to a single column or layout block
  /// by grouping into visual lines (top-to-bottom) and sorting left-to-right within each line.
  List<PaddleTextBox> _sortBoxesInBlock(List<PaddleTextBox> boxes) {
    if (boxes.length <= 1) return boxes;

    final sorted = List<PaddleTextBox>.from(boxes)
      ..sort((a, b) => a.minY.compareTo(b.minY));

    final lines = <List<PaddleTextBox>>[];
    for (final box in sorted) {
      bool addedToLine = false;
      for (final line in lines) {
        final avgH = line.fold<double>(0.0, (s, b) => s + b.height) / line.length;
        final avgCenterY =
            line.fold<double>(0.0, (s, b) => s + b.centerY) / line.length;

        if ((box.centerY - avgCenterY).abs() < avgH * 0.55) {
          line.add(box);
          addedToLine = true;
          break;
        }
      }

      if (!addedToLine) {
        lines.add([box]);
      }
    }

    final result = <PaddleTextBox>[];
    for (final line in lines) {
      line.sort((a, b) => a.minX.compareTo(b.minX));
      result.addAll(line);
    }

    return result;
  }

  /// Performs CTC greedy decoding on output logits and calculates average character confidence.
  DecodedCtcResult _decodeCtcLogits(
    List<dynamic> flatLogits,
    List<String> dictionary,
  ) {
    final totalValues = flatLogits.length;
    final timeSteps = totalValues ~/ _vocabularySize;
    if (timeSteps <= 0) {
      return const DecodedCtcResult(text: '', confidence: 0.0);
    }

    final chars = <String>[];
    double totalProb = 0.0;
    int emittedCount = 0;
    int prevIndex = -1;

    for (int t = 0; t < timeSteps; t++) {
      final stepOffset = t * _vocabularySize;

      // Argmax for current timestep
      int maxIdx = 0;
      double maxLogit = -double.infinity;

      for (int v = 0; v < _vocabularySize; v++) {
        final val = (flatLogits[stepOffset + v] as num).toDouble();
        if (val > maxLogit) {
          maxLogit = val;
          maxIdx = v;
        }
      }

      // CTC Collapse: skip blank (index 0) and identical consecutive tokens
      if (maxIdx != 0 && maxIdx != prevIndex) {
        // Approximate softmax probability for the winning token
        double sumExp = 0.0;
        for (int v = 0; v < _vocabularySize; v++) {
          final val = (flatLogits[stepOffset + v] as num).toDouble();
          final diff = val - maxLogit;
          if (diff > -10.0) {
            sumExp += exp(diff);
          }
        }
        final prob = sumExp > 0 ? (1.0 / sumExp).clamp(0.01, 1.0) : 0.85;

        if (maxIdx == _spaceTokenIndex) {
          chars.add(' ');
        } else if (maxIdx < dictionary.length) {
          chars.add(dictionary[maxIdx]);
          totalProb += prob;
          emittedCount++;
        }
      }

      prevIndex = maxIdx;
    }

    final text = chars.join('');
    final confidence = emittedCount > 0 ? (totalProb / emittedCount) : 0.85;

    return DecodedCtcResult(
      text: text,
      confidence: confidence.clamp(0.0, 1.0),
    );
  }

  @override
  Future<void> dispose() async {
    try {
      await _detSession?.close();
    } catch (_) {}
    try {
      await _recSession?.close();
    } catch (_) {}
    _detSession = null;
    _recSession = null;
  }
}
