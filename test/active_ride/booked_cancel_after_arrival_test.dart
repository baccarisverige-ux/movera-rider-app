import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
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

  void add(
    RideStatus status, {
    RealtimeKind? kind,
    double? lat,
    double? lng,
    Map<String, Object?> payload = const {},
  }) {
    _sequence += 1;
    _events.add(
      RideRealtimeEvent(
        tripId: 'bk-cancel',
        status: status,
        sequence: _sequence,
        version: _sequence,
        kind: kind,
        driver: const MatchedDriver(id: 'd1', firstName: 'Anna'),
        latitude: lat,
        longitude: lng,
        locationAt: lat == null ? null : DateTime.now(),
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

/// Contract v0.18.51 §73 (bookedRide0_18_51.fees, owner "If rider cancel do
/// booking fee"): on a booked ride the cancel sheet after the driver
/// arrived shows the booked-ride cancel fee (the reservation cancel rule,
/// feeKind cancel), never the no-show fee.
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

  testWidgets('booked ride, driver arrived, free waiting over: the cancel '
      'sheet says the booking fee', (tester) async {
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
          currency: 'SEK',
          paymentMethod: 'Cash',
          rideId: 'bk-cancel',
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
          'currency': 'SEK',
          'freeWaitMin': 5,
          'waitPerMin': {'amountMinor': 500, 'currency': 'SEK'},
          'noShowAfterMin': 5,
          'noShowFee': {'amountMinor': 6500, 'currency': 'SEK'},
          'cancelRule': {'freeMin': 120, 'type': 'fixed', 'value': 5000},
          'cancelAfterArrivedIsNoShow': true,
          'maxPickupMoveMeters': 200,
        },
        waitingArrivedAtKey: WireTime.format(
          now.subtract(const Duration(minutes: 10)),
        ),
        waitingFreeUntilKey: WireTime.format(
          now.subtract(const Duration(minutes: 1)),
        ),
        bookedPickupAtKey: WireTime.format(
          now.subtract(const Duration(minutes: 6)),
        ),
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The arrived sheet, when announced on top, is closed first.
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
    // The close control's own action (the test view's top bar overlaps
    // it for a hit test).
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
    final booking = L10n.current.cancelCostsNow(
      formatMoney(const Money(5000, 'SEK')),
    );
    final noShow = L10n.current.cancelCostsNow(
      formatMoney(const Money(6500, 'SEK')),
    );
    expect(find.text(noShow), findsNothing, reason: 'the no-show fee');
    expect(find.text(booking), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
