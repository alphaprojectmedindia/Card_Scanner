import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../models/meeting.dart';
import '../../services/api_client.dart';
import '../../services/meeting_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_spacing.dart';
import '../../utils/timezone_helper.dart';

class MeetingDetailsScreen extends StatefulWidget {
  final Meeting meeting;
  final MeetingService? meetingService;
  final ProfileService? profileService;

  const MeetingDetailsScreen({
    super.key,
    required this.meeting,
    this.meetingService,
    this.profileService,
  });

  @override
  State<MeetingDetailsScreen> createState() => _MeetingDetailsScreenState();
}

class _MeetingDetailsScreenState extends State<MeetingDetailsScreen> {
  late final MeetingService _meetingService;
  late final ProfileService _profileService;

  late Meeting _meeting;
  String _currentUserId = '';
  bool _isActionInProgress = false;
  String _actionError = '';

  @override
  void initState() {
    super.initState();
    _meeting = widget.meeting;
    _meetingService = widget.meetingService ?? MeetingService();
    _profileService = widget.profileService ?? ProfileService();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final profile = await _profileService.getMyProfile();
      if (mounted) {
        setState(() {
          _currentUserId = profile.userId;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleAccept() async {
    setState(() {
      _isActionInProgress = true;
      _actionError = '';
    });

    try {
      final updated = await _meetingService.acceptMeeting(_meeting.id);
      if (mounted) {
        setState(() {
          _meeting = updated;
          _isActionInProgress = false;
        });
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
        setState(() {
          _actionError = 'That time is no longer available.';
          _isActionInProgress = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _actionError = e.message;
          _isActionInProgress = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _actionError = 'Unable to accept meeting.';
          _isActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleReject() async {
    setState(() {
      _isActionInProgress = true;
      _actionError = '';
    });

    try {
      final updated = await _meetingService.rejectMeeting(_meeting.id);
      if (mounted) {
        setState(() {
          _meeting = updated;
          _isActionInProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Meeting request rejected.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _actionError = e.message;
          _isActionInProgress = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _actionError = 'Unable to reject meeting.';
          _isActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Meeting?'),
        content: const Text('Are you sure you want to cancel this meeting?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isActionInProgress = true;
      _actionError = '';
    });

    try {
      final updated = await _meetingService.cancelMeeting(_meeting.id);
      if (mounted) {
        setState(() {
          _meeting = updated;
          _isActionInProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Meeting cancelled.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _actionError = e.message;
          _isActionInProgress = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _actionError = 'Unable to cancel meeting.';
          _isActionInProgress = false;
        });
      }
    }
  }

  Color _getStatusColor(String status, ThemeData theme) {
    switch (status) {
      case MeetingStatus.accepted:
        return theme.colorScheme.primary;
      case MeetingStatus.pending:
        return Colors.orange.shade700;
      case MeetingStatus.rejected:
        return theme.colorScheme.error;
      case MeetingStatus.cancelled:
        return theme.colorScheme.onSurfaceVariant;
      default:
        return theme.colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final otherName = _meeting.otherParticipantName(_currentUserId);
    final otherPhoto = _meeting.otherParticipantPhotoUrl(_currentUserId);
    final isRecipient = _meeting.isRecipient(_currentUserId);
    final isRequester = _meeting.isRequester(_currentUserId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meeting Details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Header Card with participant info
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: AppSpacing.radiusLg,
              side: BorderSide(
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: ApiConfig.resolveImageUrl(otherPhoto) != null
                        ? NetworkImage(
                            ApiConfig.resolveImageUrl(otherPhoto)!)
                        : null,
                    child: ApiConfig.resolveImageUrl(otherPhoto) == null
                        ? Icon(
                            Icons.person,
                            color: theme.colorScheme.primary,
                            size: 32,
                          )
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Meeting with',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          otherName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(_meeting.status, theme)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _meeting.status.toUpperCase(),
                            style: TextStyle(
                              color: _getStatusColor(_meeting.status, theme),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Error banner if any
          if (_actionError.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: AppSpacing.radiusMd,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: theme.colorScheme.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _actionError,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Details Card
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: AppSpacing.radiusLg,
              side: BorderSide(
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    'Title',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _meeting.title?.isNotEmpty == true
                        ? _meeting.title!
                        : 'No title provided',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(height: 24),

                  // Date and Time
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date & Time (Local)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '${TimezoneHelper.formatDateTime(_meeting.localStartTime)} – ${_meeting.localEndTime.hour.toString().padLeft(2, '0')}:${_meeting.localEndTime.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text('${_meeting.durationMinutes} min'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),

                  // Note (if present)
                  if (_meeting.note?.isNotEmpty == true) ...[
                    const Divider(height: 24),
                    Text(
                      'Note',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _meeting.note!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Action Buttons depending on status & role
          if (_isActionInProgress)
            const Center(child: CircularProgressIndicator())
          else ...[
            // 1. Incoming Pending Request -> Reject / Accept
            if (_meeting.status == MeetingStatus.pending && isRecipient) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _handleReject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        side: BorderSide(color: theme.colorScheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppSpacing.radiusMd,
                        ),
                      ),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _handleAccept,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppSpacing.radiusMd,
                        ),
                      ),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],

            // 2. Outgoing Pending Request -> Cancel Request
            if (_meeting.status == MeetingStatus.pending && isRequester) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _handleCancel,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel Request'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppSpacing.radiusMd,
                    ),
                  ),
                ),
              ),
            ],

            // 3. Accepted Meeting -> Cancel Meeting (allowed by either participant)
            if (_meeting.status == MeetingStatus.accepted) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _handleCancel,
                  icon: Icon(
                    Icons.cancel_outlined,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    'Cancel Meeting',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: theme.colorScheme.error.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppSpacing.radiusMd,
                    ),
                  ),
                ),
              ),
            ],
          ],

          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}
