import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/signed_in_loads.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/observability/http_observability.dart';
import 'package:movera_rider/core/observability/observability.dart';
import 'package:movera_rider/features/auth/application/phone_country_default.dart';
import 'package:movera_rider/features/auth/domain/phone_country.dart';
import 'package:movera_rider/features/profile/application/app_language_controller.dart';
import 'package:movera_rider/features/profile/data/app_language_store.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.2, owner decisions of 2026-10-30 for the sign-in screens.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => L10n.use('en'));

  final se = PhoneCountries.sweden;
  final fr = PhoneCountries.france;

  group('auth.startCountry ("France or sweden")', () {
    test('an English (USA) phone starts with Sweden +46, not +1', () {
      // The test binding's locale is en-US, as on the live bug.
      expect(
        TestWidgetsFlutterBinding.instance.platformDispatcher.locale.toString(),
        'en_US',
      );
      expect(initialPhoneCountry(), se);
      expect(initialPhoneCountry().dialLabel, '+46');
      expect(PhoneCountries.defaultFor(localeRegion: 'US'), se);
    });

    test('a French phone starts with France +33', () {
      expect(PhoneCountries.defaultFor(localeRegion: 'FR'), fr);
    });

    test('fix, then zone, then device region, each only Sweden or France', () {
      // Fix in Tunis: skipped, the device's French region is next.
      expect(
        PhoneCountries.defaultFor(
          lastFixLat: 36.8,
          lastFixLng: 10.18,
          localeRegion: 'FR',
        ),
        fr,
      );
      // Last zone Tunisia, a German phone: Sweden.
      expect(
        PhoneCountries.defaultFor(
          lastZone: RiderZones.tunisia,
          localeRegion: 'DE',
        ),
        se,
      );
      // The last zone France wins over an English (USA) phone.
      expect(
        PhoneCountries.defaultFor(
          lastZone: RiderZones.france,
          localeRegion: 'US',
        ),
        fr,
      );
      // A Swedish fix wins over a French phone.
      expect(
        PhoneCountries.defaultFor(
          lastFixLat: 59.33,
          lastFixLng: 18.06,
          localeRegion: 'FR',
        ),
        se,
      );
    });

    test('every other country can still be picked', () {
      expect(PhoneCountries.search('+1', 'en'), isNotEmpty);
      expect(PhoneCountries.byIso('US'), isNotNull);
      expect(PhoneCountries.all.length, greaterThan(100));
    });
  });

  group('auth.firstLanguage ("Phone language (Recommended)")', () {
    const seeds = SeedRiderConfigRepository();

    test('an English phone opens the app in English, not Swedish', () async {
      // The test binding's phone language is English (en-US).
      final language = AppLanguageController(store: MemoryAppLanguageStore());
      await language.load(config: seeds, zone: RiderZones.sweden);
      expect(language.code, 'en');
      expect(L10n.code, 'en');
    });

    test('a French phone in Sweden opens in French', () async {
      final language = AppLanguageController(
        store: MemoryAppLanguageStore(),
        deviceLanguage: () => 'fr',
        deviceRegion: () => 'FR',
      );
      await language.load(config: seeds, zone: RiderZones.sweden);
      expect(language.code, 'fr');
    });

    test('a phone language the app does not ship: the start country decides, '
        'else English', () async {
      for (final (zone, region, expected) in [
        (RiderZones.sweden, 'DE', 'sv'),
        (RiderZones.france, 'DE', 'fr'),
        // Tunisia is no start country: the French region is next.
        (RiderZones.tunisia, 'FR', 'fr'),
        // ... and without a French region, Sweden.
        (RiderZones.tunisia, 'TN', 'sv'),
      ]) {
        final language = AppLanguageController(
          store: MemoryAppLanguageStore(),
          deviceLanguage: () => 'de',
          deviceRegion: () => region,
        );
        await language.load(config: seeds, zone: zone);
        expect(language.code, expected, reason: '${zone.id} $region');
      }
    });

    test('a picked language is kept and wins over the phone', () async {
      final store = MemoryAppLanguageStore();
      final first = AppLanguageController(
        store: store,
        deviceLanguage: () => 'fr',
      );
      await first.load(config: seeds, zone: RiderZones.sweden);
      expect(first.code, 'fr');
      await first.choose('sv');
      expect(first.code, 'sv');

      final relaunched = AppLanguageController(
        store: store,
        deviceLanguage: () => 'fr',
      );
      await relaunched.load(config: seeds, zone: RiderZones.france);
      expect(relaunched.code, 'sv');
    });
  });

  group('auth.beforeSignIn ("Yes, stop it (Recommended)")', () {
    const staging = AppEnv(
      flavor: AppFlavor.staging,
      apiBaseUrl: 'https://api.movera.invalid',
    );

    test('no stored session: no bearer call leaves the app; sign-in calls '
        'do', () async {
      final sent = <String>[];
      final client = MockClient((request) async {
        sent.add('${request.method} ${request.url.path}');
        return http.Response(
          jsonEncode({'code': 'unauthorized', 'message': 'no'}),
          401,
        );
      });
      final api = ApiClient(
        env: staging,
        client: client,
        tokens: MemoryTokenStore(),
      );
      for (final path in [
        '/api/v1/rider/config?zoneId=Z001',
        '/api/v1/rider/zones',
        '/api/v1/rider/profile',
        '/api/v1/rider/content?zoneId=Z001',
      ]) {
        await expectLater(
          api.get(path),
          throwsA(
            isA<ApiError>().having((e) => e.statusCode, 'statusCode', 401),
          ),
        );
      }
      await expectLater(
        api.openEventStream('/api/v1/rider/config/stream?zoneId=Z001'),
        throwsA(isA<ApiError>()),
      );
      expect(sent, isEmpty);

      await expectLater(
        api.post('/api/v1/auth/otp/request', body: {'phone': '+46700000000'}),
        throwsA(isA<ApiError>()),
      );
      expect(sent, ['POST /api/v1/auth/otp/request']);
    });

    test('a signed-in rider still calls them', () async {
      final sent = <String>[];
      final tokens = MemoryTokenStore();
      await tokens.save(access: 'a', refresh: 'r');
      final api = ApiClient(
        env: staging,
        tokens: tokens,
        client: MockClient((request) async {
          sent.add(request.url.path);
          return http.Response('{}', 200);
        }),
      );
      await api.get('/api/v1/rider/zones');
      expect(sent, ['/api/v1/rider/zones']);
    });

    test('a 401 on the config stream is not retried in a loop', () {
      fakeAsync((async) {
        final sent = <String>[];
        final api = ApiClient(
          env: staging,
          // A stored token the server no longer accepts, with no way to
          // renew it: every call answers 401.
          tokens: _FixedTokens(),
          client: MockClient((request) async {
            sent.add(request.url.path);
            return http.Response(
              jsonEncode({'code': 'unauthorized', 'message': 'no'}),
              401,
            );
          }),
          onSessionExpired: () async {},
        );
        final repo = ApiRiderConfigRepository(
          api: api,
          cache: MemoryRiderConfigCache(),
        );
        unawaited(repo.watch(RiderZones.sweden.id));
        async.elapse(const Duration(seconds: 60));
        final config = sent
            .where((path) => path.startsWith('/api/v1/rider/config'))
            .length;
        // Live: 13 config reads and 12 stream opens in 60 s.
        expect(config, lessThanOrEqualTo(4), reason: '$sent');
        repo.dispose();
        async.flushTimers();
      });
    });

    test('a 401 is not sent as a log line or an error report', () async {
      final posted = <String>[];
      final sink = HttpObservabilitySink(
        baseUrl: 'https://api.movera.invalid',
        client: MockClient((request) async {
          posted.add(request.url.path);
          return http.Response('{}', 202);
        }),
      );
      const unauthorized = ApiError(
        code: 'unauthorized',
        message: 'no',
        statusCode: 401,
      );
      sink.log(
        TelemetryLevel.info,
        'api.GET',
        extra: {'path': '/api/v1/rider/config', 'status': 401},
      );
      sink.log(
        TelemetryLevel.warning,
        'rider_config.fetch_failed',
        extra: {'error': unauthorized.toString()},
      );
      sink.log(
        TelemetryLevel.warning,
        'rider_zones.fetch_failed',
        error: unauthorized,
      );
      sink.record(unauthorized, StackTrace.empty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(posted, isEmpty);

      // Anything else still goes out.
      sink.log(TelemetryLevel.warning, 'rider_config.fetch_failed');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(posted, ['/api/v1/telemetry/logs']);
      sink.dispose();
    });

    test('at launch the signed-in reads wait for a session; after sign-in '
        'they start', () async {
      var loads = 0;
      var signedIn = false;
      final loader = SignedInLoads(
        needsSession: () => true,
        hasSession: () async => signedIn,
        load: () async => loads++,
      );
      expect(await loader.atLaunch(), isFalse);
      expect(loads, 0);
      signedIn = true;
      await loader.afterSignIn();
      expect(loads, 1);
      expect(await loader.atLaunch(), isTrue);
      expect(loads, 2);
    });
  });
}

class _FixedTokens implements TokenStore {
  @override
  Future<String?> readAccess() async => 'stale';

  @override
  Future<String?> readRefresh() async => null;

  @override
  Future<void> save({required String access, required String refresh}) async {}

  @override
  Future<void> clear() async {}
}
