import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
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
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/features/safety/presentation/pin_verification_page.dart';
import 'package:movera_rider/features/scheduled_rides/application/scheduled_rides_controller.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/support/application/support_controller.dart';
import 'package:movera_rider/features/support/domain/support.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'safety/safety_test.dart' show TestSafetyRecorder;

/// Quotes [totalMinor] for each ride type, at once (as
/// phase139_select_ride_characterization_test); null never answers.
class _Quotes implements QuoteRepository {
  _Quotes(this.totalMinor);
  final int? Function(String rideType) totalMinor;

  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int durationSeconds = 600,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) {
    final total = totalMinor(rideType);
    if (total == null) return Completer<RideQuote>().future;
    return Future<RideQuote>.value(
      RideQuote(
        id: 'q-$rideType',
        rideType: rideType,
        totalMinor: total,
        currency: 'SEK',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        signedPayload: 'sig',
      ),
    );
  }
}

/// A device with no dialer (web, tablet).
class _NoDialer implements EmergencyDialer {
  @override
  Future<void> open(String number) async =>
      throw const EmergencyCallException('No phone app on this device');
}

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
  ) => controller.create(
    ReservationDraft(
      scheduledPickupAt: pickupAt,
      pickup: const ReservationPlace(label: 'Home', lat: 59.33, lng: 18.06),
      destination: const ReservationPlace(
        label: 'Arlanda',
        lat: 59.65,
        lng: 17.93,
      ),
      categoryId: 'comfort',
      categoryName: 'Comfort',
      categoryImage: 'assets/images/rides/comfort.webp',
      price: 450,
      paymentMethod: 'Cash',
    ),
  );

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

  /// Select Ride from [pickup] on [quotes], tall enough that every ride is
  /// on screen.
  Future<RideSelectionController> openSelectRide(
    WidgetTester tester,
    QuoteRepository quotes, {
    LatLng pickup = const LatLng(59.3293, 18.0686),
    LatLng destination = const LatLng(59.3429, 18.0496),
  }) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final selection = RideSelectionController(quotes: quotes);
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Pickup',
          destinationAddress: 'Destination',
          pickupPosition: pickup,
          destinationPosition: destination,
          pickupAlreadyConfirmed: true,
          selection: selection,
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return selection;
  }

  /// Safety over the in-process backend (as audit_fix_r52ab_test's
  /// rider-u35), with [dialer]; [store] is the session's store.
  late SafetyStore store;
  SafetyController safetyWith({EmergencyDialer? dialer}) {
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
    store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    final safety = SafetyController(
      session: store,
      emergency: EmergencyCallService(
        dialer: dialer ?? RecordingEmergencyDialer(),
      ),
      audio: SafetyAudioService(recorder: TestSafetyRecorder(), store: store),
    );
    SafetyController.sharedForTest = safety;
    addTearDown(() => SafetyController.sharedForTest = null);
    return safety;
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

  test(
    'rider-u156: a sign-out after the reauthentication window says so',
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
    },
  );

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
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 'OK',
              'rideTypes': [
                type('economy', 'Movera'),
                type('comfort', 'Comfort'),
              ],
            }),
            200,
          ),
        ),
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

    await openFrom(
      tester,
      (context) =>
          PromotionDetailsSheet.open(context, promotion, catalog: catalog),
    );

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

  testWidgets('rider-u160: the chrono countdown fits its disc in French at '
      'large text', (tester) async {
    L10n.use('fr');
    addTearDown(() => L10n.use('en'));
    clock = DateTime(2026, 10, 22, 8);
    final controller = reservations();
    await book(controller, DateTime(2026, 10, 22, 10));
    clock = DateTime(2026, 10, 22, 9, 59, 30); // 'Maintenant'

    await pumpPage(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: HomeReservationChrono(
                controller: controller,
                now: () => clock,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Maintenant'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
  });

  testWidgets('rider-j8-2: a completed reservation is not headed "Upcoming '
      'ride" or "reserved for"', (tester) async {
    clock = DateTime(2026, 10, 22, 8);
    final controller = reservations();
    final ride = await book(controller, DateTime(2026, 10, 22, 10));
    await controller.applyDriverAssignment(
      ride.reservationId,
      driver: const ReservationDriver(firstName: 'Amina', rating: 4.9),
    );
    await controller.update(
      ride.reservationId,
      const ReservationPatch(status: ReservationStatus.completed),
    );

    await pumpPage(
      tester,
      UpcomingReservationPage(
        reservationId: ride.reservationId,
        controller: controller,
      ),
    );

    expect(find.text('Upcoming ride'), findsNothing);
    expect(find.textContaining('Your ride is reserved for'), findsNothing);
    expect(find.text('Completed ride'), findsOneWidget);
  });

  testWidgets('rider-u172: "Things to know" stops saying "free until" once '
      'the free window closes', (tester) async {
    clock = DateTime(2026, 10, 22, 8);
    final controller = reservations();
    final ride = await book(controller, DateTime(2026, 10, 22, 10));
    String cancellation() => ReservationFormat.cancellationSummary(
      controller.cancelTermsFor(controller.byId(ride.reservationId)!),
    );
    clock = DateTime(2026, 10, 22, 8, 50);
    await pumpPage(
      tester,
      UpcomingReservationPage(
        reservationId: ride.reservationId,
        controller: controller,
      ),
    );
    await tester.scrollUntilVisible(
      find.text('View scheduled ride terms'),
      300,
    );
    final free = cancellation();
    expect(find.text(free), findsOneWidget);

    // The rider keeps the page open past the free window.
    clock = DateTime(2026, 10, 22, 9, 5);
    await tester.pump(const Duration(minutes: 15));

    expect(cancellation(), isNot(free));
    expect(find.text(cancellation()), findsOneWidget);
  });

  testWidgets('rider-r3-7: each row shows the fare it was quoted (the '
      'filter chips are gone since owner round 2)', (tester) async {
    // Priority lists dearer than Movera but is quoted cheapest.
    final selection = await openSelectRide(
      tester,
      _Quotes((type) => type == 'priority' ? 10000 : 30000),
    );
    await tester.tap(find.byKey(const ValueKey('select-ride-sheet-handle')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Cheaper'), findsNothing);
    final list = find.byKey(const ValueKey('select-ride-list'));
    final priority = selection.rideByIdOrNull('priority')!;
    expect(priority.price, isNot(100));
    expect(
      find.descendant(of: list, matching: find.text('100 kr')),
      findsWidgets,
    );
  });

  testWidgets('rider-80: no wallet split from a kronor list price on a euro '
      'pickup before its quote', (tester) async {
    // As currency_by_zone_test: a 50 € wallet in Paris; no quote yet.
    SharedPreferences.setMockInitialValues({
      WalletStore.balanceKeyFor('EUR'): 50.0,
    });
    final selection = await openSelectRide(
      tester,
      _Quotes((_) => null),
      pickup: const LatLng(48.8606, 2.3376),
      destination: const LatLng(48.8809, 2.3553),
    );
    expect(selection.currency, 'EUR');
    expect(selection.walletBalance, 50);

    expect(find.byKey(const ValueKey('select-ride-wallet-line')), findsNothing);
    // Let Select Ride's pending quote timers run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  test('rider-81: a call to 112 that never opened is not saved as '
      '"Called 112"', () async {
    final rideCheck = RideCheckController.forSafety(
      safetyWith(dialer: _NoDialer()),
    );
    RideCheckController.sharedForTest = rideCheck;
    addTearDown(() {
      RideCheckController.sharedForTest = null;
      rideCheck.dispose();
    });
    rideCheck.attachTrip(
      const RideCheckTripContext(rideId: 'r1'),
      const RideCheckPlan(
        pickup: GeoPoint(59.3293, 18.0686),
        destination: GeoPoint(59.3600, 18.0000),
      ),
    );
    await rideCheck.open(RideCheckTrigger.longStop, rideId: 'r1');

    await rideCheck.call112();

    final session = rideCheck.session!;
    expect(session.callError, isNotNull);
    expect(
      session.answers.map((answer) => answer.kind),
      isNot(contains(RideCheckAnswerKind.call112)),
    );
    expect(
      session.alertState,
      isNot(RideCheckAlertState.none),
      reason: 'the alert is still sent',
    );
  });

  testWidgets('rider-u203: a PIN change that failed says so', (tester) async {
    final safety = safetyWith();
    await safety.load();
    await pumpPage(tester, PinVerificationPage(controller: safety));

    store.failNextWrite = true; // offline
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Change PIN'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not change PIN.'), findsOneWidget);
  });

  testWidgets('rider-u225: a return-ride prefill off the slot grid says it '
      'moved', (tester) async {
    final now = DateTime.now();
    // Three hours ahead, at :02 (off the 5-minute grid).
    final prefill = DateTime(now.year, now.month, now.day, now.hour + 3, 2);
    await openFrom(
      tester,
      (context) => ScheduleDateTimeSelector.choose(
        context,
        initial: prefill,
        now: () => now,
      ),
    );

    expect(
      find.text('Pickup time updated to the next available slot.'),
      findsOneWidget,
    );
  });

  testWidgets('rider-u227: a pickup time that went stale on screen is '
      'corrected on Continue, not greyed out', (tester) async {
    var now = DateTime.now();
    var confirmed = 0;
    final session = ScheduledRideSession();
    Widget picker() => ScheduleDateTimeSelector(
      body: const SizedBox.shrink(),
      session: session,
      now: () => now,
      onConfirm: () => confirmed++,
    );
    await pumpPage(tester, picker());

    // The rider waits past the earliest slot; something rebuilds the page.
    now = now.add(const Duration(hours: 2));
    await tester.pumpWidget(MaterialApp(home: picker()));
    await tester.tap(find.byKey(const Key('schedule-continue')));
    await tester.pumpAndSettle();

    expect(
      find.text('Pickup time updated to the next available slot.'),
      findsOneWidget,
    );
    expect(confirmed, 0, reason: 'the corrected time is shown first');
  });

  testWidgets('rider-u229: Support cases does not say "No active cases" '
      'with nothing behind it', (tester) async {
    // The rider has just sent a ride issue; no case list backs this page.
    await pumpPage(tester, const SupportMessages());

    expect(find.text('No active cases'), findsNothing);
    expect(
      find.text("Your cases aren't listed in the app yet"),
      findsOneWidget,
    );
  });

  test(
    'rider-u230: Support shows a late-cancel fee, not 0 or the fare',
    () async {
      clock = DateTime(2026, 10, 22, 9, 30);
      final controller = reservations();
      final ride = await book(controller, DateTime(2026, 10, 22, 10));
      final cancelled = await controller.cancel(
        ride.reservationId,
        fee: const Money(5000),
      );

      final row = SupportController.rideFor(cancelled);

      expect(row.priceLabel, contains('50'));
      expect(row.priceLabel, isNot(contains('450')));
    },
  );

  testWidgets('rider-r3-2: a ride history that could not load says so and '
      'retries', (tester) async {
    var loads = 0;
    await pumpPage(
      tester,
      SelectSupportRide(
        loadRides: () async {
          if (loads++ == 0) throw http.ClientException('offline');
          return const <SupportRide>[];
        },
      ),
    );
    expect(find.text('No rides yet'), findsNothing);
    expect(find.text('Couldn’t load rides'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.text('No rides yet'), findsOneWidget);
  });

  testWidgets('rider-96: the side gutter follows a window resize', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<double> gutterAt(double width) async {
      tester.view.physicalSize = Size(width, 844);
      late double gutter;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => Builder(
            builder: (_) {
              gutter = screenHorizPadding;
              return const SizedBox();
            },
          ),
        ),
      );
      return gutter;
    }

    expect(await gutterAt(390), 16);
    expect(await gutterAt(487.5), 20, reason: '16 at the 1.25 scale');
  });
}
