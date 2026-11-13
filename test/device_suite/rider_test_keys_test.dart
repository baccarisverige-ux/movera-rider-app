import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_reason_sheet.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_top_actions.dart';
import 'package:movera_rider/features/home/presentation/widgets/where_to_card.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_complete/presentation/give_review.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/domain/nearby_car.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G31 rider (owner 2026-11-12 ~17:30 UTC, "Rider test keys: Yes, add
/// (Rec.)"): the real-phone trip suite (integration_test/
/// trip_lifecycle_test.dart) finds the rider's main controls by invisible
/// test names instead of English texts. A key changes nothing a rider can
/// see or do; these tests pin that each name is on the control the suite
/// taps (or reads), so a refactor cannot drop one silently.

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _screen(Widget home) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, __) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

AuthController _auth({http.Client? client}) {
  final tokens = MemoryTokenStore();
  return AuthController(
    auth: AuthRepository(
      api: ApiClient(
        env: AppEnv(
          flavor: client == null ? AppFlavor.test : AppFlavor.staging,
          apiBaseUrl: 'https://api.test.movera.invalid',
        ),
        client: client ?? InProcessMockClient(),
        tokens: tokens,
      ),
      tokens: tokens,
    ),
  );
}

class _Quotes implements QuoteRepository {
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
  }) => Future<RideQuote>.value(
    RideQuote(
      id: 'q-$rideType',
      rideType: rideType,
      totalMinor: 25900,
      currency: 'SEK',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      signedPayload: 'sig',
    ),
  );
}

class _NoCars implements NearbyCarsSource {
  @override
  Future<NearbyCarsAnswer> near(GeoPoint point) async =>
      const NearbyCarsAnswer(cars: [], refresh: Duration(seconds: 30));
}

ReservationController _reservations() => ReservationController(
  store: LocalReservationRepository(
    storage: MemoryReservationStorage(),
    nextId: () => 'rsv_keys',
  ),
  clock: () => DateTime(2026, 9, 22, 12),
);

final _draft = ReservationDraft(
  scheduledPickupAt: DateTime(2026, 9, 23, 6, 55),
  pickup: const ReservationPlace(label: 'Klockarvägen 37'),
  destination: const ReservationPlace(label: 'T-Centralen'),
  categoryId: 'economy',
  categoryName: 'Movera',
  categoryImage: 'assets/images/rides/movera.webp',
  price: 339,
  paymentMethod: 'Cash',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sign in: auth-phone-field, auth-continue', (tester) async {
    _phone(tester);
    final server = MockClient(
      (_) async => http.Response(
        jsonEncode({'code': 'not_found', 'message': 'x'}),
        404,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tester.pumpWidget(_screen(SignIn(controller: _auth(client: server))));
    await tester.pump(const Duration(seconds: 6));
    expect(
      find.descendant(
        of: _key('auth-phone-field'),
        matching: find.byType(EditableText),
      ),
      findsOneWidget,
    );
    expect(tester.widget(_key('auth-phone-field')), isA<TextField>());
    expect(_key('auth-continue'), findsOneWidget);
    expect(_key('auth-consent'), findsOneWidget);
  });

  testWidgets('code screen: auth-code (with its text field), auth-verify', (
    tester,
  ) async {
    _phone(tester);
    final auth = _auth();
    final challenge = (await tester.runAsync(
      () => auth.requestOtp(phone: '+46700000000'),
    ))!;
    await tester.pumpWidget(
      _screen(PhoneVerification(challenge: challenge, controller: auth)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(
        of: _key('auth-code'),
        matching: find.byType(EditableText),
      ),
      findsOneWidget,
    );
    expect(_key('auth-verify'), findsOneWidget);
  });

  testWidgets('Home: home-where-to, home-schedule-later, home-menu', (
    tester,
  ) async {
    _phone(tester);
    var where = 0, later = 0, menu = 0;
    await tester.pumpWidget(
      _screen(
        Scaffold(
          body: Column(
            children: [
              PremiumTopActions(onMenuTap: () => menu++, onAccountTap: () {}),
              WhereToCard(
                destinationAddress: null,
                onDestinationTap: () => where++,
                onOpenSchedule: () => later++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(_key('home-where-to'));
    await tester.tap(_key('home-schedule-later'));
    await tester.tap(_key('home-menu'));
    expect((where, later, menu), (1, 1, 1));
  });

  testWidgets('menu: menu-ride-history opens Ride History', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_screen(const RiderMenuPage()));
    await _frames(tester);
    final tile = _key('menu-ride-history');
    expect(tile, findsOneWidget);
    expect(
      find.descendant(of: tile, matching: find.text('Ride History')),
      findsOneWidget,
    );
  });

  testWidgets('route picker: route-picker-field-destination and the server '
      'suggestion rows route-picker-row-<i>', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _screen(
        Scaffold(
          body: RoutePickerPage(
            pickupAddress: 'Sveavägen 1, Stockholm',
            destinationAddress: '',
            stops: const [],
            stopsSupported: true,
            initialField: 'destination',
            capture: EarlyInputCapture(),
            here: const GeoPoint(59.33, 18.06),
            homeAddress: null,
            workAddress: null,
            recent: const [],
            onSetFavourite: (_) async => null,
            onPickOnMap: ({required pickup, required address}) async => null,
            onFinish: (_) async => null,
          ),
        ),
      ),
    );
    await tester.pump();
    final field = _key('route-picker-field-destination');
    expect(field, findsOneWidget);
    expect(_key('route-picker-field-pickup'), findsOneWidget);
    await tester.enterText(field, 'Drott');
    await tester.pump(RoutePickerPage.suggestDebounce);
    for (var i = 0; i < 30 && !tester.any(_key('route-picker-row-0')); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_key('route-picker-row-0'), findsOneWidget);
    expect(tester.widget(_key('route-picker-row-0')), isA<InkWell>());
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('choose ride: select-ride-tile-<category>, select-ride-payment, '
      'select-ride-book, select-ride-book-later', (tester) async {
    _phone(tester);
    final selection = RideSelectionController(quotes: _Quotes());
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      _screen(
        SelectRide(
          pickupAddress: 'Sergels torg',
          destinationAddress: 'Odenplan',
          pickupPosition: const LatLng(59.3326, 18.0649),
          destinationPosition: const LatLng(59.3429, 18.0496),
          pickupAlreadyConfirmed: true,
          selection: selection,
          nearbyCars: _NoCars(),
        ),
      ),
    );
    await _frames(tester, 12);
    final tiles = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('select-ride-tile-'),
    );
    expect(tiles, findsWidgets);
    final selected = selection.selectedRideId;
    expect(selected, isNotNull);
    expect(_key('select-ride-tile-$selected'), findsOneWidget);
    expect(_key('select-ride-payment'), findsOneWidget);
    expect(_key('select-ride-book'), findsOneWidget);
    expect(_key('select-ride-book-later'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('driver card: waiting-chat, waiting-chat-unread, waiting-call; '
      'chat: chat-field, chat-send', (tester) async {
    _phone(tester);
    addTearDown(MessagesRepository.clearAllSessions);
    var calls = 0;
    await tester.pumpWidget(
      _screen(
        Scaffold(
          body: WaitingDriverCard(
            driver: const MatchedDriver(id: 'd1', firstName: 'Erik'),
            rideId: 'trp_keys',
            onOpenProfile: () {},
            onCall: () => calls++,
            onMore: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_key('waiting-chat'), findsOneWidget);
    expect(_key('waiting-chat-unread'), findsNothing);
    await tester.tap(_key('waiting-call'));
    expect(calls, 1);
    await tester.tap(_key('waiting-chat'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: _key('chat-field'),
        matching: find.byType(EditableText),
      ),
      findsOneWidget,
    );
    expect(_key('chat-send'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    MessagesController.ingestStreamMessage('trp_keys', {
      'messageId': 'msg_keys',
      'tripId': 'trp_keys',
      'from': 'driver',
      'text': 'I am outside',
      'at': '2026-10-26T08:35:00Z',
    });
    await _frames(tester, 4);
    expect(_key('waiting-chat-unread'), findsOneWidget);
  });

  testWidgets('safety: trip-safety-button (map) and trip-safety-row (sheet)', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _screen(
        const Scaffold(
          body: Column(
            children: [
              SafetyKitMapButton(rideId: 'trp_keys'),
              SafetyKitSheetRow(rideId: 'trp_keys'),
            ],
          ),
        ),
      ),
    );
    expect(_key('trip-safety-button'), findsOneWidget);
    expect(_key('trip-safety-row'), findsOneWidget);
  });

  testWidgets('rating: rating-star-1 .. rating-star-5', (tester) async {
    _phone(tester);
    final ratings = <double>[];
    await tester.pumpWidget(
      MoveraScreenUtilInit(
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: RideCompletedGiveReview(onRatingChanged: ratings.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var n = 1; n <= 5; n++) {
      expect(_key('rating-star-$n'), findsOneWidget);
    }
    await tester.tap(_key('rating-star-5'));
    await tester.pump();
    expect(ratings.last, 5);
  });

  testWidgets('history: history-ride-<id> on a completed ride', (tester) async {
    _phone(tester);
    final reservations = _reservations();
    await reservations.create(_draft);
    await reservations.update(
      'rsv_keys',
      const ReservationPatch(status: ReservationStatus.completed),
    );
    await tester.pumpWidget(
      MaterialApp(home: RideHistory(reservations: reservations)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(_key('history-ride-rsv_keys'), findsOneWidget);
  });

  testWidgets('booked ride: home-reservation-<id>, '
      'reservation-scheduled-done, reservation-cancel, '
      'reservation-cancel-confirm, cancel-reason-<id>, cancel-reason-submit', (
    tester,
  ) async {
    _phone(tester);
    final reservations = _reservations();
    await reservations.create(_draft);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeReservationChrono(
            controller: reservations,
            now: () => DateTime(2026, 9, 22, 12),
          ),
        ),
      ),
    );
    expect(_key('home-reservation-rsv_keys'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: RideScheduledPage(
          reservationId: 'rsv_keys',
          controller: reservations,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_key('reservation-scheduled-done'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: UpcomingReservationPage(
          reservationId: 'rsv_keys',
          controller: reservations,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cancel = _key('reservation-cancel');
    await tester.scrollUntilVisible(cancel, 300);
    expect(tester.widget(cancel), isA<TextButton>());
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(_key('reservation-cancel-confirm'), findsOneWidget);
    await tester.tap(_key('reservation-cancel-confirm'));
    await tester.pumpAndSettle();
    final reasons = CancellationReason.forPhase(CancelPhase.reservation);
    expect(_key('cancel-reason-${reasons.first.id}'), findsOneWidget);
    expect(_key('cancel-reason-submit'), findsOneWidget);
  });

  testWidgets('cancel reasons: every reason row and the submit are keyed', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CancelReasonSheet(phase: CancelPhase.matched)),
      ),
    );
    for (final reason in CancellationReason.forPhase(CancelPhase.matched)) {
      expect(_key('cancel-reason-${reason.id}'), findsOneWidget);
    }
    expect(_key('cancel-reason-submit'), findsOneWidget);
  });

  testWidgets('arrived sheet: driver-arrived-on-way', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _screen(const Scaffold(body: DriverArrivedSheet(pin: '9031'))),
    );
    await tester.pumpAndSettle();
    expect(tester.widget(_key('driver-arrived-on-way')), isA<FilledButton>());
  });
}
