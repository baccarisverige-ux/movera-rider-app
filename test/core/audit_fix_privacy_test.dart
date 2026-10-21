import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/observability/http_observability.dart';
import 'package:movera_rider/core/observability/observability.dart';
import 'package:movera_rider/l10n/l10n.dart';

class _Tokens implements TokenStore {
  @override
  Future<String?> readAccess() async => 'token';
  @override
  Future<String?> readRefresh() async => null;
  @override
  Future<void> save({required String access, required String refresh}) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AUD-1 public reverse geocoding is demo-only', () {
    ApiClient placeholderApi() => ApiClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {'address': AppGeocoding.placeholderReverseLabel},
          }),
          200,
        ),
      ),
      env: const AppEnv(
        flavor: AppFlavor.production,
        apiBaseUrl: 'https://api.movera.example',
      ),
      tokens: _Tokens(),
    );

    test('without the demo flag the browser never calls Nominatim', () async {
      var publicCalls = 0;
      final geocoding = AppGeocoding(
        api: placeholderApi(),
        isWeb: true,
        publicReverse: (point, {timeout = Duration.zero}) async {
          publicCalls += 1;
          return 'Sveavägen 1';
        },
      );
      final address = await geocoding.reverse(const GeoPoint(59.33, 18.06));
      expect(publicCalls, 0);
      expect(address, AppGeocoding.placeholderReverseLabel);
    });

    test('the demo flag keeps the street-name fallback on the web', () async {
      var publicCalls = 0;
      final geocoding = AppGeocoding(
        api: placeholderApi(),
        isWeb: true,
        allowPublicReverseFallback: true,
        publicReverse: (point, {timeout = Duration.zero}) async {
          publicCalls += 1;
          return 'Sveavägen 1';
        },
      );
      expect(
        await geocoding.reverse(const GeoPoint(59.33, 18.06)),
        'Sveavägen 1',
      );
      expect(publicCalls, 1);
    });

    // rider-r4-43: a failed Nominatim lookup (e.g. rate-limited) cached the
    // 'Current location' placeholder for 10 minutes; it is retried now.
    test('a failed street lookup is not cached', () async {
      final answers = <String?>[null, 'Sveavägen 1'];
      final geocoding = AppGeocoding(
        api: placeholderApi(),
        isWeb: true,
        allowPublicReverseFallback: true,
        publicReverse: (point, {timeout = Duration.zero}) async =>
            answers.removeAt(0),
      );
      const point = GeoPoint(59.33, 18.06);
      expect(
        await geocoding.reverse(point),
        AppGeocoding.placeholderReverseLabel,
      );
      expect(await geocoding.reverse(point), 'Sveavägen 1');
    });

    // rider-r4-44: the cache key ignored the app language.
    test('a language switch looks the street up again', () async {
      var publicCalls = 0;
      final geocoding = AppGeocoding(
        api: placeholderApi(),
        isWeb: true,
        allowPublicReverseFallback: true,
        publicReverse: (point, {timeout = Duration.zero}) async =>
            'Rue ${++publicCalls}',
      );
      addTearDown(() => L10n.use('en'));
      const point = GeoPoint(48.86, 2.35);
      L10n.use('en');
      await geocoding.reverse(point);
      L10n.use('fr');
      expect(await geocoding.reverse(point), 'Rue 2');
    });

    test('the app enables it only for mock-transport flavours', () {
      expect(AppGeocoding().allowPublicReverseFallback, isFalse);
      expect(
        AppScope.instance.geocoding.allowPublicReverseFallback,
        AppScope.instance.environment.allowsMockTransport,
      );
    });
  });

  group('CODE-18 telemetry scrubbing', () {
    test(
      'keys match case-insensitively, by word and substring, recursively',
      () {
        final safe = Observability.sanitize({
          'riderPhone': '+46701234567',
          'Email': 'a@b.se',
          'pickupAddress': 'Sveavägen 1',
          'pickup_lat': 59.3,
          'lng': 18.0,
          'holderName': 'Ada',
          'refresh_token': 'x',
          'cardNumber': '4242',
          'rideId': 'r1',
          'status': 'ok',
          'platform': 'ios',
          'nested': {
            'email': 'c@d.se',
            'Latitude': 59.3,
            'reason': 'timeout',
            'list': [
              {'phoneE164': '+46700000000', 'code': 'E1'},
            ],
          },
        });
        expect(
          safe.keys,
          unorderedEquals(['rideId', 'status', 'platform', 'nested']),
        );
        final nested = safe['nested']! as Map<String, Object?>;
        expect(nested.keys, unorderedEquals(['reason', 'list']));
        expect((nested['list']! as List).single, {'code': 'E1'});
      },
    );

    test('free text loses e-mails, phone numbers and coordinates', () {
      final text = Observability.scrubText(
        'Auth failed for anna@example.se at +46 70 123 45 67 / 070-123 45 67 '
        'near 59.334512, 18.063240 (status 401 at 2026-01-05 10:30, ride r_12)',
      );
      expect(text, isNot(contains('anna@example.se')));
      expect(text, isNot(contains('123 45 67')));
      expect(text, isNot(contains('59.334512')));
      expect(text, isNot(contains('18.063240')));
      expect(text, contains('status 401'));
      expect(text, contains('2026-01-05 10:30'));
      expect(text, contains('ride r_12'));
    });

    test('string values that are kept are scrubbed too', () {
      final safe = Observability.sanitize({'error': 'no rider for bo@x.se'});
      expect(safe['error'], 'no rider for [email]');
    });

    test(
      'error text and stack traces are scrubbed before they are sent',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final sink = HttpObservabilitySink(
          baseUrl: 'https://api.movera.example',
          client: MockClient((request) async {
            bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response('{}', 200);
          }),
        );
        sink.log(
          TelemetryLevel.error,
          'auth.failed',
          error: StateError('OTP for +46701234567 rejected'),
        );
        sink.record(
          StateError('ride at 59.334512,18.063240 for x@y.se'),
          StackTrace.fromString('#0 main (pickup 59.334512)'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final sent = jsonEncode(bodies);
        expect(sent, isNot(contains('+46701234567')));
        expect(sent, isNot(contains('59.334512')));
        expect(sent, isNot(contains('x@y.se')));
        sink.dispose();
      },
    );
  });
}
