import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/core/maps/web_road_route.dart';

/// uat-r1: the web demo's in-process transport answers /api/v1/routes with
/// the two end points only, so every booking map drew a straight line
/// (owner's iPhone report). On the web demo the road geometry comes from a
/// public router instead, retried once and shared between screens; it is
/// never asked outside the demo.
void main() {
  const env = AppEnv(flavor: AppFlavor.test, apiBaseUrl: 'https://t.invalid');
  const from = GeoPoint(59.1955, 17.6165);
  const to = GeoPoint(59.2000, 17.6300);
  const road = [
    GeoPoint(59.1955, 17.6165),
    GeoPoint(59.1970, 17.6200),
    GeoPoint(59.1990, 17.6260),
    GeoPoint(59.2000, 17.6300),
  ];

  List<String> ll(List<GeoPoint>? points) => [
    for (final p in points ?? const <GeoPoint>[])
      '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}',
  ];

  RoutingService demoRouting(PublicRoadRouter router) => RoutingService(
    api: ApiClient(client: InProcessMockClient(), env: env),
    allowPublicRoadFallback: true,
    isWeb: true,
    publicRoad: router,
  );

  test('web demo: the two-point demo answer is completed by the public road '
      'router', () async {
    var calls = 0;
    final routing = demoRouting((a, b, {timeout = Duration.zero}) async {
      calls += 1;
      return road;
    });
    expect(await routing.roadLine(from: from, to: to), road);
    expect(calls, 1);
    // The road line is kept: the next screen draws it without asking again.
    expect(await routing.roadLine(from: from, to: to), road);
    expect(calls, 1);
  });

  test('a slow or failed public answer is retried once, never a straight '
      'line for one bad attempt', () async {
    var calls = 0;
    final routing = demoRouting((a, b, {timeout = Duration.zero}) async {
      calls += 1;
      if (calls == 1) throw TimeoutException('slow mobile network');
      return road;
    });
    expect(await routing.roadLine(from: from, to: to), road);
    expect(calls, 2);
  });

  test('two screens asking for the same leg share one public request',
      () async {
    var calls = 0;
    final gate = Completer<void>();
    final routing = demoRouting((a, b, {timeout = Duration.zero}) async {
      calls += 1;
      await gate.future;
      return road;
    });
    final selectRide = routing.roadLine(from: from, to: to);
    final finding = routing.roadLine(from: from, to: to);
    gate.complete();
    expect(await selectRide, road);
    expect(await finding, road);
    expect(calls, 1);
  });

  test('when the public router has nothing the direct line is drawn and '
      'the next request asks again', () async {
    var calls = 0;
    final routing = demoRouting((a, b, {timeout = Duration.zero}) async {
      calls += 1;
      return null;
    });
    expect(ll(await routing.roadLine(from: from, to: to)), ll([from, to]));
    expect(calls, 2);
    expect(ll(await routing.roadLine(from: from, to: to)), ll([from, to]));
    expect(calls, 4);
  });

  test('outside the demo (and off the web) the public router is never asked',
      () async {
    var calls = 0;
    Future<List<GeoPoint>?> router(
      GeoPoint a,
      GeoPoint b, {
      Duration timeout = Duration.zero,
    }) async {
      calls += 1;
      return road;
    }
    final production = RoutingService(
      api: ApiClient(client: InProcessMockClient(), env: env),
      isWeb: true,
      publicRoad: router,
    );
    expect(ll(await production.roadLine(from: from, to: to)), ll([from, to]));
    final native = RoutingService(
      api: ApiClient(client: InProcessMockClient(), env: env),
      allowPublicRoadFallback: true,
      isWeb: false,
      publicRoad: router,
    );
    expect(ll(await native.roadLine(from: from, to: to)), ll([from, to]));
    expect(calls, 0);
  });

  test('OSRM geojson is read as lat/lng points; bad answers are null',
      () async {
    Uri? asked;
    final client = MockClient((request) async {
      asked = request.url;
      return http.Response(
        jsonEncode({
          'code': 'Ok',
          'routes': [
            {
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [17.6165, 59.1955],
                  [17.6200, 59.1970],
                  [17.6300, 59.2000],
                ],
              },
            },
          ],
        }),
        200,
      );
    });
    final points = await openSourceRoutingMachineRoute(
      from,
      to,
      client: client,
    );
    expect(ll(points), ll(const [
      GeoPoint(59.1955, 17.6165),
      GeoPoint(59.1970, 17.6200),
      GeoPoint(59.2000, 17.6300),
    ]));
    expect(asked?.scheme, 'https');
    expect(asked?.host, 'router.project-osrm.org');
    expect(asked?.path, '/route/v1/driving/17.616500,59.195500;17.630000,59.200000');
    expect(asked?.queryParameters['geometries'], 'geojson');
    expect(asked?.queryParameters['overview'], 'full');

    final noRoute = MockClient(
      (_) async => http.Response(jsonEncode({'code': 'NoRoute'}), 200),
    );
    expect(
      await openSourceRoutingMachineRoute(from, to, client: noRoute),
      isNull,
    );
    final down = MockClient((_) async => http.Response('', 503));
    expect(
      await openSourceRoutingMachineRoute(from, to, client: down),
      isNull,
    );
  });
}
