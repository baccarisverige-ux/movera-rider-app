/// Wall-clock time in a Rider zone's IANA time zone, with no extra package
/// (Q9: booking times are the pickup zone's local time).
///
/// The zone's id comes from its config document (`RiderAppConfig.timeZone`,
/// set by Admin). The ids below are known: the European ones follow the EU
/// rule (summer time from the last Sunday of March 01:00 UTC to the last
/// Sunday of October 01:00 UTC) on top of their standard offset (WET 0,
/// CET +1, EET +2); the African ones keep one offset all year
/// (Africa/Tunis UTC+1, no DST since 2009). Any other id is read as
/// Europe/Stockholm, the home zone.
abstract final class ZoneClock {
  static const stockholm = 'Europe/Stockholm';
  static const paris = 'Europe/Paris';
  static const tunis = 'Africa/Tunis';

  /// Standard offset, in hours, of the zones on the EU summer-time rule.
  static const _euStandardHours = <String, int>{
    'Europe/Lisbon': 0, 'Europe/London': 0, 'Europe/Dublin': 0,
    'Atlantic/Canary': 0, 'Atlantic/Madeira': 0,
    stockholm: 1, paris: 1, 'Europe/Berlin': 1, 'Europe/Madrid': 1,
    'Europe/Rome': 1, 'Europe/Amsterdam': 1, 'Europe/Brussels': 1,
    'Europe/Luxembourg': 1, 'Europe/Monaco': 1, 'Europe/Vienna': 1,
    'Europe/Zurich': 1, 'Europe/Copenhagen': 1, 'Europe/Oslo': 1,
    'Europe/Prague': 1, 'Europe/Warsaw': 1, 'Europe/Budapest': 1,
    'Europe/Malta': 1, 'Europe/Ljubljana': 1, 'Europe/Zagreb': 1,
    'Europe/Bratislava': 1, 'Europe/Belgrade': 1,
    'Europe/Helsinki': 2, 'Europe/Athens': 2, 'Europe/Bucharest': 2,
    'Europe/Sofia': 2, 'Europe/Riga': 2, 'Europe/Tallinn': 2,
    'Europe/Vilnius': 2, 'Asia/Nicosia': 2,
  };

  /// Zones with one offset all year, in hours.
  static const _fixedHours = <String, int>{
    tunis: 1,
    'Africa/Algiers': 1,
    'Africa/Lagos': 1,
    'UTC': 0,
    'Etc/UTC': 0,
  };

  /// Whether [timeZone] is one this clock knows (else it reads as
  /// Europe/Stockholm).
  static bool knows(String timeZone) =>
      _euStandardHours.containsKey(timeZone) ||
      _fixedHours.containsKey(timeZone);

  /// The zone's offset from UTC at [instant].
  static Duration offsetAt(String timeZone, DateTime instant) {
    final fixed = _fixedHours[timeZone];
    if (fixed != null) return Duration(hours: fixed);
    final standard = _euStandardHours[timeZone] ?? _euStandardHours[stockholm]!;
    return Duration(hours: standard + (_euSummer(instant.toUtc()) ? 1 : 0));
  }

  /// The wall-clock time in [timeZone] at [instant], as a plain (local,
  /// offset-free) [DateTime] the pickers can show as is.
  static DateTime wallTime(String timeZone, DateTime instant) {
    final utc = instant.toUtc();
    final local = utc.add(offsetAt(timeZone, utc));
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
    );
  }

  /// The UTC instant of the wall-clock time [wall] in [timeZone]. In the
  /// hour that does not exist (spring forward) the summer offset is used;
  /// in the hour that happens twice, the later one.
  static DateTime toUtc(DateTime wall, String timeZone) {
    final asUtc = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
      wall.millisecond,
    );
    final guess = asUtc.subtract(offsetAt(timeZone, asUtc));
    return asUtc.subtract(offsetAt(timeZone, guess));
  }

  static bool _euSummer(DateTime utc) {
    final start = _lastSundayUtc(utc.year, 3).add(const Duration(hours: 1));
    final end = _lastSundayUtc(utc.year, 10).add(const Duration(hours: 1));
    return !utc.isBefore(start) && utc.isBefore(end);
  }

  static DateTime _lastSundayUtc(int year, int month) {
    final firstOfNext = month == 12
        ? DateTime.utc(year + 1, 1, 1)
        : DateTime.utc(year, month + 1, 1);
    var day = firstOfNext.subtract(const Duration(days: 1));
    while (day.weekday != DateTime.sunday) {
      day = day.subtract(const Duration(days: 1));
    }
    return DateTime.utc(day.year, day.month, day.day);
  }
}
