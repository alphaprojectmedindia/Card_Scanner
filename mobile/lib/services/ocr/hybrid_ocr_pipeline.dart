import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../../models/ocr_side_result.dart';
import 'field_candidate.dart';
import 'field_semantic_evaluator.dart';
import 'ml_kit_ocr_engine.dart';
import 'ocr_engine.dart';
import 'ocr_quality_assessment.dart';
import 'paddle_ocr_engine.dart';

/// Production Hybrid OCR Pipeline.
///
/// Orchestrates on-device Google ML Kit (fast path: ~350ms) and PaddleOCR PP-OCRv5 Mobile
/// (high accuracy fallback: ~4200ms) with deterministic quality assessment, intelligent
/// conservative merging, sequential execution locking, and fail-soft error handling.
class HybridOcrPipeline {
  static HybridOcrPipeline? _sharedInstance;

  /// Global shared pipeline instance ensuring ONNX sessions are loaded once and
  /// reused across scans rather than reloaded per image.
  static HybridOcrPipeline get shared {
    _sharedInstance ??= HybridOcrPipeline();
    return _sharedInstance!;
  }

  /// Resets the shared instance (used for test isolation).
  static void resetForTesting() {
    _sharedInstance?.dispose();
    _sharedInstance = null;
  }

  final OcrEngine primaryEngine;
  final OcrEngine secondaryEngine;
  final bool enableMultiPass;

  /// Concurrency mutex to ensure sequential execution and prevent overlapping
  /// native ONNX inferences on mobile devices.
  Completer<void>? _sequentialLock;

  HybridOcrPipeline({
    OcrEngine? primaryEngine,
    OcrEngine? secondaryEngine,
    this.enableMultiPass = false,
  })  : primaryEngine = primaryEngine ?? const MlKitOcrEngine(),
        secondaryEngine = secondaryEngine ?? PaddleOcrEngine();

  /// Processes a business card image on-device through the hybrid pipeline.
  ///
  /// [onProgressUpdate] receives subtle progress notifications for the UI
  /// (e.g. 'Reading contact information on-device' -> 'Improving scan accuracy...').
  Future<OcrSideResult> processCardSide({
    required String imagePath,
    required CardSide side,
    void Function(String message)? onProgressUpdate,
  }) async {
    // 1. Acquire sequential execution lock
    while (_sequentialLock != null) {
      await _sequentialLock!.future;
    }
    _sequentialLock = Completer<void>();
    String? pass2ImagePath;

    try {
      final totalStopwatch = Stopwatch()..start();
      onProgressUpdate?.call('Reading contact information on-device');

      // 2. Step 1: Run Primary Engine (Google ML Kit - Fast Path)
      OcrEngineResult primaryResult;
      try {
        primaryResult = await primaryEngine.recognize(imagePath);
      } catch (e) {
        primaryResult = OcrEngineResult.failure(
          engineName: primaryEngine.name,
          error: 'Primary engine exception: $e',
        );
      }

      // 3. Step 2: Deterministic Quality Assessment of Primary Result
      final primaryAssessment =
          OcrQualityEvaluator.assessEngineResult(primaryResult);

      if (kDebugMode) {
        debugPrint('[HybridOCR] Primary engine (${primaryEngine.name}): '
            'score=${primaryAssessment.score.toStringAsFixed(1)}, '
            'sufficient=${primaryAssessment.isSufficient}, '
            'hasSemanticWarning=${primaryAssessment.semanticAssessment?.hasSemanticWarning ?? false}, '
            'latency=${primaryResult.processingTime.inMilliseconds}ms');
      }

      // Critical Field Completeness Evaluation (Section 7, 8, 14):
      // Independently evaluates Name, Phone, and Email.
      // An overall score >= 60.0 must NEVER bypass fallback if ANY critical field fails!
      final criticalCompleteness = primaryAssessment.criticalFields ??
          OcrQualityEvaluator.assessText(primaryResult.detectedLines.join('\n')).criticalFields ??
          const CriticalFieldCompleteness(
            hasName: false,
            hasPhone: false,
            hasEmail: false,
            nameFieldFailure: true,
            phoneFieldFailure: true,
            emailFieldFailure: true,
          );

      final bool isCriticalFieldFailure = criticalCompleteness.hasAnyFailure;
      final bool hasSemanticWarning =
          primaryAssessment.semanticAssessment?.hasSemanticWarning ?? false;
      final bool meetsGeneralThreshold =
          primaryAssessment.score >= OcrQualityThresholds.sufficiencyScoreThreshold;

      if (kDebugMode) {
        debugPrint('[HybridOCR] Critical fields evaluation: '
            'hasName=${criticalCompleteness.hasName} (conf=${criticalCompleteness.nameConfidence.toStringAsFixed(2)}), '
            'hasPhone=${criticalCompleteness.hasPhone} (conf=${criticalCompleteness.phoneConfidence.toStringAsFixed(2)}), '
            'hasEmail=${criticalCompleteness.hasEmail} (conf=${criticalCompleteness.emailConfidence.toStringAsFixed(2)}), '
            'nameFail=${criticalCompleteness.nameFieldFailure}, '
            'phoneFail=${criticalCompleteness.phoneFieldFailure}, '
            'emailFail=${criticalCompleteness.emailFieldFailure}');
      }

      // FAST PATH: If primary result is sufficient (general score >= 60.0 AND no semantic warnings!),
      // AND all three critical fields are complete without failure, return immediately.
      final bool canUseFastPath = meetsGeneralThreshold &&
          primaryAssessment.isSufficient &&
          !hasSemanticWarning &&
          !isCriticalFieldFailure;

      if (canUseFastPath) {
        totalStopwatch.stop();
        return _buildSideResult(
          side: side,
          imagePath: imagePath,
          lines: primaryResult.detectedLines,
          engineName: primaryResult.engineName,
          processingTime: totalStopwatch.elapsed,
          fallbackInvoked: false,
          primaryAssessment: primaryAssessment,
        );
      }

      // Fast path bypassed -> Log exact trigger reasons in debug mode
      String fallbackReason = '';
      if (kDebugMode) {
        final reasons = <String>[];
        if (!meetsGeneralThreshold) reasons.add('Score ${primaryAssessment.score.toStringAsFixed(1)} < ${OcrQualityThresholds.sufficiencyScoreThreshold}');
        if (hasSemanticWarning) reasons.add('Semantic warning');
        if (criticalCompleteness.nameFieldFailure) reasons.add('Name missing/weak');
        if (criticalCompleteness.phoneFieldFailure) reasons.add('Phone missing/weak');
        if (criticalCompleteness.emailFieldFailure) reasons.add('Email missing/weak');
        fallbackReason = reasons.join('; ');
        debugPrint('[HybridOCR] Fast path bypassed. Trigger reason(s): $fallbackReason');
      }

      // 4. Multi-Pass Strategy (Section 15):
      // Pass 2: Contrast-enhanced card on primary engine before heavy secondary engine
      OcrEngineResult effectivePrimaryResult = primaryResult;
      OcrQualityAssessment effectivePrimaryAssessment = primaryAssessment;

      if (enableMultiPass) {
        pass2ImagePath = await _generateEnhancedPass(imagePath);
        if (pass2ImagePath != null) {
          try {
            final pass2Result = await primaryEngine.recognize(pass2ImagePath);
            if (pass2Result.isSuccess && pass2Result.detectedLines.isNotEmpty) {
              final combinedLines = _combineUniqueLines(
                primaryResult.detectedLines,
                pass2Result.detectedLines,
              );
              final pass2Assessment = OcrQualityEvaluator.assessEngineResult(
                OcrEngineResult(
                  engineName: primaryEngine.name,
                  rawText: combinedLines.join('\n'),
                  detectedLines: combinedLines,
                  lineCount: combinedLines.length,
                  characterCount:
                      combinedLines.fold(0, (sum, l) => sum + l.length),
                  processingTime:
                      primaryResult.processingTime + pass2Result.processingTime,
                  isSuccess: true,
                ),
              );

              // If Pass 2 recovers all critical fields and has no semantic warnings, return without PaddleOCR!
              final pass2Completeness = pass2Assessment.criticalFields;
              if (pass2Completeness != null &&
                  pass2Completeness.isComplete &&
                  !(pass2Assessment.semanticAssessment?.hasSemanticWarning ??
                      false)) {
                totalStopwatch.stop();
                return _buildSideResult(
                  side: side,
                  imagePath: imagePath,
                  lines: combinedLines,
                  engineName: '${primaryResult.engineName} (Multi-pass)',
                  processingTime: totalStopwatch.elapsed,
                  fallbackInvoked: false,
                  primaryAssessment: pass2Assessment,
                );
              }

              effectivePrimaryResult = OcrEngineResult(
                engineName: primaryResult.engineName,
                rawText: combinedLines.join('\n'),
                detectedLines: combinedLines,
                lineCount: combinedLines.length,
                characterCount:
                    combinedLines.fold(0, (sum, l) => sum + l.length),
                processingTime:
                    primaryResult.processingTime + pass2Result.processingTime,
                isSuccess: true,
              );
              effectivePrimaryAssessment = pass2Assessment;
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[HybridOCR] Multi-pass Pass 2 error: $e');
            }
          }
        }
      }

      // 5. Pass 3: Secondary Engine (Targeted PaddleOCR Fallback)
      onProgressUpdate?.call('Improving scan accuracy...');

      OcrEngineResult secondaryResult;
      try {
        secondaryResult = await secondaryEngine.recognize(imagePath);
      } catch (e) {
        secondaryResult = OcrEngineResult.failure(
          engineName: secondaryEngine.name,
          error: 'Secondary engine exception: $e',
        );
      }

      final secondaryAssessment =
          OcrQualityEvaluator.assessEngineResult(secondaryResult);

      if (kDebugMode) {
        debugPrint('[HybridOCR] Secondary engine (${secondaryEngine.name}): '
            'score=${secondaryAssessment.score.toStringAsFixed(1)}, '
            'sufficient=${secondaryAssessment.isSufficient}, '
            'latency=${secondaryResult.processingTime.inMilliseconds}ms');
      }

      totalStopwatch.stop();

      // 6. Field-Level Resolution & Merge
      return _mergeAndSelect(
        side: side,
        imagePath: imagePath,
        primaryResult: effectivePrimaryResult,
        primaryAssessment: effectivePrimaryAssessment,
        secondaryResult: secondaryResult,
        secondaryAssessment: secondaryAssessment,
        totalDuration: totalStopwatch.elapsed,
        fallbackReasonTrigger: fallbackReason,
      );
    } finally {
      _deleteTempFile(pass2ImagePath);
      // Release sequential execution lock
      final completer = _sequentialLock;
      _sequentialLock = null;
      completer?.complete();
    }
  }

  /// Merges results from both engines conservatively:
  /// - Selects the higher-quality engine as base
  /// - Preserves valid complementary phones, emails, and addresses
  /// - Resolves conflicting names without concatenating strings
  /// - Tracks engine agreement
  /// - Never invents characters
  OcrSideResult _mergeAndSelect({
    required CardSide side,
    required String imagePath,
    required OcrEngineResult primaryResult,
    required OcrQualityAssessment primaryAssessment,
    required OcrEngineResult secondaryResult,
    required OcrQualityAssessment secondaryAssessment,
    required Duration totalDuration,
    String? fallbackReasonTrigger,
  }) {
    // Fallback failure handling: If PaddleOCR failed or timed out,
    // preserve partial ML Kit result if usable, or return failure.
    if (!secondaryResult.isSuccess) {
      if (kDebugMode) {
        debugPrint('[HybridOCR] Secondary fallback failed: ${secondaryResult.error}. '
            'Preserving primary output.');
      }
      return _buildSideResult(
        side: side,
        imagePath: imagePath,
        lines: primaryResult.detectedLines,
        engineName: '${primaryResult.engineName} (Fallback failed)',
        processingTime: totalDuration,
        fallbackInvoked: true,
        primaryAssessment: primaryAssessment,
        secondaryAssessment: secondaryAssessment,
        fallbackReason: 'Secondary failed: ${secondaryResult.error}',
      );
    }

    if (!primaryResult.isSuccess) {
      return _buildSideResult(
        side: side,
        imagePath: imagePath,
        lines: secondaryResult.detectedLines,
        engineName: secondaryResult.engineName,
        processingTime: totalDuration,
        fallbackInvoked: true,
        primaryAssessment: primaryAssessment,
        secondaryAssessment: secondaryAssessment,
        fallbackReason: 'Primary failed: ${primaryResult.error}',
      );
    }

    // 6. Step 5: Field-Level Hybrid Resolution (CRITICAL RULE #3: No Global Engine Winner)
    // Resolve each field (Name, Title, Company, Address, Phones, Emails, Website) independently
    // comparing semantic evidence rather than global engine OCR quality scores!
    final fieldResolution = FieldSemanticEvaluator.resolveFields(
      primaryLines: primaryResult.detectedLines,
      primaryEngineName: primaryResult.engineName,
      primaryOcrQualityScore: primaryAssessment.score,
      secondaryLines: secondaryResult.detectedLines,
      secondaryEngineName: secondaryResult.engineName,
      secondaryOcrQualityScore: secondaryAssessment.score,
    );

    if (kDebugMode) {
      final phoneEngines =
          fieldResolution.phones.map((p) => p.sourceEngine).toSet().join(',');
      final emailEngines =
          fieldResolution.emails.map((e) => e.sourceEngine).toSet().join(',');
      final webEngines =
          fieldResolution.websites.map((w) => w.sourceEngine).toSet().join(',');
      debugPrint('[HybridOCR] FIELD RESOLUTION ENGINES: '
          'Name=${fieldResolution.name?.sourceEngine ?? "none"}, '
          'Title=${fieldResolution.jobTitle?.sourceEngine ?? "none"}, '
          'Company=${fieldResolution.company?.sourceEngine ?? "none"}, '
          'Phone=${phoneEngines.isEmpty ? "none" : phoneEngines}, '
          'Email=${emailEngines.isEmpty ? "none" : emailEngines}, '
          'Website=${webEngines.isEmpty ? "none" : webEngines}, '
          'Address=${fieldResolution.address?.sourceEngine ?? "none"}');
    }

    // Assemble resolved lines: Name first (if present), then Title, Company,
    // Phones, Emails, Website, Address, followed by any remaining unique text.
    final finalLines = <String>[];
    final seenNormalized = <String>{};

    void addLine(String? line) {
      if (line == null) return;
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;
      final norm = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (norm.isNotEmpty && !seenNormalized.contains(norm)) {
        seenNormalized.add(norm);
        finalLines.add(trimmed);
      }
    }

    if (fieldResolution.name != null &&
        fieldResolution.name!.value.isNotEmpty) {
      addLine(fieldResolution.name!.value);
    }
    if (fieldResolution.jobTitle != null &&
        fieldResolution.jobTitle!.value.isNotEmpty) {
      addLine(fieldResolution.jobTitle!.value);
    }
    if (fieldResolution.company != null &&
        fieldResolution.company!.value.isNotEmpty) {
      addLine(fieldResolution.company!.value);
    }
    for (final p in fieldResolution.phones) {
      addLine(p.value);
    }
    for (final e in fieldResolution.emails) {
      addLine(e.value);
    }
    for (final w in fieldResolution.websites) {
      addLine(w.value);
    }
    if (fieldResolution.address != null &&
        fieldResolution.address!.value.isNotEmpty) {
      addLine(fieldResolution.address!.value);
    }

    // Preserve any remaining non-empty lines from primary and secondary engines
    // so no novel text or lines are ever lost
    for (final line in [
      ...primaryResult.detectedLines,
      ...secondaryResult.detectedLines
    ]) {
      addLine(line);
    }

    // Determine descriptive selected engine attribution reflecting field sources
    final selectedEngineName =
        'Hybrid Field-Resolved (${primaryResult.engineName} + ${secondaryResult.engineName})';

    return _buildSideResult(
      side: side,
      imagePath: imagePath,
      lines: finalLines,
      engineName: selectedEngineName,
      processingTime: totalDuration,
      fallbackInvoked: true,
      primaryAssessment: primaryAssessment,
      secondaryAssessment: secondaryAssessment,
      fallbackReason: primaryAssessment.reasons.join('; '),
      agreedSignals: fieldResolution.agreedSignals,
      alternatives: fieldResolution.alternatives,
      fieldResolution: fieldResolution,
    );
  }

  /// Builds a strongly-typed [OcrSideResult] carrying structured lines and metadata.
  OcrSideResult _buildSideResult({
    required CardSide side,
    required String imagePath,
    required List<String> lines,
    required String engineName,
    required Duration processingTime,
    required bool fallbackInvoked,
    OcrQualityAssessment? primaryAssessment,
    OcrQualityAssessment? secondaryAssessment,
    String? fallbackReason,
    List<String> agreedSignals = const [],
    Map<String, List<String>> alternatives = const {},
    FieldResolutionResult? fieldResolution,
  }) {
    final lineMetas = <OcrLineMetadata>[];
    for (int i = 0; i < lines.length; i++) {
      lineMetas.add(OcrLineMetadata(
        text: lines[i],
        side: side,
        lineIndex: i,
        blockIndex: 0,
        boundingBox: Rect.zero,
      ));
    }

    final rawText = lines.join('\n');

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
      metadata: {
        'pipeline': 'Hybrid OCR Pipeline',
        'selectedEngine': engineName,
        'fallbackInvoked': fallbackInvoked,
        'fallbackReason': ?fallbackReason,
        'processingTimeMs': processingTime.inMilliseconds,
        'primaryAssessment': ?primaryAssessment?.toJson(),
        'secondaryAssessment': ?secondaryAssessment?.toJson(),
        if (fieldResolution != null)
          'fieldResolution': fieldResolution.toJson(),
        if (fieldResolution != null)
          'hybridFieldResolution': fieldResolution.toJson(),
        if (fieldResolution != null)
          'fieldSources': {
            if (fieldResolution.name != null)
              'name': fieldResolution.name!.sourceEngine,
            if (fieldResolution.jobTitle != null)
              'jobTitle': fieldResolution.jobTitle!.sourceEngine,
            if (fieldResolution.company != null)
              'company': fieldResolution.company!.sourceEngine,
            if (fieldResolution.address != null)
              'address': fieldResolution.address!.sourceEngine,
            'phones': fieldResolution.phones
                .map((p) => '${p.value} (${p.sourceEngine})')
                .toList(),
            'emails': fieldResolution.emails
                .map((e) => '${e.value} (${e.sourceEngine})')
                .toList(),
            'websites': fieldResolution.websites
                .map((w) => '${w.value} (${w.sourceEngine})')
                .toList(),
          },
        if (agreedSignals.isNotEmpty) 'agreedSignals': agreedSignals,
        if (alternatives.isNotEmpty) 'alternatives': alternatives,
      },
    );
  }

  Future<String?> _generateEnhancedPass(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) return null;

      final enhanced = img.adjustColor(original, contrast: 1.25, gamma: 0.95);
      final tempDir = Directory.systemTemp.path;
      final tempFile = File(
          '$tempDir/digital_share_enhanced_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(img.encodeJpg(enhanced, quality: 90), flush: true);
      return tempFile.path;
    } catch (_) {
      return null;
    }
  }

  void _deleteTempFile(String? path) {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  List<String> _combineUniqueLines(List<String> primary, List<String> secondary) {
    final result = List<String>.from(primary);
    final seen = primary.map((l) => l.trim().toLowerCase()).toSet();
    for (final line in secondary) {
      final trimmed = line.trim();
      final norm = trimmed.toLowerCase();
      if (norm.isNotEmpty && !seen.contains(norm)) {
        seen.add(norm);
        result.add(trimmed);
      }
    }
    return result;
  }

  /// Disposes any open sessions and release resources.
  Future<void> dispose() async {
    try {
      await primaryEngine.dispose();
    } catch (_) {}
    try {
      await secondaryEngine.dispose();
    } catch (_) {}
  }
}
