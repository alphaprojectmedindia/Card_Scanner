import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../models/availability_settings.dart';
import '../../models/public_availability.dart';
import '../../services/api_client.dart';
import '../../services/availability_service.dart';
import '../../theme/app_spacing.dart';
import '../meetings/request_meeting_screen.dart';

class AvailabilityViewerScreen extends StatefulWidget {
  final String targetUserId;
  final String userName;
  final String? userPhotoUrl;
  final AvailabilityService? availabilityService;

  const AvailabilityViewerScreen({
    super.key,
    required this.targetUserId,
    required this.userName,
    this.userPhotoUrl,
    this.availabilityService,
  });

  @override
  State<AvailabilityViewerScreen> createState() =>
      _AvailabilityViewerScreenState();
}

class _AvailabilityViewerScreenState extends State<AvailabilityViewerScreen> {
  late final AvailabilityService _availabilityService;

  bool _isLoading = true;
  String _errorMessage = '';
  PublicAvailability? _availability;

  final List<int> _daysOrder = [1, 2, 3, 4, 5, 6, 0];

  @override
  void initState() {
    super.initState();
    _availabilityService =
        widget.availabilityService ?? AvailabilityService();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final res =
          await _availabilityService.getUserAvailability(widget.targetUserId);
      if (mounted) {
        setState(() {
          _availability = res;
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
          _errorMessage = "Couldn't load availability.";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = _availability?.fullName.isNotEmpty == true
        ? _availability!.fullName
        : widget.userName;
    final photoUrl = _availability?.profilePhotoUrl ?? widget.userPhotoUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text("$displayName's Availability"),
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
                          onPressed: _loadAvailability,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    // User Header Card
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
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              backgroundImage:
                                  ApiConfig.resolveImageUrl(photoUrl) != null
                                      ? NetworkImage(
                                          ApiConfig.resolveImageUrl(photoUrl)!)
                                      : null,
                              child:
                                  ApiConfig.resolveImageUrl(photoUrl) == null
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
                                    displayName,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.language_rounded,
                                        size: 15,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Timezone: ${_availability?.timeZoneId ?? "UTC"}',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Disabled notice if meeting requests are off
                    if (_availability?.meetingRequestsEnabled == false) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer
                              .withValues(alpha: 0.6),
                          borderRadius: AppSpacing.radiusMd,
                          border: Border.all(
                            color: theme.colorScheme.error.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.event_busy_rounded,
                              color: theme.colorScheme.error,
                              size: 22,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Meeting requests are currently unavailable.',
                                style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Weekly Availability Title
                    Text(
                      'Weekly Schedule',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    // Days listing
                    ..._daysOrder.map((day) {
                      final daySlots = (_availability?.slots ?? [])
                          .where((s) => s.dayOfWeek == day)
                          .toList()
                        ..sort((a, b) => a.startTime.compareTo(b.startTime));
                      final dayName = AvailabilitySlot.dayOfWeekName(day);

                      return Card(
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppSpacing.radiusMd,
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                dayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (daySlots.isEmpty)
                                Text(
                                  'Unavailable',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 13,
                                  ),
                                )
                              else
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: daySlots.map((s) {
                                    return Text(
                                      '${s.startTime} – ${s.endTime}',
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    );
                                  }).toList(),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: AppSpacing.xl),

                    // Request Meeting Button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _availability?.meetingRequestsEnabled == true
                            ? () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => RequestMeetingScreen(
                                      availability: _availability!,
                                    ),
                                  ),
                                );
                              }
                            : null,
                        icon: const Icon(Icons.add_task_rounded),
                        label: const Text(
                          'Request Meeting',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppSpacing.radiusMd,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
    );
  }
}
