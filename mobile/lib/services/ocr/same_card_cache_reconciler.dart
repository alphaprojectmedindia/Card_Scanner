import 'dart:math';
import '../../models/business_card_data.dart';
import '../../models/business_card_email.dart';
import '../../models/business_card_phone.dart';
import '../../models/field_evidence.dart';
import '../../models/imported_contact.dart';
import '../../models/ocr_side_result.dart';
import '../storage/local_contact_record.dart';

/// Result returned after reconciling a new card scan with a previously approved contact.
class SameCardReconciliationResult {
  final BusinessCardData reconciledCardData;
  final List<String> improvementsApplied;
  final List<String> conflictsDetected;
  final Map<String, String> conflictingCachedValues;
  final bool isSamePersonVerified;
  final bool hasCriticalConflicts;
  final bool wasAssistedByCache;

  const SameCardReconciliationResult({
    required this.reconciledCardData,
    this.improvementsApplied = const [],
    this.conflictsDetected = const [],
    this.conflictingCachedValues = const {},
    this.isSamePersonVerified = true,
    this.hasCriticalConflicts = false,
    this.wasAssistedByCache = false,
  });

  static const SameCardReconciliationResult unassisted =
      SameCardReconciliationResult(
    reconciledCardData: BusinessCardData(),
    wasAssistedByCache: false,
  );
}

/// Reconciles new OCR scan output against previously saved and approved contact evidence (Phase 7 Priority 2).
///
/// **Strict Rules & Negative Constraints**:
/// 1. Compares cached values against the new scan's OCR observations and raw text.
/// 2. Only uses matching cached values as additional evidence when supported by new OCR tokens.
/// 3. Never blindly overwrites new OCR results with old values.
/// 4. Never transfers personal information (name, personal phone, personal email)
///    from one employee to a different employee at the same company.
/// 5. Preserves the original new image and its OCR evidence (observations, bounding boxes).
/// 6. Surfaces conflicting values as review-required alternatives instead of silent replacement.
class SameCardCacheReconciler {
  const SameCardCacheReconciler();

  SameCardReconciliationResult reconcile({
    required BusinessCardData newScanData,
    required OcrSideResult frontOcr,
    OcrSideResult? backOcr,
    required LocalContactRecord cachedRecord,
    double matchConfidence = 1.0,
  }) {
    final improvements = <String>[];
    final conflicts = <String>[];
    final conflictingValues = <String, String>{};

    final rawText = '${frontOcr.rawText}\n${backOcr?.rawText ?? ''}'.toLowerCase();

    // 1. Employee Isolation / Same-Person Verification
    final targetName = newScanData.fullName?.trim() ?? '';
    final cachedName = cachedRecord.fullName?.trim() ?? '';

    final nameSim = _stringSimilarity(targetName, cachedName);
    final hasDirectPhoneMatch = _hasPhoneMatch(newScanData.phoneNumbers, cachedRecord.phoneNumbers);
    final hasDirectEmailMatch = _hasEmailMatch(newScanData.emailAddresses, cachedRecord.emailAddresses);
    final hasNameTokenOverlap = _hasTokenOverlap(targetName, cachedName) ||
        _hasTokenOverlap(cachedName, targetName);

    // If both cards have a person name, and similarity is low (< 0.60) without direct phone/email match
    // and without token overlap, they are different employees from the same company!
    final bool isDistinctEmployee = targetName.isNotEmpty &&
        cachedName.isNotEmpty &&
        nameSim < 0.60 &&
        !hasNameTokenOverlap &&
        !hasDirectPhoneMatch &&
        !hasDirectEmailMatch;

    final bool isSamePerson = !isDistinctEmployee;

    String? reconciledFullName = newScanData.fullName;
    String? reconciledCompany = newScanData.company;
    String? reconciledJobTitle = newScanData.jobTitle;
    String? reconciledWebsite = newScanData.website;
    String? reconciledAddress = newScanData.address;
    List<BusinessCardPhone> reconciledPhones = List.from(newScanData.phoneNumbers);
    List<BusinessCardEmail> reconciledEmails = List.from(newScanData.emailAddresses);

    final updatedEvidence = Map<String, FieldEvidence>.from(newScanData.fieldEvidence);
    final updatedAlternatives = Map<String, List<String>>.from(newScanData.alternativeCandidates);

    // --- RECONCILE FULL NAME ---
    if (isSamePerson) {
      if (reconciledFullName == null || reconciledFullName.trim().isEmpty) {
        // New scan missed the name, but cached name tokens are present in raw text
        if (cachedName.isNotEmpty && _hasTokenOverlap(cachedName, rawText)) {
          reconciledFullName = cachedName;
          improvements.add('Recovered missing full name "$cachedName" supported by OCR text tokens');
          _setEvidence(
            updatedEvidence,
            'fullName',
            cachedName,
            status: FieldVerificationStatus.verified,
            notes: 'Recovered from cached contact evidence (${cachedRecord.id})',
          );
        }
      } else {
        // New scan has a name
        if (nameSim >= 0.85) {
          // Clean match or minor character variation (e.g. OCR 0 vs O or missing accent)
          if (reconciledFullName != cachedName && _hasTokenOverlap(cachedName, rawText)) {
            improvements.add('Refined full name from "$reconciledFullName" to "$cachedName"');
            reconciledFullName = cachedName;
          }
          _setEvidence(
            updatedEvidence,
            'fullName',
            reconciledFullName,
            status: FieldVerificationStatus.verified,
            notes: 'Corroborated by cached contact evidence',
          );
        } else if ((nameSim >= 0.60 || _hasTokenOverlap(reconciledFullName, cachedName)) &&
            cachedName.isNotEmpty &&
            _hasTokenOverlap(cachedName, rawText)) {
          // Partial name in new scan (e.g. initials, single name, or honorific+first)
          improvements.add('Expanded full name "$reconciledFullName" to approved full name "$cachedName"');
          reconciledFullName = cachedName;
          _setEvidence(
            updatedEvidence,
            'fullName',
            reconciledFullName,
            status: FieldVerificationStatus.verified,
          );
        } else if (cachedName.isNotEmpty && nameSim < 0.60) {
          // Conflict: new scan has a name, cached has another name
          conflicts.add('Full name conflict: new scan has "$reconciledFullName", cached had "$cachedName"');
          conflictingValues['fullName'] = cachedName;
          _addAlternative(updatedAlternatives, 'fullName', cachedName);
          _setEvidence(
            updatedEvidence,
            'fullName',
            reconciledFullName,
            status: FieldVerificationStatus.reviewRequired,
            notes: 'Conflict with cached name "$cachedName"',
          );
        }
      }
    } else {
      improvements.add('Suppressed personal field transfer: distinct employee names identified at same company');
    }

    // --- RECONCILE COMPANY ---
    final cachedCompany = cachedRecord.company?.trim() ?? '';
    if (reconciledCompany == null || reconciledCompany.trim().isEmpty) {
      if (cachedCompany.isNotEmpty && _hasTokenOverlap(cachedCompany, rawText)) {
        reconciledCompany = cachedCompany;
        improvements.add('Recovered missing company "$cachedCompany" supported by OCR text');
        _setEvidence(
          updatedEvidence,
          'company',
          cachedCompany,
          status: FieldVerificationStatus.verified,
          notes: 'Recovered from cached contact evidence',
        );
      }
    } else {
      final compSim = _stringSimilarity(reconciledCompany, cachedCompany);
      if (compSim >= 0.80) {
        if (reconciledCompany != cachedCompany && _hasTokenOverlap(cachedCompany, rawText)) {
          improvements.add('Refined company name from "$reconciledCompany" to "$cachedCompany"');
          reconciledCompany = cachedCompany;
        }
        _setEvidence(
          updatedEvidence,
          'company',
          reconciledCompany,
          status: FieldVerificationStatus.verified,
        );
      } else if (cachedCompany.isNotEmpty && compSim < 0.60) {
        conflicts.add('Company conflict: new scan has "$reconciledCompany", cached had "$cachedCompany"');
        conflictingValues['company'] = cachedCompany;
        _addAlternative(updatedAlternatives, 'company', cachedCompany);
        _setEvidence(
          updatedEvidence,
          'company',
          reconciledCompany,
          status: FieldVerificationStatus.reviewRequired,
        );
      }
    }

    // --- RECONCILE JOB TITLE ---
    final cachedTitle = cachedRecord.jobTitle?.trim() ?? '';
    if (isSamePerson) {
      if (reconciledJobTitle == null || reconciledJobTitle.trim().isEmpty) {
        if (cachedTitle.isNotEmpty && _hasTokenOverlap(cachedTitle, rawText)) {
          reconciledJobTitle = cachedTitle;
          improvements.add('Recovered missing job title "$cachedTitle" supported by OCR text');
          _setEvidence(
            updatedEvidence,
            'jobTitle',
            cachedTitle,
            status: FieldVerificationStatus.verified,
          );
        }
      } else {
        final titleSim = _stringSimilarity(reconciledJobTitle, cachedTitle);
        if (titleSim >= 0.85) {
          _setEvidence(
            updatedEvidence,
            'jobTitle',
            reconciledJobTitle,
            status: FieldVerificationStatus.verified,
          );
        } else if (cachedTitle.isNotEmpty && titleSim < 0.60) {
          // Title changed (e.g. promotion or different role)
          conflicts.add('Job title conflict: new scan has "$reconciledJobTitle", cached had "$cachedTitle"');
          conflictingValues['jobTitle'] = cachedTitle;
          _addAlternative(updatedAlternatives, 'jobTitle', cachedTitle);
          _setEvidence(
            updatedEvidence,
            'jobTitle',
            reconciledJobTitle,
            status: FieldVerificationStatus.reviewRequired,
            notes: 'Potential role update from previous "$cachedTitle"',
          );
        }
      }
    }

    // --- RECONCILE PHONE NUMBERS ---
    if (isSamePerson) {
      for (final cachedPhone in cachedRecord.phoneNumbers) {
        final cachedDigits = _canonicalDigits(cachedPhone.number);
        if (cachedDigits.length < 7) continue;

        bool matchedInNew = false;
        for (int i = 0; i < reconciledPhones.length; i++) {
          final newDigits = _canonicalDigits(reconciledPhones[i].number);
          if (newDigits == cachedDigits) {
            matchedInNew = true;
            _setEvidence(
              updatedEvidence,
              'phone',
              reconciledPhones[i].number,
              status: FieldVerificationStatus.verified,
            );
            break;
          } else if (cachedDigits.endsWith(newDigits) || newDigits.endsWith(cachedDigits) ||
                     (newDigits.length >= 7 && cachedDigits.startsWith(newDigits))) {
            // Broken or truncated OCR phone recovered by approved cached phone
            improvements.add('Completed truncated phone "${reconciledPhones[i].number}" to "${cachedPhone.number}"');
            reconciledPhones[i] = BusinessCardPhone(
              number: cachedPhone.number,
              label: cachedPhone.label ?? 'Mobile',
            );
            matchedInNew = true;
            _setEvidence(
              updatedEvidence,
              'phone',
              cachedPhone.number,
              status: FieldVerificationStatus.verified,
            );
            break;
          }
        }

        // If not found in new scan phone candidates, check if its digits exist in raw OCR text
        if (!matchedInNew) {
          if (rawText.replaceAll(RegExp(r'\D'), '').contains(cachedDigits)) {
            reconciledPhones.add(BusinessCardPhone(
              number: cachedPhone.number,
              label: cachedPhone.label ?? 'Mobile',
            ));
            improvements.add('Recovered missing phone "${cachedPhone.number}" supported by raw OCR digits');
            _setEvidence(
              updatedEvidence,
              'phone',
              cachedPhone.number,
              status: FieldVerificationStatus.verified,
            );
          } else if (reconciledPhones.isNotEmpty) {
            conflicts.add('phone');
            conflictingValues['phone'] = cachedPhone.number;
            _addAlternative(updatedAlternatives, 'phone', cachedPhone.number);
            _setEvidence(
              updatedEvidence,
              'phone',
              reconciledPhones.first.number,
              status: FieldVerificationStatus.reviewRequired,
              notes: 'Phone differs from saved contact value "${cachedPhone.number}"',
            );
          }
        }
      }
    }

    // --- RECONCILE EMAIL ADDRESSES ---
    if (isSamePerson) {
      for (final cachedEmail in cachedRecord.emailAddresses) {
        final cleanCached = cachedEmail.email.trim().toLowerCase();
        if (cleanCached.isEmpty) continue;

        bool matchedInNew = false;
        for (int i = 0; i < reconciledEmails.length; i++) {
          final cleanNew = reconciledEmails[i].email.trim().toLowerCase();
          if (cleanNew == cleanCached) {
            matchedInNew = true;
            _setEvidence(
              updatedEvidence,
              'email',
              reconciledEmails[i].email,
              status: FieldVerificationStatus.verified,
            );
            break;
          } else if (cleanCached.startsWith(cleanNew) && cleanNew.contains('@')) {
            // Incomplete email (e.g. missing .com at card boundary)
            improvements.add('Completed partial email "${reconciledEmails[i].email}" to "$cleanCached"');
            reconciledEmails[i] = BusinessCardEmail(
              email: cleanCached,
              label: cachedEmail.label ?? 'Work',
            );
            matchedInNew = true;
            _setEvidence(
              updatedEvidence,
              'email',
              cleanCached,
              status: FieldVerificationStatus.verified,
            );
            break;
          }
        }

        if (!matchedInNew) {
          if (rawText.contains(cleanCached)) {
            reconciledEmails.add(BusinessCardEmail(
              email: cleanCached,
              label: cachedEmail.label ?? 'Work',
            ));
            improvements.add('Recovered missing email "$cleanCached" supported by OCR text');
            _setEvidence(
              updatedEvidence,
              'email',
              cleanCached,
              status: FieldVerificationStatus.verified,
            );
          } else if (reconciledEmails.isNotEmpty) {
            conflicts.add('email');
            conflictingValues['email'] = cleanCached;
            _addAlternative(updatedAlternatives, 'email', cleanCached);
            _setEvidence(
              updatedEvidence,
              'email',
              reconciledEmails.first.email,
              status: FieldVerificationStatus.reviewRequired,
              notes: 'Email differs from saved contact value "$cleanCached"',
            );
          }
        }
      }
    }

    // --- RECONCILE WEBSITE ---
    final cachedWeb = cachedRecord.website?.trim() ?? '';
    if (reconciledWebsite == null || reconciledWebsite.trim().isEmpty) {
      final cleanDomain = cachedWeb.replaceAll(RegExp(r'https?://|www\.'), '').toLowerCase();
      if (cleanDomain.isNotEmpty && rawText.contains(cleanDomain)) {
        reconciledWebsite = cachedWeb;
        improvements.add('Recovered website "$cachedWeb" supported by raw OCR text');
        _setEvidence(
          updatedEvidence,
          'website',
          cachedWeb,
          status: FieldVerificationStatus.verified,
        );
      }
    }

    // --- RECONCILE ADDRESS ---
    final cachedAddr = cachedRecord.address?.trim() ?? '';
    if (reconciledAddress == null || reconciledAddress.trim().isEmpty) {
      if (cachedAddr.isNotEmpty && _hasTokenOverlap(cachedAddr, rawText)) {
        reconciledAddress = cachedAddr;
        improvements.add('Reconstructed address from cached contact evidence');
        _setEvidence(
          updatedEvidence,
          'address',
          cachedAddr,
          status: FieldVerificationStatus.verified,
        );
      }
    }

    final hasCriticalConflicts = conflicts.isNotEmpty;
    final wasAssisted = improvements.isNotEmpty || conflicts.isNotEmpty;

    final updatedCardData = newScanData.copyWith(
      fullName: reconciledFullName,
      company: reconciledCompany,
      jobTitle: reconciledJobTitle,
      website: reconciledWebsite,
      address: reconciledAddress,
      phoneNumbers: reconciledPhones,
      emailAddresses: reconciledEmails,
      fieldEvidence: updatedEvidence,
      alternativeCandidates: updatedAlternatives,
      parsingNotes: [
        ...newScanData.parsingNotes,
        if (wasAssisted) '[CachedAssisted] Contact ${cachedRecord.id} ($matchConfidence confidence)',
        if (improvements.isNotEmpty) '[CachedImprovements] ${improvements.join("; ")}',
        if (conflicts.isNotEmpty) '[CachedConflicts] ${conflicts.join("; ")}',
      ],
    );

    return SameCardReconciliationResult(
      reconciledCardData: updatedCardData,
      improvementsApplied: improvements,
      conflictsDetected: conflicts,
      conflictingCachedValues: conflictingValues,
      isSamePersonVerified: isSamePerson,
      hasCriticalConflicts: hasCriticalConflicts,
      wasAssistedByCache: wasAssisted,
    );
  }

  static void _setEvidence(
    Map<String, FieldEvidence> evidenceMap,
    String fieldName,
    String? value, {
    required FieldVerificationStatus status,
    String? notes,
  }) {
    if (value == null || value.trim().isEmpty) return;
    final existing = evidenceMap[fieldName];
    evidenceMap[fieldName] = FieldEvidence(
      fieldName: fieldName,
      originalOcrText: existing?.originalOcrText ?? value,
      normalizedValue: value,
      sourceEngine: 'cache_assisted',
      sourceObservationIds: existing?.sourceObservationIds ?? const [],
      boundingBoxes: existing?.boundingBoxes ?? const [],
      ocrConfidence: 0.95,
      parserConfidence: 0.95,
      verificationStatus: status,
      verificationSource: 'cachedContactAssisted',
      verifiedAt: DateTime.now().toUtc(),
      uncertaintyReason: notes ?? existing?.uncertaintyReason,
      processingVersion: '7.0.0',
    );
  }

  static void _addAlternative(
    Map<String, List<String>> alternativesMap,
    String fieldName,
    String value,
  ) {
    if (value.trim().isEmpty) return;
    final list = List<String>.from(alternativesMap[fieldName] ?? const []);
    if (!list.contains(value)) {
      list.add(value);
      alternativesMap[fieldName] = list;
    }
  }

  static bool _hasPhoneMatch(List<BusinessCardPhone> newPhones, List<ImportedContactPhone> cachedPhones) {
    for (final p1 in newPhones) {
      final d1 = _canonicalDigits(p1.number);
      if (d1.length < 7) continue;
      for (final p2 in cachedPhones) {
        final d2 = _canonicalDigits(p2.number);
        if (d2.length < 7) continue;
        if (d1.endsWith(d2) || d2.endsWith(d1)) return true;
      }
    }
    return false;
  }

  static bool _hasEmailMatch(List<BusinessCardEmail> newEmails, List<ImportedContactEmail> cachedEmails) {
    for (final e1 in newEmails) {
      final clean1 = e1.email.trim().toLowerCase();
      if (clean1.isEmpty) continue;
      for (final e2 in cachedEmails) {
        final clean2 = e2.email.trim().toLowerCase();
        if (clean2.isEmpty) continue;
        if (clean1 == clean2) return true;
        // Username match on same domain
        final u1 = clean1.split('@').first;
        final u2 = clean2.split('@').first;
        if (u1.length >= 3 && u1 == u2) return true;
      }
    }
    return false;
  }

  static bool _hasTokenOverlap(String expectedText, String rawText) {
    final cleanExpected = expectedText
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ');
    final cleanRaw = rawText
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ');

    final tokens = cleanExpected
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2)
        .toList();
    if (tokens.isEmpty) return false;
    int matches = 0;
    for (final t in tokens) {
      if (cleanRaw.contains(t)) matches++;
    }
    return (matches / tokens.length) >= 0.50;
  }

  static String _canonicalDigits(String val) => val.replaceAll(RegExp(r'\D'), '');

  static double _stringSimilarity(String a, String b) {
    final s1 = a.trim().toLowerCase();
    final s2 = b.trim().toLowerCase();
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    if (s1 == s2) return 1.0;

    final levDist = _levenshtein(s1, s2);
    final maxLen = max(s1.length, s2.length);
    final levSim = 1.0 - (levDist / maxLen);

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
