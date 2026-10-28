import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/config/rider_zones_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/not_here_view.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingStore implements RiderZonesStore {
  @override
  Future<Map<String, Object?>?> read() async => throw StateError('x');
  @override
  Future<void> write(Map<String, Object?> answer) async =>
      throw StateError('x');
}

void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.invalid',
  );
  final fixture =
      jsonDecode(File('contracts/fixtures/zones.json').readAsStringSync())
          as Map<String, dynamic>;
  final contract =
      jsonDecode(File('contracts/contract.json').readAsStringSync())
          as Map<String, dynamic>;
  final seeds = {
    for (final s in (contract['zones'] as Map)['seed'] as List)
      (s as Map)['zoneId']: s,
  };

  /// The fixture's zones as `GET /rider/zones` lists them (open only, with
  /// the contract seed's names, currency and time zone).
  Map<String, Object?> answer() => {
    'zones': [
      for (final z in fixture['zones'] as List)
        if ((z as Map)['open'] == true) {...seeds[z['zoneId']] as Map, ...z},
    ],
  };

  ApiClient api(Future<http.Response> Function(http.Request r) handler) =>
      ApiClient(env: staging, client: MockClient(handler));

  tearDown(RiderZones.useSamples);

  group('RiderZones', () {
    test('the samples serve every place; home is Stockholm', () {
      expect(RiderZones.live, isFalse);
      expect(RiderZones.serves(10, 10), isTrue);
      expect(RiderZones.serves(null, null), isTrue);
      expect(RiderZones.at(59.33, 18.07).id, 'Z001');
      expect(RiderZones.at(48.85, 2.35).id, 'FR-PC');
      expect(RiderZones.at(0, 0).id, 'Z001');
      expect(RiderZones.find(double.nan, 0), isNull);
      expect(RiderZones.home.id, 'Z001');
      expect(RiderZones.byId('TN-TC'), RiderZones.tunisia);
      expect(RiderZones.byId('nope'), isNull);
      expect(RiderZones.byCurrency('EUR'), RiderZones.france);
      expect(RiderZones.byCurrency('USD'), isNull);
      expect(RiderZones.cityNames('sv'), contains('Stockholm län'));
    });

    test('the server list: every fixture point by polygon', () {
      final zones = RiderZonesController.parse(answer())!;
      expect(zones.map((z) => z.id), ['FR-PC', 'CDG', 'ORY']);
      RiderZones.useServer(zones);
      expect(RiderZones.live, isTrue);
      for (final p in fixture['points'] as List) {
        final point = p as Map;
        final expected = point['zoneId'];
        // Only open zones are listed: TN-TC (closed) is no zone here.
        final open = expected == 'TN-TC' ? null : expected;
        final found = RiderZones.find(
          (point['lat'] as num).toDouble(),
          (point['lng'] as num).toDouble(),
        );
        expect(found?.id, open, reason: '${point['name']}');
        expect(
          RiderZones.serves(
            (point['lat'] as num).toDouble(),
            (point['lng'] as num).toDouble(),
          ),
          open != null,
        );
      }
      // Outside: home is the first city zone, a missing point is served.
      expect(RiderZones.at(36.8, 10.17).id, 'FR-PC');
      expect(RiderZones.serves(null, 1), isTrue);
      expect(RiderZones.home.id, 'FR-PC');
      expect(RiderZones.byCurrency('EUR')!.id, 'FR-PC');
      expect(RiderZones.cityNames('fr'), ['Paris & Île-de-France']);
      expect(
        RiderZones.byId('CDG')!.nameIn('sv'),
        'Paris-Charles de Gaulle flygplats',
      );
    });

    test('home: Stockholm when listed, else a city, else any', () {
      RiderZones.useServer(const []);
      expect(RiderZones.home, RiderZones.sweden);
      final cdg = RiderZones.byId('FR-PC'); // samples are gone
      expect(cdg, isNull);
      final airport = RiderZone.fromJson({
        'zoneId': 'ARN',
        'currency': 'SEK',
        'timeZone': 'Europe/Stockholm',
        'kind': 'airport',
        'polygon': [
          [59.6, 17.9],
          [59.7, 17.9],
          [59.7, 18.0],
        ],
      })!;
      RiderZones.useServer([airport]);
      expect(RiderZones.home.id, 'ARN');
      expect(RiderZones.byCurrency('SEK')!.id, 'ARN');
      RiderZones.useServer([airport, RiderZones.sweden]);
      expect(RiderZones.home.id, 'Z001');
    });

    test('a point on the edge is inside; a square', () {
      const square = [
        [0.0, 0.0],
        [0.0, 1.0],
        [1.0, 1.0],
        [1.0, 0.0],
      ];
      expect(polygonHolds(square, 0.5, 0.5), isTrue);
      expect(polygonHolds(square, 0, 0.5), isTrue);
      expect(polygonHolds(square, 1, 1), isTrue);
      expect(polygonHolds(square, 1.5, 0.5), isFalse);
    });

    test('fromJson refuses what is not a zone; names fall back', () {
      final base = <String, Object?>{
        'zoneId': 'X',
        'currency': 'EUR',
        'timeZone': 'Europe/Paris',
        'polygon': [
          [0, 0],
          [0, 1],
          [1, 1],
        ],
      };
      expect(RiderZone.fromJson('x'), isNull);
      expect(RiderZone.fromJson({...base, 'zoneId': ''}), isNull);
      expect(RiderZone.fromJson({...base, 'currency': 1}), isNull);
      expect(RiderZone.fromJson({...base, 'polygon': 'x'}), isNull);
      expect(
        RiderZone.fromJson({
          ...base,
          'polygon': [
            [0],
          ],
        }),
        isNull,
      );
      expect(
        RiderZone.fromJson({
          ...base,
          'polygon': [
            ['a', 1],
          ],
        }),
        isNull,
      );
      expect(
        RiderZone.fromJson({
          ...base,
          'polygon': [
            [0, 0],
            [1, 1],
          ],
        }),
        isNull,
      );
      final zone = RiderZone.fromJson(base)!;
      expect(zone.nameIn('sv'), 'X');
      expect(zone.kind, 'operating');
      expect(zone.country, isNull);
      final named = RiderZone.fromJson({
        ...base,
        'country': 'FR',
        'names': {'fr': 'Ici', 'sv': ' ', 1: 'x'},
      })!;
      expect(named.nameIn('sv'), 'Ici');
      expect(named.toJson()['country'], 'FR');
      final round = RiderZone.fromJson(RiderZones.sweden.toJson())!;
      expect(round.contains(59.33, 18.07), isTrue);
    });

    test('seedFor: a server zone gets the seed in its currency', () {
      RiderZones.useServer(RiderZonesController.parse(answer())!);
      expect(SeedRiderConfigRepository.seedFor('CDG').currency, 'EUR');
      expect(SeedRiderConfigRepository.seedFor('nope').zoneId, 'Z001');
    });
  });

  group('RiderZonesController', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('PrefsRiderZonesStore round-trips', () async {
      const store = PrefsRiderZonesStore();
      expect(await store.read(), isNull);
      await store.write({'zones': <Object?>[]});
      expect(await store.read(), {'zones': <Object?>[]});
      SharedPreferences.setMockInitialValues({PrefsRiderZonesStore.key: '[]'});
      expect(await store.read(), isNull);
    });

    test('the demo (no api) keeps the samples', () async {
      final c = RiderZonesController(store: MemoryRiderZonesStore());
      await c.start();
      expect(await c.refresh(), isFalse);
      expect(RiderZones.live, isFalse);
      expect(c.zones, RiderZones.samples);
    });

    test('kept answer first, then the server, kept again', () async {
      final store = MemoryRiderZonesStore()
        ..answer = {
          'zones': [RiderZones.tunisia.toJson()],
        };
      final paths = <String>[];
      final c = RiderZonesController(
        api: api((r) async {
          paths.add(r.url.path);
          return http.Response(jsonEncode(answer()), 200);
        }),
        store: store,
      );
      var notified = 0;
      c.addListener(() => notified++);
      await c.loadCached();
      expect(RiderZones.all.single.id, 'TN-TC');
      expect(await c.refresh(), isTrue);
      expect(paths, ['/api/v1/rider/zones']);
      expect(RiderZones.all.map((z) => z.id), ['FR-PC', 'CDG', 'ORY']);
      expect((store.answer!['zones'] as List).length, 3);
      expect(notified, 2);
      c.onConfigEvent({'kind': 'config_published', 'doc': 'content'});
      c.onConfigEvent({'kind': 'config_published', 'doc': 'zones'});
      await Future<void>.delayed(Duration.zero);
      await c.refresh();
      expect(paths.length, greaterThanOrEqualTo(2));
    });

    test('a failing server or store keeps what was in use', () async {
      final c = RiderZonesController(
        api: api((r) async => http.Response('{"x":1}', 200)),
        store: _FailingStore(),
      );
      await c.start();
      expect(await c.refresh(), isFalse);
      expect(RiderZones.live, isFalse);
      final ok = RiderZonesController(
        api: api((r) async => http.Response(jsonEncode(answer()), 200)),
        store: _FailingStore(),
      );
      expect(await ok.refresh(), isTrue);
      expect(RiderZones.live, isTrue);
      expect(RiderZonesController.parse({'zones': 'x'}), isNull);
      expect(
        RiderZonesController.parse({
          'zones': [
            {...RiderZones.france.toJson(), 'open': false},
            'x',
          ],
        }),
        isEmpty,
      );
    });
  });

  test('isNotServedError: only 403 service_not_available', () {
    expect(
      isNotServedError(
        const ApiError(
          code: 'forbidden',
          message: 'm',
          statusCode: 403,
          reason: 'service_not_available',
        ),
      ),
      isTrue,
    );
    expect(
      isNotServedError(
        const ApiError(code: 'forbidden', message: 'm', statusCode: 403),
      ),
      isFalse,
    );
    expect(isNotServedError(StateError('x')), isFalse);
  });

  for (final (code, title) in [
    ('sv', 'Movera finns inte här än'),
    ('fr', 'Movera n’est pas encore ici'),
    ('en', "Movera isn't here yet"),
  ]) {
    testWidgets('NotHereView in $code', (tester) async {
      var changed = 0;
      L10n.use(code);
      addTearDown(() => L10n.use('en'));
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(code),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NotHereView(onChangePickup: () => changed++),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.byKey(const ValueKey('not-here-zones')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('not-here-change-pickup')));
      await tester.tap(find.byIcon(Icons.arrow_back));
      expect(changed, 2);
    });
  }

  testWidgets('NotHereView pops without a callback', (tester) async {
    RiderZones.useServer(const []);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const NotHereView()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('not-here-zones')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('not-here-change-pickup')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
