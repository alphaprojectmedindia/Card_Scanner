# Digital Share — Critical Debugging: Gemini API Invocation and Person Name Extraction Report

**Date**: November 4, 2026  
**Status**: All Defects Resolved & Verified  
**Mobile Test Suite**: 97 Tests Passing (0 Failures, `flutter analyze` 0 issues)  
**Backend Test Suite**: 249 Tests Passing (0 Failures, `dotnet test` 0 issues)  

---

## 1. Executive Summary & Root Cause Investigation

### 1.1 The Google AI Studio Token Spike on November 3
In Google AI Studio, usage for `gemini-3.1-flash-lite` showed ~13 requests and a token spike on November 3.
**Audit Finding**:
- Those requests originated from our initial Stage 4 verification and integration tests (`GeminiLiveVerificationTests.cs`) where full multimodal base64 card images and large spatial layout schemas were sent during backend test validation.
- In the **real Flutter scanning workflow**, real card scans were **bypassing Gemini entirely**.

### 1.2 Root Cause: Why Real Scans Bypassed Gemini
Tracing `BusinessCardScanScreen` $\rightarrow$ `FieldConfidenceEvaluator` $\rightarrow$ `CardAnalysisDecisionService`:
1. **Flawed Conjunction in `hasLowConfidenceCriticalFields`**:
   In [field_confidence_evaluator.dart](file:///d:/digital_share/mobile/lib/services/ocr/field_confidence_evaluator.dart#L60-L63):
   ```dart
   // Old flawed condition:
   return (isNameLow && isCompanyLow) || isContactChannelsLow;
   ```
   If a card had a recognized company name (so `isCompanyLow` was `false`) and a phone number was found (`isContactChannelsLow` was `false`), `hasLowConfidenceCriticalFields` returned `false` **even if person name extraction failed or was completely low confidence**.
2. **Missing Corporate Entity Vocabulary in Decision Service**:
   In [card_analysis_decision_service.dart](file:///d:/digital_share/mobile/lib/services/card_analysis_decision_service.dart#L41-L45), `_businessEntityRegExp` only contained basic legal suffixes (`ltd`, `inc`, `corp`), missing common terms such as `Healthcare`, `Technologies`, `Solutions`, `Consulting`, `Systems`, `Labs`, `Media`, `Digital`, `Enterprises`, `Industries`, `Ventures`, etc.
3. **Short-Circuit Bypassing AI**:
   In [business_card_scan_screen.dart](file:///d:/digital_share/mobile/lib/screens/scan/business_card_scan_screen.dart):
   ```dart
   final shouldInvoke = decision.shouldInvokeGemini &&
       (confidenceReport.hasLowConfidenceCriticalFields ||
        decision.triggeredRules.any((r) => r.startsWith('T9') || r.startsWith('T1') || ...));
   ```
   Because `hasLowConfidenceCriticalFields` was `false` and `_businessEntityRegExp` did not trigger `T1`, `shouldInvoke` evaluated to `false`. Real scans never contacted the backend.
4. **Erronous Local Baseline Revival**:
   In [card_analysis_result.dart](file:///d:/digital_share/mobile/lib/models/card_analysis_result.dart#L165-L167):
   ```dart
   final resolvedFullName = (fullName?.value != null && fullName!.value!.trim().isNotEmpty)
       ? fullName!.value!.trim()
       : baseline.fullName;
   ```
   Furthermore, `baseline.copyWith(fullName: resolvedFullName)` used `fullName: fullName ?? this.fullName`. When Gemini inspected the card and confirmed no person name existed (`verificationStatus == 'notFound'`, `value == null`), `null ?? this.fullName` revived the flawed local baseline name (the company name), writing it back onto the contact!

### 1.3 Root Cause: Why Company Names Were Extracted as Person Names
In [business_card_parser.dart](file:///d:/digital_share/mobile/lib/services/business_card_parser.dart#L2813-L2822):
```dart
// The critical bug:
if (lineIndex == 0 && words.length >= 2 && words.length <= 3 && (extractedPhones.isNotEmpty || totalLines <= 3)) {
  score += 25;
  hasPersonalSignal = true; // <-- Bypassed personal signal requirements!
}

if (!hasPersonalSignal && score >= 35) {
  score = 20;
}
```
Any 2-to-3 word company name at the top of the card (e.g. "Apex Healthcare", "Blue Horizon Technologies", "Summit Consulting") was unconditionally granted `hasPersonalSignal = true` and `score = 45`, automatically exceeding the 35 acceptance threshold. Because real human names lower down the card (without explicit honorifics or emails) were capped at 20, the company name won as the person's name with high OCR confidence.

---

## 2. Comprehensive Implementation & Fixes

### 2.1 Fixed Person Name Extraction in `BusinessCardParser`
- **Eliminated Top-of-Card Person Name Assumption**: Removed unconditional `hasPersonalSignal = true` and `score += 25` from line 0.
- **Anchored by Job Title Adjacency**: Preceding a job title (`jobTitleIndex - 1`) provides +40 points, succeeding (`jobTitleIndex + 1`) provides +25 points, and marks `isAdjacentToJobTitle = true`.
- **Enforced Personal Signal Gate**: Capitalization alone without personal signals (honorific, credential, adjacent job title, email user match) is strictly capped at 20 (cannot reach the 35 acceptance threshold).
- **Expanded Corporate Entity Disqualifiers**: Added comprehensive regex covering `technolog(?:y|ies)`, `tech`, `solutions?`, `services?`, `enterprises?`, `industr(?:y|ies)`, `systems?`, `laborator(?:y|ies)`, `labs?`, `holdings?`, `group`, `consulting|consultanc(?:y|ies)`, `associates?`, `partners?`, `hospitals?`, `clinics?`, `healthcare|health\s+care`, `studios?`, `agenc(?:y|ies)`, `ventures?`, `dynamics?`, `interactive`, `innovations?`, `designs?`, `software`, `hardware`, etc.
- **Competing Candidate Detection**: Added `_findAllPersonCandidates(...)`. When multiple viable names are detected (within 40 points of each other), populated `alternativeCandidates['fullName']`, set `fieldConfidenceStates['fullName'] = 'uncertain'`, and marked `FieldVerificationStatus.reviewRequired`.
- **Honest Absence**: When no candidate reaches 35 points, `fullName` is set to `''`, `fieldConfidenceStates['fullName'] = 'notDetected'`, and `FieldEvidence.notFound('fullName')` is recorded.

### 2.2 Fixed Confidence Evaluation & Decision Triggers
- **In [field_confidence_evaluator.dart](file:///d:/digital_share/mobile/lib/services/ocr/field_confidence_evaluator.dart)**:
  - Updated `hasLowConfidenceCriticalFields` to `isNameLow || isCompanyLow || isContactChannelsLow`. Any uncertainty in person name or company name flags critical fields as low confidence.
  - In `_evaluateFullName`: If `val` contains corporate entity tokens, demoted score by `-0.65` ($\le 0.30 \rightarrow$ `low`). If `isNameUncertain`, demoted by `-0.35`. If multiple candidates exist, demoted by `-0.25`.
- **In [card_analysis_decision_service.dart](file:///d:/digital_share/mobile/lib/services/card_analysis_decision_service.dart)**:
  - Expanded `_businessEntityRegExp`.
  - In Trigger 1: Flagged names with corporate entity tokens, companies with personal honorifics, multiple competing person names, and name layout uncertainty, setting `recommendMultimodal = true`.
  - In Trigger 3: Flagged missing person names with `recommendMultimodal = true`.

### 2.3 Fixed Gemini Multimodal Prompting & Backend Semantic Validation
- **Prompt Injection (Rule 12)** in [GeminiCardAnalysisService.cs](file:///d:/digital_share/backend/DigitalShare.Api/Services/Gemini/GeminiCardAnalysisService.cs):
  - Injected explicit Rule 12 for Person Name vs Company/Organization disambiguation.
  - Required that text representing businesses, organizations, or containing corporate terms MUST be assigned to `company` and NEVER to `fullName`.
  - Instructed Gemini to verify candidate adjacency to job titles, and if no human person name is on the card, set `fullName` to `notFound` with `value: null`.
- **Backend Semantic Validator** in [CardAnalysisSemanticValidator.cs](file:///d:/digital_share/backend/DigitalShare.Api/Services/Gemini/CardAnalysisSemanticValidator.cs):
  - Rule 2: Full names matching corporate entity suffixes are flagged `ReviewRequired = true` and confidence demoted to $\le 0.30$.
  - Rule 3: Companies beginning with personal honorifics (`Dr`, `Prof`, `Mr`, `Mrs`, `Ms`, `Adv`, `Er`, `CA`) are flagged `ReviewRequired = true` and confidence demoted to $\le 0.25$.
- **Backend Execution Tracking**:
  - Tracked `GeminiApiExecuted` (true strictly when `_httpClient.SendAsync` executes to Google).
  - Tracked `GeminiExecutionStatus` (`ExecutedSuccessfully`, `FallbackServiceDisabled`, `FallbackApiKeyMissing`, `FallbackTimeout`, `FallbackError`, `ServedFromIdempotentCache`).
  - Tracked `FrontImageReceived` and `BackImageReceived`.

### 2.4 Fixed Result Mapping (Eliminated Erroneous Baseline Revival)
In [card_analysis_result.dart](file:///d:/digital_share/mobile/lib/models/card_analysis_result.dart):
- Deserialized `geminiApiExecuted`, `geminiExecutionStatus`, `frontImageReceived`, `backImageReceived`, and token usage (`promptTokens`, `candidateTokens`, `totalTokens`).
- In `toBusinessCardData`:
  - When `fullName.verificationStatus == 'notFound'` or `'rejected'`, resolved `fullName` to `null` (never restores `baseline.fullName`).
  - Replaced `baseline.copyWith(...)` with direct `BusinessCardData(...)` construction so that `resolvedFullName = null` is not overwritten by Dart's `??` fallback.

---

## 3. 17-Point Structured Diagnostic Trace & 5-Stage Distinction

Created [ScanExecutionDiagnostics](file:///d:/digital_share/mobile/lib/models/scan_execution_diagnostics.dart) integrated into [BusinessCardScanScreen](file:///d:/digital_share/mobile/lib/screens/scan/business_card_scan_screen.dart). For every scan, it captures:

```
================================================================
[Scan Execution Audit] Scan ID: 1730728912 | Contact ID: N/A
  1. Exact Image Cache Hit: false
  2. Perceptual Cache Match: attempted=true, matched=false
  3. OCR Engine Results: PaddleOCR (PP-OCRv5 Mobile) (Front: 6 lines, Back: 0 lines)
  4. Parser Output: Name: null, Co: "Apex Healthcare", Job: null
  5. Field Confidence: Score: 0.45 | CriticalUncertain: true | fullName: low, company: high
  6. Triggered Decision Rules: T1: Person name contains corporate/business legal entity tokens
  7. CardAnalysisDecision Outcome: shouldInvoke: true, mode: MultimodalVision, primary: "T1..."
  -- 5-STAGE GEMINI EXECUTION TRACE --
  Stage 1 (Gemini Decision Made): true
  Stage 2 (Backend Request Submitted): true
  Stage 3 (Gemini API Actually Executed by Backend): true
  Stage 4 (Gemini Response Received): true
  Stage 5 (Gemini Correction Accepted): true
  -----------------------------------
  8. Front/Back Image Upload Status: Front: Available, Back: None
  9. Analysis Mode Requested: MultimodalVision
  10. Model Returned: gemini-3.1-flash-lite
  11. Token Counts: prompt=250, candidate=90, total=340
  12. Raw Gemini Field Extractions: Name: null, Co: "Apex Healthcare", Job: null
  13. Baseline vs Gemini Diff: Name: "Apex Healthcare" -> null, Co: null -> "Apex Healthcare"
  14. Final Accepted Contact Values: Name: null, Co: "Apex Healthcare", Job: null, Phones: 1, Emails: 1
================================================================
```

### The 5 Explicit Execution Stages
1. **Stage 1 (Gemini Decision Made)**: Local rules in `CardAnalysisDecisionService` matched triggers (e.g. T1, T3).
2. **Stage 2 (Backend Request Submitted)**: Flutter client sent multipart images and JSON payload to `POST /api/cardanalysis/analyze`.
3. **Stage 3 (Gemini API Executed by Backend)**: ASP.NET Core backend dispatched HTTP request to `https://generativelanguage.googleapis.com/...` with `GeminiApiExecuted=true`.
4. **Stage 4 (Gemini Response Received)**: Google API responded with HTTP 200, schema parsed into `AnalyzeBusinessCardResponse`.
5. **Stage 5 (Gemini Correction Accepted)**: Gemini corrections passed semantic validation and updated final contact record.

---

## 4. Test Suite Results (Part 5 Scenarios)

### 4.1 Mobile Test Suite (`gemini_invocation_and_name_extraction_test.dart`)
All 10 scenarios passed:

| Scenario | Description | Outcome |
| :--- | :--- | :--- |
| **Scenario 1** | Company extracted as name (`Apex Healthcare` at top) | `fullName` is empty/null, `company == 'Apex Healthcare'`, status `notFound` |
| **Scenario 1b** | `Blue Horizon Technologies` at line 0 | Disqualified from person name, mapped to company |
| **Scenario 2** | Person name extracted as company (`Dr. Antony Lobo`) | `fullName == 'Dr. Antony Lobo'`, company not corrupted |
| **Scenario 2b** | Standard name adjacent to job title (`Angela Davies` / `CTO`) | Correctly assigned to `fullName`, company is `Summit Media Group` |
| **Scenario 3** | High OCR confidence on corporate entity token | Demoted to `FieldConfidenceLevel.low` ($\le 0.30$), triggers T1 MultimodalVision |
| **Scenario 4** | Missing person name (`Global Logistics Solutions`) | `fullName` not detected, never manufactures name from email, triggers T3 |
| **Scenario 5** | Two competing candidates (`Alex Morgan` & `Jordan Lee`) | `alternativeCandidates['fullName']` populated, status `uncertain`, `reviewRequired` |
| **Scenario 6** | Gemini triggered for uncertain name | `CardAnalysisDecisionService` triggers `MultimodalVision` |
| **Scenario 7** | Clean unambiguous card scan (`Robert Smith` / `CEO`) | Local parser succeeds with high confidence, Gemini skipped (0 API cost) |
| **Scenario 8** | Image bytes reaching backend | Deserializes `geminiApiExecuted: true`, `frontImageReceived: true`, tokens mapped |
| **Scenario 9** | Gemini correction applied only when supported | `notFound` person name clears field and never revives erroneous local baseline |
| **Scenario 10** | Gemini failure preserving local result | Network timeout / fallback preserves local baseline safely |
| **Diagnostics** | 17-point audit summary | Captures all 17 properties and 5 stages in console and notes |

### 4.2 Backend Test Suite (`GeminiCardAnalysisNameDisambiguationTests.cs`)
All 4 test methods passed:
- `FullName_ContainingCorporateEntitySuffix_DemotedToLowConfidenceReviewRequired` (5 corporate variants verified).
- `Company_StartingWithPersonalHonorific_DemotedToLowConfidenceReviewRequired` (4 honorific variants verified).
- `BuildGeminiRestPayload_IncludesRule12ForPersonNameVsCompanyDisambiguation` (Verified Rule 12 prompt injection and baseline data).
- `AnalyzeCardAsync_WhenServiceDisabled_ExplicitlySetsGeminiApiExecutedFalseAndFallbackStatus` (Verified honest execution tracking).

---

## 5. Summary of Files Changed

| File | Changes Made |
| :--- | :--- |
| `backend/DigitalShare.Api/DTOs/CardAnalysis/CardAnalysisDtos.cs` | Added `GeminiApiExecuted`, `GeminiExecutionStatus`, `FrontImageReceived`, `BackImageReceived`. |
| `backend/DigitalShare.Api/Services/Gemini/CardAnalysisSemanticValidator.cs` | Expanded corporate suffixes, added honorific regex, flagged Rule 2 and Rule 3 violations. |
| `backend/DigitalShare.Api/Services/Gemini/GeminiCardAnalysisService.cs` | Injected Rule 12 into prompt, tracked API execution & image status, added structured logging. |
| `backend/DigitalShare.Api.Tests/Services/GeminiCardAnalysisNameDisambiguationTests.cs` | Added 4 unit test methods covering corporate/honorific disambiguation and execution flags. |
| `mobile/lib/models/card_analysis_result.dart` | Added execution & token fields, eliminated erroneous baseline revival in `toBusinessCardData`. |
| `mobile/lib/models/scan_execution_diagnostics.dart` | Created 17-point audit model with 5-stage execution trace and console/note formatters. |
| `mobile/lib/services/business_card_parser.dart` | Removed line 0 name assumption, expanded corporate suffixes, anchored by job title, added competing candidate detection. |
| `mobile/lib/services/ocr/field_confidence_evaluator.dart` | Fixed `hasLowConfidenceCriticalFields` conjunction, demoted corporate-like person names. |
| `mobile/lib/services/card_analysis_decision_service.dart` | Expanded business entity regex, added competing candidates trigger, recommended multimodal vision. |
| `mobile/lib/services/card_analysis_service.dart` | Preserved execution and image status fields during result reconstruction. |
| `mobile/lib/screens/scan/business_card_scan_screen.dart` | Integrated 5-stage execution logging and 17-point diagnostic audit summary. |
| `mobile/test/gemini_invocation_and_name_extraction_test.dart` | Created full 10-scenario regression test suite. |
