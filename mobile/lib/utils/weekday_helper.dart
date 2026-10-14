/// Centralized helper for explicit conversion between Dart DateTime weekday (1=Monday..7=Sunday)
/// and backend DayOfWeek (0=Sunday..6=Saturday).
class WeekdayHelper {
  WeekdayHelper._();

  /// Converts Dart DateTime.weekday (Monday=1 .. Sunday=7) to backend DayOfWeek (Sunday=0 .. Saturday=6).
  ///
  /// Examples:
  /// - DateTime.monday (1) -> 1
  /// - DateTime.tuesday (2) -> 2
  /// - DateTime.wednesday (3) -> 3
  /// - DateTime.thursday (4) -> 4
  /// - DateTime.friday (5) -> 5
  /// - DateTime.saturday (6) -> 6
  /// - DateTime.sunday (7) -> 0
  static int toBackendDayOfWeek(int dartWeekday) {
    return dartWeekday == DateTime.sunday ? 0 : dartWeekday;
  }

  /// Converts backend DayOfWeek (Sunday=0 .. Saturday=6) to Dart DateTime.weekday (Monday=1 .. Sunday=7).
  ///
  /// Examples:
  /// - 0 (Sunday) -> DateTime.sunday (7)
  /// - 1 (Monday) -> DateTime.monday (1)
  /// - 2 (Tuesday) -> DateTime.tuesday (2)
  /// - 3 (Wednesday) -> DateTime.wednesday (3)
  /// - 4 (Thursday) -> DateTime.thursday (4)
  /// - 5 (Friday) -> DateTime.friday (5)
  /// - 6 (Saturday) -> DateTime.saturday (6)
  static int toDartWeekday(int backendDayOfWeek) {
    return backendDayOfWeek == 0 ? DateTime.sunday : backendDayOfWeek;
  }

  /// Returns the human-readable English day name for a backend DayOfWeek (0=Sunday .. 6=Saturday).
  static String getDayName(int backendDayOfWeek) {
    switch (backendDayOfWeek) {
      case 0:
        return 'Sunday';
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      default:
        return 'Day $backendDayOfWeek';
    }
  }

  /// Safely parses a dynamic backend dayOfWeek (int 0..6 or String 'Wednesday', '3') to int 0..6.
  static int parseBackendDayOfWeek(dynamic value) {
    if (value is int) {
      if (value >= 0 && value <= 6) return value;
      if (value == 7) return 0;
      return value % 7;
    }
    if (value is String) {
      final lower = value.trim().toLowerCase();
      switch (lower) {
        case 'sunday':
        case 'sun':
        case '0':
          return 0;
        case 'monday':
        case 'mon':
        case '1':
          return 1;
        case 'tuesday':
        case 'tue':
        case '2':
          return 2;
        case 'wednesday':
        case 'wed':
        case '3':
          return 3;
        case 'thursday':
        case 'thu':
        case '4':
          return 4;
        case 'friday':
        case 'fri':
        case '5':
          return 5;
        case 'saturday':
        case 'sat':
        case '6':
          return 6;
        case '7':
          return 0;
      }
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed == 7 ? 0 : parsed % 7;
    }
    return 0;
  }
}
