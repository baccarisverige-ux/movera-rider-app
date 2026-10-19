import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/plan_return_ride.dart';
import 'package:movera_rider/features/reservations/presentation/scheduled_category_gate.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

Reservation _originWithoutPoints() => Reservation(
  reservationId: 'rsv_no_points',
  createdAt: DateTime.utc(2026, 9, 1),
  scheduledPickupAt: DateTime.utc(2026, 9, 23, 6, 55),
  pickup: ReservationPlace(label: 'Klockarvägen 37'),
  destination: ReservationPlace(label: 'Arlanda Express'),
  categoryId: 'economy',
  categoryName: 'Movera',
  categoryImage: 'assets/images/rides/movera.webp',
  price: 522,
  paymentMethod: 'Cash',
  status: ReservationStatus.completed,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('CODE-4: the Schedule map has no sample "Your location" pin', () {
    // The only markers the Schedule map draws; the template's red pin at
    // Stockholm Centralen claimed to be the rider's position.
    expect(ScheduleRide.mapMarkers, isEmpty);
  });

  test('CODE-5: no fix for "Current location" gives no point, not the city '
      'centre', () async {
    // The test host has no location service, like a slow or refused fix.
    final point = await resolveScheduledPoint('Current location');
    expect(point, isNull);
  });

  test('CODE-5: a return ride is never built on invented points', () {
    final origin = _originWithoutPoints();
    expect(SelectRide.canPlanReturn(origin), isFalse);
    expect(() => SelectRide.forReturnRide(origin), throwsArgumentError);
  });

  testWidgets(
    'CODE-5: Plan return without points sends the rider to Schedule',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PlanReturnRidePage(origin: _originWithoutPoints())),
      );
      await tester.pump();
      expect(find.byType(SelectRide), findsNothing);
      expect(find.text('Schedule a ride'), findsOneWidget);
    },
  );
}
