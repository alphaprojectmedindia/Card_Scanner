import '../utils/weekday_helper.dart';

class AvailabilitySlot {
  final String? id;
  final int dayOfWeek; // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
  final String startTime; // "HH:mm"
  final String endTime; // "HH:mm"

  AvailabilitySlot({
    this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });

  static String dayOfWeekName(int day) => WeekdayHelper.getDayName(day);

  String get dayName => dayOfWeekName(dayOfWeek);

  factory AvailabilitySlot.fromJson(Map<String, dynamic> json) {
    return AvailabilitySlot(
      id: json['id']?.toString(),
      dayOfWeek: WeekdayHelper.parseBackendDayOfWeek(json['dayOfWeek']),
      startTime: json['startTime'] as String? ?? '09:00',
      endTime: json['endTime'] as String? ?? '17:00',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'endTime': endTime,
    };
  }

  AvailabilitySlot copyWith({
    String? id,
    int? dayOfWeek,
    String? startTime,
    String? endTime,
  }) {
    return AvailabilitySlot(
      id: id ?? this.id,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}

class AvailabilitySettings {
  final bool meetingRequestsEnabled;
  final String timeZoneId;
  final List<AvailabilitySlot> slots;

  AvailabilitySettings({
    this.meetingRequestsEnabled = true,
    this.timeZoneId = 'UTC',
    this.slots = const [],
  });

  factory AvailabilitySettings.fromJson(Map<String, dynamic> json) {
    var rawSlots = json['slots'] as List<dynamic>? ?? [];
    return AvailabilitySettings(
      meetingRequestsEnabled: json['meetingRequestsEnabled'] as bool? ?? true,
      timeZoneId: json['timeZoneId'] as String? ?? 'UTC',
      slots: rawSlots
          .map((s) => AvailabilitySlot.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'meetingRequestsEnabled': meetingRequestsEnabled,
      'timeZoneId': timeZoneId,
      'slots': slots.map((s) => s.toJson()).toList(),
    };
  }

  AvailabilitySettings copyWith({
    bool? meetingRequestsEnabled,
    String? timeZoneId,
    List<AvailabilitySlot>? slots,
  }) {
    return AvailabilitySettings(
      meetingRequestsEnabled:
          meetingRequestsEnabled ?? this.meetingRequestsEnabled,
      timeZoneId: timeZoneId ?? this.timeZoneId,
      slots: slots ?? this.slots,
    );
  }
}
