import 'package:flutter/foundation.dart';

/// rider-r4-32: the server's clock, as the device last saw it.
///
/// Server stamps such as a quote's `expiresAt` are server time. Judged
/// against a phone whose clock runs minutes fast, every quote is spent on
/// arrival; against a slow one an expired quote still looks good. Each API
/// response's `Date` header tells how far the device clock is off; checks of
/// a server stamp compare it with [now] instead of the raw device clock.
/// Without a `Date` header (a web build whose server does not expose it)
/// the offset stays zero: the device clock, as before.
abstract final class ServerClock {
  /// An offset below this is the header's one-second resolution plus the
  /// response's travel time, not a wrong clock.
  static const tolerance = Duration(seconds: 5);

  static Duration _offset = Duration.zero;

  /// How far the server clock is ahead of this device (negative: behind).
  static Duration get offset => _offset;

  /// The server's time now, on the device clock.
  static DateTime now() => DateTime.now().add(_offset);

  /// A server stamp [server] on the device clock, so elapsed time measured
  /// with `DateTime.now()` from it is the server's (rider-r4-13).
  static DateTime toDevice(DateTime server) => server.subtract(_offset);

  /// Learns the offset from a response's `Date` header [header], received
  /// at [receivedAt] on the device clock. An unreadable header is ignored.
  static void observeDateHeader(String? header, {DateTime? receivedAt}) {
    final server = parseHttpDate(header);
    if (server == null) return;
    final offset = server.difference(receivedAt ?? DateTime.now());
    _offset = offset.abs() < tolerance ? Duration.zero : offset;
  }

  @visibleForTesting
  static void reset() => _offset = Duration.zero;

  static const _months = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  static final _imfFixdate = RegExp(
    r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  );

  /// An RFC 9110 IMF-fixdate ("Sun, 06 Nov 1994 08:49:37 GMT") in UTC.
  static DateTime? parseHttpDate(String? raw) {
    final match = raw == null ? null : _imfFixdate.firstMatch(raw.trim());
    if (match == null) return null;
    final month = _months[match.group(2)];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }
}
