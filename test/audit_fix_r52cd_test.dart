import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/presentation/security.dart';
import 'package:movera_rider/features/promotions/domain/rider_promotion.dart';
import 'package:movera_rider/features/promotions/presentation/promotion_details_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wave 5 R5.2 parts c+d: messages that claim success they did not get.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps a phone-sized app around [home].
  Future<void> pumpPage(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  /// Pumps a page with one button that runs [open], and taps it.
  Future<void> openFrom(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open,
  ) =>
      pumpPage(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ).then((_) async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      });

  /// Reservations on a clock the test moves ([clock]).
  var clock = DateTime(2026, 10, 22, 8);
  var reservationIds = 0;
  ReservationController reservations() {
    final controller = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv-r52cd-${reservationIds++}',
      ),
      clock: () => clock,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// Books a Comfort ride at [pickupAt] on [controller].
  Future<Reservation> book(
    ReservationController controller,
    DateTime pickupAt,
  ) =>
      controller.create(ReservationDraft(
        scheduledPickupAt: pickupAt,
        pickup: const ReservationPlace(label: 'Home', lat: 59.33, lng: 18.06),
        destination:
            const ReservationPlace(label: 'Arlanda', lat: 59.65, lng: 17.93),
        categoryId: 'comfort',
        categoryName: 'Comfort',
        categoryImage: 'assets/images/rides/comfort.webp',
        price: 450,
        paymentMethod: 'Cash',
      ));

  /// Pumps frames until [finder] finds something (at most [max] frames).
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    int max = 40,
  }) async {
    for (var i = 0; i < max && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// A Security controller over an API answering GET with [security];
  /// [posts] counts the sign-out requests.
  final posts = <String>[];
  Future<AccountSecurityController> securityWith(
    Map<String, dynamic> security,
  ) async {
    posts.clear();
    final controller = AccountSecurityController(
      repository: AccountSecurityRepository(
        api: ApiClient(
          client: MockClient((request) async {
            if (request.method == 'POST') posts.add(request.url.path);
            return http.Response(
              jsonEncode({'code': 'OK', 'security': security}),
              200,
            );
          }),
          env: AppEnv.current,
        ),
      ),
    );
    await controller.load();
    return controller;
  }

  test('rider-u156: a sign-out after the reauthentication window says so',
      () async {
    final security = await securityWith({
      'reauthenticatedAt': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 6))
          .toIso8601String(),
      'capabilities': {'reauthentication': true, 'signOutOtherDevices': true},
      'sessions': [
        {'id': 's1', 'device': 'This phone', 'current': true},
        {'id': 's2', 'device': 'iPad'},
      ],
    });

    await security.signOutOtherDevices();

    expect(posts, isEmpty);
    expect(security.errorMessage, L10n.current.reauthBeforeRevoke);
  });

  testWidgets('rider-u157: a session without a place has no dangling '
      'separator', (tester) async {
    final security = await securityWith({
      'sessions': [
        {'id': 's1', 'device': 'This phone', 'current': true},
        {'id': 's2', 'device': 'iPad', 'source': 'Web'},
      ],
    });
    await pumpPage(tester, SecurityPage(securityController: security));

    expect(find.text('This session'), findsOneWidget);
    expect(find.text('Web'), findsOneWidget);
  });

  testWidgets('rider-61: promotion details list the live catalog, not the '
      'built-in one', (tester) async {
    // Admin publishes two categories; the built-in list has fourteen.
    Map<String, dynamic> type(String id, String name) => {
          'id': id,
          'name': name,
          'seats': 4,
          'etaMin': 5,
          'price': {'amountMinor': 25900, 'currency': 'SEK'},
          'enabled': true,
        };
    final catalog = RideCatalogController(
      api: ApiClient(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'code': 'OK',
                'rideTypes': [type('economy', 'Movera'), type('comfort', 'Comfort')],
              }),
              200,
            )),
        env: AppEnv.current,
      ),
      cache: MemoryRideCatalogCache(),
    );
    await catalog.load(); // as bootstrap does
    final promotion = RiderPromotion.fromJson({
      'id': 'p1',
      'title': '30% off your next 5 rides',
      'percentOff': 30,
      'ridesLeft': 4,
      'ridesTotal': 5,
      'endsAt': '2026-11-30T23:59:00',
      'rideTypes': <String>[],
      'rules': <String>[],
    })!;

    await openFrom(tester, (context) =>
        PromotionDetailsSheet.open(context, promotion, catalog: catalog));

    final sheet = tester.widget<PromotionDetailsSheet>(
      find.byType(PromotionDetailsSheet),
    );
    expect(sheet.categories.map((c) => c.id), ['economy', 'comfort']);
  });

  testWidgets('rider-j8-10: a later ride\'s driver on the way opens its '
      'live page past an unresolved "no driver found" ride', (tester) async {
    clock = DateTime(2026, 10, 22, 8);
    final controller = reservations();
    await book(controller, DateTime(2026, 10, 22, 9)); // never got a driver
    final later = await book(controller, DateTime(2026, 10, 22, 11));
    await controller.applyDriverAssignment(
      later.reservationId,
      driver: const ReservationDriver(firstName: 'Amina', rating: 4.9),
    );
    await controller.update(
      later.reservationId,
      const ReservationPatch(status: ReservationStatus.driverEnRoute),
    );
    clock = DateTime(2026, 10, 22, 10, 58);

    await pumpPage(
      tester,
      Scaffold(
        body: HomeReservationChrono(controller: controller, now: () => clock),
      ),
    );
    await pumpUntil(tester, find.byType(WaitingForDriver));

    expect(find.byType(WaitingForDriver), findsOneWidget);
  });
}
