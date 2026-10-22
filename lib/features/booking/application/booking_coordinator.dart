import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/contracts/cancel_reasons.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/analytics/analytics.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/mutation_attempt.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/booking/application/booking_attempt.dart';
import 'package:movera_rider/features/fare/domain/fare_rules.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/active_trip_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/core/contracts/server_clock.dart';

class BookingCoordinator {
  BookingCoordinator({ApiClient? api, ActiveTripRepository? activeTrips})
    : _api = api,
      _activeTrips = activeTrips;

  final ApiClient? _api;
  final ActiveTripRepository? _activeTrips;
  final MutationAttempt _duplicateCancelMutation =
      MutationAttempt('duplicate-ride-cancel');
  Future<String>? _inflight;
  BookingAttempt? _attempt;
  String? _autoQuoteIntent;
  _BookingQuoteBinding? _autoQuoteBinding;

  ApiClient get _client => _api ?? AppScope.instance.api;

  /// Lock only while the Finding UI is actually mounted.
  /// Do not treat a leftover [RideSession] status as an active search — tests
  /// and a dismissed route share the process-wide [AppScope].
  bool get _findingAlreadyActive => FindingDriverController.active != null;

  Future<String> _refuseOrExisting() {
    final id = AppScope.instance.ride.rideId;
    if (id != null) return Future<String>.value(id);
    return Future<String>.error(StateError('Finding already active'));
  }

  BookingAttempt _attemptFor(String intentKey) {
    final current = _attempt;
    if (current != null && current.matches(intentKey)) return current;
    final next = BookingAttempt(intentKey: intentKey);
    _attempt = next;
    return next;
  }

  void _releaseWhenDone(
    Future<String> started,
    BookingAttempt attempt,
  ) {
    started.then<void>(
      (_) {
        if (identical(_inflight, started)) _inflight = null;
        if (identical(_attempt, attempt)) _attempt = null;
      },
      onError: (Object error, StackTrace _) {
        // Keep the logical attempt after failure so an explicit retry of the
        // same booking intent reuses the exact same idempotency key. A
        // refusal means no ride exists: the next try is a new booking.
        if (identical(_inflight, started)) _inflight = null;
        if (_isRefusal(error) && identical(_attempt, attempt)) {
          _attempt = null;
        }
      },
    );
  }

  /// The server answered and refused (a 4xx such as an expired quote): no
  /// ride exists. A timeout, network error or 5xx may have created one.
  static bool _isRefusal(Object error) {
    if (error is! ApiError) return false;
    final status = error.statusCode;
    return status != null &&
        status >= 400 &&
        status < 500 &&
        !error.isRetryable;
  }

  String _requireRideId(Map<String, dynamic> json) {
    final rawRide = json['ride'];
    if (rawRide is! Map) {
      throw const FormatException('Booking response missing ride object');
    }
    final rawId = rawRide['id'];
    if (rawId is! String) {
      throw const FormatException('Booking response missing ride id');
    }
    final id = rawId.trim();
    if (id.isEmpty || id.toLowerCase() == 'null') {
      throw const FormatException('Booking response contains invalid ride id');
    }
    return id;
  }

  /// The trip status the server created the ride in (contract v0.3.0:
  /// `requested` for a reservation, `searching` for a live trip). The
  /// client never assumes it (audit B5).
  RideStatus _createdStatus(Map<String, dynamic> json) {
    final ride = json['ride'];
    final status = ride is Map ? RideStatusWire.fromProjection(ride) : null;
    if (status == null) {
      throw StateError('The created ride carries no contract status');
    }
    return status;
  }

  int? _rideVersion(Map<String, dynamic> json) {
    final ride = json['ride'];
    if (ride is! Map) return null;
    return (ride['version'] as num?)?.toInt();
  }

  DateTime? _rideUpdatedAt(Map<String, dynamic> json) {
    final ride = json['ride'];
    if (ride is! Map) return null;
    return DateTime.tryParse(ride['updatedAt'] as String? ?? '');
  }

  /// A booking for later. RIDE-22: the intent and the body carry the route
  /// (pickup, destination, stops) and, when Select Ride priced it, the quote,
  /// so two different scheduled rides at the same time never share a key.
  Future<String> requestBooking({
    required String rideType,
    required String paymentMethod,
    String? scheduledAt,
    String? pickupAddress,
    double? pickupLat,
    double? pickupLng,
    String? destinationAddress,
    double? destinationLat,
    double? destinationLng,
    List<RouteStop> stops = const <RouteStop>[],
    String? quoteId,
    String? quoteSignedPayload,
    DateTime? quoteExpiresAt,
    int? quoteTotalMinor,
    String quoteCurrency = Money.defaultCurrency,
  }) {
    if (_inflight != null) return _inflight!;
    if (scheduledAt == null && _findingAlreadyActive) {
      return _refuseOrExisting();
    }
    final intentKey = jsonEncode(<String, Object?>{
      'operation': 'requestBooking',
      'rideType': rideType,
      'paymentMethod': paymentMethod,
      'scheduledAt': scheduledAt,
      'pickupAddress': pickupAddress,
      'pickup': _intentPoint(pickupLat, pickupLng),
      'destinationAddress': destinationAddress,
      'destination': _intentPoint(destinationLat, destinationLng),
      'stops': [
        for (final stop in stops) _intentPoint(stop.latitude, stop.longitude),
      ],
    });
    final attempt = _attemptFor(intentKey);
    final body = <String, dynamic>{
      'categoryId': rideType,
      'paymentMethodId': paymentMethod,
      'scheduledAt': scheduledAt,
      if (pickupAddress != null) 'pickupAddress': pickupAddress,
      if (pickupLat != null && pickupLng != null) ...{
        'pickupLat': pickupLat,
        'pickupLng': pickupLng,
      },
      if (destinationAddress != null)
        'destinationAddress': destinationAddress,
      if (destinationLat != null && destinationLng != null) ...{
        'destinationLat': destinationLat,
        'destinationLng': destinationLng,
      },
      if (stops.isNotEmpty) 'stops': [for (final stop in stops) stop.toJson()],
      if (quoteId != null) ...{
        'quoteId': quoteId,
        'quoteSignedPayload': quoteSignedPayload,
        'quoteExpiresAt': quoteExpiresAt?.toUtc().toIso8601String(),
        'quoteTotalMinor': quoteTotalMinor,
        if (quoteTotalMinor != null)
          'fare': Money(quoteTotalMinor, quoteCurrency).toJson(),
      },
    };
    // RC-04: a retry of an unfinished attempt resends its first body.
    Future<String> send() =>
        _requestBooking(body: body, scheduledAt: scheduledAt, attempt: attempt);
    final replay = attempt.replay;
    attempt.replay ??= send;
    final started = replay != null ? replay() : send();
    _inflight = started;
    _releaseWhenDone(started, attempt);
    return started;
  }

  /// A point in a booking intent, to about 11 m: the same trip confirmed
  /// again from a pin that moved a step is still the same booking.
  static List<int>? _intentPoint(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    return [(lat * 1e4).round(), (lng * 1e4).round()];
  }

  Future<String> _requestBooking({
    required Map<String, dynamic> body,
    String? scheduledAt,
    required BookingAttempt attempt,
  }) async {
    final id = attempt.idempotencyKey;
    final json = await _client.post(
      '/api/v1/rides',
      body: body,
      idempotencyKey: id,
    );
    final rideId = _requireRideId(json);
    final created = _createdStatus(json);
    AppScope.instance.ride
      ..backendReconcile(
        created,
        id: rideId,
        version: _rideVersion(json),
        updatedAt: _rideUpdatedAt(json),
      )
      // R-O2: the first expectedVersion of this trip.
      ..observeProjection(json);
    Analytics.bookingSubmitted(rideId: rideId);
    return rideId;
  }

  /// rider-u107: a fresh, signed quote for booking the same route again
  /// ("Try again" after no driver), so the screen can ask the rider to
  /// accept a changed price before it books. Throws when no bookable quote
  /// could be had.
  Future<RideQuote> freshQuote({
    required String rideType,
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    List<RouteStop> stops = const <RouteStop>[],
  }) async {
    final quote = await ApiQuoteRepository(api: _client).quote(
      rideType: rideType,
      distanceMeters: _approxDistanceMeters(
        pickupLat,
        pickupLng,
        destinationLat,
        destinationLng,
      ),
      pickup: pickupAddress,
      destination: destinationAddress,
      pickupPoint: GeoPoint(pickupLat, pickupLng),
      destinationPoint: GeoPoint(destinationLat, destinationLng),
      stops: stops,
    );
    _BookingQuoteBinding(
      id: quote.id,
      signedPayload: quote.signedPayload ?? '',
      expiresAt: quote.expiresAt,
      totalMinor: quote.totalMinor,
      currency: quote.currency,
    ).validate();
    return quote;
  }

  Future<String> submitFinding({
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    required String rideType,
    required double price,
    required String paymentMethod,
    String? quoteId,
    String? quoteSignedPayload,
    DateTime? quoteExpiresAt,
    int? quoteTotalMinor,
    String quoteCurrency = Money.defaultCurrency,
    String? rideTypeLabel,
    String? paymentMethodLabel,
    RideNotes notes = RideNotes.empty,
    List<RouteStop> stops = const <RouteStop>[],
    bool useWalletFirst = false,
    int walletAmountMinor = 0,
  }) {
    if (_inflight != null) return _inflight!;
    if (_findingAlreadyActive) {
      return _refuseOrExisting();
    }

    final started = _prepareFinding(
      pickupAddress: pickupAddress,
      destinationAddress: destinationAddress,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      rideType: rideType,
      requestedPrice: price,
      paymentMethod: paymentMethod,
      quoteId: quoteId,
      quoteSignedPayload: quoteSignedPayload,
      quoteExpiresAt: quoteExpiresAt,
      quoteTotalMinor: quoteTotalMinor,
      quoteCurrency: quoteCurrency,
      rideTypeLabel: rideTypeLabel,
      paymentMethodLabel: paymentMethodLabel,
      notes: notes,
      stops: stops,
      useWalletFirst: useWalletFirst,
      walletAmountMinor: walletAmountMinor,
    );
    _inflight = started;
    started.then<void>(
      (_) {
        if (identical(_inflight, started)) _inflight = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_inflight, started)) _inflight = null;
      },
    );
    return started;
  }

  Future<String> _prepareFinding({
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    required String rideType,
    required double requestedPrice,
    required String paymentMethod,
    String? quoteId,
    String? quoteSignedPayload,
    DateTime? quoteExpiresAt,
    int? quoteTotalMinor,
    String quoteCurrency = Money.defaultCurrency,
    String? rideTypeLabel,
    String? paymentMethodLabel,
    RideNotes notes = RideNotes.empty,
    List<RouteStop> stops = const <RouteStop>[],
    bool useWalletFirst = false,
    int walletAmountMinor = 0,
  }) async {
    final baseIntent = jsonEncode(<String, Object?>{
      'pickupAddress': pickupAddress,
      'destinationAddress': destinationAddress,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'destinationLat': destinationLat,
      'destinationLng': destinationLng,
      'categoryId': rideType,
      'paymentMethodId': paymentMethod,
      'notes': notes.toJson(),
      'stops': [for (final stop in stops) stop.toJson()],
      'useWalletFirst': useWalletFirst,
    });

    // RIDE-3: the key belongs to the rider's trip, not to the quote. A
    // retry after a timeout is the same booking, so it reuses the key and
    // the server can never create a second ride for it. RC-04: it also
    // resends the first request unchanged (same quote, same pin), since a
    // contract server answers a different body under the same key with
    // 409. Notes and the wallet choice are part of the intent: changing
    // them is a different request.
    final intentKey = jsonEncode(<String, Object?>{
      'operation': 'submitFinding',
      'pickup': _intentPoint(pickupLat, pickupLng),
      'destination': _intentPoint(destinationLat, destinationLng),
      'categoryId': rideType,
      'paymentMethodId': paymentMethod,
      'stops': [
        for (final stop in stops) _intentPoint(stop.latitude, stop.longitude),
      ],
      'notes': notes.toJson(),
      'useWalletFirst': useWalletFirst,
    });
    // rider-u80: the last attempt was sent and never answered (it may have
    // created the ride) and this one would get a new key: a moved pin, or
    // a retry after the reuse window. Ask the server first, so the ghost
    // ride is adopted rather than booked a second time.
    final uncertain = _attempt;
    if (uncertain != null &&
        uncertain.replay != null &&
        !uncertain.matches(intentKey)) {
      final adopted = await _adoptActiveTrip(
        destinationLat,
        destinationLng,
        anyDestination: true,
      );
      if (identical(_attempt, uncertain)) _attempt = null;
      if (adopted != null) return adopted;
    }
    final attempt = _attemptFor(intentKey);

    try {
      final replay = attempt.replay;
      String id;
      if (replay != null) {
        id = await _sendOrRecover(attempt, replay, destinationLat, destinationLng);
      } else {
        final binding = await _resolveQuoteBinding(
          baseIntent: baseIntent,
          pickupAddress: pickupAddress,
          destinationAddress: destinationAddress,
          pickupLat: pickupLat,
          pickupLng: pickupLng,
          destinationLat: destinationLat,
          destinationLng: destinationLng,
          rideType: rideType,
          requestedPrice: requestedPrice,
          quoteId: quoteId,
          quoteSignedPayload: quoteSignedPayload,
          quoteExpiresAt: quoteExpiresAt,
          quoteTotalMinor: quoteTotalMinor,
          quoteCurrency: quoteCurrency,
          stops: stops,
        );
        // Whole units of the quote's currency (Q7: the pickup's zone).
        final effectivePrice = binding.total.major;
        // "Use wallet balance first": the part the rider was shown, never
        // more than the fare, and nothing when the rider switched it off.
        final walletMinor = useWalletFirst
            ? walletAmountMinor.clamp(0, binding.totalMinor).toInt()
            : 0;
        Future<String> send({bool isReplay = false}) => _submitFinding(
          pickupAddress: pickupAddress,
          destinationAddress: destinationAddress,
          pickupLat: pickupLat,
          pickupLng: pickupLng,
          destinationLat: destinationLat,
          destinationLng: destinationLng,
          rideType: rideType,
          price: effectivePrice,
          paymentMethod: paymentMethod,
          quoteId: binding.id,
          quoteSignedPayload: binding.signedPayload,
          quoteExpiresAt: binding.expiresAt,
          quoteTotalMinor: binding.totalMinor,
          quoteCurrency: binding.currency,
          rideTypeLabel: rideTypeLabel,
          paymentMethodLabel: paymentMethodLabel,
          notes: notes,
          stops: stops,
          useWalletFirst: useWalletFirst,
          walletAmountMinor: walletMinor,
          attempt: attempt,
          isReplay: isReplay,
          onSending: () => attempt.replay ??= () => send(isReplay: true),
        );
        id = await _sendOrRecover(attempt, send, destinationLat, destinationLng);
      }
      if (identical(_attempt, attempt)) _attempt = null;
      if (_autoQuoteIntent == baseIntent) {
        _autoQuoteIntent = null;
        _autoQuoteBinding = null;
      }
      return id;
    } on ApiError catch (error) {
      // The server answered and refused (a 4xx such as an expired quote):
      // no ride exists, so the next try is a new booking with a new key.
      // A timeout, network error or 5xx keeps the key: the ride may exist.
      if (_isRefusal(error) && identical(_attempt, attempt)) _attempt = null;
      rethrow;
    }
  }

  /// RC-09: a timeout, network error or 5xx after the request went out may
  /// still have created the ride. Before the rider is told the booking
  /// failed, the same request is sent once more (same key, same body) and
  /// then the server is asked for the rider's active trip; a live trip to
  /// the same destination is this booking and is adopted.
  Future<String> _sendOrRecover(
    BookingAttempt attempt,
    Future<String> Function() send,
    double destinationLat,
    double destinationLng,
  ) async {
    try {
      return await send();
    } catch (error) {
      final replay = attempt.replay;
      if (!maybeCreated(error) || replay == null) rethrow;
      AppLog.warning('booking.maybe_created', extra: {'error': '$error'});
      try {
        return await replay();
      } catch (again) {
        if (!maybeCreated(again)) rethrow;
      }
      final adopted = await _adoptActiveTrip(destinationLat, destinationLng);
      if (adopted != null) return adopted;
      rethrow;
    }
  }

  /// A failure after which the server may still have created the ride: a
  /// timeout, a dropped connection or a 5xx (never a refusal).
  static bool maybeCreated(Object error) => error is ApiError
      ? error.isRetryable
      : error is http.ClientException;

  /// The rider's live trip on the server, when it is the booking being
  /// made (same destination): adopted as the created ride. Null otherwise.
  ///
  /// [anyDestination] (rider-u80): an earlier booking may exist, and the
  /// server keeps no one-live-trip rule, so any live trip is that booking.
  /// A lookup that fails the way a request can while offline is then
  /// rethrown: no new key may go out until the server was asked.
  Future<String?> _adoptActiveTrip(
    double destinationLat,
    double destinationLng, {
    bool anyDestination = false,
  }) async {
    RideSnapshot? trip;
    try {
      trip = await (_activeTrips ?? AppScope.instance.activeTrips).fetchActive();
    } catch (error) {
      AppLog.warning('booking.active_trip_failed', extra: {'error': '$error'});
      if (anyDestination && maybeCreated(error)) rethrow;
      return null;
    }
    final id = trip?.rideId?.trim();
    if (trip == null ||
        id == null ||
        id.isEmpty ||
        trip.status.isTerminal ||
        trip.status.tripStatus.isTerminal) {
      return null;
    }
    final same = _intentPoint(trip.destinationLat, trip.destinationLng)
            ?.join(',') ==
        _intentPoint(destinationLat, destinationLng)?.join(',');
    if (!same && !anyDestination) return null;
    final collision = await _standDownIfFindingOwned(createdRideId: id);
    if (collision != null) return collision;
    final session = AppScope.instance.ride;
    session.backendReconcile(
      trip.status,
      id: id,
      version: trip.version,
      updatedAt: trip.serverUpdatedAt,
    );
    session
      ..bookedCategoryId = trip.categoryId ?? session.bookedCategoryId
      ..bookedPaymentMethodId =
          trip.paymentMethodId ?? session.bookedPaymentMethodId
      ..bookedMaxOfferMinor = trip.maxOfferMinor ?? session.bookedMaxOfferMinor;
    await RideSnapshotStore.save(trip);
    AppLog.info('booking.adopted_active_trip', extra: {'rideId': id});
    return id;
  }

  Future<_BookingQuoteBinding> _resolveQuoteBinding({
    required String baseIntent,
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    required String rideType,
    required double requestedPrice,
    String? quoteId,
    String? quoteSignedPayload,
    DateTime? quoteExpiresAt,
    int? quoteTotalMinor,
    String quoteCurrency = Money.defaultCurrency,
    List<RouteStop> stops = const <RouteStop>[],
  }) async {
    final supplied = <Object?>[
      quoteId,
      quoteSignedPayload,
      quoteExpiresAt,
      quoteTotalMinor,
    ];
    final suppliedCount = supplied.where((value) => value != null).length;
    if (suppliedCount != 0 && suppliedCount != supplied.length) {
      throw StateError('Incomplete authoritative quote binding');
    }

    if (suppliedCount == supplied.length) {
      final binding = _BookingQuoteBinding(
        id: quoteId!,
        signedPayload: quoteSignedPayload!,
        expiresAt: quoteExpiresAt!,
        totalMinor: quoteTotalMinor!,
        currency: quoteCurrency,
      );
      binding.validate(requestedPrice: requestedPrice);
      return binding;
    }

    final cached = _autoQuoteBinding;
    if (_autoQuoteIntent == baseIntent &&
        cached != null &&
        cached.expiresAt.isAfter(ServerClock.now())) {
      return cached;
    }

    final quote = await ApiQuoteRepository(api: _client).quote(
      rideType: rideType,
      distanceMeters: _approxDistanceMeters(
        pickupLat,
        pickupLng,
        destinationLat,
        destinationLng,
      ),
      pickup: pickupAddress,
      destination: destinationAddress,
      pickupPoint: GeoPoint(pickupLat, pickupLng),
      destinationPoint: GeoPoint(destinationLat, destinationLng),
      stops: stops,
    );
    final binding = _BookingQuoteBinding(
      id: quote.id,
      signedPayload: quote.signedPayload ?? '',
      expiresAt: quote.expiresAt,
      totalMinor: quote.totalMinor,
      currency: quote.currency,
    )..validate();

    _autoQuoteIntent = baseIntent;
    _autoQuoteBinding = binding;
    return binding;
  }

  int _approxDistanceMeters(
    double pickupLat,
    double pickupLng,
    double destinationLat,
    double destinationLng,
  ) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = pickupLat * math.pi / 180;
    final lat2 = destinationLat * math.pi / 180;
    final dLat = (destinationLat - pickupLat) * math.pi / 180;
    final dLng = (destinationLng - pickupLng) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return math.max(1, (earthRadiusMeters * c).round());
  }

  Future<String> _submitFinding({
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    required String rideType,
    required double price,
    required String paymentMethod,
    required String quoteId,
    required String quoteSignedPayload,
    required DateTime quoteExpiresAt,
    required int quoteTotalMinor,
    String quoteCurrency = Money.defaultCurrency,
    String? rideTypeLabel,
    String? paymentMethodLabel,
    RideNotes notes = RideNotes.empty,
    List<RouteStop> stops = const <RouteStop>[],
    bool useWalletFirst = false,
    int walletAmountMinor = 0,
    required BookingAttempt attempt,
    bool isReplay = false,
    void Function()? onSending,
  }) async {
    if (quoteId.trim().isEmpty ||
        quoteSignedPayload.trim().isEmpty ||
        // A replay may carry a quote that expired meanwhile: the server
        // either returns the ride it already created or refuses it.
        (!isReplay && !quoteExpiresAt.isAfter(ServerClock.now())) ||
        quoteTotalMinor <= 0 ||
        // ARCH-11: the shown price must be the quote, compared in minor
        // units of the quote's currency.
        Money.fromLegacyMajor(price, quoteCurrency).amountMinor !=
            quoteTotalMinor) {
      throw StateError('A fresh authoritative quote is required for booking');
    }

    final key = attempt.idempotencyKey;
    onSending?.call();
    final json = await _client.post(
      '/api/v1/rides',
      body: {
        'pickupAddress': pickupAddress,
        'destinationAddress': destinationAddress,
        'pickupLat': pickupLat,
        'pickupLng': pickupLng,
        'destinationLat': destinationLat,
        'destinationLng': destinationLng,
        'categoryId': rideType,
        // Contract v0.3.0: the confirmed fare as Money (it equals the
        // quote, in the quote's currency).
        'fare': Money(quoteTotalMinor, quoteCurrency).toJson(),
        'paymentMethodId': paymentMethod,
        'quoteId': quoteId,
        'quoteSignedPayload': quoteSignedPayload,
        'quoteExpiresAt': quoteExpiresAt.toUtc().toIso8601String(),
        'quoteTotalMinor': quoteTotalMinor,
        // Bags, pet, baby and child are accessibility and safety options, not
        // cosmetics: the driver needs them before accepting, so they travel
        // with the booking rather than stopping at the selection screen.
        'notes': notes.toJson(),
        if (stops.isNotEmpty) 'stops': [for (final stop in stops) stop.toJson()],
        // ARCH-5 / contract C-3: the wallet split the rider was shown is a
        // booking intent the server applies, not presentation state.
        'useWalletFirst': useWalletFirst,
        'walletAmountMinor': walletAmountMinor,
      },
      idempotencyKey: key,
    );
    final id = _requireRideId(json);
    // Booking → Finding only on the server's word: the response must say
    // the trip is requested / searching.
    final created = _createdStatus(json);
    if (!created.isSearching) {
      throw StateError('The server did not open a search (${created.name})');
    }
    Analytics.bookingSubmitted(rideId: id);

    // R-O2: known before a race-losing duplicate is stood down below.
    AppScope.instance.ride.observeProjection(json);
    final collisionBeforeCommit = await _standDownIfFindingOwned(createdRideId: id);
    if (collisionBeforeCommit != null) return collisionBeforeCommit;

    final version = _rideVersion(json);
    final serverUpdatedAt = _rideUpdatedAt(json);
    final session = AppScope.instance.ride;
    session.backendReconcile(
      created,
      id: id,
      version: version,
      updatedAt: serverUpdatedAt,
    );
    // ARCH-20: the offer ceiling comes from the server when it says, else
    // from the booked fare, once; a raised offer never moves it.
    final maxOfferMinor =
        _maxOfferMinorFrom(json) ??
        Money.fromLegacyMajor(FareRules.maximum(price), quoteCurrency)
            .amountMinor;
    session
      ..bookedCategoryId = rideType
      ..bookedPaymentMethodId = paymentMethod
      ..bookedMaxOfferMinor = maxOfferMinor;
    final now = DateTime.now();
    // ARCH-1 / RIDE-17: the first snapshot already carries the server's
    // ordering (version + updatedAt) and the stops, so a reload in the first
    // seconds of the search restores the same ride, in the right order.
    await RideSnapshotStore.save(
      RideSnapshot(
        status: created,
        savedAt: now,
        searchStartedAt: now,
        version: version,
        serverUpdatedAt: serverUpdatedAt?.toUtc(),
        stops: stops,
        categoryId: rideType,
        paymentMethodId: paymentMethod,
        maxOfferMinor: maxOfferMinor,
        pickupAddress: pickupAddress,
        destinationAddress: destinationAddress,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
        rideType: rideTypeLabel ?? rideType,
        price: price,
        currency: quoteCurrency,
        paymentMethod: paymentMethodLabel ?? paymentMethod,
        rideId: id,
        notes: notes,
        walletAmountMinor: _walletMinorFrom(json) ?? walletAmountMinor,
      ),
    );

    // The snapshot save crosses an async boundary. A Finding surface can
    // become authoritative while persistence is in flight, so close that
    // second race window before returning the created id to presentation.
    final collisionAfterCommit = await _standDownIfFindingOwned(createdRideId: id);
    if (collisionAfterCommit != null) return collisionAfterCommit;

    return id;
  }

  /// The offer ceiling the server set for the ride, when it says.
  int? _maxOfferMinorFrom(Map<String, dynamic> json) {
    final ride = json['ride'];
    if (ride is! Map) return null;
    final raw = ride['maxOfferMinor'];
    return raw is num && raw > 0 ? raw.round() : null;
  }

  /// The wallet part the server accepted, when it says.
  int? _walletMinorFrom(Map<String, dynamic> json) {
    final ride = json['ride'];
    if (ride is! Map) return null;
    return (ride['walletAmountMinor'] as num?)?.round();
  }

  Future<String?> _standDownIfFindingOwned({
    required String createdRideId,
  }) async {
    final owner = FindingDriverController.active;
    if (owner == null) return null;

    final ownerId = owner.ownedRideId;
    final ownerSnapshot = owner.ownershipSnapshot;
    if (ownerId == null ||
        ownerId.isEmpty ||
        ownerSnapshot == null ||
        ownerId == createdRideId) {
      return ownerId == createdRideId ? createdRideId : null;
    }

    // A visible Finding surface already owns another ride. The race-losing
    // backend ride must be explicitly stood down; never leave two live rides.
    final cancelIntent = createdRideId;
    final key = _duplicateCancelMutation.keyFor(cancelIntent);
    // rider-u81: queued first, with the same key, so a stand-down the
    // network loses is retried by the outbox flush (launch, reconnect)
    // instead of leaving a second live ride. Its failure is not this
    // booking's: the rider's ride is the owner's, which is fine.
    await PendingCancelStore.enqueue(
      rideId: createdRideId,
      idempotencyKey: key,
      expectedVersion: AppScope.instance.ride.projectionVersionOf(
        createdRideId,
      ),
    );
    try {
      await _client.post(
        '/api/v1/rides/$createdRideId/cancel',
        body: _cancelBody(createdRideId),
        idempotencyKey: key,
      );
      _duplicateCancelMutation.succeeded(cancelIntent);
      await PendingCancelStore.remove(createdRideId);
    } catch (error) {
      if (isPermanentCancelFailure(error)) {
        // Gone or already over on the server: nothing left to stand down.
        _duplicateCancelMutation.succeeded(cancelIntent);
        await PendingCancelStore.remove(createdRideId);
      }
      AppLog.warning(
        'booking.duplicate_stand_down_failed',
        extra: {'rideId': createdRideId, 'error': error.toString()},
      );
    }

    // Restore the visible owner's identity after the duplicate create response
    // may have temporarily projected the new id into the process-wide session.
    AppScope.instance.ride.backendReconcile(
      ownerSnapshot.status,
      id: ownerId,
    );
    await RideSnapshotStore.save(
      ownerSnapshot.copyWith(savedAt: DateTime.now()),
    );
    return ownerId;
  }

  /// Reconcile a ride that was successfully created while presentation was
  /// handing ownership to Finding. Returns the ride id that remains
  /// authoritative after any collision is resolved.
  Future<String> reconcileCreatedFinding(String createdRideId) async {
    final resolved = await _standDownIfFindingOwned(
      createdRideId: createdRideId,
    );
    return resolved ?? createdRideId;
  }

  Future<void> cancel({required String rideId, required String key}) {
    return _client.post(
      '/api/v1/rides/$rideId/cancel',
      body: _cancelBody(rideId),
      idempotencyKey: key,
    );
  }

  /// R-O2: the trip version the create response carried, when known, and
  /// the contract `reasonCode` every rider cancel names (rider-u19).
  static Map<String, dynamic> _cancelBody(String rideId) {
    final version = AppScope.instance.ride.projectionVersionOf(rideId);
    return {
      ...CancelReasonCodes.riderCancelBody(null),
      'expectedVersion': ?version,
    };
  }
}


class _BookingQuoteBinding {
  const _BookingQuoteBinding({
    required this.id,
    required this.signedPayload,
    required this.expiresAt,
    required this.totalMinor,
    this.currency = Money.defaultCurrency,
  });

  final String id;
  final String signedPayload;
  final DateTime expiresAt;
  final int totalMinor;

  /// The quote's currency (Q7: the pickup's zone).
  final String currency;

  Money get total => Money(totalMinor, currency);

  void validate({double? requestedPrice}) {
    if (id.trim().isEmpty ||
        signedPayload.trim().isEmpty ||
        !expiresAt.isAfter(ServerClock.now()) ||
        totalMinor <= 0) {
      throw StateError('A fresh authoritative quote is required for booking');
    }
    if (requestedPrice != null &&
        Money.fromLegacyMajor(requestedPrice, currency).amountMinor !=
            totalMinor) {
      throw StateError('Selected fare no longer matches the authoritative quote');
    }
  }
}
