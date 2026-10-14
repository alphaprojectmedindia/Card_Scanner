import 'imported_contact.dart';

class CheckDuplicateResult {
  final bool isDuplicate;
  final ImportedContact? existingContact;
  final String? matchedBy;

  const CheckDuplicateResult({
    required this.isDuplicate,
    this.existingContact,
    this.matchedBy,
  });

  factory CheckDuplicateResult.fromJson(Map<String, dynamic> json) {
    return CheckDuplicateResult(
      isDuplicate: json['isDuplicate'] as bool? ?? false,
      existingContact: json['existingContact'] != null
          ? ImportedContact.fromJson(json['existingContact'] as Map<String, dynamic>)
          : null,
      matchedBy: json['matchedBy'] as String?,
    );
  }
}
