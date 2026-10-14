import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../models/availability_settings.dart';
import '../../models/public_availability.dart';
import '../../services/api_client.dart';
import '../../services/meeting_service.dart';
import '../../theme/app_spacing.dart';
import '../../utils/timezone_helper.dart';
import '../../utils/weekday_helper.dart';

class RequestMeetingScreen extends StatefulWidget {
  final PublicAvailability availability;
  final MeetingService? meetingService;
  final DateTime? initialDate;

  const RequestMeetingScreen({
    super.key,
    required this.availability,
    this.meetingService,
    this.initialDate,
  });

  @override
  State<RequestMeetingScreen> createState() => _RequestMeetingScreenState();
}

class _RequestMeetingScreenState extends State<RequestMeetingScreen> {
  late final MeetingService _meetingService;

  DateTime? _selectedDate;
  int _selectedDurationMinutes = 30; // 15, 30, 45, 60
  String? _selectedStartTime; // "HH:mm"

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  bool _isSending = false;
  String _errorMessage = '';

  final List<int> _durations = [15, 30, 45, 60];

  @override
  void initState() {
    super.initState();
    _meetingService = widget.meetingService ?? MeetingService();
    _selectedDate = widget.initialDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _minutesToTime(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  int get _selectedBackendDayOfWeek => _selectedDate != null
      ? WeekdayHelper.toBackendDayOfWeek(_selectedDate!.weekday)
      : -1;

  List<AvailabilitySlot> get _daySlots {
    if (_selectedDate == null) return [];
    return widget.availability.slots
        .where((s) => s.dayOfWeek == _selectedBackendDayOfWeek)
        .toList();
  }

  // Returns list of valid start times for the selected date and duration
  List<String> _getAvailableStartTimes() {
    if (_selectedDate == null) return [];

    final daySlots = _daySlots;
    if (daySlots.isEmpty) return [];

    final recipientNow =
        TimezoneHelper.getNowInTimezone(widget.availability.timeZoneId);
    final isTodayInRecipientTz = _selectedDate!.year == recipientNow.year &&
        _selectedDate!.month == recipientNow.month &&
        _selectedDate!.day == recipientNow.day;
    final currentMinutesInRecipientTz =
        recipientNow.hour * 60 + recipientNow.minute;

    final availableTimesSet = <String>{};

    for (final slot in daySlots) {
      final slotStartMin = TimezoneHelper.parseTimeToMinutes(slot.startTime);
      final slotEndMin = TimezoneHelper.parseTimeToMinutes(slot.endTime);

      if (slotStartMin >= slotEndMin) continue;

      // Candidate start times every 15 minutes
      for (int m = slotStartMin;
          m + _selectedDurationMinutes <= slotEndMin;
          m += 15) {
        if (isTodayInRecipientTz && m <= currentMinutesInRecipientTz) {
          continue;
        }
        final timeStr = _minutesToTime(m);
        availableTimesSet.add(timeStr);
      }
    }

    final list = availableTimesSet.toList()
      ..sort((a, b) => TimezoneHelper.parseTimeToMinutes(a)
          .compareTo(TimezoneHelper.parseTimeToMinutes(b)));
    return list;
  }

  void _revalidateSelectedTime() {
    final available = _getAvailableStartTimes();
    if (_selectedStartTime != null && !available.contains(_selectedStartTime)) {
      _selectedStartTime = null;
    }
  }

  bool get _isFormValid {
    if (_isSending) return false;
    if (_selectedDate == null) return false;
    if (_selectedStartTime == null) return false;
    final available = _getAvailableStartTimes();
    return available.contains(_selectedStartTime);
  }

  Future<void> _pickDate() async {
    final recipientNow =
        TimezoneHelper.getNowInTimezone(widget.availability.timeZoneId);
    final firstDate =
        DateTime(recipientNow.year, recipientNow.month, recipientNow.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate != null && !_selectedDate!.isBefore(firstDate)
          ? _selectedDate!
          : firstDate,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _errorMessage = '';
        _revalidateSelectedTime();
      });
    }
  }

  Future<void> _handleSendRequest() async {
    if (!_isFormValid) return;

    setState(() {
      _isSending = true;
      _errorMessage = '';
    });

    final parts = _selectedStartTime!.split(':');
    final startHour = int.parse(parts[0]);
    final startMin = int.parse(parts[1]);

    final startAtUtc = TimezoneHelper.wallClockToUtc(
      year: _selectedDate!.year,
      month: _selectedDate!.month,
      day: _selectedDate!.day,
      hour: startHour,
      minute: startMin,
      timeZoneId: widget.availability.timeZoneId,
    );

    final endAtUtc =
        startAtUtc.add(Duration(minutes: _selectedDurationMinutes));

    try {
      await _meetingService.createMeeting(
        recipientUserId: widget.availability.userId,
        startAtUtc: startAtUtc,
        endAtUtc: endAtUtc,
        title: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : null,
        note: _noteController.text.trim().isNotEmpty
            ? _noteController.text.trim()
            : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Meeting request sent successfully!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } on ConflictException {
      if (mounted) {
        setState(() {
          _errorMessage = 'That time is no longer available.';
          _isSending = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isSending = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Unable to send meeting request.';
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availableTimes = _getAvailableStartTimes();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Meeting'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Meeting with header Card
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
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: ApiConfig.resolveImageUrl(
                                widget.availability.profilePhotoUrl) !=
                            null
                        ? NetworkImage(ApiConfig.resolveImageUrl(
                            widget.availability.profilePhotoUrl)!)
                        : null,
                    child: ApiConfig.resolveImageUrl(
                                widget.availability.profilePhotoUrl) ==
                            null
                        ? Icon(
                            Icons.person,
                            color: theme.colorScheme.primary,
                            size: 28,
                          )
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.md),
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
                          widget.availability.fullName.isNotEmpty
                              ? widget.availability.fullName
                              : 'Connection',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Timezone: ${widget.availability.timeZoneId}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
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
          if (_errorMessage.isNotEmpty) ...[
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
                      _errorMessage,
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

          // 1. Date selection
          Text(
            'Date',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text(
              _selectedDate != null
                  ? '${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year} (${WeekdayHelper.getDayName(_selectedBackendDayOfWeek)})'
                  : 'Select Date',
              style: TextStyle(
                fontWeight: _selectedDate != null
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              alignment: Alignment.centerLeft,
              shape: RoundedRectangleBorder(
                borderRadius: AppSpacing.radiusMd,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 2. Duration selection
          Text(
            'Duration',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: 8,
            children: _durations.map((duration) {
              final isSelected = _selectedDurationMinutes == duration;
              return ChoiceChip(
                label: Text('$duration min'),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedDurationMinutes = duration;
                      _revalidateSelectedTime();
                    });
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 3. Time selection (filtered strictly to available slots)
          Text(
            'Time',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (_selectedDate == null)
            Text(
              'Select a date first to view available times.',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            )
          else if (_daySlots.isEmpty)
            Text(
              'No availability on this day.',
              style: TextStyle(
                color: theme.colorScheme.error,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            )
          else if (availableTimes.isEmpty)
            Text(
              'No available times for a $_selectedDurationMinutes-minute meeting.',
              style: TextStyle(
                color: theme.colorScheme.error,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: availableTimes.map((time) {
                final isSelected = _selectedStartTime == time;
                return ChoiceChip(
                  label: Text(time),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedStartTime = selected ? time : null;
                    });
                  },
                );
              }).toList(),
            ),
          const SizedBox(height: AppSpacing.lg),

          // 4. Meeting Title
          Text(
            'Title',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: 'e.g. Project Discussion',
              border: OutlineInputBorder(
                borderRadius: AppSpacing.radiusMd,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 5. Meeting Note
          Text(
            'Note',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _noteController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: "e.g. Let's discuss the project roadmap.",
              border: OutlineInputBorder(
                borderRadius: AppSpacing.radiusMd,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Send Button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isFormValid ? _handleSendRequest : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: AppSpacing.radiusMd,
                ),
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Send Request',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
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
