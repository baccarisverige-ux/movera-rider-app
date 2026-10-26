import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/config/zone_clock.dart';

/// Book-later pickup rules in one zone's wall-clock time (Q9: the pickup
/// zone's local time). Times in and out are wall-clock times of [timeZone]
/// as [ZoneClock.wallTime] carries them (UTC-tagged fields, so the phone's
/// own time zone never moves them; owner decision 9). A device-local value
/// passed in is read by its fields.
class PickupSchedule {
  const PickupSchedule(
    this.timeZone, {
    this.horizonDays = RiderAppConfig.defaultBookingHorizonDays,
  });

  /// The schedule of the zone a pickup at [lat], [lng] is in, in the time
  /// zone its config names ([config] when the caller has the zone's
  /// document, else the built-in seed's).
  factory PickupSchedule.at(
    double? lat,
    double? lng, {
    RiderAppConfig? config,
  }) {
    final zone = RiderZones.at(lat, lng);
    final document = config != null && config.zoneId == zone.id
        ? config
        : SeedRiderConfigRepository.seedFor(zone.id);
    return PickupSchedule(
      document.timeZone,
      horizonDays: document.bookingHorizonDays,
    );
  }

  static const stockholm = PickupSchedule(ZoneClock.stockholm);

  /// IANA id, e.g. `Europe/Stockholm`, `Africa/Tunis`.
  final String timeZone;

  /// rider-r4-10: how many days ahead the zone takes reservations
  /// (`booking.bookingHorizonDays`).
  final int horizonDays;

  /// Current wall-clock time in [timeZone]. [now] is any instant.
  DateTime zoneNow([DateTime? now]) =>
      ZoneClock.wallTime(timeZone, now ?? StockholmSchedule.clock());

  /// Earliest legal pickup: zone now + lead, rounded up to the 5-min slot.
  /// rider-r5-8: a slot the zone's clock skips (02:20 on spring-forward
  /// night) moves forward by the gap (03:20), the time it is booked as.
  DateTime minimumPickup([DateTime? now]) {
    final slot = StockholmSchedule.roundToFive(
      zoneNow(now).add(const Duration(minutes: StockholmSchedule.leadMinutes)),
    );
    return ZoneClock.wallTime(timeZone, toUtc(slot));
  }

  DateTime defaultPickup([DateTime? now]) => minimumPickup(now);

  /// rider-r4-10: the latest pickup a zone taking reservations [days]
  /// ahead accepts, on the slot at or before it. The horizon is elapsed
  /// time from [now] (a DST change in between does not stretch it), read
  /// as the zone's wall clock.
  DateTime latestPickup(int days, [DateTime? now]) {
    final latest = zoneNow(
      (now ?? StockholmSchedule.clock()).add(Duration(days: days)),
    );
    return DateTime.utc(
      latest.year,
      latest.month,
      latest.day,
      latest.hour,
      latest.minute - latest.minute % StockholmSchedule.slotMinutes,
    );
  }

  DateTime clampPickup(DateTime dt, [DateTime? now]) {
    final min = minimumPickup(now);
    if (ZoneClock.wall(dt).isBefore(min)) return min;
    final slot = StockholmSchedule.roundToFive(dt);
    // rider-r4-12: a wall time the zone skips (02:30 on the EU
    // spring-forward night) moves forward by the gap (03:30), the instant
    // it is booked as, so what the rider sees is what the driver is sent
    // for; the picker says it moved.
    return ZoneClock.wallTime(timeZone, toUtc(slot, now));
  }

  bool isLegalPickup(DateTime dt, [DateTime? now]) =>
      !ZoneClock.wall(dt).isBefore(minimumPickup(now));

  DateTime timePickerMinFor(DateTime date, [DateTime? now]) {
    final min = minimumPickup(now);
    final day = DateTime.utc(date.year, date.month, date.day);
    final minDay = DateTime.utc(min.year, min.month, min.day);
    if (!day.isAfter(minDay)) return min;
    return day;
  }

  /// The UTC instant of the wall-clock pickup [wall] in [timeZone]; a wall
  /// time the zone has twice is the copy still to come at [now]
  /// (rider-r5-7).
  DateTime toUtc(DateTime wall, [DateTime? now]) => ZoneClock.toUtc(
    wall,
    timeZone,
    notBefore: now ?? StockholmSchedule.clock(),
  );
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
  /// Wall-clock arithmetic on [dt]'s fields (a [ZoneClock.wallTime]).
  static DateTime roundToFive(DateTime dt) {
    final wall = ZoneClock.wall(dt);
    final remainder = wall.minute % slotMinutes;
    final shifted = wall.add(
      Duration(minutes: remainder == 0 ? 0 : slotMinutes - remainder),
    );
    return DateTime.utc(
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
