import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/auth/token_store.dart';
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

  test('G7 live fix: a fresh read of the same version takes the served '
      'routeChange the admin changed in the driver document', () async {
    var beforePickup = true;
    final repo = ApiRiderConfigRepository(
      api: ApiClient(
        env: staging,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              ...document(5),
              'routeChange': {'on': true, 'beforePickup': beforePickup},
            }),
            200,
          ),
        ),
      ),
      cache: MemoryRiderConfigCache(),
    );
    expect((await repo.forZone('Z001')).routeChangeBeforePickup, isTrue);
    beforePickup = false;
    // The kept document answers until the server is read again.
    expect((await repo.forZone('Z001')).routeChangeBeforePickup, isTrue);
    await repo.refresh('Z001');
    expect((await repo.forZone('Z001')).routeChangeBeforePickup, isFalse);
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

  test(
    'the device cache keeps the document per zone (shared preferences)',
    () async {
      const cache = PrefsRiderConfigCache();
      expect(await cache.read('Z001'), isNull);
      await cache.write('Z001', document(4));
      expect((await cache.read('Z001'))?['version'], 4);
      expect(await cache.read('FR-PC'), isNull);
    },
  );

  test('a broken device cache never stops the app', () async {
    final repo = ApiRiderConfigRepository(
      api: ApiClient(
        env: staging,
        client: MockClient(
          (_) async => http.Response(jsonEncode(document(5)), 200),
        ),
      ),
      cache: _BrokenCache(),
    );
    expect((await repo.forZone('Z001')).version, 5);
    final offline = ApiRiderConfigRepository(
      api: ApiClient(
        env: staging,
        client: MockClient((_) async => throw http.ClientException('offline')),
      ),
      cache: _BrokenCache(),
    );
    expect(
      (await offline.forZone('Z001')).version,
      SeedRiderConfigRepository.seed.version,
    );
  });

  test('a refused or ended stream is opened again, after a fresh read; '
      'the token and the last version go with it', () async {
    var streams = 0;
    var reads = 0;
    final seen = <Map<String, String>>[];
    final client = MockClient.streaming((request, _) async {
      if (request.url.path.endsWith('/stream')) {
        streams++;
        seen.add(request.headers);
        // First refused, then a stream that ends at once.
        return streams == 1
            ? http.StreamedResponse(Stream.value(utf8.encode('{}')), 503)
            : http.StreamedResponse(const Stream.empty(), 200);
      }
      reads++;
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(document(5)))),
        200,
      );
    });
    final repo = ApiRiderConfigRepository(
      api: ApiClient(env: staging, client: client, tokens: _tokensWithAccess()),
      cache: MemoryRiderConfigCache(),
      retryAfter: const Duration(milliseconds: 10),
    );
    await repo.watch('Z001');
    await repo.watch('Z001');
    for (var i = 0; i < 50 && streams < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(streams, greaterThanOrEqualTo(3));
    expect(reads, greaterThanOrEqualTo(2));
    expect(seen.last['Authorization'], 'Bearer access-1');
    expect(seen.last['Last-Event-ID'], '5');
    // Another zone: the watch moves there.
    await repo.watch('FR-PC');
    repo.dispose();
  });

  test(
    'openEventStream: an error answer is an ApiError with its status',
    () async {
      final api = ApiClient(
        env: staging,
        client: MockClient.streaming(
          (_, _) async =>
              http.StreamedResponse(Stream.value(utf8.encode('no')), 401),
        ),
      );
      await expectLater(
        api.openEventStream('/api/v1/rider/config/stream', lastEventId: '3'),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    },
  );
}

class _BrokenCache implements RiderConfigCache {
  @override
  Future<Map<String, Object?>?> read(String zoneId) async =>
      throw StateError('disk');

  @override
  Future<void> write(String zoneId, Map<String, Object?> document) async =>
      throw StateError('disk');
}

TokenStore _tokensWithAccess() =>
    MemoryTokenStore()..save(access: 'access-1', refresh: 'refresh-1');
