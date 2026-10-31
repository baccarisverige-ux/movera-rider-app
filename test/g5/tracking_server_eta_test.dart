import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/trip_terms.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/cancel_fee_texts.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/finding_driver/domain/driver_eta.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';

class _Feed implements RideRealtime {
  final events = StreamController<RideRealtimeEvent>.broadcast();

  @override
  bool get supportsRiderSignals => false;

  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => events.stream;

  @override
  Future<void> reconnectAndResync(String rideId) async {}

  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}

  @override
  void unsubscribe() {}

  @override
  void cancelRide() {}

  @override
  void researchAfterDriverCancel() {}

  @override
  void dispose() => unawaited(events.close());
}

/// Driver group 5 (contract v0.18.7): what the rider's trip screen shows
/// comes from the server — the road-route ETA and distance (Q4), the
/// trip's terms, the waiting cost (Q5), the cancel fee and kind (Q2/Q6)
/// and a moved pickup (item 4). The app computes no ETA of its own.
void main() {
  Map<String, Object?> eta(
    DateTime at, {
    int seconds = 250,
    int meters = 1234,
  }) => {
    'etaSeconds': seconds,
    'distanceMeters': meters,
    'target': 'pickup',
    'at': at.toUtc().toIso8601String(),
    'source': 'osrm',
  };

  late _Feed feed;
  late DriverTrackingController tracking;
  var sequence = 0;

  setUp(() {
    sequence = 0;
    feed = _Feed();
    tracking = DriverTrackingController(
      realtime: feed,
      pickupLat: 59.3293,
      pickupLng: 18.0686,
      destinationLat: 59.3326,
      destinationLng: 18.0649,
      persistRideSnapshot: false,
    )..start(rideId: 'trp_1', initialStatus: RideStatus.driverArriving);
  });

  tearDown(() {
    tracking.dispose();
    feed.dispose();
    L10n.use('en');
  });

  Future<void> send({
    RideStatus status = RideStatus.driverArriving,
    RealtimeKind? kind,
    double? lat,
    double? lng,
    DateTime? locationAt,
    int? etaSeconds,
    Map<String, Object?> payload = const {},
  }) async {
    sequence += 1;
    feed.events.add(
      RideRealtimeEvent(
        tripId: 'trp_1',
        status: status,
        sequence: sequence,
        version: sequence,
        kind: kind,
        latitude: lat,
        longitude: lng,
        locationAt: locationAt,
        etaSeconds: etaSeconds,
        payload: payload,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  test('the server ETA and distance are what the headline says (sv)', () async {
    L10n.use('sv');
    final now = DateTime.now();
    await send(
      lat: 59.34,
      lng: 18.05,
      locationAt: now,
      etaSeconds: 250,
      payload: {etaKey: eta(now)},
    );
    expect(tracking.serverEta?.distanceMeters, 1234);
    final shown = tracking.eta!;
    expect(shown.seconds, 250);
    expect(
      shown.distanceMeters,
      1234,
      reason: 'the road distance, not a guess',
    );
    expect(shown.stale, isFalse);
    expect(
      shown.headline(status: RideStatus.driverArriving),
      'Anländer om 5 min · 1,2 km',
    );
  });

  test('on board the line says "There in … · …" to the drop-off', () async {
    L10n.use('en');
    final now = DateTime.now();
    await send(
      status: RideStatus.tripInProgress,
      lat: 59.34,
      lng: 18.05,
      locationAt: now,
      payload: {
        etaKey: {
          'etaSeconds': 601,
          'distanceMeters': 3449,
          'target': 'dropoff',
          'at': now.toUtc().toIso8601String(),
          'source': 'estimate',
        },
      },
    );
    expect(
      tracking.eta!.subtitle(status: RideStatus.tripInProgress),
      'There in 11 min · 3.4 km',
    );
  });

  test(
    'a parked driver whose phone sends few fixes is not "updating location" '
    'while the server still ticks the ETA (stale only after 120 s)',
    () async {
      L10n.use('en');
      final now = DateTime.now();
      // The last fix is 60 s old (the old rule flagged 25 s), the ETA tick
      // is fresh: not stale.
      await send(
        lat: 59.34,
        lng: 18.05,
        locationAt: now.subtract(const Duration(seconds: 60)),
        payload: {etaKey: eta(now)},
      );
      expect(tracking.eta!.stale, isFalse);
      expect(tracking.eta!.headline(), isNot('Updating driver location…'));
      expect(DriverEta.staleAfter, const Duration(seconds: 120));
      // Nothing from the server for more than 120 s: stale, said so.
      final old = tracking.eta!.withStalenessCheckedAt(
        now.add(const Duration(seconds: 121)),
      );
      expect(old.stale, isTrue);
      expect(old.headline(), 'Updating driver location…');
      // 119 s: still fine.
      expect(
        tracking.eta!
            .withStalenessCheckedAt(now.add(const Duration(seconds: 119)))
            .stale,
        isFalse,
      );
    },
  );

  test(
    'the server says the ETA itself is stale: last known, said so',
    () async {
      L10n.use('en');
      final now = DateTime.now();
      await send(
        lat: 59.34,
        lng: 18.05,
        locationAt: now,
        payload: {
          etaKey: {...eta(now), 'source': 'stale'},
        },
      );
      expect(tracking.eta!.stale, isTrue);
    },
  );

  test('no ETA while the driver waits at the pickup', () async {
    final now = DateTime.now();
    await send(
      lat: 59.34,
      lng: 18.05,
      locationAt: now,
      payload: {etaKey: eta(now)},
    );
    expect(tracking.serverEta, isNotNull);
    await send(
      status: RideStatus.driverWaiting,
      lat: 59.3293,
      lng: 18.0686,
      locationAt: now,
      payload: {waitingArrivedAtKey: now.toUtc().toIso8601String()},
    );
    expect(tracking.serverEta, isNull);
    expect(
      tracking.eta!.headline(status: RideStatus.driverWaiting),
      'Driver has arrived',
    );
  });

  test(
    'terms, the waiting cost so far and the fare come from the trip',
    () async {
      final now = DateTime.now();
      await send(
        status: RideStatus.driverWaiting,
        payload: {
          waitingArrivedAtKey: now.toUtc().toIso8601String(),
          termsKey: {
            'currency': 'EUR',
            'freeWaitMin': 3,
            'waitPerMin': {'amountMinor': 110, 'currency': 'EUR'},
            'noShowAfterMin': 3,
            'noShowFee': {'amountMinor': 800, 'currency': 'EUR'},
            'cancelRule': null,
            'cancelAfterArrivedIsNoShow': true,
            'maxPickupMoveMeters': 200,
          },
          waitingChargedSoFarKey: {'amountMinor': 330, 'currency': 'EUR'},
          waitingChargedSecondsNowKey: 180,
          fareKey: {'amountMinor': 1800, 'currency': 'EUR'},
        },
      );
      expect(tracking.terms?.waitPerMin, const Money(110, 'EUR'));
      expect(tracking.terms?.cancelRule, isNull);
      expect(tracking.waitingChargedSoFar, const Money(330, 'EUR'));
      expect(tracking.waitingChargedSecondsNow, 180);
      expect(tracking.fare, const Money(1800, 'EUR'));
      // Boarded: the fare now holds the waiting (Q5); the running cost is over.
      await send(
        status: RideStatus.tripStarted,
        payload: {
          fareKey: {'amountMinor': 2130, 'currency': 'EUR'},
        },
      );
      expect(tracking.fare, const Money(2130, 'EUR'));
      expect(tracking.waitingChargedSoFar, isNull);
      expect(tracking.terms, isNotNull, reason: 'the terms stay for the trip');
    },
  );

  test('a pickup_moved event moves the pickup the ETA measures to', () async {
    await send(
      kind: RealtimeKind.pickupMoved,
      payload: {
        pickupKey: {'address': 'Vasagatan 9', 'lat': 59.3302, 'lng': 18.069},
      },
    );
    expect(tracking.pickupLat, 59.3302);
    expect(tracking.pickupLng, 18.069);
    final moved = tracking.takeMovedPickup();
    expect(moved?.address, 'Vasagatan 9');
    expect(tracking.takeMovedPickup(), isNull, reason: 'taken once');
    // The same pickup again is not a move.
    await send(
      payload: {
        pickupKey: {'address': 'Vasagatan 9', 'lat': 59.3302, 'lng': 18.069},
      },
    );
    expect(tracking.takeMovedPickup(), isNull);
  });

  test(
    'after a cancel the rider reads the fee and its kind (sv/fr/en)',
    () async {
      await send(
        status: RideStatus.cancelledByRider,
        kind: RealtimeKind.riderCancelled,
        payload: {
          cancellationKey: {
            'actor': 'rider',
            'reasonCode': 'changed_mind',
            'at': DateTime.now().toUtc().toIso8601String(),
            'fee': {'amountMinor': 6500, 'currency': 'SEK'},
            'feeKind': 'no_show',
            'feeStatus': 'owed',
          },
        },
      );
      final outcome = tracking.cancellation!;
      expect(outcome.kind, CancelFeeKind.noShow);
      L10n.use('en');
      expect(riderCancelFeeText(outcome), 'No-show fee 65 kr');
      L10n.use('sv');
      expect(riderCancelFeeText(outcome), 'Avgift för utebliven kund 65 kr');
      L10n.use('fr');
      expect(riderCancelFeeText(outcome), 'Frais de client absent 65 kr');
      L10n.use('en');
      expect(
        riderCancelFeeText(
          const RiderCancelOutcomeFee(
            fee: Money(500, 'EUR'),
            kind: CancelFeeKind.cancel,
          ),
        ),
        'Cancellation fee 5,00 €',
      );
      expect(
        riderCancelFeeText(const RiderCancelOutcomeFee(fee: null, kind: null)),
        'No fee',
      );
      expect(riderCancelFeeText(null), isNull);
    },
  );
}
