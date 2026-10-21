import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/notifications/application/notifications_controller.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:movera_rider/features/notifications/presentation/notifications.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/scheduled_rides/application/scheduled_rides_controller.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wave 5 R5.3: small semantics checks (label, tap action, value, size)
/// for the accessibility fixes, one case per bug.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MoveraScreenUtilInit(
        builder: (_, __) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('rider-u64: Share trip is a 44 px named button', (tester) async {
    await pump(
      tester,
      const Scaffold(body: Center(child: WaitingShareButton())),
    );
    final handle = tester.ensureSemantics();
    final share = find.bySemanticsLabel('Share trip');
    expect(tester.getSize(share).shortestSide, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(share),
      isSemantics(
        label: 'Share trip',
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('rider-u110: the raise-offer sheet leaves Cancel uncovered '
      'on a short viewport', (tester) async {
    const rideId = 'a11y-price-bump';
    final server = InProcessMockClient();
    server.rides[rideId] = {'id': rideId, 'status': 'searching'};
    AppScope.instance.ride
      ..rideId = rideId
      ..status = RideStatus.findingDriver
      ..suppressRestore = false;
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
    final controller = FindingDriverController(
      realtime: realtime,
      api: ApiClient(client: server),
      priceBumpAfter: const Duration(seconds: 1),
    );
    // iPhone SE in Safari: about 375 x 548.
    await pump(
      tester,
      FindingDrivers(
        pickupAddress: 'Stockholm Central',
        destinationAddress: 'Arlanda Airport',
        pickupPosition: const LatLng(59.33, 18.059),
        destinationPosition: const LatLng(59.6519, 17.9186),
        rideType: 'Movera',
        price: 349,
        paymentMethod: 'Apple Pay',
        realtime: realtime,
        controller: controller,
      ),
      size: const Size(375, 548),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(controller.showPriceBump, isTrue);

    final handle = find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == const Color(0xFFE7EBEE),
    );
    // Any touch on the sheet settles it on its stops (the card's 520 px).
    await tester.drag(handle.first, const Offset(0, -20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.getRect(handle.first).top, greaterThanOrEqualTo(56));
    final close = find.byIcon(Icons.close_rounded).first;
    final hits = tester.hitTestOnBinding(tester.getCenter(close));
    expect(
      hits.path.any((entry) => entry.target == tester.renderObject(close)),
      isTrue,
      reason: 'the sheet paints over the Cancel button',
    );

    realtime.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('rider-u130: an unread notification is announced as unread', (
    tester,
  ) async {
    final controller = NotificationsController(store: NotificationsRepository())
      ..ingest(
        const PushPayload(
          type: 'ride.completed',
          title: 'New one',
          body: 'Not read yet.',
          messageId: 'a11y-unread',
        ),
        read: false,
      )
      ..ingest(
        const PushPayload(
          type: 'ride.completed',
          title: 'Old one',
          body: 'Already read.',
          messageId: 'a11y-read',
        ),
        read: true,
      );
    final handle = tester.ensureSemantics();
    await pump(tester, NotificationScreen(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('New one'), findsOneWidget);
    expect(find.text('Old one'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Unread')), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('Unread'))).label,
      contains('New one'),
    );
    handle.dispose();
  });

  testWidgets('rider-u151: a choice sheet marks the current option selected', (
    tester,
  ) async {
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAccountChoice(
              context,
              title: 'Language',
              options: const ['English', 'Français', 'Svenska'],
              selected: 'Svenska',
            ),
            child: const Text('open-choice'),
          ),
        ),
      ),
    );
    final handle = tester.ensureSemantics();
    await tester.tap(find.text('open-choice'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('Svenska')),
      isSemantics(isSelected: true, hasSelectedState: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.text('English')),
      isSemantics(isSelected: false, hasTapAction: true),
    );
    handle.dispose();
  });

  testWidgets('rider-u167: scheduling close and back buttons are named and '
      'at least 44 px', (tester) async {
    final handle = tester.ensureSemantics();
    void expectNamedButton(String label) {
      final node = find.bySemanticsLabel(label);
      expect(node, findsOneWidget, reason: label);
      expect(
        tester.getSemantics(node),
        isSemantics(isButton: true, hasTapAction: true),
      );
      expect(tester.getSize(node).shortestSide, greaterThanOrEqualTo(44));
    }

    final reservations = ReservationController(
      store: LocalReservationRepository(storage: MemoryReservationStorage()),
    );
    final ride = await reservations.create(
      ReservationDraft(
        scheduledPickupAt: DateTime.now().add(const Duration(days: 1)),
        pickup: const ReservationPlace(label: 'Home'),
        destination: const ReservationPlace(label: 'Arlanda Express'),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 522,
        paymentMethod: 'Card',
      ),
    );
    await pump(
      tester,
      RideScheduledPage(
        reservationId: ride.reservationId,
        controller: reservations,
      ),
    );
    expectNamedButton('Close');

    await pump(
      tester,
      ScheduleDateTimeSelector(
        body: const SizedBox.shrink(),
        session: ScheduledRideSession(),
        onConfirm: () {},
      ),
    );
    expectNamedButton('Back');

    await pump(tester, const ScheduleRide());
    expectNamedButton('Back');
    handle.dispose();
  });

  testWidgets('rider-68: the driver card reads the plate in the app language',
      (tester) async {
    L10n.use('sv');
    addTearDown(() => L10n.use('en'));
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const Scaffold(
        body: ReservationDriverCard(
          driver: ReservationDriver(firstName: 'Anna', plate: 'ABC 123'),
        ),
      ),
    );
    final card = find.bySemanticsLabel(RegExp('Anna'));
    final label = tester.getSemantics(card).label;
    expect(label, contains('registreringsnummer ABC 123'));
    expect(label, isNot(contains('plate')));
    expect(L10n.current.restoringRide, isNot('Restoring active ride'));
    handle.dispose();
  });
}
