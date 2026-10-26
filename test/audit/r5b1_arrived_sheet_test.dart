import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Feed extends RideRealtime {
  final events = StreamController<RideRealtimeEvent>.broadcast();
  var _seq = 0;
  void add(RideStatus status, MatchedDriver driver, {RealtimeKind? kind}) =>
      events.add(
        RideRealtimeEvent(
          rideId: 'r5-26',
          status: status,
          sequence: ++_seq,
          version: _seq,
          driver: driver,
          kind: kind,
        ),
      );
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
  void dispose() {}
}

void main() {
  testWidgets('rider-r5-26: a replaced driver\'s closed sheet does not '
      'unhook the new arrived sheet from trip start', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.driverAssigned,
      id: 'r5-26',
    );
    const a = MatchedDriver(id: 'a', firstName: 'Anna');
    const b = MatchedDriver(id: 'b', firstName: 'Bo');
    final feed = _Feed();
    await tester.pumpWidget(
      MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'P',
          destinationAddress: 'D',
          pickupPosition: const LatLng(59.33, 18.07),
          destinationPosition: const LatLng(59.34, 18.06),
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          driver: a,
          realtime: feed,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    feed.add(RideStatus.driverWaiting, a);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(find.byType(DriverArrivedSheet), findsOneWidget);
    feed.add(RideStatus.driverWaiting, b, kind: RealtimeKind.driverCancelled);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(find.byType(DriverArrivedSheet), findsOneWidget);
    feed.add(RideStatus.tripStarted, b);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(find.byType(DriverArrivedSheet), findsNothing);
  });
}
