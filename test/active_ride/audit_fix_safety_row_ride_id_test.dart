import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-u66: the Safety Kit row on the Waiting sheet took its ride id from
/// the on-demand session, not from the screen's ride, so on a scheduled
/// live ride SOS, trip sharing and recording targeted no ride or the
/// previous Book Now ride. The map button on the same screen was right.
class _Feed implements RideRealtime {
  final StreamController<RideRealtimeEvent> _events =
      StreamController<RideRealtimeEvent>.broadcast();

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
  void dispose() => _events.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    // The previous Book Now ride is still the session's ride.
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.closed, id: 'bn-earlier');
  });

  testWidgets('the sheet\'s Safety Kit row targets the screen\'s ride', (
    tester,
  ) async {
    final feed = _Feed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Stockholm pickup',
          destinationAddress: 'Stockholm destination',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.3326, 18.0649),
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          rideId: 'rsv-live-1',
          realtime: feed,
          persistRideSnapshot: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final row = tester.widget<SafetyKitSheetRow>(
      find.byType(SafetyKitSheetRow),
    );
    expect(row.rideId, 'rsv-live-1');
    final button = tester.widget<SafetyKitMapButton>(
      find.byType(SafetyKitMapButton),
    );
    expect(button.rideId, 'rsv-live-1');
    await tester.pumpWidget(const SizedBox());
  });
}
