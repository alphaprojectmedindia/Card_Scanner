import 'package:flutter/foundation.dart';

/// Comprehensive structured diagnostic model capturing the complete 17-point audit trace
/// and the 5 explicit execution stages for every business card scan.
class ScanExecutionDiagnostics {
  final String scanId;
  final String? contactId;
  final bool exactCacheHit;
  final bool perceptualCacheAttempted;
  final bool perceptualCacheMatched;
  final String ocrEngineResults;
  final String parserOutputSummary;
  final String fieldConfidenceSummary;
  final List<String> triggeredDecisionRules;
  final String decisionOutcome;

  // Explicit 5-Stage Gemini Execution Tracking
  final bool stage1DecisionMade;
  final bool stage2BackendSubmitted;
  final bool stage3GeminiApiExecuted;
  final bool stage4GeminiResponseReceived;
  final bool stage5GeminiCorrectionAccepted;

  final String? imageUploadStatus;
  final String? analysisModeRequested;
  final String? modelNameReturned;
  final int? promptTokens;
  final int? candidateTokens;
  final int? totalTokens;
  final String? rawGeminiExtractions;
  final String? baselineVsGeminiDiff;
  final String finalAcceptedContactValues;

  const ScanExecutionDiagnostics({
    required this.scanId,
    this.contactId,
    this.exactCacheHit = false,
    this.perceptualCacheAttempted = false,
    this.perceptualCacheMatched = false,
    this.ocrEngineResults = '',
    this.parserOutputSummary = '',
    this.fieldConfidenceSummary = '',
    this.triggeredDecisionRules = const [],
    this.decisionOutcome = '',
    this.stage1DecisionMade = false,
    this.stage2BackendSubmitted = false,
    this.stage3GeminiApiExecuted = false,
    this.stage4GeminiResponseReceived = false,
    this.stage5GeminiCorrectionAccepted = false,
    this.imageUploadStatus,
    this.analysisModeRequested,
    this.modelNameReturned,
    this.promptTokens,
    this.candidateTokens,
    this.totalTokens,
    this.rawGeminiExtractions,
    this.baselineVsGeminiDiff,
    this.finalAcceptedContactValues = '',
  });

  /// Logs all 17 audit properties and the 5 distinct execution stages to console.
  void logToConsole() {
    debugPrint('================================================================');
    debugPrint('[Scan Execution Audit] Scan ID: $scanId | Contact ID: ${contactId ?? "N/A"}');
    debugPrint('  1. Exact Image Cache Hit: $exactCacheHit');
    debugPrint('  2. Perceptual Cache Match: attempted=$perceptualCacheAttempted, matched=$perceptualCacheMatched');
    debugPrint('  3. OCR Engine Results: $ocrEngineResults');
    debugPrint('  4. Parser Output: $parserOutputSummary');
    debugPrint('  5. Field Confidence: $fieldConfidenceSummary');
    debugPrint('  6. Triggered Decision Rules: ${triggeredDecisionRules.isEmpty ? "None" : triggeredDecisionRules.join("; ")}');
    debugPrint('  7. CardAnalysisDecision Outcome: $decisionOutcome');
    debugPrint('  -- 5-STAGE GEMINI EXECUTION TRACE --');
    debugPrint('  Stage 1 (Gemini Decision Made): $stage1DecisionMade');
    debugPrint('  Stage 2 (Backend Request Submitted): $stage2BackendSubmitted');
    debugPrint('  Stage 3 (Gemini API Actually Executed by Backend): $stage3GeminiApiExecuted');
    debugPrint('  Stage 4 (Gemini Response Received): $stage4GeminiResponseReceived');
    debugPrint('  Stage 5 (Gemini Correction Accepted): $stage5GeminiCorrectionAccepted');
    debugPrint('  -----------------------------------');
    if (imageUploadStatus != null) debugPrint('  8. Front/Back Image Upload Status: $imageUploadStatus');
    if (analysisModeRequested != null) debugPrint('  9. Analysis Mode Requested: $analysisModeRequested');
    if (modelNameReturned != null && modelNameReturned!.isNotEmpty) debugPrint('  10. Model Returned: $modelNameReturned');
    if (promptTokens != null || candidateTokens != null || totalTokens != null) {
      debugPrint('  11. Token Counts: prompt=$promptTokens, candidate=$candidateTokens, total=$totalTokens');
    }
    if (rawGeminiExtractions != null && rawGeminiExtractions!.isNotEmpty) {
      debugPrint('  12. Raw Gemini Field Extractions: $rawGeminiExtractions');
    }
    if (baselineVsGeminiDiff != null && baselineVsGeminiDiff!.isNotEmpty) {
      debugPrint('  13. Baseline vs Gemini Diff: $baselineVsGeminiDiff');
    }
    debugPrint('  14. Final Accepted Contact Values: $finalAcceptedContactValues');
    debugPrint('================================================================');
  }

  /// Formats a concise summary string suitable for persistence in parsing notes.
  String toAuditSummary() {
    final sb = StringBuffer();
    sb.writeln('[Audit] ScanId=$scanId | Decision=$stage1DecisionMade | BackendSubmitted=$stage2BackendSubmitted | ApiExecuted=$stage3GeminiApiExecuted | ResponseRecv=$stage4GeminiResponseReceived | CorrectionAccepted=$stage5GeminiCorrectionAccepted');
    if (triggeredDecisionRules.isNotEmpty) {
      sb.writeln('[Audit] Triggers: ${triggeredDecisionRules.join(", ")}');
    }
    if (baselineVsGeminiDiff != null && baselineVsGeminiDiff!.isNotEmpty) {
      sb.writeln('[Audit] Diff: $baselineVsGeminiDiff');
    }
    return sb.toString().trim();
  }
}

