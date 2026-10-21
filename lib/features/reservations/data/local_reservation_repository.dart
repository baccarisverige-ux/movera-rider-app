import 'dart:convert';
import 'dart:math';

import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/reservations/data/reservation_policy_catalog.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_policy.dart';
import 'package:movera_rider/features/reservations/domain/reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/trips/domain/trip.dart';

abstract class ReservationStorage {
  Future<String?> read();
  Future<void> write(String json);
}

class PrefsReservationStorage implements ReservationStorage {
  static const key = 'movera_reservations_v1';

  @override
  Future<String?> read() async {
    try {
      final prefs = await PreferencesStore.load();
      return prefs.getString(key);
    } catch (error, stackTrace) {
      AppLog.error('reservation.storage.read_failed', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  @override
  Future<void> write(String json) async {
    try {
      final prefs = await PreferencesStore.load();
      await prefs.setString(key, json);
    } catch (error, stackTrace) {
      AppLog.error('reservation.storage.write_failed', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }
}

class MemoryReservationStorage implements ReservationStorage {
  MemoryReservationStorage([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async {
    value = json;
  }
}

class LocalReservationRepository implements ReservationRepository {
  LocalReservationRepository({
    ReservationStorage? storage,
    ReservationPolicy? policy,
    String Function()? nextId,
    DateTime Function()? clock,
  }) : _storage = storage ?? PrefsReservationStorage(),
       _policy = policy,
       _nextId = nextId ?? _defaultId,
       _clock = clock ?? DateTime.now;

  final ReservationStorage _storage;
  /// Null: [ReservationPolicyCatalog.current], in the app language.
  final ReservationPolicy? _policy;
  final String Function() _nextId;
  final DateTime Function() _clock;
  final List<Reservation> _items = [];
  bool _hydrated = false;

  static String _defaultId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final salt = Random().nextInt(1 << 20).toRadixString(16);
    return 'rsv_${now}_$salt';
  }

  @override
  List<Reservation> get cached => List.unmodifiable(_items);

  @override
  ReservationPolicy get policy => _policy ?? ReservationPolicyCatalog.current;

  @override
  Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    final raw = await _storage.read();
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      final list = decoded is List
          ? decoded
          : decoded is Map && decoded['reservations'] is List
          ? decoded['reservations'] as List
          : const [];
      _items
        ..clear()
        ..addAll(list.map(Reservation.tryParse).whereType<Reservation>());
    } catch (_) {
      // Ignore corrupt local data rather than crash on restore.
    }
  }

  @override
  void clearLocal() {
    _items.clear();
    _hydrated = false;
  }

  /// The change in flight, if any.
  Future<void>? _lastChange;

  /// Runs changes one at a time, so each builds on the one before it
  /// instead of a stale copy of the rides. With nothing in flight a change
  /// starts straight away, as before.
  Future<T> _oneAtATime<T>(Future<T> Function() change) {
    final previous = _lastChange;
    final result = previous == null ? change() : previous.then((_) => change());
    late final Future<void> done;
    done = result.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_lastChange, done)) _lastChange = null;
    });
    _lastChange = done;
    return result;
  }

  /// Saves [next] before it becomes what the rider sees. If the write fails,
  /// the rides stay exactly as they were, so a failed cancel never shows the
  /// ride as cancelled while it is still booked.
  Future<void> _commit(List<Reservation> next) async {
    await _storage.write(
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
    _items
      ..clear()
      ..addAll(next);
  }

  List<Reservation> _replacing(String reservationId, Reservation next) =>
      [..._items]..[_indexOf(reservationId)] = next;

  Reservation _require(String reservationId) {
    for (final item in _items) {
      if (item.reservationId == reservationId) return item;
    }
    throw StateError('Unknown reservation $reservationId');
  }

  int _indexOf(String reservationId) {
    return _items.indexWhere((item) => item.reservationId == reservationId);
  }

  @override
  Future<Reservation> createReservation(ReservationDraft draft) {
    return _oneAtATime(() async {
      await hydrate();
      final created = Reservation(
        reservationId: _nextId(),
        createdAt: _clock(),
        scheduledPickupAt: draft.scheduledPickupAt,
        estimatedDropoffAt: draft.estimatedDropoffAt,
        pickup: draft.pickup,
        destination: draft.destination,
        categoryId: draft.categoryId,
        categoryName: draft.categoryName,
        categoryImage: draft.categoryImage,
        passengerCount: draft.passengerCount,
        price: draft.price,
        currency: draft.currency,
        paymentMethod: draft.paymentMethod,
        status: ReservationStatus.scheduled,
        note: draft.note,
        policyVersion: policy.version,
        parentReservationId: draft.parentReservationId,
      );
      await _commit([created, ..._items]);
      return created;
    });
  }

  @override
  Future<Reservation> updateReservation(
    String reservationId,
    ReservationPatch patch,
  ) {
    return _oneAtATime(() async {
      await hydrate();
      final current = _require(reservationId);
      // rider-u159: decided before an earlier change in the queue (the
      // rider's cancel, the trip's end) committed. A finished ride stays
      // finished.
      if (!current.status.isUpcoming) return current;
      final next = current.copyWith(
        scheduledPickupAt: patch.scheduledPickupAt,
        estimatedDropoffAt: patch.estimatedDropoffAt,
        pickup: patch.pickup,
        destination: patch.destination,
        categoryId: patch.categoryId,
        categoryName: patch.categoryName,
        categoryImage: patch.categoryImage,
        passengerCount: patch.passengerCount,
        paymentMethod: patch.paymentMethod,
        price: patch.price,
        currency: patch.currency,
        note: patch.note,
        status: patch.status,
        driver: patch.driver,
        clearDriver: patch.clearDriver,
        previousDriver: patch.previousDriver,
      );
      await _commit(_replacing(reservationId, next));
      return next;
    });
  }

  @override
  Future<Reservation> cancelReservation(
    String reservationId, {
    String? reason,
    Money? fee,
  }) {
    return _oneAtATime(() async {
      await hydrate();
      final current = _require(reservationId);
      final next = current.copyWith(
        status: ReservationStatus.cancelled,
        cancellationReason: reason,
        cancellationActor: TripCancellationActor.rider,
        cancelledAt: _clock().toUtc(),
        cancellationFee: fee != null && fee.isPositive ? fee : null,
      );
      await _commit(_replacing(reservationId, next));
      return next;
    });
  }

  @override
  Future<Reservation?> getReservation(String reservationId) async {
    await hydrate();
    for (final item in _items) {
      if (item.reservationId == reservationId) return item;
    }
    return null;
  }

  @override
  Future<List<Reservation>> getUpcomingReservations() async {
    await hydrate();
    return _items.where((item) => item.status.isUpcoming).toList();
  }

  @override
  Future<List<Reservation>> getRideHistory() async {
    await hydrate();
    return cached;
  }

  @override
  Future<Reservation> assignDriver(
    String reservationId, {
    ReservationDriver? driver,
  }) {
    return _oneAtATime(() async {
      await hydrate();
      final current = _require(reservationId);
      // rider-u159: as in [updateReservation].
      if (!current.status.isUpcoming) return current;
      final leaving = current.driver;
      // The driver who had the ride and is now losing it, if any. A repeat
      // of the same assignment changes nothing.
      final replaced =
          leaving != null && (driver == null || !driver.isSameAs(leaving))
          ? leaving
          : null;
      final next = driver == null
          ? current.copyWith(
              status: ReservationStatus.driverAssignmentPending,
              clearDriver: true,
              previousDriver: replaced,
            )
          : current.copyWith(
              status: ReservationStatus.driverAssigned,
              driver: driver,
              previousDriver: replaced,
            );
      await _commit(_replacing(reservationId, next));
      return next;
    });
  }
}
