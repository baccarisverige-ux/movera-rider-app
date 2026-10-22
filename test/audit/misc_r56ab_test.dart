import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/location/location_point.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/map_camera_motion.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/core/notifications/push_permission_gate.dart';
import 'package:movera_rider/core/notifications/push_service.dart';
import 'package:movera_rider/core/web/rider_map_bridge.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_sheet.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/presentation/auth_navigation.dart';
import 'package:movera_rider/features/destination_search/domain/place_suggestion.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart';
import 'package:shared_preferences/shared_preferences.dart';
/// A [Random] that always answers [value].
class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final int value;
  @override
  int nextInt(int max) => value % max;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

/// Takes camera moves instead of driving a platform map.
class _FakeMap extends Fake implements GoogleMapController {
  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate) => Future<void>.value();
}

/// Pumps [child] alone on a phone-sized screen.
Future<void> _pumpPage(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pump();
}

/// Push registration that hangs (a poor connection) once [slow] is set,
/// until [answer].
class _SlowPush extends Fake implements PushService {
  bool slow = false;
  final answer = Completer<void>();
  @override
  Future<void> register() => slow ? answer.future : Future<void>.value();
}

/// R5.6 parts a and b: small local fixes, one short test per bug.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('rider-u13: chained pickup moves after accept are measured from '
      'the accepted pickup', () async {
    // Driver on the way; each move is about 300 m north of the last one.
    final mock = InProcessMockClient();
    mock.rides['ride-chain'] = {
      'id': 'ride-chain',
      'status': 'driverArriving',
      'pickupAddress': 'Start',
      'pickupLat': 59.3326,
      'pickupLng': 18.0649,
      'destinationAddress': 'Odenplan 2',
      'destinationLat': 59.3426,
      'destinationLng': 18.0498,
      'price': 200.0,
      'bookedPrice': 200.0,
      'bookedKm': 1.4,
      'stops': <Map<String, dynamic>>[],
      'version': 3,
    };
    final api = ApiClient(client: mock);
    Future<void> moveTo(String name, double lat) => api.patch(
      '/api/v1/rides/ride-chain',
      body: {
        'routeChange': true,
        'pickupAddress': name,
        'pickupLat': lat,
        'pickupLng': 18.0649,
        'destinationAddress': 'Odenplan 2',
        'destinationLat': 59.3426,
        'destinationLng': 18.0498,
        'stops': const <Object>[],
      },
    );
    await moveTo('First', 59.3353);
    await expectLater(
      moveTo('Second', 59.3380),
      throwsA(
        isA<ApiError>().having((e) => e.detail, 'detail', 'pickup_too_far'),
      ),
    );
    expect(mock.rides['ride-chain']!['pickupAddress'], 'First');
  });

  test('rider-u16: the demo safety PIN comes from a random source, not '
      'the clock', () {
    final before = SafetyMockApi.pinRandom;
    addTearDown(() => SafetyMockApi.pinRandom = before);
    SafetyMockApi.pinRandom = _FixedRandom(4321);
    expect((SafetyMockApi()..reset()).pin['pin'], '4321');
  });

  testWidgets('rider-j8-15: a recenter during a follow glide flies on the '
      'web frame clock', (tester) async {
    final flights = <CameraPosition>[];
    RiderMapBridge.debugFlight = (_, to, _) {
      flights.add(to);
      return Future.value(true);
    };
    addTearDown(() => RiderMapBridge.debugFlight = null);
    final fake = _FakeMap();
    mapViewOf(fake)
      ..mapId = 1
      ..pose = const CameraPosition(target: LatLng(59.33, 18.06), zoom: 13);
    unawaited(
      easeCameraTo(
        fake,
        const CameraPosition(target: LatLng(59.331, 18.06), zoom: 13),
      ),
    );
    await tester.pump(cameraEaseFrame);
    const recenter = CameraPosition(target: LatLng(59.34, 18.07), zoom: 15);
    unawaited(easeCameraTo(fake, recenter, duration: cameraFlightDuration));
    await tester.pump(cameraEaseFrame);
    expect(flights, [recenter]);
    mapViewOf(fake).interrupt();
    await tester.pump(cameraEaseFrame);
  });

  test('rider-u20: the road-route cache stays bounded on a long ride', () async {
    final routing = RoutingService(api: ApiClient(client: InProcessMockClient()));
    const pickup = GeoPoint(59.3326, 18.0649);
    // A driver moving: every 10 s refresh has a new origin.
    for (var i = 0; i < roadCacheLimit + 20; i++) {
      await routing.roadLine(from: GeoPoint(59.30 + i * 0.0001, 18.06), to: pickup);
    }
    expect(roadCacheLengthOf(routing), roadCacheLimit);
  });

  test('rider-20: the home puck glides to a new fix over the window', () {
    final engine = MotionEngine();
    final t0 = DateTime(2026, 10, 22, 12);
    LocationPoint fix(double lat, DateTime at) => LocationPoint(
      point: GeoPoint(lat, 18.06),
      timestamp: at,
      accuracyMeters: 5,
    );
    engine.ingest(fix(59.3300, t0), now: t0);
    // The next fix arrives a second later (1 Hz GPS).
    final t1 = t0.add(const Duration(seconds: 1));
    final start = engine.ingest(fix(59.3310, t1), now: t1)!;
    final half = engine.poseAt(t1.add(MotionEngine.window ~/ 2))!;
    final end = engine.poseAt(t1.add(MotionEngine.window))!;
    expect(start.position.latitude, closeTo(59.3300, 1e-9));
    expect(half.position.latitude, closeTo(59.3305, 1e-9));
    expect(end.position.latitude, closeTo(59.3310, 1e-9));
    expect(end.progress, 1);
  });

  testWidgets('rider-u43: a 0.40 EUR route change is not "Same price" and '
      'asks for the card step', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _pumpPage(
      tester,
      const RouteChangeSheet(
        quote: RouteChangeQuote(
          pickupAddress: 'Rue de Rivoli 1',
          pickupPoint: GeoPoint(48.86, 2.34),
          destinationAddress: 'Gare du Nord',
          destinationPoint: GeoPoint(48.88, 2.355),
          stops: [],
          oldPriceKr: 18.20,
          newPriceKr: 18.60,
          currency: 'EUR',
        ),
        paymentMethod: 'Visa •••• 4242',
      ),
    );
    expect(find.text('Same price as before.'), findsNothing);
    expect(find.text('Confirm · next: payment'), findsOneWidget);
  });

  testWidgets('rider-u61: on the web the car comes turned to its heading', (
    tester,
  ) async {
    final car = BitmapDescriptor.defaultMarker;
    // Phones: the map turns the bitmap.
    expect(MoveraVehicleMarker.look(car, 90, web: false).rotation, 90);
    // Web ignores Marker.rotation: a turned bitmap is built, then used.
    await tester.runAsync(() {
      final ready = Completer<void>();
      final first = MoveraVehicleMarker.look(
        car,
        90,
        web: true,
        onReady: ready.complete,
      );
      expect(first.rotation, 0);
      expect(first.icon, same(car), reason: 'upright until built');
      return ready.future.timeout(const Duration(seconds: 10));
    });
    final turned = MoveraVehicleMarker.look(car, 92, web: true);
    expect(turned.rotation, 0);
    expect(turned.icon, isNot(same(car)));
  });

  test('rider-u67: sign-in does not wait for push registration', () async {
    final push = _SlowPush();
    final gate = PushPermissionGate(push: push, enabled: true);
    // The rider allowed notifications on an earlier sign-in.
    await gate.accept();
    push.slow = true;
    final tokens = MemoryTokenStore();
    final auth = AuthController(
      auth: AuthRepository(
        api: ApiClient(
          env: const AppEnv(
            flavor: AppFlavor.test,
            apiBaseUrl: 'https://api.test.movera.invalid',
          ),
          client: InProcessMockClient(),
          tokens: tokens,
        ),
        tokens: tokens,
      ),
      pushPermission: gate,
    );
    final challenge = await auth.requestOtp(phone: '+46701234567');
    await auth
        .verifyOtp(challenge: challenge, code: '1234')
        .timeout(const Duration(seconds: 5));
    push.answer.complete();
  });

  test('rider-r3-11: sign-in takes only a Swedish mobile number', () {
    expect(swedishNumberFromField('70 123 45 67'), '+46701234567');
    expect(swedishNumberFromField('70 123 45 6'), isNull, reason: 'a digit short');
    expect(swedishNumberFromField('08 123 456 78'), isNull, reason: 'a landline');
  });

  test('rider-u84: the highlight range is in the title\'s own offsets', () {
    // On the web 'İ' lower-cases to two code units ('i' + a combining dot).
    String webLower(String value) =>
        foldForSearch(value.replaceAll('İ', 'i\u0307'));
    const title = 'İzmir Kebab';
    final (start, end) = matchRange(title, 'kebab', fold: webLower)!;
    expect(title.substring(start, end), 'Kebab');
    expect(matchRange('Klockarvägen 3', 'klockarvag'), (0, 10));
  });

  testWidgets('rider-u86: Where to? asks for suggestions once typing '
      'pauses', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _pumpPage(
      tester,
      RoutePickerPage(
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
    );
    final search = AppScope.instance.destinationSearch;
    final before = search.suggestRequests;
    final field = tester.widget<TextField>(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Where to?',
      ),
    );
    for (final typed in ['D', 'Dr', 'Dro', 'Drot', 'Drott']) {
      field.controller!.text = typed;
      field.onChanged!(typed);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(RoutePickerPage.suggestDebounce);
    expect(search.suggestRequests - before, 1);
    await tester.pumpWidget(const SizedBox());
  });

  test('rider-u113: Upcoming lists the next pickup first', () async {
    var ids = 0;
    final reservations = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_${ids++}',
      ),
    );
    final today = DateTime.now();
    ReservationDraft at(DateTime when) => ReservationDraft(
      scheduledPickupAt: when,
      pickup: const ReservationPlace(label: 'Klockarvägen 37'),
      destination: const ReservationPlace(label: 'T-Centralen'),
      categoryId: 'comfort',
      categoryName: 'Comfort',
      categoryImage: 'assets/images/rides/comfort.webp',
      price: 339,
      paymentMethod: 'Cash',
    );
    // Booked first: the later pickup.
    await reservations.create(at(today.add(const Duration(days: 3))));
    await reservations.create(at(today.add(const Duration(days: 2))));
    final upcoming = reservations.upcoming();
    expect(upcoming, hasLength(2));
    expect(
      upcoming.first.scheduledPickupAt.isBefore(upcoming.last.scheduledPickupAt),
      isTrue,
    );
  });
}
