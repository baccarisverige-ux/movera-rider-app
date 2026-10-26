import 'dart:async';
import 'dart:convert';

import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

typedef OnDemandArchiveWriter =
    Future<void> Function(
      RideSnapshot snapshot,
      RideStatus terminalStatus,
      String? cancellationReason,
    );

/// Local archive for finished Book Now rides.
///
/// The backend remains the future source of truth. Until then, retain at most
/// 100 rides for 180 days on this device. Records are keyed by the real rideId
/// so retries cannot create duplicate History entries.
abstract final class OnDemandRideHistoryStore {
  static const key = 'movera_on_demand_ride_history_v1';
  static const maxRecords = 100;
  static const retention = Duration(days: 180);

  /// How many times a write re-reads and retries before giving up on proving
  /// its own record survived a concurrent archive.
  static const _maxWriteAttempts = 6;

  static final StreamController<void> _changes =
      StreamController<void>.broadcast();

  /// Fires after every write, so screens that show history figures (Home's
  /// month card, FLOW-13) can refresh instead of keeping what they read once.
  static Stream<void> get changes => _changes.stream;

  static Future<List<Reservation>> read() async {
    final prefs = await PreferencesStore.load();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final cutoff = DateTime.now().subtract(retention);
      final byId = <String, Reservation>{};
      for (final value in decoded) {
        final ride = _local(Reservation.tryParse(value));
        if (ride == null || !ride.scheduledPickupAt.isAfter(cutoff)) continue;
        final current = byId[ride.reservationId];
        if (current == null ||
            ride.scheduledPickupAt.isAfter(current.scheduledPickupAt)) {
          byId[ride.reservationId] = ride;
        }
      }
      final rides = byId.values.toList()
        ..sort((a, b) => b.scheduledPickupAt.compareTo(a.scheduledPickupAt));
      return rides.take(maxRecords).toList(growable: false);
    } catch (error, stackTrace) {
      AppLog.error('history.read_failed', error: error, stackTrace: stackTrace);
      return const [];
    }
  }

  /// Archives a cancelled Book Now ride then clears the live snapshot.
  ///
  /// Cancel-first stays intact: the snapshot is always cleared, even when
  /// History has nothing to keep (missing rideId, already cleared, etc.).
  static Future<void> archiveCancelledThenClear({
    RideSnapshot? snapshot,
    String? reasonId,
    OnDemandArchiveWriter? archiveWriter,
  }) async {
    final candidate = snapshot ?? await RideSnapshotStore.readForArchive();
    final rideId = candidate?.rideId?.trim();
    if (candidate != null && rideId != null && rideId.isNotEmpty) {
      try {
        if (archiveWriter != null) {
          await archiveWriter(candidate, RideStatus.cancelledByRider, reasonId);
        } else {
          await archive(
            candidate,
            terminalStatus: RideStatus.cancelledByRider,
            cancellationReason: reasonId,
          );
        }
      } catch (error, stackTrace) {
        AppLog.error(
          'history.cancel_archive_failed',
          error: error,
          stackTrace: stackTrace,
          extra: {'rideId': rideId},
        );
      }
    }
    await RideSnapshotStore.clear();
  }

  static Future<void> archive(
    RideSnapshot snapshot, {
    required RideStatus terminalStatus,
    DateTime? endedAt,
    String? cancellationReason,
    bool endedEarly = false,
    Money? charged,
    Money? cancellationFee,
  }) async {
    final rideId = snapshot.rideId?.trim();
    if (rideId == null || rideId.isEmpty) {
      throw ArgumentError.value(
        snapshot.rideId,
        'rideId',
        'A stable rideId is required for History archival.',
      );
    }

    final record = recordFor(
      snapshot,
      terminalStatus: terminalStatus,
      endedAt: endedAt,
      cancellationReason: cancellationReason,
      endedEarly: endedEarly,
      charged: charged,
      cancellationFee: cancellationFee,
    );
    if (record == null) {
      throw ArgumentError.value(
        terminalStatus,
        'terminalStatus',
        'Only completed or explicitly cancelled rides can be archived.',
      );
    }

    // Two archives finishing at once both read, prepend and write, so the
    // slower reader can overwrite the faster writer's record. Rather than queue
    // writes behind a shared future — where one write that never settles wedges
    // every later archive and rides silently stop reaching History — each write
    // re-reads and retries until its own record is proven stored, the same
    // compare-and-verify shape the live snapshot store uses.
    for (var attempt = 1; attempt <= _maxWriteAttempts; attempt++) {
      final rides = await read();
      final updated = <Reservation>[
        record,
        ...rides.where((ride) => ride.reservationId != record.reservationId),
      ]..sort((a, b) => b.scheduledPickupAt.compareTo(a.scheduledPickupAt));
      final retained = updated.take(maxRecords).toList(growable: false);

      final prefs = await PreferencesStore.load();
      await prefs.setString(key, jsonEncode(retained.map(_stored).toList()));
      _changes.add(null);

      // A record trimmed by maxRecords or already past retention was never
      // meant to be readable, so only verify the writes that claim a slot.
      final claimsSlot =
          retained.any((ride) => ride.reservationId == record.reservationId) &&
          record.scheduledPickupAt.isAfter(DateTime.now().subtract(retention));
      if (!claimsSlot) return;

      final stored = await read();
      if (stored.any((ride) => ride.reservationId == record.reservationId)) {
        return;
      }
      if (attempt == _maxWriteAttempts) {
        throw StateError(
          'History archive for ${record.reservationId} kept losing its slot to '
          'a concurrent write after $_maxWriteAttempts attempts.',
        );
      }
    }
  }

  /// The History record for a finished ride, or null when [terminalStatus]
  /// is neither completed nor an explicit cancel. Also used to read server
  /// trips (`ApiRideHistoryRepository`), so both sources look the same.
  /// [cancellationFee] is what the server charged for a cancel (rider-u33:
  /// contract §6 `cancellation.fee`), shown on the record when positive.
  static Reservation? recordFor(
    RideSnapshot snapshot, {
    required RideStatus terminalStatus,
    DateTime? endedAt,
    String? cancellationReason,
    bool endedEarly = false,
    Money? charged,
    Money? cancellationFee,
  }) {
    final rideId = snapshot.rideId?.trim();
    final reservationStatus = _reservationStatus(terminalStatus);
    if (rideId == null || rideId.isEmpty || reservationStatus == null) {
      return null;
    }
    final ended = endedAt ?? DateTime.now();
    return Reservation(
      reservationId: 'ondemand-$rideId',
      createdAt: snapshot.createdAt.toUtc(),
      // rider-36: History reads the hour and day straight off this value,
      // as it does for Book later's wall-clock times, so hold the rider's
      // local time. It is still stored as UTC ([_stored]).
      scheduledPickupAt: ended.toLocal(),
      pickup: ReservationPlace(
        label: snapshot.pickupAddress,
        lat: snapshot.pickupLat,
        lng: snapshot.pickupLng,
      ),
      destination: ReservationPlace(
        label: snapshot.destinationAddress,
        lat: snapshot.destinationLat,
        lng: snapshot.destinationLng,
      ),
      // H7: the booked id, never one derived from the label.
      categoryId: snapshot.categoryId != null
          ? CategoryIds.canonical(snapshot.categoryId!)
          : _categoryId(snapshot.rideType),
      categoryName: snapshot.rideType.trim().isEmpty
          ? 'Movera'
          : snapshot.rideType,
      categoryImage: _categoryImage(snapshot.rideType),
      price: snapshot.price,
      currency: snapshot.currency,
      paymentMethod: snapshot.paymentMethod,
      status: reservationStatus,
      driver: _driver(snapshot),
      note: snapshot.notes.selected.isEmpty
          ? null
          : snapshot.notes.selected.join(', '),
      cancellationReason:
          cancellationReason ??
          snapshot.cancellationReason ??
          _endedSearchReason(terminalStatus),
      endedEarly: endedEarly && terminalStatus == RideStatus.cancelledByRider,
      chargedFare: charged,
      cancellationFee: cancellationFee != null && cancellationFee.isPositive
          ? cancellationFee
          : null,
      paymentFailed: terminalStatus == RideStatus.paymentFailed,
    );
  }

  /// [ride] with its History time in the rider's local time; records
  /// written by older builds hold it in UTC.
  static Reservation? _local(Reservation? ride) =>
      ride?.copyWith(scheduledPickupAt: ride.scheduledPickupAt.toLocal());

  /// The persisted form: the History time as a UTC instant, so a stored
  /// ride keeps its moment if the device changes time zone.
  static Map<String, dynamic> _stored(Reservation ride) =>
      ride.copyWith(scheduledPickupAt: ride.scheduledPickupAt.toUtc()).toJson();

  static Future<void> clear() async {
    final prefs = await PreferencesStore.load();
    await prefs.remove(key);
    _changes.add(null);
  }

  static ReservationStatus? _reservationStatus(RideStatus status) {
    // rider-37: a trip paid and rated (or rating skipped) is `closed`, and
    // one whose payment failed is still a completed trip; History keeps
    // both (the second with a "Payment failed" label).
    if (status.isCompletedSurface ||
        status == RideStatus.closed ||
        status == RideStatus.paymentFailed) {
      return ReservationStatus.completed;
    }
    if (status == RideStatus.cancelledByRider ||
        status == RideStatus.cancelledByDriver ||
        status == RideStatus.cancelledBySystem ||
        status == RideStatus.cancelledByAdmin ||
        status == RideStatus.endedByDriver ||
        status == RideStatus.noShow ||
        status == RideStatus.tripFailed ||
        // ARCH-3 / RIDE-5: a search the server ended is a request that did
        // not happen; History keeps the attempt as a cancelled ride.
        status == RideStatus.noDriverFound ||
        status == RideStatus.bookingExpired) {
      return ReservationStatus.cancelled;
    }
    return null;
  }

  /// rider-u112: a reason code, not an English sentence;
  /// ReservationFormat.reasonLabel shows it in the app language.
  static String? _endedSearchReason(RideStatus status) => switch (status) {
    RideStatus.noDriverFound => 'system_no_driver',
    RideStatus.bookingExpired => 'system_expired',
    // Contract v0.3.0: each cause stays distinct in History.
    RideStatus.cancelledByAdmin => 'admin_cancelled',
    RideStatus.cancelledBySystem => 'system_cancelled',
    RideStatus.noShow => 'rider_no_show',
    RideStatus.tripFailed => 'system_trip_failed',
    RideStatus.endedByDriver => 'driver_ended',
    _ => null,
  };

  static ReservationDriver? _driver(RideSnapshot snapshot) {
    final driver = snapshot.driver;
    if (driver == null) return null;
    return ReservationDriver(
      firstName: driver.firstName,
      rating: driver.rating,
      vehicle: driver.vehicleLabel.isEmpty ? null : driver.vehicleLabel,
      plate: driver.plate,
      photoAsset: driver.photoAsset,
    );
  }

  static String _categoryId(String rideType) {
    final id = rideType.trim().toLowerCase().replaceAll(' ', '-');
    return id.isEmpty ? CategoryIds.economy : id;
  }

  static String _categoryImage(String rideType) {
    final value = rideType.toLowerCase();
    if (value.contains('comfort')) return 'assets/images/rides/comfort.webp';
    if (value.contains('premium')) return 'assets/images/rides/premium.webp';
    if (value.contains('electric')) return 'assets/images/rides/electric.webp';
    if (value.contains('xl')) return 'assets/images/rides/xl.webp';
    if (value.contains('pet')) return 'assets/images/rides/pet.webp';
    if (value.contains('priority')) return 'assets/images/rides/priority.webp';
    return 'assets/images/rides/movera.webp';
  }
}
