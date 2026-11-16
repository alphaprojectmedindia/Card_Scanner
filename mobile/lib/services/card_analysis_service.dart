import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import '../config/api_config.dart';
import '../models/business_card_data.dart';
import '../models/card_analysis_result.dart';
import '../models/field_evidence.dart';
import '../models/ocr_side_result.dart';
import 'api_client.dart';
import 'card_analysis_decision_service.dart';
import 'ocr/ocr_observation.dart';
import 'storage/local_scan_cache_manager.dart';

/// Client service that orchestrates selective business-card interpretation with Google's Gemini API.
/// Incorporates persistent disk caching and immediate offline fallback.
class CardAnalysisService {
  final ApiClient _apiClient;
  final bool _isCustomClient;
  final CardAnalysisDecisionService _decisionService;
  final LocalScanCacheManager _scanCacheManager;
  final bool Function()? isOnlineCheck;

  /// Tracks actual network invocations for test instrumentation and auditing.
  int geminiApiCallCount = 0;

  /// In-memory session cache to avoid duplicate API requests during the same user session.
  static final Map<String, CardAnalysisResult> _sessionCache = {};

  CardAnalysisService({
    ApiClient? apiClient,
    CardAnalysisDecisionService? decisionService,
    LocalScanCacheManager? scanCacheManager,
    this.isOnlineCheck,
  })  : _apiClient = apiClient ?? ApiClient(),
        _isCustomClient = apiClient != null,
        _decisionService = decisionService ?? const CardAnalysisDecisionService(),
        _scanCacheManager = scanCacheManager ?? LocalScanCacheManager();

  /// Clears the session cache (useful for testing).
  @visibleForTesting
  static void clearSessionCache() {
    _sessionCache.clear();
  }

  /// Resets the network invocation counter (for verification tests).
  void resetCallCount() {
    geminiApiCallCount = 0;
  }

  /// Computes a deterministic canonical SHA-256 hash of the card content.
  String computeScanContentHash({
    required BusinessCardData cardData,
    required OcrSideResult frontOcr,
    OcrSideResult? backOcr,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(frontOcr.rawText.trim());
    if (backOcr != null) {
      buffer.writeln(backOcr.rawText.trim());
    }
    final obs = _extractObservations(frontOcr, backOcr);
    for (final o in obs) {
      buffer.writeln(
        '${o.id}:${o.text}:${o.normalizedBoundingBox.left.toStringAsFixed(4)},${o.normalizedBoundingBox.top.toStringAsFixed(4)}',
      );
    }
    final bytes = utf8.encode(buffer.toString());
    return sha256.convert(bytes).toString();
  }

  /// Selectively analyzes the business card with Gemini if criteria in [CardAnalysisDecisionService] are met.
  /// 1. If criteria are not met, returns null (using local baseline).
  /// 2. If already cached in memory or persistent disk cache, returns cached result immediately (0 network calls).
  /// 3. If offline or remote call fails, safely falls back to local baseline without blocking the user.
  /// 4. Ensures exactly one combined Gemini call per card scan.
  Future<CardAnalysisResult?> analyzeIfTriggered({
    required BusinessCardData cardData,
    required OcrSideResult frontOcr,
    OcrSideResult? backOcr,
    CardAnalysisDecision? precomputedDecision,
  }) async {
    return _executeAnalysis(
      cardData: cardData,
      frontOcr: frontOcr,
      backOcr: backOcr,
      precomputedDecision: precomputedDecision,
      forceMultimodal: false,
    );
  }

  /// MAXIMUM ACCURACY PRIORITY:
  /// Mandatory multimodal extraction with Google Gemini across both images and all OCR observations.
  /// Bypasses selective confidence heuristics and directly runs full multimodal extraction.
  Future<CardAnalysisResult?> analyzeFullMultimodal({
    required BusinessCardData cardData,
    required OcrSideResult frontOcr,
    OcrSideResult? backOcr,
    String? scanId,
  }) async {
    return _executeAnalysis(
      cardData: cardData,
      frontOcr: frontOcr,
      backOcr: backOcr,
      forceMultimodal: true,
      scanId: scanId,
    );
  }

  Future<CardAnalysisResult?> _executeAnalysis({
    required BusinessCardData cardData,
    required OcrSideResult frontOcr,
    OcrSideResult? backOcr,
    CardAnalysisDecision? precomputedDecision,
    bool forceMultimodal = false,
    String? scanId,
  }) async {
    // 0. Offline and test safety check
    final bool isTestBinding = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    final isTestEnvironment = isTestBinding ||
        Platform.environment.containsKey('FLUTTER_TEST') ||
        Platform.script.path.contains('_test.dart') ||
        const bool.fromEnvironment('flutter.test');
    if (isTestEnvironment && !_isCustomClient) {
      return null;
    }

    if (isOnlineCheck != null && !isOnlineCheck!()) {
      return null;
    }

    final decision = precomputedDecision ??
        (forceMultimodal
            ? const CardAnalysisDecision(
                shouldInvokeGemini: true,
                mode: AnalysisMode.multimodalVision,
                primaryReason: 'Maximum Accuracy Gemini-First Scan Policy',
                triggeredRules: ['T0_MAXIMUM_ACCURACY_MANDATE'],
              )
            : _decisionService.evaluate(
                cardData: cardData,
                frontOcr: frontOcr,
                backOcr: backOcr,
              ));

    if (!forceMultimodal && !decision.shouldInvokeGemini) {
      return null;
    }

    final hash = computeScanContentHash(
      cardData: cardData,
      frontOcr: frontOcr,
      backOcr: backOcr,
    );

    // 1. Check in-memory session cache
    if (_sessionCache.containsKey(hash)) {
      return _sessionCache[hash]!;
    }

    // 2. Check persistent local disk cache
    final diskCached = await _scanCacheManager.getGeminiCorrection(hash);
    if (diskCached != null) {
      _sessionCache[hash] = diskCached;
      return diskCached;
    }

    final clientRequestId = 'req_${hash.substring(0, 16)}';
    String? frontStorageKey;
    String? backStorageKey;
    String? uploadFailureReason;
    bool frontUploaded = false;
    bool backUploaded = false;
    String modeString = decision.mode == AnalysisMode.multimodalVision
        ? 'MultimodalVision'
        : 'TextAndLayout';

    // 3. Path B: If MultimodalVision is requested, upload front and back images
    if (decision.mode == AnalysisMode.multimodalVision) {
      if (frontOcr.imagePath.isNotEmpty) {
        try {
          final uploadResponse = await _apiClient.postMultipart(
            ApiConfig.uploadBusinessCardImageEndpoint,
            fieldName: 'file',
            filePath: frontOcr.imagePath,
            fields: {'cardSide': 'front'},
            requiresAuth: true,
          );

          if (uploadResponse is Map<String, dynamic> &&
              uploadResponse['storageKey'] != null) {
            frontStorageKey = uploadResponse['storageKey'] as String;
            frontUploaded = true;
          } else {
            uploadFailureReason = 'Failed to upload front card image to storage.';
          }
        } catch (e) {
          uploadFailureReason = 'Failed to upload front card image: $e';
        }
      }

      if (backOcr != null && backOcr.imagePath.isNotEmpty) {
        try {
          final uploadResponse = await _apiClient.postMultipart(
            ApiConfig.uploadBusinessCardImageEndpoint,
            fieldName: 'file',
            filePath: backOcr.imagePath,
            fields: {'cardSide': 'back'},
            requiresAuth: true,
          );

          if (uploadResponse is Map<String, dynamic> &&
              uploadResponse['storageKey'] != null) {
            backStorageKey = uploadResponse['storageKey'] as String;
            backUploaded = true;
          } else {
            uploadFailureReason = (uploadFailureReason == null)
                ? 'Failed to upload back card image to storage.'
                : '$uploadFailureReason | Failed to upload back card image.';
          }
        } catch (e) {
          uploadFailureReason = (uploadFailureReason == null)
              ? 'Back image upload failed: $e'
              : '$uploadFailureReason | Back image upload failed: $e';
        }
      }

      if (!frontUploaded && !backUploaded) {
        modeString = 'TextAndLayout';
        uploadFailureReason ??= 'No images were uploaded for multimodal verification.';
      }
    }

    // 4. Construct request payload
    final observationsWithSide = _extractObservationsWithSide(frontOcr, backOcr);
    final ocrDtos = observationsWithSide.map((item) {
      final o = item.observation;
      return {
        'id': o.id,
        'text': o.text,
        'engine': o.engine,
        'cardSide': item.side,
        'lineIndex': o.lineIndex,
        'confidence': o.confidence,
        'region': o.region,
        'boundingBox': {
          'top': o.normalizedBoundingBox.top,
          'left': o.normalizedBoundingBox.left,
          'bottom': o.normalizedBoundingBox.bottom,
          'right': o.normalizedBoundingBox.right,
        },
      };
    }).toList();

    final localBaselineDto = {
      'fullName': cardData.fullName,
      'company': cardData.company,
      'jobTitle': cardData.jobTitle,
      'website': cardData.website,
      'address': cardData.address,
      'phoneNumbers': cardData.phoneNumbers.map((p) => p.number).toList(),
      'emailAddresses': cardData.emailAddresses.map((e) => e.email).toList(),
      'unclassifiedLines': cardData.unclassifiedLines,
    };

    final uncertainFields = <String>[];
    for (final entry in cardData.fieldConfidenceStates.entries) {
      if (entry.value == 'uncertain') {
        uncertainFields.add(entry.key);
      }
    }
    for (final entry in cardData.fieldEvidence.entries) {
      if (entry.value.verificationStatus == FieldVerificationStatus.reviewRequired &&
          !uncertainFields.contains(entry.key)) {
        uncertainFields.add(entry.key);
      }
    }

    final localEvidenceDto = cardData.fieldEvidence.map((k, v) => MapEntry(k, {
      'fieldName': v.fieldName,
      'originalOcrText': v.originalOcrText,
      'normalizedValue': v.normalizedValue,
      'sourceEngine': v.sourceEngine,
      'sourceObservationIds': v.sourceObservationIds,
      'ocrConfidence': v.ocrConfidence,
      'parserConfidence': v.parserConfidence,
      'verificationStatus': v.verificationStatus.name,
      'userApprovedValue': v.userApprovedValue,
      'verificationSource': v.verificationSource,
      'uncertaintyReason': v.uncertaintyReason,
      'cardSide': v.side.name,
    }));

    String? frontSha256;
    if (frontOcr.imagePath.isNotEmpty && File(frontOcr.imagePath).existsSync()) {
      try {
        final bytes = File(frontOcr.imagePath).readAsBytesSync();
        frontSha256 = sha256.convert(bytes).toString();
      } catch (_) {}
    }
    String? backSha256;
    if (backOcr != null && backOcr.imagePath.isNotEmpty && File(backOcr.imagePath).existsSync()) {
      try {
        final bytes = File(backOcr.imagePath).readAsBytesSync();
        backSha256 = sha256.convert(bytes).toString();
      } catch (_) {}
    }

    final requestBody = {
      'clientRequestId': clientRequestId,
      'scanContentHash': hash,
      'frontImageStorageKey': frontStorageKey,
      'backImageStorageKey': backStorageKey,
      'invocationReason': decision.primaryReason,
      'analysisMode': modeString,
      'frontImageSha256': frontSha256,
      'backImageSha256': backSha256,
      'paddleOcrRawText': (frontOcr.metadata['paddleOcrRawText'] as String?) ??
          (frontOcr.engineName.toLowerCase().contains('paddle') ? frontOcr.rawText : null),
      'mlKitRawText': (frontOcr.metadata['mlKitRawText'] as String?) ??
          (frontOcr.engineName.toLowerCase().contains('ml kit') ? frontOcr.rawText : null),
      'scanId': scanId ?? clientRequestId,
      'pipelineVersion': '2.0.0',
      'parserVersion': '5.0.0',
      'ocrModelVersion': 'PP-OCRv5',
      'geminiPromptVersion': '3.0.0',
      'uncertainFields': uncertainFields,
      'localFieldEvidence': localEvidenceDto,
      'ocrObservations': ocrDtos,
      'localBaseline': localBaselineDto,
    };

    try {
      geminiApiCallCount++;
      final response = await _apiClient.post(
        ApiConfig.analyzeBusinessCardEndpoint,
        body: requestBody,
        requiresAuth: true,
      );

      if (response is Map<String, dynamic>) {
        var result = CardAnalysisResult.fromJson(response);

        // Negative Constraint: If image upload failed, ensure we never claim visual verification!
        if (uploadFailureReason != null) {
          result = CardAnalysisResult(
            clientRequestId: result.clientRequestId,
            analysisCacheKey: result.analysisCacheKey,
            fullName: result.fullName,
            company: result.company,
            jobTitle: result.jobTitle,
            address: result.address,
            phoneNumbers: result.phoneNumbers,
            emailAddresses: result.emailAddresses,
            websites: result.websites,
            department: result.department,
            credentials: result.credentials,
            unclassifiedLines: result.unclassifiedLines,
            overallConfidence: result.overallConfidence,
            requiresManualReview: true,
            reviewWarnings: [
              ...result.reviewWarnings,
              '[Image Upload Failure] $uploadFailureReason',
            ],
            modelId: result.modelId,
            fromCache: result.fromCache,
            processingDurationMs: result.processingDurationMs,
            fallbackToLocalBaseline: result.fallbackToLocalBaseline,
            visualVerificationPerformed: false,
            frontImageVerified: false,
            backImageVerified: false,
            imageVerificationFailureReason: uploadFailureReason,
            fieldVerifications: result.fieldVerifications,
            geminiApiExecuted: result.geminiApiExecuted,
            geminiExecutionStatus: result.geminiExecutionStatus,
            frontImageReceived: result.frontImageReceived,
            backImageReceived: result.backImageReceived,
            promptTokens: result.promptTokens,
            candidateTokens: result.candidateTokens,
            totalTokens: result.totalTokens,
          );
        }

        _sessionCache[hash] = result;
        await _scanCacheManager.putGeminiCorrection(cacheKey: hash, result: result);
        return result;
      }

      return CardAnalysisResult(
        clientRequestId: clientRequestId,
        analysisCacheKey: '',
        fallbackToLocalBaseline: true,
        requiresManualReview: true,
        visualVerificationPerformed: false,
        imageVerificationFailureReason: 'Invalid response structure from analysis service.',
        reviewWarnings: const ['Invalid response structure from analysis service.'],
      );
    } catch (e) {
      // Non-blocking fallback: Never block the user if Gemini or network fails
      return CardAnalysisResult(
        clientRequestId: clientRequestId,
        analysisCacheKey: '',
        fallbackToLocalBaseline: true,
        requiresManualReview: true,
        visualVerificationPerformed: false,
        imageVerificationFailureReason: 'Gemini analysis call failed: $e',
        reviewWarnings: const ['Gemini analysis temporarily unavailable. Used on-device baseline.'],
      );
    }
  }

  List<OcrObservation> _extractObservations(OcrSideResult front, OcrSideResult? back) {
    return _extractObservationsWithSide(front, back)
        .map((e) => e.observation)
        .toList();
  }

  List<({OcrObservation observation, String side})> _extractObservationsWithSide(
    OcrSideResult front,
    OcrSideResult? back,
  ) {
    final list = <({OcrObservation observation, String side})>[];
    _extractSideObservations(front, 'front', list);
    if (back != null) {
      _extractSideObservations(back, 'back', list);
    }
    return list;
  }

  void _extractSideObservations(
    OcrSideResult side,
    String sideLabel,
    List<({OcrObservation observation, String side})> destination,
  ) {
    final rawObs = side.metadata['observations'];
    final beforeCount = destination.length;

    if (rawObs is List) {
      for (final item in rawObs) {
        if (item is OcrObservation) {
          destination.add((observation: item, side: sideLabel));
        } else if (item is Map<String, dynamic>) {
          try {
            destination.add((observation: OcrObservation.fromJson(item), side: sideLabel));
          } catch (_) {}
        } else if (item is Map) {
          try {
            destination.add((
              observation: OcrObservation.fromJson(Map<String, dynamic>.from(item)),
              side: sideLabel,
            ));
          } catch (_) {}
        }
      }
    }

    // Fallback: If metadata['observations'] was absent or empty, construct from lines
    if (destination.length == beforeCount && side.lines.isNotEmpty) {
      final engineName = side.metadata['selectedEngine'] as String? ?? 'On-Device OCR';
      for (final lineMeta in side.lines) {
        destination.add((
          observation: OcrObservation.fromLineMetadata(
            lineMeta,
            imageWidth: 1000.0,
            imageHeight: 1000.0,
            engine: engineName,
          ),
          side: sideLabel,
        ));
      }
    }
  }
}
