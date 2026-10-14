import 'package:flutter/material.dart';
import '../../models/availability_settings.dart';
import '../../services/api_client.dart';
import '../../services/availability_service.dart';
import '../../theme/app_spacing.dart';

class AvailabilitySettingsScreen extends StatefulWidget {
  final AvailabilityService? availabilityService;

  const AvailabilitySettingsScreen({
    super.key,
    this.availabilityService,
  });

  @override
  State<AvailabilitySettingsScreen> createState() =>
      _AvailabilitySettingsScreenState();
}

class _AvailabilitySettingsScreenState
    extends State<AvailabilitySettingsScreen> {
  late final AvailabilityService _availabilityService;

  bool _isLoading = true;
  bool _isSaving = false;
  String _errorMessage = '';
  String _validationError = '';

  bool _meetingRequestsEnabled = true;
  String _timeZoneId = 'UTC';
  List<AvailabilitySlot> _slots = [];

  static const List<String> _commonTimezones = [
    'UTC',
    'Asia/Kolkata',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'Europe/London',
    'Europe/Paris',
    'Europe/Berlin',
    'Asia/Dubai',
    'Asia/Singapore',
    'Asia/Tokyo',
    'Australia/Sydney',
  ];

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
      final settings = await _availabilityService.getAvailability();
      if (mounted) {
        setState(() {
          _meetingRequestsEnabled = settings.meetingRequestsEnabled;
          _timeZoneId = settings.timeZoneId.isNotEmpty ? settings.timeZoneId : 'UTC';
          _slots = List.from(settings.slots);
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

  // Weekdays in order Monday (1) to Sunday (0)
  final List<int> _daysOrder = [1, 2, 3, 4, 5, 6, 0];

  int _timeToMinutes(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final h = tod.hour.toString().padLeft(2, '0');
    final m = tod.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String? _validateSlots(List<AvailabilitySlot> slots) {
    for (final day in _daysOrder) {
      final daySlots = slots.where((s) => s.dayOfWeek == day).toList();
      for (final s in daySlots) {
        final startMin = _timeToMinutes(s.startTime);
        final endMin = _timeToMinutes(s.endTime);
        if (startMin >= endMin) {
          return 'Start time must be before end time for ${AvailabilitySlot.dayOfWeekName(day)}.';
        }
      }

      // Check overlap
      for (int i = 0; i < daySlots.length; i++) {
        for (int j = i + 1; j < daySlots.length; j++) {
          final aStart = _timeToMinutes(daySlots[i].startTime);
          final aEnd = _timeToMinutes(daySlots[i].endTime);
          final bStart = _timeToMinutes(daySlots[j].startTime);
          final bEnd = _timeToMinutes(daySlots[j].endTime);

          if (aStart < bEnd && aEnd > bStart) {
            return 'Overlapping slots detected on ${AvailabilitySlot.dayOfWeekName(day)} (${daySlots[i].startTime}-${daySlots[i].endTime} and ${daySlots[j].startTime}-${daySlots[j].endTime}).';
          }
        }
      }
    }
    return null;
  }

  void _removeSlot(AvailabilitySlot slot) {
    setState(() {
      _slots.remove(slot);
      _validationError = '';
    });
  }

  Future<void> _addSlotForDay(int day) async {
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);

    final result = await showDialog<AvailabilitySlot>(
      context: context,
      builder: (dialogCtx) {
        TimeOfDay tempStart = startTime;
        TimeOfDay tempEnd = endTime;
        String? dialogError;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            return AlertDialog(
              title: Text('Add Slot: ${AvailabilitySlot.dayOfWeekName(day)}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dialogError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        dialogError!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: tempStart,
                            );
                            if (picked != null) {
                              setDialogState(() {
                                tempStart = picked;
                                dialogError = null;
                              });
                            }
                          },
                          child: Text('Start: ${_formatTimeOfDay(tempStart)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: tempEnd,
                            );
                            if (picked != null) {
                              setDialogState(() {
                                tempEnd = picked;
                                dialogError = null;
                              });
                            }
                          },
                          child: Text('End: ${_formatTimeOfDay(tempEnd)}'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final startFormatted = _formatTimeOfDay(tempStart);
                    final endFormatted = _formatTimeOfDay(tempEnd);
                    final startMin = _timeToMinutes(startFormatted);
                    final endMin = _timeToMinutes(endFormatted);

                    if (startMin >= endMin) {
                      setDialogState(() {
                        dialogError = 'Start time must be before end time.';
                      });
                      return;
                    }

                    // Check overlap against existing slots for this day
                    final existing =
                        _slots.where((s) => s.dayOfWeek == day).toList();
                    for (final s in existing) {
                      final exStart = _timeToMinutes(s.startTime);
                      final exEnd = _timeToMinutes(s.endTime);
                      if (startMin < exEnd && endMin > exStart) {
                        setDialogState(() {
                          dialogError =
                              'Slot overlaps with ${s.startTime}-${s.endTime}.';
                        });
                        return;
                      }
                    }

                    Navigator.of(dialogCtx).pop(
                      AvailabilitySlot(
                        dayOfWeek: day,
                        startTime: startFormatted,
                        endTime: endFormatted,
                      ),
                    );
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _slots.add(result);
        _validationError = '';
      });
    }
  }

  Future<void> _handleSave() async {
    final validation = _validateSlots(_slots);
    if (validation != null) {
      setState(() {
        _validationError = validation;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _validationError = '';
    });

    try {
      final updated = await _availabilityService.updateAvailability(
        AvailabilitySettings(
          meetingRequestsEnabled: _meetingRequestsEnabled,
          timeZoneId: _timeZoneId,
          slots: _slots,
        ),
      );

      if (mounted) {
        setState(() {
          _meetingRequestsEnabled = updated.meetingRequestsEnabled;
          _timeZoneId = updated.timeZoneId;
          _slots = List.from(updated.slots);
          _isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Availability saved successfully.'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _validationError = e.message;
          _isSaving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _validationError = 'Failed to save availability.';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Availability Settings'),
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
                    // Timezone selection Card
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
                            Row(
                              children: [
                                Icon(
                                  Icons.language_rounded,
                                  color: theme.colorScheme.primary,
                                  size: 22,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  'Timezone',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Availability windows are interpreted in this timezone.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            DropdownButtonFormField<String>(
                              initialValue: _commonTimezones.contains(_timeZoneId)
                                  ? _timeZoneId
                                  : 'UTC',
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: AppSpacing.radiusMd,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                              items: _commonTimezones.map((tz) {
                                return DropdownMenuItem(
                                  value: tz,
                                  child: Text(tz),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _timeZoneId = val;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Meeting Requests Switch Card
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppSpacing.radiusLg,
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: SwitchListTile(
                        value: _meetingRequestsEnabled,
                        onChanged: (val) {
                          setState(() {
                            _meetingRequestsEnabled = val;
                          });
                        },
                        title: const Text(
                          'Meeting Requests',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          _meetingRequestsEnabled
                              ? 'Connections can request meetings during your available slots.'
                              : 'Meeting requests are currently unavailable.',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        activeThumbColor: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Weekly Availability Header
                    Text(
                      'Weekly Availability',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    if (_validationError.isNotEmpty) ...[
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
                                _validationError,
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

                    // Weekday Cards
                    ..._daysOrder.map((day) {
                      final daySlots =
                          _slots.where((s) => s.dayOfWeek == day).toList()
                            ..sort((a, b) => _timeToMinutes(a.startTime)
                                .compareTo(_timeToMinutes(b.startTime)));
                      final dayName = AvailabilitySlot.dayOfWeekName(day);

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
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    dayName,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _addSlotForDay(day),
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Add Slot'),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                              ),
                              if (daySlots.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.xs),
                                  child: Text(
                                    'Unavailable',
                                    style: TextStyle(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                      fontSize: 13,
                                    ),
                                  ),
                                )
                              else
                                ...daySlots.map((slot) {
                                  return Container(
                                    margin: const EdgeInsets.only(
                                        top: AppSpacing.xs),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md,
                                      vertical: AppSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.5),
                                      borderRadius: AppSpacing.radiusSm,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.access_time_rounded,
                                              size: 16,
                                              color: theme.colorScheme.primary,
                                            ),
                                            const SizedBox(
                                                width: AppSpacing.xs),
                                            Text(
                                              '${slot.startTime} – ${slot.endTime}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18,
                                          ),
                                          color: theme.colorScheme.error,
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => _removeSlot(slot),
                                          tooltip: 'Remove Slot',
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: AppSpacing.lg),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _handleSave,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppSpacing.radiusMd,
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Availability',
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
