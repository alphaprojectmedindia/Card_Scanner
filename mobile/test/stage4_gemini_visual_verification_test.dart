import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/business_card_data.dart';
import 'package:digital_share/models/business_card_email.dart';
import 'package:digital_share/models/business_card_phone.dart';
import 'package:digital_share/models/card_analysis_result.dart';
import 'package:digital_share/models/field_evidence.dart';
import 'package:digital_share/models/ocr_side_result.dart';
import 'package:digital_share/services/api_client.dart';
import 'package:digital_share/services/card_analysis_decision_service.dart';
import 'package:digital_share/services/card_analysis_service.dart';
import 'package:digital_share/services/storage/local_scan_cache_manager.dart';

/// Test double extending [ApiClient] for deterministic Stage 4 mocking without real network calls.
class FakeCardAnalysisApiClient extends ApiClient {
  final Map<String, dynamic>? mockAnalysisResponse;
  final String? mockStorageKeyPrefix;
  final bool shouldFailImageUpload;
  final bool shouldFailAnalysisCall;

  final List<Map<String, dynamic>> recordedMultipartUploads = [];
  final List<Map<String, dynamic>> recordedAnalysisPosts = [];

  FakeCardAnalysisApiClient({
    this.mockAnalysisResponse,
    this.mockStorageKeyPrefix = 'scans/test_',
    this.shouldFailImageUpload = false,
    this.shouldFailAnalysisCall = false,
  });

  @override
  Future<dynamic> postMultipart(
    String url, {
    required String fieldName,
    String? filePath,
    List<int>? fileBytes,
    String? filename,
    String? contentType,
    Map<String, String>? fields,
    bool requiresAuth = true,
  }) async {
    recordedMultipartUploads.add({
      'endpoint': url,
      'fieldName': fieldName,
      'filePath': filePath,
      'fields': fields,
    });

    if (shouldFailImageUpload) {
      throw ApiException('Simulated storage upload network failure', statusCode: 503);
    }

    final side = fields?['cardSide'] ?? 'front';
    return {
      'storageKey': '$mockStorageKeyPrefix${side}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      'cardSide': side,
      'fileSizeBytes': 10240,
    };
  }

  @override
  Future<dynamic> post(
    String url, {
    dynamic body,
    bool requiresAuth = false,
    Duration? timeout,
  }) async {
    recordedAnalysisPosts.add({
      'endpoint': url,
      'body': body,
    });

    if (shouldFailAnalysisCall) {
      throw ApiException('Simulated Gemini backend analysis error', statusCode: 500);
    }

    return mockAnalysisResponse ??
        {
          'clientRequestId': body?['clientRequestId'] ?? 'req_test',
          'analysisCacheKey': 'cache_test_key',
          'modelId': 'gemini-3.8-flash',
          'visualVerificationPerformed': true,
          'frontImageVerified': true,
          'backImageVerified': true,
          'overallConfidence': 0.95,
          'requiresManualReview': false,
          'reviewWarnings': <String>[],
          'fullName': {
            'value': 'Dr. Marcus Vance',
            'confidence': 0.96,
            'isVisuallyVerified': true,
            'verificationStatus': 'verified',
            'sourceObservationIds': ['obs_1'],
          },
          'company': {
            'value': 'Apex Biosystems Inc',
            'confidence': 0.97,
            'isVisuallyVerified': true,
            'verificationStatus': 'verified',
            'sourceObservationIds': ['obs_2'],
          },
          'jobTitle': {
            'value': 'VP of Research',
            'confidence': 0.94,
            'isVisuallyVerified': true,
            'verificationStatus': 'verified',
            'sourceObservationIds': ['obs_3'],
          },
          'address': {
            'fullAddress': '500 Innovation Blvd, Suite 200, Boston, MA 02110',
            'confidence': 0.92,
            'isVisuallyVerified': true,
            'verificationStatus': 'verified',
            'sourceObservationIds': ['obs_4'],
          },
          'phoneNumbers': [
            {
              'number': '+1 617 555 0199',
              'label': 'Work',
              'confidence': 0.98,
              'isVisuallyVerified': true,
              'verificationStatus': 'verified',
              'sourceObservationIds': ['obs_5'],
            }
          ],
          'emailAddresses': [
            {
              'email': 'm.vance@apexbio.com',
              'label': 'Work',
              'confidence': 0.99,
              'isVisuallyVerified': true,
              'verificationStatus': 'verified',
              'sourceObservationIds': ['obs_6'],
            }
          ],
          'websites': [
            {
              'url': 'www.apexbio.com',
              'confidence': 0.97,
              'isVisuallyVerified': true,
              'verificationStatus': 'verified',
              'sourceObservationIds': ['obs_7'],
            }
          ],
        };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File testFrontImage;
  late File testBackImage;

  setUp(() async {
    CardAnalysisService.clearSessionCache();
    tempDir = await Directory.systemTemp.createTemp('ds_stage4_test_');
    testFrontImage = File('${tempDir.path}/front_card.jpg');
    await testFrontImage.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]); // JPEG magic header
    testBackImage = File('${tempDir.path}/back_card.jpg');
    await testBackImage.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Stage 4 — Gemini Multimodal Request Building & Uploads', () {
    test('Uploads both front and back card images before invoking Gemini multimodal vision', () async {
      final fakeApi = FakeCardAnalysisApiClient();
      final service = CardAnalysisService(
        apiClient: fakeApi,
        scanCacheManager: LocalScanCacheManager(cacheDirectory: tempDir),
        isOnlineCheck: () => true,
      );

      final cardData = BusinessCardData(
        fullName: 'Marcus Vance',
        company: 'Apex Biosystems',
        fieldConfidenceStates: const {'fullName': 'uncertain'},
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Marcvs Vance',
            normalizedValue: 'Marcus Vance',
            sourceEngine: 'PaddleOCR',
            verificationStatus: FieldVerificationStatus.reviewRequired,
            uncertaintyReason: 'Stage 3 OCR glyph uncertainty',
          ),
        },
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: testFrontImage.path,
        rawText: 'Marcus Vance\nApex Biosystems',
      );

      final backOcr = OcrSideResult.fromText(
        side: CardSide.back,
        imagePath: testBackImage.path,
        rawText: '500 Innovation Blvd\nwww.apexbio.com',
      );

      final result = await service.analyzeIfTriggered(
        cardData: cardData,
        frontOcr: frontOcr,
        backOcr: backOcr,
        precomputedDecision: const CardAnalysisDecision(
          shouldInvokeGemini: true,
          mode: AnalysisMode.multimodalVision,
          primaryReason: 'T9: Unresolved uncertain fields from Stage 3',
        ),
      );

      expect(result, isNotNull);
      expect(fakeApi.recordedMultipartUploads.length, equals(2));
      expect(fakeApi.recordedMultipartUploads[0]['fields']['cardSide'], equals('front'));
      expect(fakeApi.recordedMultipartUploads[1]['fields']['cardSide'], equals('back'));

      expect(fakeApi.recordedAnalysisPosts.length, equals(1));
      final postBody = fakeApi.recordedAnalysisPosts[0]['body'] as Map<String, dynamic>;
      expect(postBody['analysisMode'], equals('MultimodalVision'));
      expect(postBody['frontImageStorageKey'], contains('front'));
      expect(postBody['backImageStorageKey'], contains('back'));
      expect(postBody['uncertainFields'], contains('fullName'));
      expect(postBody['localFieldEvidence'], isNotNull);
    });

    test('Uploads front image only for single-sided card', () async {
      final fakeApi = FakeCardAnalysisApiClient();
      final service = CardAnalysisService(
        apiClient: fakeApi,
        scanCacheManager: LocalScanCacheManager(cacheDirectory: tempDir),
        isOnlineCheck: () => true,
      );

      final cardData = BusinessCardData(
        fullName: 'Jane Doe',
        company: 'TechCorp',
        fieldConfidenceStates: const {'company': 'uncertain'},
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: testFrontImage.path,
        rawText: 'Jane Doe\nTechCorp',
      );

      await service.analyzeIfTriggered(
        cardData: cardData,
        frontOcr: frontOcr,
        backOcr: null,
        precomputedDecision: const CardAnalysisDecision(
          shouldInvokeGemini: true,
          mode: AnalysisMode.multimodalVision,
          primaryReason: 'T1: Company uncertain',
        ),
      );

      expect(fakeApi.recordedMultipartUploads.length, equals(1));
      expect(fakeApi.recordedMultipartUploads[0]['fields']['cardSide'], equals('front'));
      final postBody = fakeApi.recordedAnalysisPosts[0]['body'] as Map<String, dynamic>;
      expect(postBody['backImageStorageKey'], isNull);
    });
  });

  group('Stage 4 — Image Upload Failure & Non-Visual Verification Negative Constraints', () {
    test('Image upload failure explicitly sets visualVerificationPerformed to false and records failure', () async {
      final fakeApi = FakeCardAnalysisApiClient(shouldFailImageUpload: true);
      final service = CardAnalysisService(
        apiClient: fakeApi,
        scanCacheManager: LocalScanCacheManager(cacheDirectory: tempDir),
        isOnlineCheck: () => true,
      );

      final cardData = BusinessCardData(
        fullName: 'Uncertain User',
        company: 'Unknown Co',
        fieldConfidenceStates: const {'fullName': 'uncertain'},
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: testFrontImage.path,
        rawText: 'Uncertain User',
      );

      final result = await service.analyzeIfTriggered(
        cardData: cardData,
        frontOcr: frontOcr,
        backOcr: null,
        precomputedDecision: const CardAnalysisDecision(
          shouldInvokeGemini: true,
          mode: AnalysisMode.multimodalVision,
          primaryReason: 'Stage 3 uncertain field',
        ),
      );

      expect(result, isNotNull);
      // Negative constraint: System must NEVER falsely claim visual verification when image upload fails!
      expect(result!.visualVerificationPerformed, isFalse);
      expect(result.frontImageVerified, isFalse);
      expect(result.backImageVerified, isFalse);
      expect(result.imageVerificationFailureReason, isNotNull);
      expect(result.imageVerificationFailureReason, contains('Failed to upload'));
      expect(result.requiresManualReview, isTrue);
      expect(result.reviewWarnings.any((w) => w.contains('[Image Upload Failure]')), isTrue);
    });

    test('Text-only mode never produces verified status from Gemini in toBusinessCardData', () {
      final baseline = BusinessCardData(
        fullName: 'Marcus Vance',
        company: 'Apex Bio',
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Marcus Vance',
            normalizedValue: 'Marcus Vance',
            sourceEngine: 'PaddleOCR',
            verificationStatus: FieldVerificationStatus.probable,
          ),
        },
      );

      const textOnlyAiResult = CardAnalysisResult(
        clientRequestId: 'req_text_only',
        analysisCacheKey: 'cache_text_only',
        visualVerificationPerformed: false, // Text-only mode: NO image inspected
        fullName: ExtractedField(
          value: 'Marcus Vance',
          confidence: 0.99,
          isVisuallyVerified: false,
          verificationStatus: 'verified', // Backend falsely claimed verified
          sourceObservationIds: ['obs_1'],
        ),
      );

      final merged = textOnlyAiResult.toBusinessCardData(baseline);

      // Negative constraint: A text-only result must NEVER be marked as verified!
      final fullNameEv = merged.fieldEvidence['fullName'];
      expect(fullNameEv, isNotNull);
      expect(fullNameEv!.verificationStatus, isNot(equals(FieldVerificationStatus.verified)));
      expect(fullNameEv.verificationStatus, equals(FieldVerificationStatus.probable));
      expect(fullNameEv.verificationSource, equals('geminiAiTextVerification'));
    });
  });

  group('Stage 4 — Evidence Grounding & Visual Verification Ground Truth', () {
    test('Successful visual verification promotes field evidence to verified status with ground truth source', () {
      final baseline = BusinessCardData(
        fullName: 'Marcus Vance',
        company: 'Apex Biosystems Inc',
        jobTitle: 'VP Research',
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Marcvs Vance',
            normalizedValue: 'Marcus Vance',
            sourceEngine: 'PaddleOCR',
            verificationStatus: FieldVerificationStatus.reviewRequired,
          ),
          'company': FieldEvidence(
            fieldName: 'company',
            originalOcrText: 'Apex Biosystems',
            normalizedValue: 'Apex Biosystems',
            sourceEngine: 'Google ML Kit',
            verificationStatus: FieldVerificationStatus.probable,
          ),
        },
      );

      const verifiedAiResult = CardAnalysisResult(
        clientRequestId: 'req_vis_success',
        analysisCacheKey: 'cache_vis_success',
        visualVerificationPerformed: true,
        frontImageVerified: true,
        backImageVerified: true,
        fullName: ExtractedField(
          value: 'Marcus Vance',
          confidence: 0.98,
          isVisuallyVerified: true,
          verificationStatus: 'verified',
          visualEvidenceDescription: 'Clean visible font in top center header',
          sourceObservationIds: ['obs_1'],
        ),
        company: ExtractedField(
          value: 'Apex Biosystems Inc',
          confidence: 0.99,
          isVisuallyVerified: true,
          verificationStatus: 'verified',
          visualEvidenceDescription: 'Readable corporate logo and text',
          sourceObservationIds: ['obs_2'],
        ),
      );

      final merged = verifiedAiResult.toBusinessCardData(baseline);

      final nameEv = merged.fieldEvidence['fullName'];
      expect(nameEv, isNotNull);
      expect(nameEv!.verificationStatus, equals(FieldVerificationStatus.verified));
      expect(nameEv.verificationSource, equals('geminiAiVisualVerification'));
      expect(nameEv.verifiedAt, isNotNull);

      final compEv = merged.fieldEvidence['company'];
      expect(compEv, isNotNull);
      expect(compEv!.verificationStatus, equals(FieldVerificationStatus.verified));
      expect(compEv.verificationSource, equals('geminiAiVisualVerification'));
    });

    test('Unreadable or blurry fields are flagged reviewRequired with genuine readability false', () {
      final baseline = BusinessCardData(
        fullName: 'Marcus Vance',
        company: 'Apex Bio',
      );

      const blurredAiResult = CardAnalysisResult(
        clientRequestId: 'req_vis_blur',
        analysisCacheKey: 'cache_vis_blur',
        visualVerificationPerformed: true,
        fullName: ExtractedField(
          value: 'M???? Vance',
          confidence: 0.40,
          isGenuinelyReadable: false,
          isVisuallyVerified: false,
          reviewRequired: true,
          correctionReason: 'Severe ink smudge over first name',
          sourceObservationIds: ['obs_1'],
        ),
      );

      final merged = blurredAiResult.toBusinessCardData(baseline);
      final nameEv = merged.fieldEvidence['fullName'];
      expect(nameEv, isNotNull);
      expect(nameEv!.verificationStatus, equals(FieldVerificationStatus.reviewRequired));
      expect(nameEv.uncertaintyReason, contains('Severe ink smudge'));
    });
  });

  group('Stage 4 — User-Approved Value Protection Negative Constraint', () {
    test('Gemini visual verification NEVER overwrites a user-approved correction', () {
      final baseline = BusinessCardData(
        fullName: 'User Confirmed Name',
        company: 'Apex Biosystems',
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Muddled Name',
            normalizedValue: 'Muddled Name',
            userApprovedValue: 'User Confirmed Name', // Manually edited by user
            sourceEngine: 'UserConfirmed',
            verificationStatus: FieldVerificationStatus.verified,
            verificationSource: 'userManualEdit',
          ),
        },
      );

      const aiAttemptedOverride = CardAnalysisResult(
        clientRequestId: 'req_override',
        analysisCacheKey: 'cache_override',
        visualVerificationPerformed: true,
        fullName: ExtractedField(
          value: 'AI Proposed Marcus Vance', // Gemini thinks it knows better
          confidence: 0.99,
          isVisuallyVerified: true,
          verificationStatus: 'verified',
        ),
      );

      final merged = aiAttemptedOverride.toBusinessCardData(baseline);

      // Negative constraint: User edit is 100% authoritative!
      final nameEv = merged.fieldEvidence['fullName'];
      expect(nameEv, isNotNull);
      expect(nameEv!.userApprovedValue, equals('User Confirmed Name'));
      expect(nameEv.verificationSource, equals('userManualEdit'));
    });
  });

  group('Stage 4 — Absent Fields and Decision Gating Negative Constraints', () {
    test('Absent fields are marked notFound and never hallucinated', () {
      final baseline = BusinessCardData(
        fullName: 'Jane Doe',
        company: null, // Card has no company
      );

      const aiResult = CardAnalysisResult(
        clientRequestId: 'req_absent',
        analysisCacheKey: 'cache_absent',
        visualVerificationPerformed: true,
        company: ExtractedField(
          value: null, // Absent on card
          confidence: 0.0,
          verificationStatus: 'notFound',
        ),
      );

      final merged = aiResult.toBusinessCardData(baseline);
      final compEv = merged.fieldEvidence['company'];
      expect(compEv, isNotNull);
      expect(compEv!.verificationStatus, equals(FieldVerificationStatus.notFound));
    });

    test('Decision service skips Gemini when all detected fields are already verified', () {
      const decisionService = CardAnalysisDecisionService();

      final fullyVerifiedCard = BusinessCardData(
        fullName: 'Alice Walker',
        company: 'Global Health Inc',
        phoneNumbers: const [BusinessCardPhone(number: '+1 555 123 4567')],
        emailAddresses: const [BusinessCardEmail(email: 'alice@globalhealth.org')],
        fieldConfidenceStates: const {
          'fullName': 'highConfidence',
          'company': 'highConfidence',
        },
        fieldEvidence: {
          'fullName': FieldEvidence(
            fieldName: 'fullName',
            originalOcrText: 'Alice Walker',
            normalizedValue: 'Alice Walker',
            sourceEngine: 'PaddleOCR',
            verificationStatus: FieldVerificationStatus.verified,
          ),
          'company': FieldEvidence(
            fieldName: 'company',
            originalOcrText: 'Global Health Inc',
            normalizedValue: 'Global Health Inc',
            sourceEngine: 'PaddleOCR',
            verificationStatus: FieldVerificationStatus.verified,
          ),
        },
      );

      final frontOcr = OcrSideResult.fromText(
        side: CardSide.front,
        imagePath: testFrontImage.path,
        rawText: 'Alice Walker\nGlobal Health Inc\n+1 555 123 4567\nalice@globalhealth.org',
      );

      final decision = decisionService.evaluate(
        cardData: fullyVerifiedCard,
        frontOcr: frontOcr,
        backOcr: null,
      );

      // Negative constraint: Zero network calls when card details are already verified with high confidence!
      expect(decision.shouldInvokeGemini, isFalse);
      expect(decision.mode, equals(AnalysisMode.none));
    });
  });
}
