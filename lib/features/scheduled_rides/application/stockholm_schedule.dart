import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/config/zone_clock.dart';

/// Book-later pickup rules in one zone's wall-clock time (Q9: the pickup
/// zone's local time). Times in and out are plain wall-clock [DateTime]s
/// of [timeZone].
class PickupSchedule {
  const PickupSchedule(this.timeZone);

  /// The schedule of the zone a pickup at [lat], [lng] is in, in the time
  /// zone its config names ([config] when the caller has the zone's
  /// document, else the built-in seed's).
  factory PickupSchedule.at(double? lat, double? lng, {RiderAppConfig? config}) {
    final zone = RiderZones.at(lat, lng);
    final document = config != null && config.zoneId == zone.id
        ? config
        : SeedRiderConfigRepository.seedFor(zone.id);
    return PickupSchedule(document.timeZone);
  }

  static const stockholm = PickupSchedule(ZoneClock.stockholm);

  /// IANA id, e.g. `Europe/Stockholm`, `Africa/Tunis`.
  final String timeZone;

  /// Current wall-clock time in [timeZone]. [now] is any instant.
  DateTime zoneNow([DateTime? now]) =>
      ZoneClock.wallTime(timeZone, now ?? StockholmSchedule.clock());

  /// Earliest legal pickup: zone now + lead, rounded up to the 5-min slot.
  DateTime minimumPickup([DateTime? now]) => StockholmSchedule.roundToFive(
    zoneNow(now).add(const Duration(minutes: StockholmSchedule.leadMinutes)),
  );

  DateTime defaultPickup([DateTime? now]) => minimumPickup(now);

  DateTime clampPickup(DateTime dt, [DateTime? now]) {
    final min = minimumPickup(now);
    if (dt.isBefore(min)) return min;
    return StockholmSchedule.roundToFive(
      DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute),
    );
  }

  bool isLegalPickup(DateTime dt, [DateTime? now]) =>
      !dt.isBefore(minimumPickup(now));

  DateTime timePickerMinFor(DateTime date, [DateTime? now]) {
    final min = minimumPickup(now);
    final day = DateTime(date.year, date.month, date.day);
    final minDay = DateTime(min.year, min.month, min.day);
    if (!day.isAfter(minDay)) return min;
    return day;
  }

  /// The UTC instant of the wall-clock pickup [wall] in [timeZone].
  DateTime toUtc(DateTime wall) => ZoneClock.toUtc(wall, timeZone);
}

/// Europe/Stockholm wall-clock pickup rules (CET/CEST, no extra deps); the
/// home zone's [PickupSchedule], kept for its callers.
class StockholmSchedule {
  static const int leadMinutes = 30;
  static const int slotMinutes = 5;

  /// Source of "now" when no explicit time is passed. Tests move it to make
  /// the earliest legal slot roll over at a chosen step of a booking flow.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Current wall-clock time in Europe/Stockholm.
  ///
  /// [now] is converted to UTC first so tests can pass `DateTime.utc(...)`.
  static DateTime stockholmNow([DateTime? now]) =>
      PickupSchedule.stockholm.zoneNow(now);

  /// Earliest legal pickup: Stockholm now + [leadMinutes], rounded to 5 min.
  static DateTime minimumPickup([DateTime? now]) =>
      PickupSchedule.stockholm.minimumPickup(now);

  /// Default Book later slot (same as [minimumPickup]).
  static DateTime defaultPickup([DateTime? now]) => minimumPickup(now);

  /// Round up to the next 5-minute slot; keep an exact 5-minute wall time.
  static DateTime roundToFive(DateTime dt) {
    final remainder = dt.minute % slotMinutes;
    final shifted = dt.add(
      Duration(minutes: remainder == 0 ? 0 : slotMinutes - remainder),
    );
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
    );
  }

  /// Raise [dt] to [minimumPickup] when it is in the past (or too soon), and
  /// otherwise still grid-align it to the 5-minute slot. A time can be legal
  /// (past the 30-minute lead) while off-grid — e.g. a return-ride prefill
  /// inherited from an outbound time that was never itself grid-aligned —
  /// and every caller of this method expects a slotted result back.
  static DateTime clampPickup(DateTime dt, [DateTime? now]) =>
      PickupSchedule.stockholm.clampPickup(dt, now);

  /// Continue-button predicate: pickup must be at/after Stockholm now+30.
  static bool isLegalPickup(DateTime dt, [DateTime? now]) =>
      PickupSchedule.stockholm.isLegalPickup(dt, now);

  /// Whether [dt] already sits on the 5-minute slot grid. A time can be a
  /// legal pickup ([isLegalPickup]) while still being off-grid — e.g. a
  /// return-ride prefill inherited from an outbound time that was never
  /// itself grid-aligned.
  static bool isOnGrid(DateTime dt) => dt.minute % slotMinutes == 0;

  /// Earliest time the time picker may land on for [date].
  static DateTime timePickerMinFor(DateTime date, [DateTime? now]) =>
      PickupSchedule.stockholm.timePickerMinFor(date, now);
}
