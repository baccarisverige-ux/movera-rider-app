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
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Feed implements RideRealtime {
  final StreamController<RideRealtimeEvent> _events =
      StreamController<RideRealtimeEvent>.broadcast();

  void add(RideRealtimeEvent event) => _events.add(event);

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

/// rider-u58: on web every driver-marker update converts the car icon to a
/// fresh blob URL that is never revoked, and an icon with no width/height
/// also makes google_maps_flutter_web probe its size with a new image load
/// on each update. With the marker eased at ~20 fps for the whole trip that
/// is thousands of leaked blobs an hour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });

  tearDown(() => driverMarkerEases = true);

  // First in the file: the icon is cached as a Future, and a widget test
  // that pumps the Waiting map would otherwise create that Future inside
  // its own fake-async zone, where it never completes for a later test.
  test(
    'the car icon declares its size, so the web plugin never probes it',
    () async {
      final icon = await MoveraVehicleMarker.createIcon();
      expect(icon, isA<BytesMapBitmap>());
      final bytes = icon as BytesMapBitmap;
      expect(bytes.width, isNotNull);
      expect(bytes.height, isNotNull);
      expect(bytes.width, bytes.height);
    },
  );

  LatLng driverMarker(WidgetTester tester) => tester
      .widget<CustomGoogleMap>(find.byKey(const ValueKey('waiting-map')))
      .markers!
      .singleWhere((marker) => marker.markerId.value == 'driver')
      .position;

  testWidgets('without the ease the car sits on each fix, no in-between', (
    tester,
  ) async {
    driverMarkerEases = false;
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
          rideId: 'web-marker-1',
          realtime: feed,
          persistRideSnapshot: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    RideRealtimeEvent fix(int sequence, double lat) => RideRealtimeEvent(
      tripId: 'web-marker-1',
      status: RideStatus.driverArriving,
      sequence: sequence,
      latitude: lat,
      longitude: 18.06,
      locationAt: DateTime.now(),
    );
    // The map paints at most every 400 ms of real time, so real time has
    // to pass between the two fixes (each pump does real work).
    Future<void> realTime(Duration span) async {
      final start = DateTime.now();
      while (DateTime.now().difference(start) < span) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    feed.add(fix(1, 59.34));
    await tester.pump();
    await realTime(const Duration(milliseconds: 450));
    expect(driverMarker(tester).latitude, 59.34);

    feed.add(fix(2, 59.335));
    await tester.pump();
    await realTime(const Duration(milliseconds: 450));
    // One update per fix: the marker is already on the new fix, with no
    // eased position in between.
    expect(driverMarker(tester).latitude, 59.335);
    await tester.pumpWidget(const SizedBox());
  });
}
