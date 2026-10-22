import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/maps/map_camera_motion.dart';
import 'package:movera_rider/core/web/rider_map_bridge.dart';

/// Wave 5 R5.4 parts a + b: state and time (low). One test per bug.
const _env = AppEnv(flavor: AppFlavor.staging, apiBaseUrl: 'https://x.invalid');

/// Books a ride on the in-process stand-in server and returns its id.
Future<String> _book(ApiClient api) async {
  const at = {
    'pickupLat': 59.3293,
    'pickupLng': 18.0686,
    'destinationLat': 59.3326,
    'destinationLng': 18.0649,
  };
  final quote = (await api.post(
    '/api/v1/quotes',
    body: {'rideType': 'economy', ...at},
  ))['quote'] as Map;
  final created = await api.post(
    '/api/v1/rides',
    body: {
      'categoryId': 'economy',
      'fare': {'amountMinor': quote['totalMinor'], 'currency': 'SEK'},
      'paymentMethodId': 'card',
      'pickupAddress': 'Pickup',
      'destinationAddress': 'Destination',
      ...at,
      'quoteId': quote['id'],
      'quoteSignedPayload': quote['signedPayload'],
      'quoteExpiresAt': quote['expiresAt'],
      'quoteTotalMinor': quote['totalMinor'],
    },
  );
  return (created['ride'] as Map)['id'] as String;
}

/// A map controller that only records camera moves.
class _FakeMap extends Fake implements GoogleMapController {
  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rider-6: a wrong OTP with an old token left is a wrong code, not an '
      'expired session', () async {
    final tokens = MemoryTokenStore();
    await tokens.save(access: 'old-access', refresh: 'mock-refresh-1');
    var expired = 0;
    var refreshes = 0;
    final api = ApiClient(
      env: _env,
      tokens: tokens,
      onSessionExpired: () async => expired++,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshes++;
          return http.Response(
            jsonEncode({'accessToken': 'new', 'refreshToken': 'r2'}),
            200,
          );
        }
        return http.Response(jsonEncode({'code': 'invalid_otp'}), 401);
      }),
    );
    await expectLater(
      api.post('/api/v1/auth/otp/verify', body: {'code': '000000'}),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'invalid_otp')),
    );
    expect(expired, 0);
    expect(refreshes, 0);
    expect(await tokens.readAccess(), 'old-access');
  });

  test('rider-8: an offer raise while searching is a committed change',
      () async {
    final server = InProcessMockClient();
    final api = ApiClient(client: server);
    final id = await _book(api);
    final before = Map<String, dynamic>.of(server.rides[id]!);
    await api.patch('/api/v1/rides/$id', body: {
      'offerIncrease': {'amountMinor': 5000, 'currency': 'SEK'},
    });
    final after = server.rides[id]!;
    expect(after['fare'], isNot(before['fare']));
    expect(after['version'], (before['version'] as int) + 1);
    expect(after['eventId'], isNot(before['eventId']));
  });

  test('rider-j8-13: a web flight stopped by a tap leaves the pose where the '
      'camera stopped', () async {
    const start = CameraPosition(target: LatLng(59.30, 18.00), zoom: 13);
    const goal = CameraPosition(target: LatLng(59.40, 18.10), zoom: 15);
    const midway = CameraPosition(target: LatLng(59.35, 18.05), zoom: 14);
    RiderMapBridge.debugFlight = (_, _, _) => Completer<bool>().future;
    RiderMapBridge.debugCancelFlight = (_) => midway;
    addTearDown(() {
      RiderMapBridge.debugFlight = null;
      RiderMapBridge.debugCancelFlight = null;
    });
    final map = _FakeMap();
    final view = mapViewOf(map)
      ..mapId = 1
      ..pose = start;
    unawaited(easeCameraTo(map, goal, duration: cameraFlightDuration));
    expect(view.easing, isTrue);
    view.touching = true; // the tap stops the flight
    expect(view.pose, midway);
  });
}
