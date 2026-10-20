/// Wall-clock time in a Rider zone's IANA time zone, with no extra package
/// (Q9: booking times are the pickup zone's local time).
///
/// Only the zones the Rider serves are known (`rider_zones.dart`):
/// Europe/Stockholm and Europe/Paris follow the EU rule (CET, CEST from
/// the last Sunday of March 01:00 UTC to the last Sunday of October 01:00
/// UTC); Africa/Tunis is UTC+1 all year (no DST since 2009). Any other id
/// is read as Europe/Stockholm, the home zone.
abstract final class ZoneClock {
  static const stockholm = 'Europe/Stockholm';
  static const paris = 'Europe/Paris';
  static const tunis = 'Africa/Tunis';

  /// The zone's offset from UTC at [instant].
  static Duration offsetAt(String timeZone, DateTime instant) {
    if (timeZone == tunis) return const Duration(hours: 1);
    return Duration(hours: _euSummer(instant.toUtc()) ? 2 : 1);
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
