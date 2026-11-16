import 'dart:math';
import '../../models/business_card_data.dart';
import '../../models/imported_contact.dart';
import '../storage/local_contact_record.dart';
import '../storage/local_contact_repository.dart';
import 'image_hash_service.dart';

enum DuplicateMatchType {
  none,
  exactImage,
  perceptualImage,
  phoneEmailMatch,
  similarCard,
}

class DuplicateDetectionResult {
  final bool isDuplicate;
  final DuplicateMatchType matchType;
  final ImportedContact? matchedContact;
  final LocalContactRecord? matchedRecord;
  final double confidence;
  final String reason;

  bool get isDefinitiveMatch => isDuplicate && confidence >= 0.75;
  bool get isUncertainMatch => isDuplicate && confidence >= 0.50 && confidence < 0.75;

  const DuplicateDetectionResult({
    required this.isDuplicate,
    required this.matchType,
    this.matchedContact,
    this.matchedRecord,
    required this.confidence,
    required this.reason,
  });

  static const DuplicateDetectionResult noDuplicate = DuplicateDetectionResult(
    isDuplicate: false,
    matchType: DuplicateMatchType.none,
    confidence: 0.0,
    reason: 'No duplicate detected.',
  );
}

/// Intelligent offline duplicate card detector operating across multiple visual and semantic signals.
class DuplicateCardDetector {
  final LocalContactRepository repository;
  final ImageHashService hashService;

  const DuplicateCardDetector({
    required this.repository,
    this.hashService = const ImageHashService(),
  });

  /// Evaluates an exact image SHA-256 fingerprint against saved local contacts.
  /// (Stage 1: Instant match with 0 OCR / 0 AI cost).
  Future<DuplicateDetectionResult> checkExactFingerprint(
    String imageFingerprint, {
    String? userId,
  }) async {
    if (imageFingerprint.isEmpty) return DuplicateDetectionResult.noDuplicate;

    final match = await repository.findByImageFingerprint(imageFingerprint, userId: userId);
    if (match != null) {
      return DuplicateDetectionResult(
        isDuplicate: true,
        matchType: DuplicateMatchType.exactImage,
        matchedContact: match.toImportedContact(),
        matchedRecord: match,
        confidence: 1.0,
        reason: 'Exact image match recognized from previously approved card.',
      );
    }

    return DuplicateDetectionResult.noDuplicate;
  }

  /// Evaluates a parsed business card and optional perceptual dHash against saved local contacts.
  /// (Stage 2: Multi-signal similarity).
  Future<DuplicateDetectionResult> checkSimilarity({
    required BusinessCardData cardData,
    String? currentDHash,
    String? userId,
  }) async {
    await repository.ensureLoaded();
    final allRecords = await repository.getAllRecords(userId: userId);
    if (allRecords.isEmpty) return DuplicateDetectionResult.noDuplicate;

    final targetPhones = cardData.phoneNumbers
        .map((p) => _canonicalDigits(p.number))
        .where((p) => p.length >= 7)
        .toList();

    final targetEmails = cardData.emailAddresses
        .map((e) => e.email.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();

    final targetName = cardData.fullName?.trim() ?? '';
    final targetCompany = cardData.company?.trim() ?? '';

    LocalContactRecord? bestRecord;
    double highestScore = 0.0;
    DuplicateMatchType bestType = DuplicateMatchType.none;
    String bestReason = '';

    for (final record in allRecords) {
      if (record.syncStatus == ContactSyncStatus.pendingDelete) continue;

      double score = 0.0;
      final reasons = <String>[];
      bool hasDirectIdentifier = false;

      // 1. Phone number match
      for (final p in record.phoneNumbers) {
        final candDigits = _canonicalDigits(p.number);
        for (final tp in targetPhones) {
          if (candDigits.endsWith(tp) || tp.endsWith(candDigits)) {
            score = max(score, 0.85);
            hasDirectIdentifier = true;
            reasons.add('Phone match (${p.number})');
            break;
          }
        }
      }

      // 2. Email address match
      for (final e in record.emailAddresses) {
        final candEmail = e.email.trim().toLowerCase();
        if (targetEmails.contains(candEmail)) {
          score = max(score, 0.90);
          hasDirectIdentifier = true;
          reasons.add('Email match ($candEmail)');
          break;
        }
      }

      // 3. Name and Company text similarity
      final recordName = record.fullName?.trim() ?? '';
      final recordCompany = record.company?.trim() ?? '';

      final nameSim = _stringSimilarity(targetName, recordName);
      final companySim = _stringSimilarity(targetCompany, recordCompany);

      final bool hasDistinctPersonNames = targetName.isNotEmpty &&
          recordName.isNotEmpty &&
          nameSim < 0.60;

      if (nameSim >= 0.88 && companySim >= 0.85) {
        score = max(score, 0.88);
        reasons.add('High person name ($targetName) and company ($targetCompany) similarity');
      } else if (hasDirectIdentifier && nameSim >= 0.70) {
        score = min(1.0, score + 0.10);
        reasons.add('Corroborating name similarity ($targetName)');
      }

      // 4. Perceptual dHash comparison
      // CRITICAL: Never automatically merge two different people from the same company based only on dHash or company similarity!
      if (!hasDistinctPersonNames &&
          currentDHash != null &&
          currentDHash.isNotEmpty &&
          record.imageDHash != null &&
          record.imageDHash!.isNotEmpty) {
        final dist = hashService.hammingDistance(currentDHash, record.imageDHash!);
        if (dist <= 6 && (hasDirectIdentifier || nameSim >= 0.70)) {
          // Extremely high visual similarity on the same individual
          score = max(score, 0.95);
          reasons.add('Perceptual visual layout match (dHash dist $dist)');
        } else if (dist <= 10 && (hasDirectIdentifier || nameSim >= 0.70)) {
          // High visual similarity with supporting identity
          score = max(score, score > 0 ? min(1.0, score + 0.15) : 0.75);
          reasons.add('Similar visual card layout (dHash dist $dist)');
        } else if (dist <= 6 && (targetName.isEmpty || recordName.isEmpty) && !hasDirectIdentifier) {
          // Priority 1 Requirement 5 & 7: Do not identify cards using company logo or layout alone.
          // Incomplete OCR without direct identifiers must not automatically accept an uncertain match.
          score = max(score, 0.55);
          reasons.add('Potential visual layout similarity with incomplete identity (dHash dist $dist)');
        }
      }

      if (score > highestScore) {
        highestScore = score;
        bestRecord = record;
        bestReason = reasons.join(', ');
        bestType = hasDirectIdentifier
            ? DuplicateMatchType.phoneEmailMatch
            : (reasons.any((r) => r.contains('dHash'))
                ? DuplicateMatchType.perceptualImage
                : DuplicateMatchType.similarCard);
      }
    }

    if (highestScore >= 0.50 && bestRecord != null) {
      return DuplicateDetectionResult(
        isDuplicate: true,
        matchType: bestType,
        matchedContact: bestRecord.toImportedContact(),
        matchedRecord: bestRecord,
        confidence: highestScore,
        reason: bestReason,
      );
    }

    return DuplicateDetectionResult.noDuplicate;
  }

  static String _canonicalDigits(String val) {
    return val.replaceAll(RegExp(r'\D'), '');
  }

  /// Normalized Levenshtein + Jaccard token similarity (0.0 to 1.0).
  static double _stringSimilarity(String a, String b) {
    final s1 = a.trim().toLowerCase();
    final s2 = b.trim().toLowerCase();
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    if (s1 == s2) return 1.0;

    final levDist = _levenshtein(s1, s2);
    final maxLen = max(s1.length, s2.length);
    final levSim = 1.0 - (levDist / maxLen);

    // Token Jaccard
    final tokens1 = s1.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
    final tokens2 = s2.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
    final intersection = tokens1.intersection(tokens2).length;
    final union = tokens1.union(tokens2).length;
    final jaccard = union == 0 ? 0.0 : intersection / union;

    return (levSim * 0.6) + (jaccard * 0.4);
  }

  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }
}

