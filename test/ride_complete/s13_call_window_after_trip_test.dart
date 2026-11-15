import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    show GoogleMapsFlutterPlatform;
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/calls/presentation/call_window_gate.dart';
import 'package:movera_rider/features/history/presentation/past_ride_route_map.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/fake_maps_platform.dart';

/// v0.18.113 BQ-S13 (owner 2026-11-01 "Keep call open for 1 hour but not
/// chat", Rules decisions/driver-g9.md:38): after the drop-off the rider can
/// still call the driver until the server's `callOpenUntil` (drop-off + the
/// country's callWindowAfterTripMin, default 60). "Call driver" shows on the
/// ride complete screen and on the past ride in History until then and
/// hides by itself; no `callOpenUntil` (calls off) → no button.
class _Realtime extends RideRealtime {
  final c = StreamController<RideRealtimeEvent>.broadcast(sync: true);
  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => c.stream;
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
  void dispose() => c.close();
}

const _button = ValueKey<String>('call-driver-after-trip');

void _server(DateTime? callOpenUntil, List<String> asked) {
  CallDriverAfterTrip.readTrip = (id) async {
    asked.add(id);
    return {
      'tripId': id,
      'status': 'completed',
      'callOpenUntil': ?callOpenUntil?.toUtc().toIso8601String(),
    };
  };
}

Future<void> _completed(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final realtime = _Realtime();
  addTearDown(realtime.dispose);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(1200, 2400),
      builder: (_, _) => MaterialApp(
        home: RideCompleted(
          status: RideStatus.paymentFinalized,
          rideId: 'trp_s13',
          realtime: realtime,
          persistOnDemandState: false,
          showConnectionBanner: false,
          receiptLoader: (_) async => null,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Reservation _past() => Reservation(
  reservationId: 'ondemand-trp_s13',
  createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
  scheduledPickupAt: DateTime.now().subtract(const Duration(minutes: 25)),
  pickup: ReservationPlace(label: 'Odenplan', lat: 59.3430, lng: 18.0490),
  destination: ReservationPlace(
    label: 'Solna centrum',
    lat: 59.3590,
    lng: 18.0000,
  ),
  categoryId: 'economy',
  categoryName: 'Movera',
  categoryImage: 'assets/images/rides/movera.webp',
  price: 259,
  paymentMethod: 'Apple Pay',
  status: ReservationStatus.completed,
);

Future<void> _history(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RideHistory(
        reservations: ReservationController(
          store: LocalReservationRepository(
            storage: MemoryReservationStorage(),
          ),
        ),
        onDemandReader: () async => [_past()],
        receiptLoader: (_) async => null,
        pathLoader: (_) async => null,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Completed'));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Solna centrum').first);
  await tester.pumpAndSettle();
  expect(find.text('Completed ride'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GoogleMapsFlutterPlatform previousPlatform;
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    LastCompletedRide.clear();
    L10n.use('en');
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
    previousPlatform = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = FakeMapsPlatform();
    CustomGoogleMap.debugWaitForMaps = false;
  });
  tearDown(() {
    CallDriverAfterTrip.readTrip = null;
    LastCompletedRide.clear();
    L10n.use('en');
    GoogleMapsFlutterPlatform.instance = previousPlatform;
    CustomGoogleMap.debugWaitForMaps = null;
    PastRideRouteMap.debugLive = null;
  });

  testWidgets('ride complete: Call driver until callOpenUntil, then gone '
      'by itself', (tester) async {
    final asked = <String>[];
    _server(DateTime.now().add(const Duration(minutes: 5)), asked);
    await _completed(tester);
    expect(asked, contains('trp_s13'));
    expect(find.byKey(_button), findsOneWidget);
    expect(find.text('Call driver'), findsOneWidget);
    await tester.pump(const Duration(minutes: 6));
    expect(find.byKey(_button), findsNothing, reason: 'the window closed');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ride complete: no callOpenUntil (calls off) → no Call driver', (
    tester,
  ) async {
    _server(null, <String>[]);
    await _completed(tester);
    expect(find.byKey(_button), findsNothing);
    expect(find.text('Call driver'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('History › Completed › a ride that ended 25 min ago shows '
      'Call driver until callOpenUntil', (tester) async {
    _server(DateTime.now().add(const Duration(minutes: 35)), <String>[]);
    await _history(tester);
    expect(find.byKey(_button), findsOneWidget);
    expect(find.text('Call driver'), findsOneWidget);
    await tester.pump(const Duration(minutes: 36));
    expect(find.byKey(_button), findsNothing, reason: 'the window closed');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('History: callOpenUntil already passed → no Call driver', (
    tester,
  ) async {
    _server(DateTime.now().subtract(const Duration(minutes: 1)), <String>[]);
    await _history(tester);
    expect(find.byKey(_button), findsNothing);
    expect(find.text('Call driver'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
