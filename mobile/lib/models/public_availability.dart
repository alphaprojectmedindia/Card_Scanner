import 'availability_settings.dart';

class PublicAvailability {
  final String userId;
  final String fullName;
  final String? profilePhotoUrl;
  final bool meetingRequestsEnabled;
  final String timeZoneId;
  final List<AvailabilitySlot> slots;

  PublicAvailability({
    required this.userId,
    required this.fullName,
    this.profilePhotoUrl,
    required this.meetingRequestsEnabled,
    required this.timeZoneId,
    required this.slots,
  });

  factory PublicAvailability.fromJson(Map<String, dynamic> json) {
    var rawSlots = json['slots'] as List<dynamic>? ?? [];
    return PublicAvailability(
      userId: json['userId'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      meetingRequestsEnabled: json['meetingRequestsEnabled'] as bool? ?? true,
      timeZoneId: json['timeZoneId'] as String? ?? 'UTC',
      slots: rawSlots
          .map((s) => AvailabilitySlot.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
