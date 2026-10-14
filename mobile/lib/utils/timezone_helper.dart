class TimezoneHelper {
  TimezoneHelper._();

  /// Map of known timezone identifiers to standard offsets in minutes.
  /// Positive for east of UTC, negative for west of UTC.
  static final Map<String, int> _standardOffsetsInMinutes = {
    'UTC': 0,
    'GMT': 0,
    'Asia/Kolkata': 330, // +05:30
    'India Standard Time': 330,
    'Asia/Dubai': 240, // +04:00
    'Asia/Singapore': 480, // +08:00
    'Asia/Tokyo': 540, // +09:00
    'Asia/Hong_Kong': 480, // +08:00
    'Asia/Shanghai': 480, // +08:00
    'Asia/Bangkok': 420, // +07:00
    'Asia/Dhaka': 360, // +06:00
    'Asia/Karachi': 300, // +05:00
    'Europe/London': 0, // GMT standard (or +60 BST in summer)
    'Europe/Paris': 60, // CET standard (+120 CEST)
    'Europe/Berlin': 60,
    'Europe/Rome': 60,
    'Europe/Madrid': 60,
    'America/New_York': -300, // EST (-240 EDT)
    'America/Chicago': -360, // CST (-300 CDT)
    'America/Denver': -420, // MST (-360 MDT)
    'America/Los_Angeles': -480, // PST (-420 PDT)
    'America/Toronto': -300,
    'America/Vancouver': -480,
    'America/Sao_Paulo': -180,
    'Australia/Sydney': 600, // AEST (+660 AEDT)
    'Australia/Melbourne': 600,
    'Australia/Perth': 480,
  };

  /// Returns estimated offset in minutes for a given timezone identifier and date,
  /// factoring in US/Europe daylight saving time where applicable.
  static int getOffsetInMinutes(String timeZoneId, DateTime date) {
    final tz = timeZoneId.trim();

    // Check if timezone is UTC
    if (tz.toUpperCase() == 'UTC' || tz.toUpperCase() == 'GMT') {
      return 0;
    }

    // DST approximation for US (2nd Sunday in March to 1st Sunday in Nov)
    bool isUsDst = date.month > 3 && date.month < 11;
    // DST approximation for EU (last Sunday in March to last Sunday in Oct)
    bool isEuDst = date.month > 3 && date.month < 10;

    if (tz.startsWith('America/')) {
      int standard = _standardOffsetsInMinutes[tz] ?? -300;
      return isUsDst ? standard + 60 : standard;
    }

    if (tz.startsWith('Europe/')) {
      int standard = _standardOffsetsInMinutes[tz] ?? 60;
      return isEuDst ? standard + 60 : standard;
    }

    if (_standardOffsetsInMinutes.containsKey(tz)) {
      return _standardOffsetsInMinutes[tz]!;
    }

    // Fallback: device's local timezone offset if unknown
    return date.timeZoneOffset.inMinutes;
  }

  /// Converts a wall-clock date and time in the specified timezone to UTC.
  static DateTime wallClockToUtc({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
    required String timeZoneId,
  }) {
    final targetDate = DateTime(year, month, day, hour, minute);
    final offsetMinutes = getOffsetInMinutes(timeZoneId, targetDate);
    final naiveUtc = DateTime.utc(year, month, day, hour, minute);
    return naiveUtc.subtract(Duration(minutes: offsetMinutes));
  }

  /// Formats a DateTime for user display with its local time.
  static String formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final y = local.year;
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  /// Returns the current wall-clock DateTime in the target timezone.
  static DateTime getNowInTimezone(String timeZoneId, [DateTime? currentUtc]) {
    final utc = (currentUtc ?? DateTime.now()).toUtc();
    final offsetMin = getOffsetInMinutes(timeZoneId, utc);
    return utc.add(Duration(minutes: offsetMin));
  }

  /// Parses a time string (in 24-hour "HH:mm" or 12-hour "h:mm a") into minutes from midnight.
  static int parseTimeToMinutes(String timeStr) {
    final trimmed = timeStr.trim().toUpperCase();
    bool isPm = trimmed.endsWith('PM');
    bool isAm = trimmed.endsWith('AM');
    final clean = trimmed.replaceAll('PM', '').replaceAll('AM', '').trim();
    final parts = clean.split(':');
    if (parts.length != 2) return 0;
    int hour = int.tryParse(parts[0].trim()) ?? 0;
    int min = int.tryParse(parts[1].trim()) ?? 0;
    if (isPm && hour < 12) hour += 12;
    if (isAm && hour == 12) hour = 0;
    return hour * 60 + min;
  }
}

