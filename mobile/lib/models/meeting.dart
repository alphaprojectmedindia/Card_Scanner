class MeetingStatus {
  static const String pending = 'Pending';
  static const String accepted = 'Accepted';
  static const String rejected = 'Rejected';
  static const String cancelled = 'Cancelled';
}

class Meeting {
  final String id;
  final String requesterUserId;
  final String requesterName;
  final String? requesterPhotoUrl;
  final String recipientUserId;
  final String recipientName;
  final String? recipientPhotoUrl;
  final DateTime startAtUtc;
  final DateTime endAtUtc;
  final String? title;
  final String? note;
  final String status;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  Meeting({
    required this.id,
    required this.requesterUserId,
    required this.requesterName,
    this.requesterPhotoUrl,
    required this.recipientUserId,
    required this.recipientName,
    this.recipientPhotoUrl,
    required this.startAtUtc,
    required this.endAtUtc,
    this.title,
    this.note,
    required this.status,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  Duration get duration => endAtUtc.difference(startAtUtc);
  int get durationMinutes => duration.inMinutes;

  DateTime get localStartTime => startAtUtc.toLocal();
  DateTime get localEndTime => endAtUtc.toLocal();

  bool isRequester(String currentUserId) => requesterUserId == currentUserId;
  bool isRecipient(String currentUserId) => recipientUserId == currentUserId;

  String otherParticipantName(String currentUserId) {
    if (isRequester(currentUserId)) {
      return recipientName.isNotEmpty ? recipientName : 'Connection';
    }
    return requesterName.isNotEmpty ? requesterName : 'Connection';
  }

  String? otherParticipantPhotoUrl(String currentUserId) {
    if (isRequester(currentUserId)) {
      return recipientPhotoUrl;
    }
    return requesterPhotoUrl;
  }

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: json['id']?.toString() ?? '',
      requesterUserId: json['requesterUserId'] as String? ?? '',
      requesterName: json['requesterName'] as String? ?? '',
      requesterPhotoUrl: json['requesterPhotoUrl'] as String?,
      recipientUserId: json['recipientUserId'] as String? ?? '',
      recipientName: json['recipientName'] as String? ?? '',
      recipientPhotoUrl: json['recipientPhotoUrl'] as String?,
      startAtUtc: json['startAtUtc'] != null
          ? DateTime.tryParse(json['startAtUtc'] as String)?.toUtc() ??
              DateTime.now().toUtc()
          : DateTime.now().toUtc(),
      endAtUtc: json['endAtUtc'] != null
          ? DateTime.tryParse(json['endAtUtc'] as String)?.toUtc() ??
              DateTime.now().toUtc()
          : DateTime.now().toUtc(),
      title: json['title'] as String?,
      note: json['note'] as String?,
      status: json['status'] as String? ?? MeetingStatus.pending,
      createdAtUtc: json['createdAtUtc'] != null
          ? DateTime.tryParse(json['createdAtUtc'] as String)?.toUtc() ??
              DateTime.now().toUtc()
          : DateTime.now().toUtc(),
      updatedAtUtc: json['updatedAtUtc'] != null
          ? DateTime.tryParse(json['updatedAtUtc'] as String)?.toUtc() ??
              DateTime.now().toUtc()
          : DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'requesterUserId': requesterUserId,
      'requesterName': requesterName,
      'requesterPhotoUrl': requesterPhotoUrl,
      'recipientUserId': recipientUserId,
      'recipientName': recipientName,
      'recipientPhotoUrl': recipientPhotoUrl,
      'startAtUtc': startAtUtc.toIso8601String(),
      'endAtUtc': endAtUtc.toIso8601String(),
      'title': title,
      'note': note,
      'status': status,
      'createdAtUtc': createdAtUtc.toIso8601String(),
      'updatedAtUtc': updatedAtUtc.toIso8601String(),
    };
  }
}

class MeetingListResponse {
  final List<Meeting> upcoming;
  final List<Meeting> requests;
  final List<Meeting> history;

  MeetingListResponse({
    this.upcoming = const [],
    this.requests = const [],
    this.history = const [],
  });

  factory MeetingListResponse.fromJson(Map<String, dynamic> json) {
    var rawUpcoming = json['upcoming'] as List<dynamic>? ?? [];
    var rawRequests = json['requests'] as List<dynamic>? ?? [];
    var rawHistory = json['history'] as List<dynamic>? ?? [];

    return MeetingListResponse(
      upcoming: rawUpcoming
          .map((m) => Meeting.fromJson(m as Map<String, dynamic>))
          .toList(),
      requests: rawRequests
          .map((m) => Meeting.fromJson(m as Map<String, dynamic>))
          .toList(),
      history: rawHistory
          .map((m) => Meeting.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}
