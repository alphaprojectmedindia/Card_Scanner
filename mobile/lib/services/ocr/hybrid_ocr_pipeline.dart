import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../../models/ocr_side_result.dart';
import '../../models/recovered_ocr_observation.dart';
import 'field_candidate.dart';
import 'field_semantic_evaluator.dart';
import 'ml_kit_ocr_engine.dart';
import 'ocr_engine.dart';
import 'ocr_observation.dart';
import 'ocr_quality_assessment.dart';
import 'paddle_ocr_engine.dart';
import 'targeted_high_res_reocr_service.dart';

/// Production Hybrid OCR Pipeline (Scanner V2: Paddle-Primary + Layout-Independent Parser).
///
/// Orchestrates on-device PaddleOCR PP-OCRv5 Mobile as PRIMARY engine and Google ML Kit
/// as RECOVERY / FALLBACK engine with deterministic quality assessment, targeted high-resolution
/// re-OCR, conservative evidence reconciliation, and fail-soft error handling.
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

  /// Asynchronously pre-warms on-device OCR engines in the background to eliminate
  /// cold-start latency and race conditions on the first business card scan.
  Future<void> prewarm() async {
    try {
      if (primaryEngine is PaddleOcrEngine) {
        await (primaryEngine as PaddleOcrEngine).prewarm();
      }
    } catch (_) {}
  }

  HybridOcrPipeline({
    OcrEngine? primaryEngine,
    OcrEngine? secondaryEngine,
    this.enableMultiPass = false,
  })  : primaryEngine = primaryEngine ?? PaddleOcrEngine(),
        secondaryEngine = secondaryEngine ?? const MlKitOcrEngine();

  /// Processes a business card image on-device through the hybrid pipeline.
  ///
  /// For physical business cards, both Google ML Kit and PaddleOCR PP-OCRv5 Mobile
  /// run sequentially for every acceptable capture, followed by independent field-level
  /// arbitration across contact and identity fields.
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

      // 2. Step 1: Run Primary Engine (defaults to PaddleOCR PP-OCRv5 Mobile)
      final primaryStopwatch = Stopwatch()..start();
      OcrEngineResult primaryResult;
      try {
        primaryResult = await primaryEngine.recognize(imagePath);
      } catch (e) {
        primaryResult = OcrEngineResult.failure(
          engineName: primaryEngine.name,
          error: 'Primary engine exception: $e',
          processingTime: primaryStopwatch.elapsed,
        );
      } finally {
        primaryStopwatch.stop();
      }

      final primaryAssessment =
          OcrQualityEvaluator.assessEngineResult(primaryResult);

      // Optional Multi-Pass enhancement on primary engine if explicitly enabled
      OcrEngineResult effectivePrimaryResult = primaryResult;
      OcrQualityAssessment effectivePrimaryAssessment = primaryAssessment;
      Duration primaryMultiPassDuration = Duration.zero;

      if (enableMultiPass) {
        pass2ImagePath = await _generateEnhancedPass(imagePath);
        if (pass2ImagePath != null) {
          final pass2Stopwatch = Stopwatch()..start();
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
          } finally {
            pass2Stopwatch.stop();
            primaryMultiPassDuration = pass2Stopwatch.elapsed;
          }
        }
      }

      final primaryTotalDuration =
          primaryStopwatch.elapsed + primaryMultiPassDuration;

      if (kDebugMode) {
        debugPrint('[HybridOCR] Primary engine (${primaryEngine.name}): '
            'score=${primaryAssessment.score.toStringAsFixed(1)}, '
            'sufficient=${primaryAssessment.isSufficient}, '
            'latency=${primaryTotalDuration.inMilliseconds}ms');
      }

      // 3. Step 2: Run Secondary Engine (defaults to Google ML Kit)
      // Fast-path bypass removed for physical business cards: BOTH engines run!
      onProgressUpdate?.call('Improving scan accuracy...');

      final secondaryStopwatch = Stopwatch()..start();
      OcrEngineResult secondaryResult;
      try {
        secondaryResult = await secondaryEngine.recognize(imagePath);
      } catch (e) {
        secondaryResult = OcrEngineResult.failure(
          engineName: secondaryEngine.name,
          error: 'Secondary engine exception: $e',
          processingTime: secondaryStopwatch.elapsed,
        );
      } finally {
        secondaryStopwatch.stop();
      }

      var secondaryAssessment =
          OcrQualityEvaluator.assessEngineResult(secondaryResult);

      if (kDebugMode) {
        debugPrint('[HybridOCR] Secondary engine (${secondaryEngine.name}): '
            'score=${secondaryAssessment.score.toStringAsFixed(1)}, '
            'sufficient=${secondaryAssessment.isSufficient}, '
            'latency=${secondaryStopwatch.elapsedMilliseconds}ms');
      }

      // Phase 3: Controlled single-pass enhancement retry for genuinely incomplete or low-confidence results.
      // Triggered only when both engines yield low-confidence/insufficient results and lack basic contact signals.
      final bool needsControlledRetry = (!effectivePrimaryAssessment.isSufficient &&
              !secondaryAssessment.isSufficient) &&
          (effectivePrimaryAssessment.score < 55.0 && secondaryAssessment.score < 55.0) &&
          !effectivePrimaryResult.rawText.contains('@') &&
          !secondaryResult.rawText.contains('@') &&
          !RegExp(r'\d{6,}').hasMatch(effectivePrimaryResult.rawText) &&
          !RegExp(r'\d{6,}').hasMatch(secondaryResult.rawText);

      if (needsControlledRetry && pass2ImagePath == null) {
        pass2ImagePath = await _generateEnhancedPass(imagePath);
        if (pass2ImagePath != null) {
          try {
            final retryResult = await secondaryEngine.recognize(pass2ImagePath);
            if (retryResult.isSuccess && retryResult.detectedLines.isNotEmpty) {
              final retryAssessment = OcrQualityEvaluator.assessEngineResult(retryResult);
              if (retryAssessment.score > secondaryAssessment.score) {
                secondaryResult = retryResult;
                secondaryAssessment = retryAssessment;
              }
            }
          } catch (_) {}
        }
      }

      // 4. Step 3: Targeted high-resolution re-OCR for uncertain phone/email fields (Part 18)
      if (effectivePrimaryResult.observations.isNotEmpty && File(imagePath).existsSync()) {
        const reOcrService = TargetedHighResReOcrService();
        final improvedLines = List<String>.from(effectivePrimaryResult.detectedLines);
        bool anyImproved = false;

        for (final obs in effectivePrimaryResult.observations) {
          final isPhoneCandidate = RegExp(r'\d{6,}').hasMatch(obs.text) &&
              obs.text.replaceAll(RegExp(r'\D'), '').length < 10;
          final isEmailCandidate = (obs.text.contains('(at)') ||
                  (obs.text.contains('@') && !obs.text.contains('.'))) &&
              !obs.text.contains('http');
          final isGarbledCandidate = FieldSemanticEvaluator.computeTextQualityScore(obs.text) < 0.60 ||
              RegExp(r'[a-zA-Z]+\d+[a-zA-Z]+|\b\d+[a-zA-Z]{3,}\b').hasMatch(obs.text);

          if (isPhoneCandidate || isEmailCandidate || isGarbledCandidate) {
            try {
              final recovered = await reOcrService.recoverRegion(
                highResImagePath: imagePath,
                observation: obs,
                primaryEngine: primaryEngine,
                recoveryEngine: secondaryEngine,
              );
              if (recovered.wasImproved && recovered.recoveredText.isNotEmpty) {
                final idx = improvedLines.indexOf(obs.text);
                if (idx != -1) {
                  improvedLines[idx] = recovered.recoveredText;
                  anyImproved = true;
                }
              }
            } catch (_) {}
          }
        }

        if (anyImproved) {
          effectivePrimaryResult = OcrEngineResult(
            engineName: effectivePrimaryResult.engineName,
            rawText: improvedLines.join('\n'),
            detectedLines: improvedLines,
            lineCount: improvedLines.length,
            characterCount: improvedLines.fold(0, (sum, l) => sum + l.length),
            processingTime: effectivePrimaryResult.processingTime,
            isSuccess: true,
            observations: effectivePrimaryResult.observations,
          );
        }
      }

      // 5. Step 4: Arbitration & Field-Level Resolution
      final arbitrationStopwatch = Stopwatch()..start();

      final attributedDurations = attributeEngineDurations(
        primaryEngine: primaryEngine,
        primaryDuration: primaryTotalDuration,
        secondaryEngine: secondaryEngine,
        secondaryDuration: secondaryStopwatch.elapsed,
      );

      final sideResult = _mergeAndSelect(
        side: side,
        imagePath: imagePath,
        primaryResult: effectivePrimaryResult,
        primaryAssessment: effectivePrimaryAssessment,
        secondaryResult: secondaryResult,
        secondaryAssessment: secondaryAssessment,
        totalDuration: totalStopwatch.elapsed,
        mlKitDuration: attributedDurations.mlKitDuration,
        paddleDuration: attributedDurations.paddleDuration,
        primaryDuration: primaryTotalDuration,
        secondaryDuration: secondaryStopwatch.elapsed,
        arbitrationStopwatch: arbitrationStopwatch,
        recoveredObservations: const [],
      );
      totalStopwatch.stop();

      return sideResult;
    } finally {
      _deleteTempFile(pass2ImagePath);
      // Release sequential execution lock
      final completer = _sequentialLock;
      _sequentialLock = null;
      completer?.complete();
    }
  }

  /// Merges results from both engines conservatively with independent field-level arbitration:
  /// - Field-level resolution: Name, Company, Job Title, Phone, Email, Website, Address
  /// - No global engine winner
  /// - Tracks engine agreement without logging PII
  /// - Never invents characters
  OcrSideResult _mergeAndSelect({
    required CardSide side,
    required String imagePath,
    required OcrEngineResult primaryResult,
    required OcrQualityAssessment primaryAssessment,
    required OcrEngineResult secondaryResult,
    required OcrQualityAssessment secondaryAssessment,
    required Duration totalDuration,
    required Duration mlKitDuration,
    required Duration paddleDuration,
    Duration primaryDuration = Duration.zero,
    Duration secondaryDuration = Duration.zero,
    required Stopwatch arbitrationStopwatch,
    List<RecoveredOcrObservation> recoveredObservations = const [],
  }) {
    // Both failed: fail-soft safely without crashing
    if (!primaryResult.isSuccess && !secondaryResult.isSuccess) {
      arbitrationStopwatch.stop();
      return _buildSideResult(
        side: side,
        imagePath: imagePath,
        lines: const [],
        engineName: 'Both engines failed',
        processingTime: totalDuration,
        mlKitDuration: mlKitDuration,
        paddleDuration: paddleDuration,
        primaryDuration: primaryDuration,
        secondaryDuration: secondaryDuration,
        arbitrationDuration: arbitrationStopwatch.elapsed,
        fallbackInvoked: true,
        primaryAssessment: primaryAssessment,
        secondaryAssessment: secondaryAssessment,
        fallbackReason: 'Primary: ${primaryResult.error}; Secondary: ${secondaryResult.error}',
        recoveredObservations: recoveredObservations,
        paddleOcrRawText: primaryResult.rawText,
        mlKitRawText: secondaryResult.rawText,
      );
    }

    // Secondary fallback failure handling: If PaddleOCR failed or timed out,
    // preserve partial ML Kit result if usable.
    if (!secondaryResult.isSuccess) {
      if (kDebugMode) {
        debugPrint('[HybridOCR] Secondary fallback failed: ${secondaryResult.error}. '
            'Preserving primary output.');
      }
      final fieldResolution = FieldSemanticEvaluator.resolveFields(
        primaryLines: primaryResult.detectedLines,
        primaryEngineName: primaryResult.engineName,
        primaryOcrQualityScore: primaryAssessment.score,
        secondaryLines: const [],
        secondaryEngineName: secondaryResult.engineName,
        secondaryOcrQualityScore: 0.0,
      );
      arbitrationStopwatch.stop();
      return _buildSideResult(
        side: side,
        imagePath: imagePath,
        lines: primaryResult.detectedLines,
        engineName: '${primaryResult.engineName} (Fallback failed)',
        processingTime: totalDuration,
        mlKitDuration: mlKitDuration,
        paddleDuration: paddleDuration,
        primaryDuration: primaryDuration,
        secondaryDuration: secondaryDuration,
        arbitrationDuration: arbitrationStopwatch.elapsed,
        fallbackInvoked: true,
        primaryAssessment: primaryAssessment,
        secondaryAssessment: secondaryAssessment,
        fallbackReason: 'Secondary failed: ${secondaryResult.error}',
        fieldResolution: fieldResolution,
        observations: primaryResult.observations,
        recoveredObservations: recoveredObservations,
        paddleOcrRawText: primaryResult.rawText,
        mlKitRawText: secondaryResult.rawText,
      );
    }

    // Primary failure handling: If ML Kit failed, preserve secondary PaddleOCR output.
    if (!primaryResult.isSuccess) {
      final fieldResolution = FieldSemanticEvaluator.resolveFields(
        primaryLines: const [],
        primaryEngineName: primaryResult.engineName,
        primaryOcrQualityScore: 0.0,
        secondaryLines: secondaryResult.detectedLines,
        secondaryEngineName: secondaryResult.engineName,
        secondaryOcrQualityScore: secondaryAssessment.score,
      );
      arbitrationStopwatch.stop();
      return _buildSideResult(
        side: side,
        imagePath: imagePath,
        lines: secondaryResult.detectedLines,
        engineName: secondaryResult.engineName,
        processingTime: totalDuration,
        mlKitDuration: mlKitDuration,
        paddleDuration: paddleDuration,
        primaryDuration: primaryDuration,
        secondaryDuration: secondaryDuration,
        arbitrationDuration: arbitrationStopwatch.elapsed,
        fallbackInvoked: true,
        primaryAssessment: primaryAssessment,
        secondaryAssessment: secondaryAssessment,
        fallbackReason: 'Primary failed: ${primaryResult.error}',
        fieldResolution: fieldResolution,
        observations: secondaryResult.observations,
        recoveredObservations: recoveredObservations,
        paddleOcrRawText: primaryResult.rawText,
        mlKitRawText: secondaryResult.rawText,
      );
    }

    // Both succeeded: Step 5 Field-Level Hybrid Resolution (CRITICAL RULE: No Global Engine Winner)
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
    arbitrationStopwatch.stop();

    if (kDebugMode) {
      final phoneEngines =
          fieldResolution.phones.map((p) => p.sourceEngine).toSet().join(',');
      final emailEngines =
          fieldResolution.emails.map((e) => e.sourceEngine).toSet().join(',');
      final webEngines =
          fieldResolution.websites.map((w) => w.sourceEngine).toSet().join(',');
      debugPrint('[OCR_DIAGNOSTIC] Timing: MLKit=${mlKitDuration.inMilliseconds}ms, '
          'Paddle=${paddleDuration.inMilliseconds}ms, '
          'Arbitration=${arbitrationStopwatch.elapsedMilliseconds}ms, '
          'Total=${totalDuration.inMilliseconds}ms');
      debugPrint('[OCR_DIAGNOSTIC] Field arbitration:');
      debugPrint('  Name: winner=${fieldResolution.name?.sourceEngine ?? "none"} '
          '(reason: ${fieldResolution.name?.positiveEvidence.join(", ") ?? "not detected"})');
      debugPrint('  Company: winner=${fieldResolution.company?.sourceEngine ?? "none"} '
          '(reason: ${fieldResolution.company?.positiveEvidence.join(", ") ?? "not detected"})');
      debugPrint('  Job Title: winner=${fieldResolution.jobTitle?.sourceEngine ?? "none"} '
          '(reason: ${fieldResolution.jobTitle?.positiveEvidence.join(", ") ?? "not detected"})');
      debugPrint('  Phone: winner=${phoneEngines.isEmpty ? "none" : phoneEngines}');
      debugPrint('  Email: winner=${emailEngines.isEmpty ? "none" : emailEngines}');
      debugPrint('  Website: winner=${webEngines.isEmpty ? "none" : webEngines}');
      debugPrint('  Address: winner=${fieldResolution.address?.sourceEngine ?? "none"} '
          '(reason: ${fieldResolution.address?.positiveEvidence.join(", ") ?? "not detected"})');
      if (fieldResolution.diagnosticNotes.isNotEmpty) {
        debugPrint('  Notes: ${fieldResolution.diagnosticNotes.join("; ")}');
      }
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

    final selectedEngineName =
        'Hybrid Field-Resolved (${primaryResult.engineName} + ${secondaryResult.engineName})';

    return _buildSideResult(
      side: side,
      imagePath: imagePath,
      lines: finalLines,
      engineName: selectedEngineName,
      processingTime: totalDuration,
      mlKitDuration: mlKitDuration,
      paddleDuration: paddleDuration,
      primaryDuration: primaryDuration,
      secondaryDuration: secondaryDuration,
      arbitrationDuration: arbitrationStopwatch.elapsed,
      fallbackInvoked: true,
      primaryAssessment: primaryAssessment,
      secondaryAssessment: secondaryAssessment,
      fallbackReason: primaryAssessment.reasons.join('; '),
      agreedSignals: fieldResolution.agreedSignals,
      alternatives: fieldResolution.alternatives,
      fieldResolution: fieldResolution,
      observations: [
        ...primaryResult.observations,
        ...secondaryResult.observations,
      ],
      recoveredObservations: recoveredObservations,
      paddleOcrRawText: primaryResult.engineName.toLowerCase().contains('paddle') ? primaryResult.rawText : secondaryResult.rawText,
      mlKitRawText: secondaryResult.engineName.toLowerCase().contains('ml kit') ? secondaryResult.rawText : primaryResult.rawText,
    );
  }

  /// Builds a strongly-typed [OcrSideResult] carrying structured lines and metadata.
  OcrSideResult _buildSideResult({
    required CardSide side,
    required String imagePath,
    required List<String> lines,
    required String engineName,
    required Duration processingTime,
    Duration mlKitDuration = Duration.zero,
    Duration paddleDuration = Duration.zero,
    Duration primaryDuration = Duration.zero,
    Duration secondaryDuration = Duration.zero,
    Duration arbitrationDuration = Duration.zero,
    required bool fallbackInvoked,
    OcrQualityAssessment? primaryAssessment,
    OcrQualityAssessment? secondaryAssessment,
    String? fallbackReason,
    List<String> agreedSignals = const [],
    Map<String, List<String>> alternatives = const {},
    FieldResolutionResult? fieldResolution,
    List<OcrObservation> observations = const [],
    List<RecoveredOcrObservation> recoveredObservations = const [],
    String? paddleOcrRawText,
    String? mlKitRawText,
  }) {
    final lineMetas = <OcrLineMetadata>[];
    for (int i = 0; i < lines.length; i++) {
      final lineText = lines[i];
      final matchingObs = observations.cast<OcrObservation?>().firstWhere(
            (o) =>
                o != null &&
                (o.text == lineText ||
                    o.text.contains(lineText) ||
                    lineText.contains(o.text)),
            orElse: () => null,
          );
      lineMetas.add(OcrLineMetadata(
        text: lineText,
        side: side,
        lineIndex: i,
        blockIndex: 0,
        boundingBox: matchingObs?.boundingBox ?? Rect.zero,
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
      recoveredObservations: recoveredObservations,
      metadata: {
        'pipeline': 'Hybrid OCR Pipeline',
        'selectedEngine': engineName,
        'fallbackInvoked': fallbackInvoked,
        'fallbackReason': ?fallbackReason,
        'processingTimeMs': processingTime.inMilliseconds,
        'timings': {
          'mlKitMs': mlKitDuration.inMilliseconds,
          'paddleMs': paddleDuration.inMilliseconds,
          'primaryMs': primaryDuration.inMilliseconds,
          'secondaryMs': secondaryDuration.inMilliseconds,
          'arbitrationMs': arbitrationDuration.inMilliseconds,
          'totalMs': processingTime.inMilliseconds,
        },
        'mlKitMs': mlKitDuration.inMilliseconds,
        'paddleMs': paddleDuration.inMilliseconds,
        'primaryMs': primaryDuration.inMilliseconds,
        'secondaryMs': secondaryDuration.inMilliseconds,
        'arbitrationMs': arbitrationDuration.inMilliseconds,
        'totalMs': processingTime.inMilliseconds,
        'primaryAssessment': ?primaryAssessment?.toJson(),
        'secondaryAssessment': ?secondaryAssessment?.toJson(),
        if (fieldResolution != null)
          'fieldResolution': fieldResolution.toJson(),
        if (fieldResolution != null)
          'hybridFieldResolution': fieldResolution.toJson(),
        if (fieldResolution != null)
          'fieldConfidenceStates': fieldResolution.fieldConfidenceStates,
        if (fieldResolution != null)
          'unclassifiedLines': fieldResolution.unclassifiedLines,
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
                .map((p) => p.sourceEngine)
                .toList(),
            'emails': fieldResolution.emails
                .map((e) => e.sourceEngine)
                .toList(),
            'websites': fieldResolution.websites
                .map((w) => w.sourceEngine)
                .toList(),
          },
        if (agreedSignals.isNotEmpty) 'agreedSignals': agreedSignals,
        if (alternatives.isNotEmpty) 'alternatives': alternatives,
        if (observations.isNotEmpty)
          'observations': observations.map((o) => o.toJson()).toList(),
        'paddleOcrRawText': ?paddleOcrRawText,
        'mlKitRawText': ?mlKitRawText,
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

  /// Returns true if [engine] is identified as Google ML Kit.
  ///
  /// Checks concrete type [MlKitOcrEngine] first, then falls back to canonical name matching.
  @visibleForTesting
  static bool isMlKitEngine(OcrEngine engine) {
    if (engine is MlKitOcrEngine) return true;
    final lower = engine.name.toLowerCase();
    return lower.contains('ml kit') || lower.contains('mlkit');
  }

  /// Returns true if [engine] is identified as PaddleOCR.
  ///
  /// Checks concrete type [PaddleOcrEngine] first, then falls back to canonical name matching.
  @visibleForTesting
  static bool isPaddleEngine(OcrEngine engine) {
    if (engine is PaddleOcrEngine) return true;
    final lower = engine.name.toLowerCase();
    return lower.contains('paddle');
  }

  /// Resolves execution durations for ML Kit and PaddleOCR based on the actual engines that executed.
  ///
  /// For known engines ([MlKitOcrEngine], [PaddleOcrEngine], or engines whose canonical names
  /// identify them as ML Kit or PaddleOCR), execution durations (including multi-pass
  /// enhancement) are attributed to the respective engine regardless of whether they
  /// ran in the primary or secondary slot.
  ///
  /// For unknown or custom engine implementations, duration is NOT falsely attributed to
  /// ML Kit or PaddleOCR (defaulting to [Duration.zero]); instead, callers can inspect
  /// `primaryMs` and `secondaryMs` in the timings metadata.
  @visibleForTesting
  static ({Duration mlKitDuration, Duration paddleDuration}) attributeEngineDurations({
    required OcrEngine primaryEngine,
    required Duration primaryDuration,
    required OcrEngine secondaryEngine,
    required Duration secondaryDuration,
  }) {
    Duration mlKit = Duration.zero;
    Duration paddle = Duration.zero;

    void recordEngineDuration(OcrEngine engine, Duration duration) {
      if (isMlKitEngine(engine)) {
        mlKit += duration;
      } else if (isPaddleEngine(engine)) {
        paddle += duration;
      }
      // Unknown or custom engines are not falsely attributed to ML Kit or PaddleOCR.
    }

    recordEngineDuration(primaryEngine, primaryDuration);
    recordEngineDuration(secondaryEngine, secondaryDuration);

    return (mlKitDuration: mlKit, paddleDuration: paddle);
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
