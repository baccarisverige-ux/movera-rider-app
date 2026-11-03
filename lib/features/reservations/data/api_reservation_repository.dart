import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/features/reservations/data/reservation_policy_catalog.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_errors.dart';
import 'package:movera_rider/features/reservations/domain/reservation_policy.dart';
import 'package:movera_rider/features/reservations/domain/reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/trips/domain/trip.dart';

/// Contract v0.18.17 Book later (`contract.json#bookLater.rider`, owner
/// 2026-11-03): the rider's booked rides are the server's trips of kind
/// `scheduled`. Booking takes a fresh scheduled quote (`POST /quotes`
/// kind scheduled) and books it (`POST /trips`); a change takes a new
/// quote and `POST /trips/{id}/reschedule`; a cancel is
/// `POST /trips/{id}/cancel`. The list is `GET /rider/trips?kind=scheduled`.
///
/// When Book later is off, the app keeps [DisabledReservationRepository].
class ApiReservationRepository
    implements ReservationRepository, ServerBackedRepository {
  ApiReservationRepository({
    required ApiClient api,
    ReservationPolicy? policy,
    this.categoryLabel,
  }) : _api = api,
       _policy = policy;

  static const listPath = '/api/v1/rider/trips?kind=scheduled&limit=100';
  static const quotesPath = '/api/v1/quotes';
  static const tripsPath = '/api/v1/trips';

  final ApiClient _api;
  final ReservationPolicy? _policy;

  /// The catalog's category names; null shows the category id.
  final String Function(String categoryId)? categoryLabel;

  final Map<String, Reservation> _byId = {};
  final Map<String, int> _versions = {};

  @override
  List<Reservation> get cached {
    final list = _byId.values.toList()
      ..sort((a, b) => a.scheduledPickupAt.compareTo(b.scheduledPickupAt));
    return List.unmodifiable(list);
  }

  @override
  ReservationPolicy get policy => _policy ?? ReservationPolicyCatalog.current;

  @override
  Future<void> hydrate() async {
    final page = await _api.get(listPath);
    final items = page['items'];
    if (items is! List) return;
    _byId.clear();
    for (final raw in items) {
      if (raw is! Map) continue;
      final trip = Map<String, dynamic>.from(raw);
      if (trip['kind'] != 'scheduled') continue;
      _keep(trip);
    }
  }

  @override
  void clearLocal() {
    _byId.clear();
    _versions.clear();
  }

  /// A fresh scheduled quote for the ride: the price the server books at.
  /// It must be the price the rider saw ([shown], whole units of
  /// [currency]); a different one throws [ScheduledQuoteRequiredException]
  /// so the screen prices it again and the rider sees the new price.
  Future<Map<String, dynamic>> _quote({
    required String categoryId,
    required DateTime at,
    required ReservationPlace pickup,
    required ReservationPlace destination,
    required List<ReservationPlace> stops,
    required double shown,
    required String currency,
    required String paymentMethod,
  }) async {
    final body = scheduledQuoteBody(
      categoryId: categoryId,
      at: at,
      pickup: pickup,
      destination: destination,
      stops: stops,
      paymentMethod: paymentMethod,
    );
    final answer = await _refusals(() => _api.post(quotesPath, body: body));
    final quotes = answer['quotes'];
    final category = CategoryIds.canonical(categoryId);
    if (quotes is! List) throw ScheduledQuoteRequiredException(categoryId);
    for (final raw in quotes) {
      if (raw is! Map || raw['categoryId'] != category) continue;
      final total = Money.fromWire(raw['total']);
      if (total == null) break;
      if (total.amountMinor != Money.fromLegacyMajor(shown, currency).amountMinor) {
        throw ScheduledQuoteRequiredException(categoryId);
      }
      return {...body, 'quoteId': raw['quoteId'], 'categoryId': category};
    }
    throw ScheduledQuoteRequiredException(categoryId);
  }

  /// `POST /quotes` for a booked ride (kind scheduled, its pickup instant).
  static Map<String, dynamic> scheduledQuoteBody({
    required String categoryId,
    required DateTime at,
    required ReservationPlace pickup,
    required ReservationPlace destination,
    required List<ReservationPlace> stops,
    required String paymentMethod,
  }) {
    Map<String, dynamic> place(ReservationPlace p) {
      final lat = p.lat;
      final lng = p.lng;
      if (lat == null || lng == null) {
        throw StateError('a booked ride needs points for its places');
      }
      return ApiQuoteRepository.contractPlace(lat, lng, p.label);
    }

    return {
      'pickup': place(pickup),
      'dropoff': place(destination),
      'stops': [for (final stop in stops) place(stop)],
      'categoryIds': [CategoryIds.canonical(categoryId)],
      'kind': 'scheduled',
      'scheduledAt': WireTime.format(at.toUtc()),
      'paymentMethod': wirePayment(paymentMethod),
    };
  }

  /// The app's payment names as contract `PaymentMethod`s.
  static String wirePayment(String method) {
    final m = method.toLowerCase();
    if (m.contains('apple')) return 'apple_pay';
    if (m.startsWith('card') || m.contains('card')) return 'card';
    return 'cash';
  }

  @override
  Future<Reservation> createReservation(ReservationDraft draft) async {
    final quoted = await _quote(
      categoryId: draft.categoryId,
      at: draft.scheduledPickupAt,
      pickup: draft.pickup,
      destination: draft.destination,
      stops: draft.stops,
      shown: draft.price,
      currency: draft.currency,
      paymentMethod: draft.paymentMethod,
    );
    final trip = await _refusals(() => _api.post(
      tripsPath,
      body: {
        'quoteId': quoted['quoteId'],
        'categoryId': quoted['categoryId'],
        'pickup': quoted['pickup'],
        'dropoff': quoted['dropoff'],
        'stops': quoted['stops'],
        'kind': 'scheduled',
        'scheduledAt': quoted['scheduledAt'],
        'paymentMethod': quoted['paymentMethod'],
        if (draft.note != null && draft.note!.trim().isNotEmpty) 'notes': draft.note!.trim(),
      },
    ));
    return _keep(trip, draft: draft);
  }

  @override
  Future<Reservation> updateReservation(String reservationId, ReservationPatch patch) async {
    final current = _byId[reservationId] ?? await getReservation(reservationId);
    if (current == null) throw StateError('No booked ride $reservationId.');
    final quoted = await _quote(
      categoryId: patch.categoryId ?? current.categoryId,
      at: patch.scheduledPickupAt ?? current.scheduledPickupAt,
      pickup: patch.pickup ?? current.pickup,
      destination: patch.destination ?? current.destination,
      stops: patch.stops ?? current.stops,
      shown: patch.price ?? current.price,
      currency: patch.currency ?? current.currency,
      paymentMethod: patch.paymentMethod ?? current.paymentMethod,
    );
    final trip = await _refusals(() => _api.post(
      '$tripsPath/${Uri.encodeComponent(reservationId)}/reschedule',
      body: {'quoteId': quoted['quoteId'], 'expectedVersion': _versions[reservationId] ?? 1},
    ));
    return _keep(trip);
  }

  @override
  Future<Reservation> cancelReservation(String reservationId, {String? reason, Money? fee}) async {
    if (!_versions.containsKey(reservationId)) await getReservation(reservationId);
    final trip = await _api.post(
      '$tripsPath/${Uri.encodeComponent(reservationId)}/cancel',
      body: {'expectedVersion': _versions[reservationId] ?? 1, 'reasonCode': riderReasonCode(reason)},
    );
    return _keep(trip);
  }

  /// The rider cancel reasons of the contract; anything else is
  /// `plans_changed`.
  static String riderReasonCode(String? reason) => switch (reason) {
    'wait_too_long' || 'driver_too_far' || 'wrong_address' || 'requested_by_mistake' || 'plans_changed' || 'other' => reason!,
    _ => 'plans_changed',
  };

  @override
  Future<Reservation?> getReservation(String reservationId) async {
    final trip = await _api.get('$tripsPath/${Uri.encodeComponent(reservationId)}');
    if (trip['tripId'] is! String) return null;
    return _keep(trip);
  }

  @override
  Future<List<Reservation>> getUpcomingReservations() async {
    await hydrate();
    return cached.where((r) => r.status.isUpcoming).toList();
  }

  @override
  Future<List<Reservation>> getRideHistory() async {
    await hydrate();
    return cached.where((r) => !r.status.isUpcoming).toList();
  }

  /// Drivers are given by the server's dispatch only.
  @override
  Future<Reservation> assignDriver(String reservationId, {ReservationDriver? driver}) async {
    final current = await getReservation(reservationId);
    if (current == null) throw StateError('No booked ride $reservationId.');
    return current;
  }

  /// The server's Book later refusals as [BookLaterRefusedException], with
  /// the zone's number from its answer ("Book at least 15 minutes ahead.").
  static Future<Map<String, dynamic>> _refusals(Future<Map<String, dynamic>> Function() call) async {
    try {
      return await call();
    } on ApiError catch (error) {
      final reason = error.reason;
      if (reason == null || !BookLaterRefusedException.reasons.contains(reason)) rethrow;
      final number = RegExp(r'\d+').firstMatch(error.message)?.group(0);
      throw BookLaterRefusedException(reason, limit: number == null ? null : int.tryParse(number));
    }
  }

  Reservation _keep(Map<String, dynamic> trip, {ReservationDraft? draft}) {
    final reservation = reservationOfTrip(trip, draft: draft, categoryLabel: categoryLabel);
    _byId[reservation.reservationId] = reservation;
    final version = trip['version'];
    if (version is num) _versions[reservation.reservationId] = version.toInt();
    return reservation;
  }

  /// `TripProjection.status` as the reservation's state.
  static ReservationStatus statusOf(Object? status) => switch (status) {
    'draft' || 'quoted' || 'requested' => ReservationStatus.scheduled,
    'searching' || 'offered' => ReservationStatus.driverAssignmentPending,
    'accepted' => ReservationStatus.driverAssigned,
    'driver_to_pickup' => ReservationStatus.driverEnRoute,
    'arrived' => ReservationStatus.driverArrived,
    'rider_onboard' || 'in_trip' || 'approaching_dropoff' => ReservationStatus.inProgress,
    'completed' => ReservationStatus.completed,
    _ => ReservationStatus.cancelled,
  };

  /// A server trip (kind scheduled) as the app's [Reservation].
  static Reservation reservationOfTrip(
    Map<String, dynamic> trip, {
    ReservationDraft? draft,
    String Function(String categoryId)? categoryLabel,
  }) {
    ReservationPlace place(Object? raw, ReservationPlace? fallback) {
      if (raw is Map) {
        return ReservationPlace(
          label: (raw['address'] as String?)?.trim().isNotEmpty == true ? raw['address'] as String : (fallback?.label ?? ''),
          lat: (raw['lat'] as num?)?.toDouble(),
          lng: (raw['lng'] as num?)?.toDouble(),
        );
      }
      return fallback ?? const ReservationPlace(label: '');
    }

    final id = trip['tripId'] as String;
    final fare = Money.fromWire(trip['fare']);
    final category = (trip['categoryId'] as String?) ?? draft?.categoryId ?? 'economy';
    final at = WireTime.tryParse(trip['scheduledAt']) ?? draft?.scheduledPickupAt ?? DateTime.now();
    final driver = trip['driver'];
    final cancellation = trip['cancellation'];
    final actor = cancellation is Map ? cancellation['actor'] : null;
    final cancelFee = cancellation is Map ? Money.fromWire(cancellation['fee']) : null;
    final stops = trip['stops'];
    return Reservation(
      reservationId: id,
      createdAt: WireTime.tryParse(trip['createdAt']) ?? DateTime.now(),
      scheduledPickupAt: at,
      pickup: place(trip['pickup'], draft?.pickup),
      destination: place(trip['dropoff'], draft?.destination),
      stops: [if (stops is List) for (final s in stops) place(s, null)],
      categoryId: category,
      categoryName: draft?.categoryName ?? categoryLabel?.call(category) ?? category,
      categoryImage: draft?.categoryImage ?? '',
      price: fare == null ? (draft?.price ?? 0) : fare.amountMinor / Money.minorPerMajor(fare.currency),
      currency: fare?.currency ?? draft?.currency ?? Money.defaultCurrency,
      paymentMethod: draft?.paymentMethod ?? (trip['paymentMethod'] as String? ?? 'cash'),
      status: statusOf(trip['status']),
      driver: driver is Map ? ReservationDriver.tryParse({...driver, 'id': driver['driverId']}) : null,
      note: draft?.note,
      cancellationActor: switch (actor) {
        'rider' => TripCancellationActor.rider,
        'driver' => TripCancellationActor.driver,
        'admin' => TripCancellationActor.admin,
        'system' => TripCancellationActor.system,
        _ => null,
      },
      cancelledAt: cancellation is Map ? WireTime.tryParse(cancellation['at']) : null,
      cancellationFee: cancelFee,
      timeZone: draft?.timeZone,
    );
  }
}
