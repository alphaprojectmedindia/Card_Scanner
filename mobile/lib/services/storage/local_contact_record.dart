import '../../models/business_card_data.dart';
import '../../models/business_card_email.dart';
import '../../models/business_card_phone.dart';
import '../../models/field_evidence.dart';
import '../../models/imported_contact.dart';
import '../../models/ocr_side_result.dart';
import '../../models/recovered_ocr_observation.dart';

/// Sync status for locally stored contacts.
enum ContactSyncStatus {
  synced,
  pendingCreate,
  pendingUpdate,
  pendingDelete,
}

/// Comprehensive local contact record stored in the persistent local database.
class LocalContactRecord {
  final String id;
  final String userId;
  final String? remoteId;
  final String? fullName;
  final String? company;
  final String? jobTitle;
  final String? website;
  final String? address;
  final String? personalRemark;
  final String? rememberThisContact;
  final List<ImportedContactPhone> phoneNumbers;
  final List<ImportedContactEmail> emailAddresses;
  final ContactSyncStatus syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// SHA-256 fingerprint of the normalized front card image.
  final String? imageFingerprint;

  /// 64-bit perceptual difference hash (dHash) hex string (16 chars).
  final String? imageDHash;

  /// Local cached front image file path.
  final String? frontImagePath;

  /// Local cached back image file path.
  final String? backImagePath;

  /// Full raw recognized text from on-device OCR (unified or front).
  final String? rawRecognizedText;

  /// Isolated raw OCR text from front side.
  final String? frontRawText;

  /// Isolated raw OCR text from back side.
  final String? backRawText;

  /// Structured OCR observations for the front side (preserving text, bounding box, confidence, engine).
  final List<Map<String, dynamic>> frontObservations;

  /// Structured OCR observations for the back side.
  final List<Map<String, dynamic>> backObservations;

  /// Primary OCR engine that processed the card (e.g. 'PaddleOCR PP-OCRv5 Mobile', 'Google ML Kit', 'Hybrid').
  final String? ocrEngineName;

  /// OCR model / checkpoint version tag.
  final String? ocrModelVersion;

  /// Overall character-level OCR recognition confidence (0.0 to 1.0).
  final double? overallOcrConfidence;

  /// Granular field-level structured evidence mapping fieldName -> FieldEvidence.
  final Map<String, FieldEvidence> fieldEvidence;

  /// Semantic parser version (e.g. '3.2.0').
  final String? parserVersion;

  /// Image preprocessing pipeline version tag.
  final String? preprocessingVersion;

  /// Optional arbitrary user or parser notes.
  final String? notes;

  /// Structured OCR observations recovered through targeted high-resolution re-OCR.
  final List<RecoveredOcrObservation> recoveredObservations;

  const LocalContactRecord({
    required this.id,
    this.userId = 'default_user',
    this.remoteId,
    this.fullName,
    this.company,
    this.jobTitle,
    this.website,
    this.address,
    this.personalRemark,
    this.rememberThisContact,
    this.phoneNumbers = const [],
    this.emailAddresses = const [],
    this.syncStatus = ContactSyncStatus.synced,
    required this.createdAt,
    required this.updatedAt,
    this.imageFingerprint,
    this.imageDHash,
    this.frontImagePath,
    this.backImagePath,
    this.rawRecognizedText,
    this.frontRawText,
    this.backRawText,
    this.frontObservations = const [],
    this.backObservations = const [],
    this.ocrEngineName,
    this.ocrModelVersion,
    this.overallOcrConfidence,
    this.fieldEvidence = const {},
    this.parserVersion,
    this.preprocessingVersion,
    this.notes,
    this.recoveredObservations = const [],
  });

  /// True if this record possesses complete observations and field evidence.
  bool get hasCompleteEvidence =>
      (frontObservations.isNotEmpty || backObservations.isNotEmpty) &&
      fieldEvidence.isNotEmpty;

  /// True if this is a legacy record that has raw text but lacks granular observations.
  bool get hasRawOcrOnly =>
      (rawRecognizedText != null && rawRecognizedText!.trim().isNotEmpty) &&
      frontObservations.isEmpty &&
      backObservations.isEmpty;

  /// Resolves an observation by its identifier across front and back observation sets.
  Map<String, dynamic>? getObservationById(String observationId) {
    for (final obs in frontObservations) {
      if (obs['id'] == observationId) return obs;
    }
    for (final obs in backObservations) {
      if (obs['id'] == observationId) return obs;
    }
    for (final rec in recoveredObservations) {
      if (rec.id == observationId) return rec.toJson();
    }
    return null;
  }

  /// Audits all field evidence entries in this record, returning a list of integrity diagnostic violations.
  /// An empty list indicates complete observation reference integrity.
  List<String> validateEvidenceIntegrity() {
    final violations = <String>[];
    final frontObsMap = <String, Map<String, dynamic>>{};
    for (int i = 0; i < frontObservations.length; i++) {
      final obs = frontObservations[i];
      final id = obs['id']?.toString() ?? 'front_$i';
      frontObsMap[id] = obs;
    }

    final backObsMap = <String, Map<String, dynamic>>{};
    for (int i = 0; i < backObservations.length; i++) {
      final obs = backObservations[i];
      final id = obs['id']?.toString() ?? 'back_$i';
      backObsMap[id] = obs;
    }

    final recObsMap = <String, RecoveredOcrObservation>{};
    for (final rec in recoveredObservations) {
      recObsMap[rec.id] = rec;
    }

    fieldEvidence.forEach((fieldKey, ev) {
      // 1. Cross-side contamination check
      if (ev.side == CardSide.front) {
        for (final obsId in ev.sourceObservationIds) {
          if (obsId.startsWith('back_')) {
            violations.add('Field "$fieldKey" on FRONT references BACK observation "$obsId"');
          } else if (recObsMap.containsKey(obsId) && recObsMap[obsId]!.side == CardSide.back) {
            violations.add('Field "$fieldKey" on FRONT references BACK observation "$obsId"');
          }
        }
      } else if (ev.side == CardSide.back) {
        for (final obsId in ev.sourceObservationIds) {
          if (obsId.startsWith('front_')) {
            violations.add('Field "$fieldKey" on BACK references FRONT observation "$obsId"');
          } else if (recObsMap.containsKey(obsId) && recObsMap[obsId]!.side == CardSide.front) {
            violations.add('Field "$fieldKey" on BACK references FRONT observation "$obsId"');
          }
        }
      }

      // 2. Existence check: every source observation ID must resolve to a stored observation
      for (final obsId in ev.sourceObservationIds) {
        final targetMap = ev.side == CardSide.front
            ? frontObsMap
            : (ev.side == CardSide.back ? backObsMap : {...frontObsMap, ...backObsMap});

        if (!targetMap.containsKey(obsId) && !recObsMap.containsKey(obsId)) {
          violations.add('Field "$fieldKey" references non-existent observation "$obsId"');
        }
      }

      // 3. Duplicate check within sourceObservationIds
      final seenIds = <String>{};
      for (final obsId in ev.sourceObservationIds) {
        if (!seenIds.add(obsId)) {
          violations.add('Field "$fieldKey" has duplicate observation reference "$obsId"');
        }
      }

      // 4. Bounding box match check for single-observation fields
      if (ev.sourceObservationIds.length == 1 && ev.boundingBoxes.isNotEmpty) {
        final obs = getObservationById(ev.sourceObservationIds.first);
        if (obs != null && obs['boundingBox'] is Map) {
          final bMap = obs['boundingBox'] as Map;
          final bLeft = (bMap['left'] as num?)?.toDouble() ?? 0.0;
          final bTop = (bMap['top'] as num?)?.toDouble() ?? 0.0;
          final bWidth = (bMap['width'] as num?)?.toDouble() ?? 0.0;
          final bHeight = (bMap['height'] as num?)?.toDouble() ?? 0.0;
          final box = ev.boundingBoxes.first;
          if ((box.left - bLeft).abs() > 0.05 ||
              (box.top - bTop).abs() > 0.05 ||
              (box.width - bWidth).abs() > 0.05 ||
              (box.height - bHeight).abs() > 0.05) {
            violations.add('Field "$fieldKey" bounding box does not match referenced observation');
          }
        }
      }
    });

    return violations;
  }

  /// Converts this record to the user-facing [ImportedContact] model.
  ImportedContact toImportedContact() {
    final memory = rememberThisContact ?? personalRemark;
    return ImportedContact(
      id: id,
      fullName: fullName,
      company: company,
      jobTitle: jobTitle,
      website: website,
      address: address,
      personalRemark: memory,
      rememberThisContact: memory,
      createdAtUtc: createdAt.toUtc(),
      updatedAtUtc: updatedAt.toUtc(),
      phoneNumbers: phoneNumbers,
      emailAddresses: emailAddresses,
    );
  }

  /// Converts this record to a [BusinessCardData] instance for parser & learning services.
  BusinessCardData toBusinessCardData() {
    return BusinessCardData(
      fullName: fullName,
      company: company,
      jobTitle: jobTitle,
      website: website,
      address: address,
      phoneNumbers: phoneNumbers
          .map((p) => BusinessCardPhone(
                number: p.number,
                label: p.label ?? 'Mobile',
              ))
          .toList(),
      emailAddresses: emailAddresses
          .map((e) => BusinessCardEmail(
                email: e.email,
                label: e.label ?? 'Work',
              ))
          .toList(),
      rawRecognizedText: rawRecognizedText ?? '',
      frontRawText: frontRawText,
      backRawText: backRawText,
      fieldEvidence: fieldEvidence,
      isDualSided: backImagePath != null && backImagePath!.isNotEmpty,
    );
  }

  /// Creates a [LocalContactRecord] from a user-facing [ImportedContact].
  factory LocalContactRecord.fromImportedContact(
    ImportedContact contact, {
    String userId = 'default_user',
    ContactSyncStatus syncStatus = ContactSyncStatus.synced,
    String? imageFingerprint,
    String? imageDHash,
    String? frontImagePath,
    String? backImagePath,
    String? rawRecognizedText,
    String? frontRawText,
    String? backRawText,
    List<Map<String, dynamic>> frontObservations = const [],
    List<Map<String, dynamic>> backObservations = const [],
    String? ocrEngineName,
    String? ocrModelVersion,
    double? overallOcrConfidence,
    Map<String, FieldEvidence> fieldEvidence = const {},
    String? parserVersion,
    String? preprocessingVersion,
    String? notes,
    List<RecoveredOcrObservation> recoveredObservations = const [],
  }) {
    final now = DateTime.now();
    return LocalContactRecord(
      id: contact.id.isNotEmpty ? contact.id : 'loc_${now.millisecondsSinceEpoch}',
      userId: userId,
      remoteId: contact.id.isNotEmpty ? contact.id : null,
      fullName: contact.fullName,
      company: contact.company,
      jobTitle: contact.jobTitle,
      website: contact.website,
      address: contact.address,
      personalRemark: contact.effectiveMemory,
      rememberThisContact: contact.effectiveMemory,
      phoneNumbers: contact.phoneNumbers,
      emailAddresses: contact.emailAddresses,
      syncStatus: syncStatus,
      createdAt: contact.createdAtUtc?.toLocal() ?? now,
      updatedAt: contact.updatedAtUtc?.toLocal() ?? now,
      imageFingerprint: imageFingerprint,
      imageDHash: imageDHash,
      frontImagePath: frontImagePath,
      backImagePath: backImagePath,
      rawRecognizedText: rawRecognizedText,
      frontRawText: frontRawText,
      backRawText: backRawText,
      frontObservations: frontObservations,
      backObservations: backObservations,
      ocrEngineName: ocrEngineName,
      ocrModelVersion: ocrModelVersion,
      overallOcrConfidence: overallOcrConfidence,
      fieldEvidence: fieldEvidence,
      parserVersion: parserVersion,
      preprocessingVersion: preprocessingVersion,
      notes: notes,
      recoveredObservations: recoveredObservations,
    );
  }

  LocalContactRecord copyWith({
    String? id,
    String? userId,
    String? remoteId,
    String? fullName,
    String? company,
    String? jobTitle,
    String? website,
    String? address,
    String? personalRemark,
    bool clearPersonalRemark = false,
    String? rememberThisContact,
    bool clearRememberThisContact = false,
    List<ImportedContactPhone>? phoneNumbers,
    List<ImportedContactEmail>? emailAddresses,
    ContactSyncStatus? syncStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? imageFingerprint,
    String? imageDHash,
    String? frontImagePath,
    String? backImagePath,
    String? rawRecognizedText,
    String? frontRawText,
    String? backRawText,
    List<Map<String, dynamic>>? frontObservations,
    List<Map<String, dynamic>>? backObservations,
    String? ocrEngineName,
    String? ocrModelVersion,
    double? overallOcrConfidence,
    Map<String, FieldEvidence>? fieldEvidence,
    String? parserVersion,
    String? preprocessingVersion,
    String? notes,
    List<RecoveredOcrObservation>? recoveredObservations,
  }) {
    return LocalContactRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      remoteId: remoteId ?? this.remoteId,
      fullName: fullName ?? this.fullName,
      company: company ?? this.company,
      jobTitle: jobTitle ?? this.jobTitle,
      website: website ?? this.website,
      address: address ?? this.address,
      personalRemark: (clearPersonalRemark || clearRememberThisContact)
          ? null
          : (rememberThisContact ?? personalRemark ?? this.rememberThisContact ?? this.personalRemark),
      rememberThisContact: (clearPersonalRemark || clearRememberThisContact)
          ? null
          : (rememberThisContact ?? personalRemark ?? this.rememberThisContact ?? this.personalRemark),
      phoneNumbers: phoneNumbers ?? this.phoneNumbers,
      emailAddresses: emailAddresses ?? this.emailAddresses,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      imageFingerprint: imageFingerprint ?? this.imageFingerprint,
      imageDHash: imageDHash ?? this.imageDHash,
      frontImagePath: frontImagePath ?? this.frontImagePath,
      backImagePath: backImagePath ?? this.backImagePath,
      rawRecognizedText: rawRecognizedText ?? this.rawRecognizedText,
      frontRawText: frontRawText ?? this.frontRawText,
      backRawText: backRawText ?? this.backRawText,
      frontObservations: frontObservations ?? this.frontObservations,
      backObservations: backObservations ?? this.backObservations,
      ocrEngineName: ocrEngineName ?? this.ocrEngineName,
      ocrModelVersion: ocrModelVersion ?? this.ocrModelVersion,
      overallOcrConfidence: overallOcrConfidence ?? this.overallOcrConfidence,
      fieldEvidence: fieldEvidence ?? this.fieldEvidence,
      parserVersion: parserVersion ?? this.parserVersion,
      preprocessingVersion: preprocessingVersion ?? this.preprocessingVersion,
      notes: notes ?? this.notes,
      recoveredObservations:
          recoveredObservations ?? this.recoveredObservations,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      if (remoteId != null) 'remoteId': remoteId,
      if (fullName != null) 'fullName': fullName,
      if (company != null) 'company': company,
      if (jobTitle != null) 'jobTitle': jobTitle,
      if (website != null) 'website': website,
      if (address != null) 'address': address,
      if ((rememberThisContact ?? personalRemark) != null)
        'personalRemark': rememberThisContact ?? personalRemark,
      if ((rememberThisContact ?? personalRemark) != null)
        'rememberThisContact': rememberThisContact ?? personalRemark,
      'phoneNumbers': phoneNumbers.map((p) => p.toJson()).toList(),
      'emailAddresses': emailAddresses.map((e) => e.toJson()).toList(),
      'syncStatus': syncStatus.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (imageFingerprint != null) 'imageFingerprint': imageFingerprint,
      if (imageDHash != null) 'imageDHash': imageDHash,
      if (frontImagePath != null) 'frontImagePath': frontImagePath,
      if (backImagePath != null) 'backImagePath': backImagePath,
      if (rawRecognizedText != null) 'rawRecognizedText': rawRecognizedText,
      if (frontRawText != null) 'frontRawText': frontRawText,
      if (backRawText != null) 'backRawText': backRawText,
      if (frontObservations.isNotEmpty) 'frontObservations': frontObservations,
      if (backObservations.isNotEmpty) 'backObservations': backObservations,
      if (ocrEngineName != null) 'ocrEngineName': ocrEngineName,
      if (ocrModelVersion != null) 'ocrModelVersion': ocrModelVersion,
      if (overallOcrConfidence != null) 'overallOcrConfidence': overallOcrConfidence,
      if (fieldEvidence.isNotEmpty)
        'fieldEvidence': fieldEvidence.map((k, v) => MapEntry(k, v.toJson())),
      if (parserVersion != null) 'parserVersion': parserVersion,
      if (preprocessingVersion != null) 'preprocessingVersion': preprocessingVersion,
      if (notes != null) 'notes': notes,
      if (recoveredObservations.isNotEmpty)
        'recoveredObservations':
            recoveredObservations.map((r) => r.toJson()).toList(),
    };
  }

  factory LocalContactRecord.fromJson(Map<String, dynamic> json) {
    final rawFrontObs = json['frontObservations'] as List<dynamic>?;
    final frontObs = rawFrontObs
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        const <Map<String, dynamic>>[];

    final rawBackObs = json['backObservations'] as List<dynamic>?;
    final backObs = rawBackObs
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        const <Map<String, dynamic>>[];

    final rawFieldEv = json['fieldEvidence'] as Map<String, dynamic>?;
    final Map<String, FieldEvidence> evidenceMap = rawFieldEv != null
        ? rawFieldEv.map(
            (k, v) => MapEntry(k, FieldEvidence.fromJson(v as Map<String, dynamic>)),
          )
        : const <String, FieldEvidence>{};

    final rawRecObs = json['recoveredObservations'] as List<dynamic>?;
    final recObs = rawRecObs
            ?.map((e) =>
                RecoveredOcrObservation.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <RecoveredOcrObservation>[];

    return LocalContactRecord(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? 'default_user',
      remoteId: json['remoteId'] as String?,
      fullName: json['fullName'] as String?,
      company: json['company'] as String?,
      jobTitle: json['jobTitle'] as String?,
      website: json['website'] as String?,
      address: json['address'] as String?,
      personalRemark: json['rememberThisContact'] as String? ?? json['personalRemark'] as String?,
      rememberThisContact: json['rememberThisContact'] as String? ?? json['personalRemark'] as String?,
      phoneNumbers: (json['phoneNumbers'] as List<dynamic>?)
              ?.map((p) => ImportedContactPhone.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
      emailAddresses: (json['emailAddresses'] as List<dynamic>?)
              ?.map((e) => ImportedContactEmail.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      syncStatus: ContactSyncStatus.values.firstWhere(
        (s) => s.name == json['syncStatus'],
        orElse: () => ContactSyncStatus.synced,
      ),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      imageFingerprint: json['imageFingerprint'] as String?,
      imageDHash: json['imageDHash'] as String?,
      frontImagePath: json['frontImagePath'] as String?,
      backImagePath: json['backImagePath'] as String?,
      rawRecognizedText: json['rawRecognizedText'] as String?,
      frontRawText: json['frontRawText'] as String? ?? json['rawRecognizedText'] as String?,
      backRawText: json['backRawText'] as String?,
      frontObservations: frontObs,
      backObservations: backObs,
      ocrEngineName: json['ocrEngineName'] as String?,
      ocrModelVersion: json['ocrModelVersion'] as String?,
      overallOcrConfidence: (json['overallOcrConfidence'] as num?)?.toDouble(),
      fieldEvidence: evidenceMap,
      parserVersion: json['parserVersion'] as String?,
      preprocessingVersion: json['preprocessingVersion'] as String?,
      notes: json['notes'] as String?,
      recoveredObservations: recObs,
    );
  }
}
