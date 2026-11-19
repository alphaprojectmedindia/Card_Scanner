class ImportedContact {
  final String id;
  final String? fullName;
  final String? company;
  final String? jobTitle;
  final String? website;
  final String? address;
  final String? personalRemark;
  final String? rememberThisContact;
  final DateTime? createdAtUtc;
  final DateTime? updatedAtUtc;
  final List<ImportedContactPhone> phoneNumbers;
  final List<ImportedContactEmail> emailAddresses;

  const ImportedContact({
    required this.id,
    this.fullName,
    this.company,
    this.jobTitle,
    this.website,
    this.address,
    this.personalRemark,
    this.rememberThisContact,
    this.createdAtUtc,
    this.updatedAtUtc,
    this.phoneNumbers = const [],
    this.emailAddresses = const [],
  });

  /// Returns the personal memory/remark note if present.
  String? get effectiveMemory => (rememberThisContact?.trim().isNotEmpty == true)
      ? rememberThisContact!.trim()
      : (personalRemark?.trim().isNotEmpty == true ? personalRemark!.trim() : null);

  String get displayName => fullName?.trim().isNotEmpty == true
      ? fullName!.trim()
      : (company?.trim().isNotEmpty == true
          ? company!.trim()
          : (phoneNumbers.isNotEmpty
              ? phoneNumbers.first.number
              : (emailAddresses.isNotEmpty ? emailAddresses.first.email : 'Unknown Contact')));

  String? get primaryPhone =>
      phoneNumbers.isNotEmpty ? phoneNumbers.first.number : null;

  String? get primaryEmail =>
      emailAddresses.isNotEmpty ? emailAddresses.first.email : null;

  String get initials {
    final name = displayName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  factory ImportedContact.fromJson(Map<String, dynamic> json) {
    final rawMemory = json['rememberThisContact'] as String? ?? json['personalRemark'] as String?;
    return ImportedContact(
      id: json['id'] as String? ?? '',
      fullName: json['fullName'] as String?,
      company: json['company'] as String?,
      jobTitle: json['jobTitle'] as String?,
      website: json['website'] as String?,
      address: json['address'] as String?,
      personalRemark: rawMemory,
      rememberThisContact: rawMemory,
      createdAtUtc: json['createdAtUtc'] != null
          ? DateTime.tryParse(json['createdAtUtc'] as String)
          : null,
      updatedAtUtc: json['updatedAtUtc'] != null
          ? DateTime.tryParse(json['updatedAtUtc'] as String)
          : null,
      phoneNumbers: (json['phoneNumbers'] as List<dynamic>?)
              ?.map((item) =>
                  ImportedContactPhone.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      emailAddresses: (json['emailAddresses'] as List<dynamic>?)
              ?.map((item) =>
                  ImportedContactEmail.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    final memory = rememberThisContact ?? personalRemark;
    return {
      'id': id,
      if (fullName != null) 'fullName': fullName,
      if (company != null) 'company': company,
      if (jobTitle != null) 'jobTitle': jobTitle,
      if (website != null) 'website': website,
      if (address != null) 'address': address,
      if (memory != null && memory.isNotEmpty) ...{
        'personalRemark': memory,
        'rememberThisContact': memory,
      },
      if (createdAtUtc != null) 'createdAtUtc': createdAtUtc!.toIso8601String(),
      if (updatedAtUtc != null) 'updatedAtUtc': updatedAtUtc!.toIso8601String(),
      'phoneNumbers': phoneNumbers.map((p) => p.toJson()).toList(),
      'emailAddresses': emailAddresses.map((e) => e.toJson()).toList(),
    };
  }
}

class ImportedContactPhone {
  final String? id;
  final String number;
  final String? normalizedNumber;
  final String? label;

  const ImportedContactPhone({
    this.id,
    required this.number,
    this.normalizedNumber,
    this.label,
  });

  factory ImportedContactPhone.fromJson(Map<String, dynamic> json) {
    return ImportedContactPhone(
      id: json['id'] as String?,
      number: json['number'] as String? ?? '',
      normalizedNumber: json['normalizedNumber'] as String?,
      label: json['label'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'number': number,
      if (normalizedNumber != null) 'normalizedNumber': normalizedNumber,
      if (label != null) 'label': label,
    };
  }
}

class ImportedContactEmail {
  final String? id;
  final String email;
  final String? normalizedEmail;
  final String? label;

  const ImportedContactEmail({
    this.id,
    required this.email,
    this.normalizedEmail,
    this.label,
  });

  factory ImportedContactEmail.fromJson(Map<String, dynamic> json) {
    return ImportedContactEmail(
      id: json['id'] as String?,
      email: json['email'] as String? ?? '',
      normalizedEmail: json['normalizedEmail'] as String?,
      label: json['label'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'email': email,
      if (normalizedEmail != null) 'normalizedEmail': normalizedEmail,
      if (label != null) 'label': label,
    };
  }
}
