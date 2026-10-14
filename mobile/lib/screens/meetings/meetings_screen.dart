import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../models/meeting.dart';
import '../../services/api_client.dart';
import '../../services/meeting_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_spacing.dart';
import '../../utils/timezone_helper.dart';
import 'meeting_details_screen.dart';

class MeetingsScreen extends StatefulWidget {
  final MeetingService? meetingService;
  final ProfileService? profileService;

  const MeetingsScreen({
    super.key,
    this.meetingService,
    this.profileService,
  });

  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen> {
  late final MeetingService _meetingService;
  late final ProfileService _profileService;

  bool _isLoading = true;
  String _errorMessage = '';
  MeetingListResponse? _meetings;
  String _currentUserId = '';

  @override
  void initState() {
    super.initState();
    _meetingService = widget.meetingService ?? MeetingService();
    _profileService = widget.profileService ?? ProfileService();
    _loadMeetings();
  }

  Future<void> _loadMeetings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final profile = await _profileService.getMyProfile();
      _currentUserId = profile.userId;

      final res = await _meetingService.getMeetings();
      if (mounted) {
        setState(() {
          _meetings = res;
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = "Couldn't load meetings.";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _quickAccept(Meeting meeting) async {
    try {
      await _meetingService.acceptMeeting(meeting.id);
      _loadMeetings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Meeting request accepted!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ConflictException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('That time is no longer available.'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _quickReject(Meeting meeting) async {
    try {
      await _meetingService.rejectMeeting(meeting.id);
      _loadMeetings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Meeting request rejected.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeetingCard(Meeting meeting, {bool isRequestsTab = false}) {
    final theme = Theme.of(context);
    final otherName = meeting.otherParticipantName(_currentUserId);
    final otherPhoto = meeting.otherParticipantPhotoUrl(_currentUserId);
    final isRecipient = meeting.isRecipient(_currentUserId);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.radiusLg,
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: AppSpacing.radiusLg,
        onTap: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (_) => MeetingDetailsScreen(
                    meeting: meeting,
                    meetingService: _meetingService,
                  ),
                ),
              )
              .then((_) => _loadMeetings());
        },
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: ApiConfig.resolveImageUrl(otherPhoto) !=
                            null
                        ? NetworkImage(
                            ApiConfig.resolveImageUrl(otherPhoto)!)
                        : null,
                    child: ApiConfig.resolveImageUrl(otherPhoto) == null
                        ? Icon(
                            Icons.person,
                            color: theme.colorScheme.primary,
                            size: 24,
                          )
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          otherName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (meeting.title?.isNotEmpty == true)
                          Text(
                            meeting.title!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: meeting.status == MeetingStatus.accepted
                          ? theme.colorScheme.primaryContainer
                          : meeting.status == MeetingStatus.pending
                              ? Colors.orange.withValues(alpha: 0.15)
                              : meeting.status == MeetingStatus.rejected
                                  ? theme.colorScheme.errorContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      meeting.status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: meeting.status == MeetingStatus.accepted
                            ? theme.colorScheme.onPrimaryContainer
                            : meeting.status == MeetingStatus.pending
                                ? Colors.orange.shade800
                                : meeting.status == MeetingStatus.rejected
                                    ? theme.colorScheme.onErrorContainer
                                    : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${TimezoneHelper.formatDateTime(meeting.localStartTime)} (${meeting.durationMinutes} min)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),

              // Quick action buttons on Requests tab for incoming pending requests
              if (isRequestsTab &&
                  meeting.status == MeetingStatus.pending &&
                  isRecipient) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _quickReject(meeting),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(color: theme.colorScheme.error),
                        ),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _quickAccept(meeting),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Accept'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Meetings'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Requests'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 48,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(_errorMessage, textAlign: TextAlign.center),
                          const SizedBox(height: AppSpacing.md),
                          FilledButton.tonal(
                            onPressed: _loadMeetings,
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : TabBarView(
                    children: [
                      // 1. UPCOMING TAB
                      RefreshIndicator(
                        onRefresh: _loadMeetings,
                        child: (_meetings?.upcoming.isEmpty ?? true)
                            ? _buildEmptyState(
                                icon: Icons.event_available_outlined,
                                title: 'No upcoming meetings.',
                                message:
                                    'Your accepted future appointments will appear here.',
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                itemCount: _meetings!.upcoming.length,
                                itemBuilder: (context, index) {
                                  return _buildMeetingCard(
                                      _meetings!.upcoming[index]);
                                },
                              ),
                      ),

                      // 2. REQUESTS TAB
                      RefreshIndicator(
                        onRefresh: _loadMeetings,
                        child: (_meetings?.requests.isEmpty ?? true)
                            ? _buildEmptyState(
                                icon: Icons.pending_actions_outlined,
                                title: 'No meeting requests.',
                                message:
                                    'Pending incoming and outgoing requests will appear here.',
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                itemCount: _meetings!.requests.length,
                                itemBuilder: (context, index) {
                                  return _buildMeetingCard(
                                    _meetings!.requests[index],
                                    isRequestsTab: true,
                                  );
                                },
                              ),
                      ),

                      // 3. HISTORY TAB
                      RefreshIndicator(
                        onRefresh: _loadMeetings,
                        child: (_meetings?.history.isEmpty ?? true)
                            ? _buildEmptyState(
                                icon: Icons.history_rounded,
                                title: 'No previous meetings.',
                                message:
                                    'Past, cancelled, and rejected meetings will be archived here.',
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                itemCount: _meetings!.history.length,
                                itemBuilder: (context, index) {
                                  return _buildMeetingCard(
                                      _meetings!.history[index]);
                                },
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
