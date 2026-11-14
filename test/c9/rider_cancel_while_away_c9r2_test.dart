import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/design_system/movera_icon_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Feed implements RideRealtime {
  final _events = StreamController<RideRealtimeEvent>.broadcast();
  int _sequence = 0;

  void add(RideStatus status, {Map<String, Object?> payload = const {}}) {
    _sequence += 1;
    _events.add(
      RideRealtimeEvent(
        tripId: 'c9-away',
        status: status,
        sequence: _sequence,
        version: _sequence,
        driver: const MatchedDriver(id: 'd1', firstName: 'Anna'),
        payload: payload,
      ),
    );
  }

  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => _events.stream;
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
  void dispose() => unawaited(_events.close());
}

/// Job C9 round 2 (contract v0.18.93 `autoArrive.riderCancel`, supervisor
/// must-fix M3; owner Rules decisions/driver-g15.md:64 "if driver drive away
/// from pickup … if rider cancel he got no cancellation fee"): while the
/// server's waiting clock stands still (`waiting.away`) the rider's cancel
/// sheet says there is no fee — also after the free wait ended. Back at
/// the pickup it is the no-show fee again (control). SEK and TND.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    L10n.use('en');
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });

  Future<void> openCancel(
    WidgetTester tester, {
    required String currency,
    required int noShowMinor,
    required bool away,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final feed = _Feed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Vasagatan 1',
          destinationAddress: 'Kungsgatan 2',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.3326, 18.0649),
          rideType: 'Movera',
          price: 300,
          currency: currency,
          paymentMethod: 'Cash',
          rideId: 'c9-away',
          driver: const MatchedDriver(id: 'd1', firstName: 'Anna'),
          realtime: feed,
          persistRideSnapshot: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final now = DateTime.now().toUtc();
    feed.add(
      RideStatus.driverWaiting,
      payload: {
        termsKey: {
          'currency': currency,
          'freeWaitMin': 5,
          'waitPerMin': {'amountMinor': 500, 'currency': currency},
          'noShowAfterMin': 5,
          'noShowFee': {'amountMinor': noShowMinor, 'currency': currency},
          'cancelRule': {'freeMin': 2, 'type': 'fixed', 'value': 3500},
          'cancelAfterArrivedIsNoShow': true,
          'maxPickupMoveMeters': 200,
        },
        acceptedAtKey: WireTime.format(
          now.subtract(const Duration(minutes: 20)),
        ),
        waitingArrivedAtKey: WireTime.format(
          now.subtract(const Duration(minutes: 10)),
        ),
        waitingFreeUntilKey: WireTime.format(
          now.subtract(const Duration(minutes: 5)),
        ),
        // The free wait ended 5 min ago; he drove away 2 min ago.
        if (away)
          waitingAwaySinceKey: WireTime.format(
            now.subtract(const Duration(minutes: 2)),
          ),
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    if (find.byType(DriverArrivedSheet).evaluate().isNotEmpty) {
      await tester.tap(
        find.descendant(
          of: find.byType(DriverArrivedSheet),
          matching: find.byType(FilledButton),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    final close = tester.widget<MoveraIconButton>(
      find.ancestor(
        of: find.byIcon(Icons.close_rounded).first,
        matching: find.byType(MoveraIconButton),
      ),
    );
    close.onPressed();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final (currency, minor) in [('SEK', 6500), ('TND', 6500)]) {
    testWidgets('$currency: driver away after the free wait: the cancel '
        'sheet says no fee (not the no-show fee)', (tester) async {
      await openCancel(
        tester,
        currency: currency,
        noShowMinor: minor,
        away: true,
      );
      final noShow = L10n.current.cancelCostsNow(
        formatMoney(Money(minor, currency)),
      );
      expect(find.text(noShow), findsNothing, reason: 'the no-show fee');
      expect(find.text(L10n.current.noFeeToCancel), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('$currency control: the driver is at the pickup: the no-show '
        'fee', (tester) async {
      await openCancel(
        tester,
        currency: currency,
        noShowMinor: minor,
        away: false,
      );
      final noShow = L10n.current.cancelCostsNow(
        formatMoney(Money(minor, currency)),
      );
      expect(find.text(noShow), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
