import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/support/application/support_contact.dart';
import 'package:movera_rider/features/support/application/support_controller.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:shared_preferences/shared_preferences.dart';

Reservation _ride(String id, String to, ReservationStatus status, int day) =>
    Reservation(
      reservationId: id,
      createdAt: DateTime.utc(2026, 10, 1),
      scheduledPickupAt: DateTime.utc(2026, 10, day, 8),
      pickup: const ReservationPlace(label: 'Sveavägen 1'),
      destination: ReservationPlace(label: to),
      categoryId: 'economy',
      categoryName: 'Movera',
      categoryImage: 'assets/images/rides/movera.webp',
      price: 249,
      paymentMethod: 'Cash',
      status: status,
    );

SupportController _controller() => SupportController(
  onDemand: () async => [
    _ride('od_1', 'Arlanda Express', ReservationStatus.completed, 10),
    _ride('od_2', 'Odenplan', ReservationStatus.cancelled, 12),
  ],
  scheduled: () => [_ride('rsv_1', 'Slussen', ReservationStatus.scheduled, 20)],
);

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pumpAndSettle();
}

/// FLOW-8: Support lists the rides Ride History shows, and offers a direct
/// contact route when the build has a support address.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Support rides are the finished and cancelled history, newest first',
    () async {
      final rides = await _controller().loadRides();
      expect(rides.map((r) => r.id), ['od_2', 'od_1']);
      expect(rides.first.cancelled, isTrue);
      expect(rides.last.title, 'To Arlanda Express');
    },
  );

  testWidgets('Support home lets the rider pick one of their rides', (
    tester,
  ) async {
    await _pump(tester, SupportHome(loadRides: _controller().loadRides));
    expect(find.text('No rides to review'), findsNothing);
    expect(find.text('To Arlanda Express'), findsOneWidget);
    await tester.tap(find.text('To Arlanda Express'));
    await tester.pumpAndSettle();
    expect(find.text('I lost an item'), findsOneWidget);
  });

  testWidgets('Select ride lists the history too', (tester) async {
    await _pump(tester, SelectSupportRide(loadRides: _controller().loadRides));
    expect(find.text('To Odenplan'), findsOneWidget);
    expect(find.text('To Slussen'), findsNothing);
  });

  testWidgets('Email support opens mail when the build has an address', (
    tester,
  ) async {
    final opened = <Uri>[];
    await _pump(
      tester,
      SupportHome(
        loadRides: () async => const [],
        contact: SupportContact(
          email: 'help@example.com',
          launcher: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Email support'), 180);
    await tester.tap(find.text('Email support'));
    await tester.pumpAndSettle();
    expect(opened.single.scheme, 'mailto');
    expect(opened.single.path, 'help@example.com');
  });

  testWidgets('no invented contact address without one', (tester) async {
    await _pump(
      tester,
      SupportHome(
        loadRides: () async => const [],
        contact: const SupportContact(email: ''),
      ),
    );
    expect(find.text('Email support'), findsNothing);
  });

  // rider-r4-37: an ended-early trip read '0 kr · Cancelled' (and the booked
  // 249 kr in the row) although History shows what the rider was charged.
  testWidgets('an ended-early ride shows the charged fare, not Cancelled', (
    tester,
  ) async {
    final ride = SupportController.rideFor(
      _ride(
        'od_3',
        'Odenplan',
        ReservationStatus.cancelled,
        12,
      ).copyWith(endedEarly: true, chargedFare: Money.fromLegacyMajor(80)),
    );
    expect(ride.cancelled, isFalse);
    expect(ride.priceLabel, '80 kr · Ended early');
    await _pump(tester, SelectSupportRide(loadRides: () async => [ride]));
    expect(find.text('80 kr'), findsOneWidget);
    expect(find.text('249 kr'), findsNothing);
  });
}
