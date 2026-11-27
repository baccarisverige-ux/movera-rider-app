import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    show GoogleMapsFlutterPlatform;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/quoted_route.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/trip_route_line.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_projection.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/fake_maps_platform.dart';

/// v0.18.169 (contract.json#riderTripRouteLine, owner 2026-11-27 "App
/// rider blocked here", "Oui, corriger": the reopened map drew a straight
/// line): the rider's trip view carries the trip's stored Google line
/// (`TripProjection.routePolyline`). Finding driver draws it first, then
/// the Quote line it kept, then the road request; the line is kept with
/// the saved ride, so a reopen draws it at once; sign-out forgets it with
/// the quote lines and batches. Movera colours only (#12201C, #2FBF5B).
const _pickup = LatLng(59.3326, 18.0649);
const _dropoff = LatLng(59.3143, 18.0735);
const _staging = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://api.example.test',
);
const _demo = AppEnv(
  flavor: AppFlavor.demo,
  apiBaseUrl: 'https://api.demo.movera.invalid',
);

/// The trip view's line: pickup, Slussen, drop-off.
const _tripPoints = <LatLng>[_pickup, LatLng(59.3197, 18.0724), _dropoff];

/// The quote's kept line: another shape of the same trip.
const _quotePoints = <LatLng>[_pickup, LatLng(59.3270, 18.0605), _dropoff];

String encode(List<LatLng> points) {
  final out = StringBuffer();
  var lat = 0;
  var lng = 0;
  void value(int v) {
    var x = v < 0 ? ~(v << 1) : v << 1;
    while (x >= 0x20) {
      out.writeCharCode((0x20 | (x & 0x1f)) + 63);
      x >>= 5;
    }
    out.writeCharCode(x + 63);
  }

  for (final p in points) {
    final la = (p.latitude * 1e5).round();
    final ln = (p.longitude * 1e5).round();
    value(la - lat);
    value(ln - lng);
    lat = la;
    lng = ln;
  }
  return out.toString();
}

final _tripLine = encode(_tripPoints);
final _quoteLine = encode(_quotePoints);

/// A routing seam that counts its calls and answers a straight line.
class _CountingRoutes extends RoutingService {
  int calls = 0;
  @override
  List<GeoPoint> line({required GeoPoint from, required GeoPoint to}) {
    calls++;
    return [from, to];
  }
}

Map<String, dynamic> _trip({String status = 'searching', String? line}) => {
  'tripId': 'trp_rtl169',
  'status': status,
  'version': 3,
  'updatedAt': '2026-11-27T09:00:00.000Z',
  'categoryId': 'economy',
  'paymentMethodId': 'cash',
  'fare': {'amountMinor': 21700, 'currency': 'SEK'},
  'pickup': {
    'address': 'Sergels torg',
    'lat': _pickup.latitude,
    'lng': _pickup.longitude,
  },
  'dropoff': {
    'address': 'Medborgarplatsen',
    'lat': _dropoff.latitude,
    'lng': _dropoff.longitude,
  },
  'routePolyline': ?line,
};

Map<String, dynamic> _quote(String id, {String? line}) => {
  'quoteId': id,
  'categoryId': 'economy',
  'total': {'amountMinor': 21700, 'currency': 'SEK'},
  'fareLines': <Object>[],
  'expiresAt': '2099-01-01T00:00:00Z',
  'pickup': {'lat': _pickup.latitude, 'lng': _pickup.longitude},
  'dropoff': {'lat': _dropoff.latitude, 'lng': _dropoff.longitude},
  'stops': <Object>[],
  'routeSource': line == null ? 'estimate' : 'google',
  'routePolyline': ?line,
};

String _quoteAnswer(String id, {String? line}) => jsonEncode({
  'quotes': [_quote(id, line: line)],
  'zoneId': 'Z001',
  'serverTime': '2026-11-27T08:00:00Z',
});

Future<void> _ask(ApiQuoteRepository repository) => repository.quote(
  rideType: 'economy',
  distanceMeters: 3000,
  pickupPoint: GeoPoint(_pickup.latitude, _pickup.longitude),
  destinationPoint: GeoPoint(_dropoff.latitude, _dropoff.longitude),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GoogleMapsFlutterPlatform previousPlatform;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    QuotedRoutes.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.idle);
    previousPlatform = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = FakeMapsPlatform();
    CustomGoogleMap.debugWaitForMaps = false;
  });

  tearDown(() {
    GoogleMapsFlutterPlatform.instance = previousPlatform;
    CustomGoogleMap.debugWaitForMaps = null;
    RoutingService.defaultProvider = null;
  });

  group('the trip view', () {
    test('carries routePolyline into the saved ride; a broken or absent '
        'line is none', () {
      expect(
        RideProjection.toSnapshot(_trip(line: _tripLine))!.routePolyline,
        _tripLine,
      );
      expect(
        RideProjection.toSnapshot(_trip(line: '_p~iF~ps|U_ulL'))!.routePolyline,
        isNull,
      );
      expect(RideProjection.toSnapshot(_trip())!.routePolyline, isNull);
    });

    test('the saved ride keeps the line across a reopen', () async {
      await RideSnapshotStore.save(
        RideProjection.toSnapshot(_trip(line: _tripLine))!,
      );
      expect((await RideSnapshotStore.read())!.routePolyline, _tripLine);
    });

    test('a moved pickup or a new stop drops the line; a status copy keeps '
        'it', () {
      final ride = RideProjection.toSnapshot(_trip(line: _tripLine))!;
      expect(
        ride.copyWith(status: RideStatus.driverAssigned).routePolyline,
        _tripLine,
      );
      expect(ride.copyWith(pickupLat: 59.34).routePolyline, isNull);
      expect(
        ride
            .copyWith(pickupLat: 59.34, routePolyline: _quoteLine)
            .routePolyline,
        _quoteLine,
      );
    });

    test(
      'a cold start from the server trip opens Finding with its line',
      () async {
        final restore = RideRestoreCoordinator(
          resync: (_) async {},
          authRequired: () => false,
          serverActiveTrip: () async {
            final mock = InProcessMockClient()
              ..rides['trp_rtl169'] = _trip(line: _tripLine);
            return ApiActiveTripRepository(
              api: ApiClient(client: mock, env: _demo),
            ).fetchActive();
          },
        );
        final page = await restore.root();
        expect(page, isA<FindingDrivers>());
        expect((page as FindingDrivers).routePolyline, _tripLine);
        expect((await RideSnapshotStore.read())!.routePolyline, _tripLine);
      },
    );
  });

  group('drawing order', () {
    test('the trip view line first, before the kept quote line and the road '
        'request', () async {
      QuotedRoutes.remember([_pickup, _dropoff], _quoteLine);
      final routing = _CountingRoutes();
      final route = await roadTripLine(
        from: _pickup,
        stops: const [],
        to: _dropoff,
        routing: routing,
        tripLine: _tripLine,
      );
      expect(route!.points, _tripPoints);
      expect(route.approximate, isFalse);
      expect(routing.calls, 0);
    });

    test('a trip line that does not decode: the kept quote line, then the '
        'road request', () async {
      QuotedRoutes.remember([_pickup, _dropoff], _quoteLine);
      final routing = _CountingRoutes();
      final quoted = await roadTripLine(
        from: _pickup,
        stops: const [],
        to: _dropoff,
        routing: routing,
        tripLine: 'broken_',
      );
      expect(quoted!.points, _quotePoints);
      QuotedRoutes.clear();
      final road = await roadTripLine(
        from: _pickup,
        stops: const [],
        to: _dropoff,
        routing: routing,
        tripLine: 'broken_',
      );
      expect(road!.points, [_pickup, _dropoff]);
      expect(routing.calls, greaterThan(0));
    });
  });

  group('SHOULD', () {
    test('a quote line that does not decode drops the older kept line', () {
      QuotedRoutes.remember([_pickup, _dropoff], _quoteLine);
      expect(QuotedRoutes.of([_pickup, _dropoff]), _quotePoints);
      QuotedRoutes.remember([_pickup, _dropoff], '_p~iF~ps|U_ulL');
      expect(QuotedRoutes.of([_pickup, _dropoff]), isNull);
      expect(QuotedRoutes.encodedOf([_pickup, _dropoff]), isNull);
    });

    test('a late answer of an older quote does not bring back its stale '
        'line', () async {
      final slow = Completer<void>();
      var asked = 0;
      final api = ApiClient(
        env: _staging,
        client: MockClient((request) async {
          asked++;
          if (asked == 1) {
            await slow.future;
            return http.Response(
              _quoteAnswer('qte_old', line: _quoteLine),
              201,
            );
          }
          return http.Response(_quoteAnswer('qte_new', line: _tripLine), 201);
        }),
      );
      final repository = ApiQuoteRepository(api: api);
      final older = _ask(repository);
      await Future<void>.delayed(Duration.zero);
      repository.forgetAnswers();
      await _ask(repository);
      expect(QuotedRoutes.of([_pickup, _dropoff]), _tripPoints);
      slow.complete();
      await older;
      expect(QuotedRoutes.of([_pickup, _dropoff]), _tripPoints);
    });

    test('a late older Google quote does not come back over a newer '
        'estimate', () async {
      final slow = Completer<void>();
      var asked = 0;
      final api = ApiClient(
        env: _staging,
        client: MockClient((request) async {
          asked++;
          if (asked == 1) {
            await slow.future;
            return http.Response(
              _quoteAnswer('qte_old', line: _quoteLine),
              201,
            );
          }
          return http.Response(_quoteAnswer('qte_new'), 201);
        }),
      );
      final repository = ApiQuoteRepository(api: api);
      final older = _ask(repository);
      await Future<void>.delayed(Duration.zero);
      repository.forgetAnswers();
      await _ask(repository);
      slow.complete();
      await older;
      expect(QuotedRoutes.of([_pickup, _dropoff]), isNull);
    });
  });

  group('sign-out', () {
    test('forgets the quote batches and the priced places', () async {
      var asked = 0;
      final api = ApiClient(
        env: _staging,
        client: MockClient((request) async {
          asked++;
          return http.Response(_quoteAnswer('qte_out', line: _quoteLine), 201);
        }),
      );
      final repository = ApiQuoteRepository(api: api);
      await _ask(repository);
      expect(ApiQuoteRepository.routeOf('qte_out'), isNotNull);
      repository.forgetAll();
      expect(ApiQuoteRepository.routeOf('qte_out'), isNull);
      await _ask(repository);
      expect(asked, 2, reason: 'no batch answers after sign-out');
    });

    test('a quote still on its way at sign-out keeps nothing', () async {
      final slow = Completer<void>();
      final api = ApiClient(
        env: _staging,
        client: MockClient((request) async {
          await slow.future;
          return http.Response(_quoteAnswer('qte_gone', line: _quoteLine), 201);
        }),
      );
      final repository = ApiQuoteRepository(api: api);
      final asked = _ask(repository);
      await Future<void>.delayed(Duration.zero);
      QuotedRoutes.clear();
      repository.forgetAll();
      slow.complete();
      await asked;
      expect(QuotedRoutes.of([_pickup, _dropoff]), isNull);
      expect(ApiQuoteRepository.routeOf('qte_gone'), isNull);
    });
  });

  group('Finding driver map', () {
    Future<GlobalKey<NavigatorState>> pumpFinding(
      WidgetTester tester, {
      String? routePolyline,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      RoutingService.defaultProvider = _CountingRoutes.new;
      final api = ApiClient(client: InProcessMockClient());
      final realtime = MockRideRealtime(
        assignAfter: const Duration(days: 1),
        api: api,
      );
      addTearDown(realtime.dispose);
      final controller = FindingDriverController(realtime: realtime, api: api);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('rtl-home')),
          ),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: AppRoutes.findingDriver),
          builder: (_) => FindingDrivers(
            pickupAddress: 'Sergels torg',
            destinationAddress: 'Medborgarplatsen',
            pickupPosition: _pickup,
            destinationPosition: _dropoff,
            rideType: 'Movera',
            price: 217,
            paymentMethod: 'Cash',
            routePolyline: routePolyline,
            realtime: realtime,
            controller: controller,
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return nav;
    }

    Set<Polyline> routeLines(WidgetTester tester) => {
      for (final element in find.byType(GoogleMap).evaluate())
        for (final line in (element.widget as GoogleMap).polylines)
          if (line.polylineId.value.startsWith('route')) line,
    };

    Future<void> close(
      WidgetTester tester,
      GlobalKey<NavigatorState> nav,
    ) async {
      nav.currentState!.pop();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 10));
    }

    testWidgets('a reopen draws the kept trip view line at once, over the '
        'quote line, in Movera colours only', (tester) async {
      QuotedRoutes.remember([_pickup, _dropoff], _quoteLine);
      final nav = await pumpFinding(tester, routePolyline: _tripLine);
      final lines = routeLines(tester);
      final casing = lines.firstWhere(
        (l) => l.polylineId.value == 'route-casing',
      );
      expect(casing.points, _tripPoints);
      expect(
        find.byKey(const ValueKey('approximate-route-badge')),
        findsNothing,
      );
      expect({
        for (final l in lines) l.color.toARGB32(),
      }, everyElement(anyOf(0xFF12201C, 0xFF2FBF5B)));
      expect(
        FindingDriverController.active?.ownershipSnapshot?.routePolyline,
        _tripLine,
        reason: 'every save keeps it for the next reopen',
      );
      await close(tester, nav);
    });

    testWidgets('no trip view line: the kept quote line, kept with the ride', (
      tester,
    ) async {
      QuotedRoutes.remember([_pickup, _dropoff], _quoteLine);
      final nav = await pumpFinding(tester);
      final casing = routeLines(
        tester,
      ).firstWhere((l) => l.polylineId.value == 'route-casing');
      expect(casing.points, _quotePoints);
      expect(
        FindingDriverController.active?.ownershipSnapshot?.routePolyline,
        _quoteLine,
      );
      await close(tester, nav);
    });
  });
}
