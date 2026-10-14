import '../config/api_config.dart';
import '../models/meeting.dart';
import 'api_client.dart';

class MeetingService {
  final ApiClient _apiClient;

  MeetingService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// Create a new meeting request with a connected Digital Share user.
  Future<Meeting> createMeeting({
    required String recipientUserId,
    required DateTime startAtUtc,
    required DateTime endAtUtc,
    String? title,
    String? note,
  }) async {
    final response = await _apiClient.post(
      ApiConfig.meetingsEndpoint,
      body: {
        'recipientUserId': recipientUserId.trim(),
        'startAtUtc': startAtUtc.toIso8601String(),
        'endAtUtc': endAtUtc.toIso8601String(),
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
      requiresAuth: true,
    );

    if (response is Map<String, dynamic>) {
      return Meeting.fromJson(response);
    }

    throw ApiException('Unable to send meeting request.');
  }

  /// Retrieve all meetings grouped into Upcoming, Requests, and History.
  Future<MeetingListResponse> getMeetings() async {
    final response = await _apiClient.get(
      ApiConfig.meetingsEndpoint,
      requiresAuth: true,
    );

    if (response is Map<String, dynamic>) {
      return MeetingListResponse.fromJson(response);
    }

    throw ApiException("Couldn't load meetings.");
  }

  /// Retrieve a specific meeting by ID.
  Future<Meeting> getMeetingById(String id) async {
    final response = await _apiClient.get(
      ApiConfig.meetingByIdEndpoint(id.trim()),
      requiresAuth: true,
    );

    if (response is Map<String, dynamic>) {
      return Meeting.fromJson(response);
    }

    throw ApiException('Meeting not found.');
  }

  /// Accept an incoming meeting request.
  Future<Meeting> acceptMeeting(String id) async {
    final response = await _apiClient.post(
      ApiConfig.acceptMeetingEndpoint(id.trim()),
      requiresAuth: true,
    );

    if (response is Map<String, dynamic>) {
      return Meeting.fromJson(response);
    }

    throw ApiException('Unable to accept meeting.');
  }

  /// Reject an incoming meeting request.
  Future<Meeting> rejectMeeting(String id) async {
    final response = await _apiClient.post(
      ApiConfig.rejectMeetingEndpoint(id.trim()),
      requiresAuth: true,
    );

    if (response is Map<String, dynamic>) {
      return Meeting.fromJson(response);
    }

    throw ApiException('Unable to reject meeting.');
  }

  /// Cancel a pending or accepted meeting.
  Future<Meeting> cancelMeeting(String id) async {
    final response = await _apiClient.post(
      ApiConfig.cancelMeetingEndpoint(id.trim()),
      requiresAuth: true,
    );

    if (response is Map<String, dynamic>) {
      return Meeting.fromJson(response);
    }

    throw ApiException('Unable to cancel meeting.');
  }
}
