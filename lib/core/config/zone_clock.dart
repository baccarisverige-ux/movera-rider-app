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
    'Europe/Lisbon': 0,
    'Europe/London': 0,
    'Europe/Dublin': 0,
    'Atlantic/Canary': 0,
    'Atlantic/Madeira': 0,
    stockholm: 1,
    paris: 1,
    'Europe/Berlin': 1,
    'Europe/Madrid': 1,
    'Europe/Rome': 1,
    'Europe/Amsterdam': 1,
    'Europe/Brussels': 1,
    'Europe/Luxembourg': 1,
    'Europe/Monaco': 1,
    'Europe/Vienna': 1,
    'Europe/Zurich': 1,
    'Europe/Copenhagen': 1,
    'Europe/Oslo': 1,
    'Europe/Prague': 1,
    'Europe/Warsaw': 1,
    'Europe/Budapest': 1,
    'Europe/Malta': 1,
    'Europe/Ljubljana': 1,
    'Europe/Zagreb': 1,
    'Europe/Bratislava': 1,
    'Europe/Belgrade': 1,
    'Europe/Helsinki': 2,
    'Europe/Athens': 2,
    'Europe/Bucharest': 2,
    'Europe/Sofia': 2,
    'Europe/Riga': 2,
    'Europe/Tallinn': 2,
    'Europe/Vilnius': 2,
    'Asia/Nicosia': 2,
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

  /// The wall-clock time in [timeZone] at [instant] (owner decision 9).
  ///
  /// A zone wall time is carried in a UTC-tagged [DateTime] whose fields
  /// (year … millisecond) are the zone's clock reading. It is not the
  /// instant: [toUtc] turns it into one. UTC has no summer time, so every
  /// wall time of every zone exists in it and the phone's own time zone
  /// can never move it (a device-local value of Tunis 02:30 does not exist
  /// on an EU phone on the spring-forward night, and Dart moved it to
  /// 03:30).
  static DateTime wallTime(String timeZone, DateTime instant) {
    final utc = instant.toUtc();
    return wall(utc.add(offsetAt(timeZone, utc)));
  }

  /// The wall time in [timeZone] [elapsed] after the wall time [wall]: real
  /// elapsed time, so it holds across a change of the zone's clock
  /// (rider-r5-9: 01:50 + 30 min on spring-forward night is 03:20).
  static DateTime wallAfter(String timeZone, DateTime wall, Duration elapsed) =>
      wallTime(timeZone, toUtc(wall, timeZone).add(elapsed));

  /// [any]'s fields as a wall time (see [wallTime]): a device-local value
  /// built from picker fields reads as the same clock reading.
  static DateTime wall(DateTime any) => any.isUtc
      ? any
      : DateTime.utc(
          any.year,
          any.month,
          any.day,
          any.hour,
          any.minute,
          any.second,
          any.millisecond,
        );

  /// The UTC instant of the wall-clock time [wall] in [timeZone]; only its
  /// fields are read.
  ///
  /// A wall time the zone skips (02:30 on the EU spring-forward night) is
  /// moved forward by the gap: it is read with the offset before the
  /// change, so it lands on 03:30. [exists] says whether that happened.
  /// A wall time the zone has twice (02:30 on the fall-back night) is the
  /// first of the two, in summer time; with [notBefore], the first of the
  /// two that is not before it (rider-r5-7: a pickup picked during the
  /// second copy of the hour is that copy, not one already past).
  static DateTime toUtc(DateTime wall, String timeZone, {DateTime? notBefore}) {
    final asUtc = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
      wall.millisecond,
    );
    // Offsets in force half a day either side: a wall time can only be
    // read with one of these (zones change at most once in that span).
    final before = offsetAt(
      timeZone,
      asUtc.subtract(const Duration(hours: 14)),
    );
    final after = offsetAt(timeZone, asUtc.add(const Duration(hours: 14)));
    DateTime? first;
    DateTime? firstToCome;
    for (final offset in {before, after}) {
      final candidate = asUtc.subtract(offset);
      if (offsetAt(timeZone, candidate) != offset) continue;
      if (first == null || candidate.isBefore(first)) first = candidate;
      if (notBefore != null &&
          !candidate.isBefore(notBefore) &&
          (firstToCome == null || candidate.isBefore(firstToCome))) {
        firstToCome = candidate;
      }
    }
    return firstToCome ?? first ?? asUtc.subtract(before);
  }

  /// Whether the wall-clock time [wall] happens in [timeZone] (false in
  /// the hour a spring-forward change skips).
  static bool exists(DateTime wall, String timeZone) =>
      wallTime(timeZone, toUtc(wall, timeZone)) ==
      ZoneClock.wall(wall).copyWith(microsecond: 0);

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
