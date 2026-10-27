import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-10-27 (settings flow): the rider app reads its settings from
/// the server, keeps the last good document, gets new ones at once from
/// config_published, and takes its car types from the published catalog.
void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.invalid',
  );

  Map<String, Object?> document(int version, {bool usesStandard = false}) => {
    ...SeedRiderConfigRepository.seedDocument,
    'version': version,
    'zoneId': 'Z001',
    if (usesStandard) 'usesStandard': true,
    'catalog': {
      'categories': [
        {'id': 'comfort', 'label': 'Comfort Plus', 'seats': 4, 'sort': 2},
        {'id': 'economy', 'label': 'Movera', 'seats': 4, 'sort': 1},
        {'id': 'child_seat', 'label': 'Child Seat', 'seats': 4, 'sort': 3},
      ],
    },
    'pickupFee': {
      'byCategory': {
        'economy': {
          'live': {'amountMinor': 1500, 'currency': 'SEK'},
          'reservation': null,
        },
      },
    },
  };

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('reads GET /rider/config, parses pickupFee and usesStandard, keeps '
      'it on the device, and ignores an older version', () async {
    var version = 5;
    final asked = <String>[];
    final cache = MemoryRiderConfigCache();
    final repo = ApiRiderConfigRepository(
      api: ApiClient(
        env: staging,
        client: MockClient((request) async {
          asked.add(request.url.toString());
          return http.Response(
            jsonEncode(document(version, usesStandard: true)),
            200,
          );
        }),
      ),
      cache: cache,
    );
    final first = await repo.forZone('Z001');
    expect(
      asked.single,
      'https://api.movera.invalid/api/v1/rider/config?zoneId=Z001',
    );
    expect(first.version, 5);
    expect(first.usesStandard, isTrue);
    expect(first.pickupFeeFor('economy')?.amountMinor, 1500);
    expect(first.pickupFeeFor('economy', reservation: true), isNull);
    expect(cache.documents['Z001']?['version'], 5);

    version = 3;
    final older = await repo.refresh('Z001');
    expect(older?.version, 5);
  });

  test(
    'no server: the last document received, else the built-in seed',
    () async {
      final offline = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      final firstRun = ApiRiderConfigRepository(
        api: ApiClient(env: staging, client: offline),
        cache: MemoryRiderConfigCache(),
      );
      expect(
        (await firstRun.forZone('Z001')).version,
        SeedRiderConfigRepository.seed.version,
      );

      final cache = MemoryRiderConfigCache()..documents['Z001'] = document(9);
      final later = ApiRiderConfigRepository(
        api: ApiClient(env: staging, client: offline),
        cache: cache,
      );
      expect((await later.forZone('Z001')).version, 9);
    },
  );

  test('config_published on /rider/config/stream fetches the new document at '
      'once', () async {
    var version = 5;
    final events = StreamController<List<int>>();
    final client = MockClient.streaming((request, _) async {
      if (request.url.path.endsWith('/stream')) {
        expect(request.headers['Accept'], 'text/event-stream');
        return http.StreamedResponse(events.stream, 200);
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(document(version)))),
        200,
      );
    });
    final repo = ApiRiderConfigRepository(
      api: ApiClient(env: staging, client: client),
      cache: MemoryRiderConfigCache(),
    );
    await repo.watch('Z001');
    await pumpEventQueue();
    expect((await repo.current()).version, 5);

    final changed = Completer<void>();
    repo.addListener(() {
      if (!changed.isCompleted) changed.complete();
    });
    version = 6;
    events.add(
      utf8.encode(
        'id: 6\nevent: config_published\ndata: '
        '{"kind":"config_published","doc":"rider_app_config","zoneId":"Z001","version":6}\n\n',
      ),
    );
    await changed.future.timeout(const Duration(seconds: 2));
    expect((await repo.current()).version, 6);
    repo.dispose();
    await events.close();
  });

  test('the SSE parser gives each event\'s data', () {
    final parser = ConfigEventParser();
    expect(parser.add(': keep-alive'), isNull);
    expect(parser.add('data: {"kind":"config_published","version":2}'), isNull);
    expect(parser.add(''), {'kind': 'config_published', 'version': 2});
    expect(parser.add('data: not json'), isNull);
    expect(parser.add(''), isNull);
  });

  test(
    'the car types come from the published catalog, never /ride-types',
    () async {
      final asked = <String>[];
      final api = ApiClient(
        env: staging,
        client: MockClient((request) async {
          asked.add(request.url.path);
          return http.Response('{}', 404);
        }),
      );
      final config = RiderAppConfig.fromJson(document(5))!;
      final catalog = RideCatalogController(
        api: api,
        configSource: () async => config,
      );
      final items = await catalog.load();
      expect(items.map((item) => item.id), [
        'economy',
        'comfort',
        'child_seat',
      ]);
      expect(items[1].name, 'Comfort Plus');
      // A known category keeps the app's picture; Child Seat has none built in
      // under that id and gets the generic car.
      expect(items[0].image, RideSelectionRepository.builtInRides.first.image);
      expect(catalog.source, RideCatalogSource.server);
      expect(asked, isEmpty);
    },
  );
}
