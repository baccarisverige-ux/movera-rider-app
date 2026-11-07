import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/features/reservations/application/reservation_error_message.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_errors.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';

/// Live test 2026-11-03 and owner A / D, contract v0.18.19. Each test
/// fails on the build before this job.
Reservation _ride(ReservationStatus status) => Reservation(
  reservationId: 'trp_1',
  createdAt: DateTime.utc(2026, 11, 3, 7),
  scheduledPickupAt: DateTime.utc(2026, 11, 5, 9),
  pickup: const ReservationPlace(label: 'Sergels torg'),
  destination: const ReservationPlace(label: 'Medborgarplatsen'),
  categoryId: 'economy',
  categoryName: 'Movera',
  categoryImage: 'assets/images/rides/movera.webp',
  price: 244,
  paymentMethod: 'Cash',
  status: status,
  driver: const ReservationDriver(firstName: 'Amina'),
);

Map<String, Object?> _doc(Map<String, Object?> booking) => {
  'version': 2,
  'publishedAt': '2026-11-01T00:00:00Z',
  'zoneId': 'Z001',
  'currency': 'SEK',
  'timeZone': 'Europe/Stockholm',
  'booking': booking,
};

void main() {
  test('owner A: the rider config reads the zone switch (on when missing)', () {
    expect(
      RiderAppConfig.fromJson(_doc({'reservationsOn': false}))!.reservationsOn,
      isFalse,
    );
    expect(RiderAppConfig.fromJson(_doc({}))!.reservationsOn, isTrue);
  });

  test('owner A: the server\'s reservations_off says "Not available in this '
      'area yet"', () {
    expect(BookLaterRefusedException.reasons, contains('reservations_off'));
    expect(
      reservationErrorMessage(
        const BookLaterRefusedException('reservations_off'),
        ReservationAction.book,
      ),
      'Not available in this area yet',
    );
  });

  test('LOW 12 + Q10: the free change rule uses the zone value, with the 5 '
      'free minutes after booking', () {
    expect(
      ReservationFormat.freeRule(60),
      'Free change more than 1 hour before pickup. '
      'Free cancel for 5 min after booking.',
    );
    expect(
      ReservationFormat.freeRule(120),
      'Free change more than 2 hours before pickup. '
      'Free cancel for 5 min after booking.',
    );
    expect(
      ReservationFormat.freeRule(45),
      'Free change more than 45 min before pickup. '
      'Free cancel for 5 min after booking.',
    );
  });

  test('owner D: "Driver assigned" with no name until the driver drives, '
      'then "Driver is on the way"', () {
    final held = _ride(ReservationStatus.driverAssigned);
    expect(ReservationFormat.statusTitle(held), 'Driver assigned');
    expect(
      ReservationFormat.statusBody(held, assignmentDisclaimer: ''),
      isNot(contains('Amina')),
    );
    expect(
      ReservationFormat.statusTitle(_ride(ReservationStatus.driverEnRoute)),
      'Driver is on the way',
    );
  });

  testWidgets('LOW 12: the time screen says the rule with the zone value', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScheduleDateTimeSelector(
          body: const SizedBox.shrink(),
          onConfirm: () {},
          freeChangeBeforeMin: 120,
          now: () => DateTime(2026, 11, 3, 8),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text(
        'Free change more than 2 hours before pickup. '
        'Free cancel for 5 min after booking.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('LOW 16: the menu\'s Later chip has its own label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RiderMenuPage(onStartBooking: () {}, onSchedule: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final labels = find
        .bySemanticsLabel(RegExp('later', caseSensitive: false))
        .evaluate()
        .map(
          (e) =>
              tester.getSemantics(find.byElementPredicate((x) => x == e)).label,
        )
        .toList();
    expect(labels, contains('Book a ride for later'));
    semantics.dispose();
  });
}
