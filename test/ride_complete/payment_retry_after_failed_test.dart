import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Realtime implements RideRealtime {
  final _events = StreamController<RideRealtimeEvent>.broadcast(sync: true);
  String? _rideId;
  int _sequence = 0;
  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) {
    _rideId = rideId;
    return _events.stream;
  }

  void emit(RideStatus status) => _events.add(RideRealtimeEvent(
        rideId: _rideId!,
        status: status,
        sequence: ++_sequence,
        at: DateTime.now(),
      ));
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

/// rider-r5-3: contract paymentTransitions has failed -> authorized, so a
/// retried charge that is captured moves the summary and History forward.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a retried payment that is captured is no longer failed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final snapshot = RideSnapshot(
      status: RideStatus.tripCompleted,
      savedAt: DateTime.now(),
      pickupAddress: 'Pickup',
      destinationAddress: 'Destination',
      pickupLat: 59.3293,
      pickupLng: 18.0686,
      destinationLat: 59.3326,
      destinationLng: 18.0649,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
      rideId: 'r5-3',
    );
    await tester.runAsync(() => RideSnapshotStore.save(snapshot));
    LastCompletedRide.remember(snapshot);
    AppScope.instance.ride
      ..rideId = 'r5-3'
      ..status = RideStatus.tripCompleted;
    final realtime = _Realtime();
    addTearDown(realtime.dispose);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(1200, 1600),
      builder: (_, __) => MaterialApp(
        home: RideCompleted(
          status: RideStatus.tripCompleted,
          rideId: 'r5-3',
          realtime: realtime,
        ),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
    }

    await settle();
    realtime.emit(RideStatus.paymentFailed);
    await settle();
    expect(find.text('Payment could not be completed'), findsOneWidget);

    realtime.emit(RideStatus.paymentFinalized);
    await settle();
    expect(find.text('Payment could not be completed'), findsNothing);
    final record = (await tester.runAsync(OnDemandRideHistoryStore.read))!;
    expect(record.single.paymentFailed, isFalse);
  });
}
