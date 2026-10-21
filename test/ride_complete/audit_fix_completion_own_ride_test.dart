// rider-u166 / rider-u176: the scheduled-ride completion screen read its
// driver, receipt and tip currency from LastCompletedRide, which still held
// the previous Book Now ride.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_live_ride.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QuietRealtime implements RideRealtime {
  final StreamController<RideRealtimeEvent> _controller =
      StreamController<RideRealtimeEvent>.broadcast(sync: true);

  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => _controller.stream;
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
  void dispose() => _controller.close();
}

/// The morning's Book Now ride, still in LastCompletedRide.
RideSnapshot _bookNow() => RideSnapshot(
  status: RideStatus.tripCompleted,
  savedAt: DateTime.now(),
  pickupAddress: 'Slussen',
  destinationAddress: 'Kista',
  pickupLat: 59.3195,
  pickupLng: 18.0722,
  destinationLat: 59.4032,
  destinationLng: 17.9447,
  rideType: 'Movera',
  price: 24,
  currency: 'EUR',
  paymentMethod: 'Visa •••• 4242',
  rideId: 'bn-1',
  driver: const MatchedDriver(
    id: 'd-ali',
    firstName: 'Ali',
    plate: 'ALI 123',
    vehicleMake: 'Toyota',
    vehicleModel: 'Prius',
  ),
);

Reservation _reservation() => Reservation(
  reservationId: 'rsv-1',
  createdAt: DateTime(2026, 10, 20, 9),
  scheduledPickupAt: DateTime(2026, 10, 21, 23, 50),
  pickup: const ReservationPlace(label: 'Home', lat: 59.33, lng: 18.06),
  destination: const ReservationPlace(label: 'Arlanda', lat: 59.65, lng: 17.93),
  categoryId: 'economy',
  categoryName: 'Economy',
  categoryImage: '',
  price: 450,
  paymentMethod: 'Cash',
  status: ReservationStatus.completed,
  driver: const ReservationDriver(
    firstName: 'Erik',
    plate: 'ERK 456',
    vehicle: 'Volvo XC40',
  ),
);

Future<void> _pump(WidgetTester tester, String rideId) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final realtime = _QuietRealtime();
  addTearDown(realtime.dispose);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(1200, 2400),
      builder: (_, __) => MaterialApp(
        home: RideCompleted(
          status: RideStatus.tripCompleted,
          rideId: rideId,
          realtime: realtime,
          persistOnDemandState: false,
          feedbackAvailableOnCompletion: true,
          showConnectionBanner: false,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LastCompletedRide.clear();
    LastCompletedRide.remember(_bookNow());
  });
  tearDown(LastCompletedRide.clear);

  testWidgets('another ride\'s completion never shows the Book Now ride', (
    tester,
  ) async {
    await _pump(tester, 'rsv-other');
    expect(find.textContaining('Ali'), findsNothing);
    expect(find.textContaining('Slussen'), findsNothing);
    expect(find.textContaining('Kista'), findsNothing);
    expect(AppScope.instance.rideComplete.driver(rideId: 'rsv-other'), isNull);
    expect(AppScope.instance.rideComplete.receipt(rideId: 'rsv-other'), isNull);
    // Q5: no EUR tips for a ride that is not the EUR one.
    expect(
      AppScope.instance.rideComplete
          .initialTips(rideId: 'rsv-other')
          .every((tip) => tip.currency == 'SEK'),
      isTrue,
    );
  });

  testWidgets('a completed reservation shows its own driver and receipt', (
    tester,
  ) async {
    ReservationLiveRide.rememberCompleted(_reservation());
    await _pump(tester, 'rsv-1');
    expect(find.textContaining('Erik'), findsWidgets);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Arlanda'), findsOneWidget);
    expect(find.textContaining('Ali'), findsNothing);
    expect(find.textContaining('Slussen'), findsNothing);
    expect(
      AppScope.instance.rideComplete.receipt(rideId: 'rsv-1')?.method,
      'Cash',
    );
  });
}
