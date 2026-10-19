import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:movera_rider/features/ride_selection/domain/ride_selection.dart';

Map<String, dynamic> _row(
  String id,
  String name, {
  int seats = 4,
  int etaMin = 9,
  num price = 300,
  String description = 'A ride',
  String? badge,
  String? glyph,
  String? imageKey,
  int? order,
  bool enabled = true,
}) => {
  'id': id,
  'name': name,
  'seats': seats,
  'etaMin': etaMin,
  'price': price,
  'description': description,
  'badge': badge,
  'glyph': glyph,
  'imageKey': imageKey ?? id,
  'order': order,
  'enabled': enabled,
};

ApiClient _apiServing(List<Map<String, dynamic>> rows) => ApiClient(
  client: MockClient((request) async {
    expect(request.url.path, RideCatalogController.path);
    return http.Response(
      jsonEncode({'code': 'OK', 'rideTypes': rows}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

ApiClient _apiFailing() => ApiClient(
  client: MockClient(
    (_) async => http.Response(
      jsonEncode({'code': 'SERVER_ERROR', 'message': 'down'}),
      500,
      headers: {'content-type': 'application/json'},
    ),
  ),
);

class _ThrowingCache implements RideCatalogCache {
  @override
  Future<List<Map<String, dynamic>>?> read() async =>
      throw StateError('no prefs');

  @override
  Future<void> write(List<Map<String, dynamic>> rows) async =>
      throw StateError('no prefs');
}

const _builtIn = [
  RideCatalogItem(
    id: 'economy',
    image: 'assets/images/rides/movera.webp',
    name: 'Movera',
    note: 'Built in',
    arrival: '8 min',
    etaMin: 8,
    price: 259,
    seats: 4,
  ),
];

void main() {
  group('RideCatalogJson', () {
    test('maps rows, drops disabled, sorts by order, falls back on keys', () {
      final items = RideCatalogJson.parseAll([
        _row('van', 'Van', seats: 8, etaMin: 14, price: 449,
            description: 'Groups and luggage', imageKey: 'xl', order: 3),
        _row('rocket', 'Rocket', glyph: 'rocket', imageKey: 'spaceship',
            order: 2),
        _row('hidden', 'Hidden', order: 1, enabled: false),
        _row('electric', 'Electric', glyph: 'bolt', order: 1),
      ]);

      expect(items.map((item) => item.id), ['electric', 'rocket', 'van']);

      final van = items.last;
      expect(van.name, 'Van');
      expect(van.seats, 8);
      expect(van.etaMin, 14);
      expect(van.arrival, '14 min');
      expect(van.price, 449);
      expect(van.note, 'Groups and luggage');
      expect(van.image, 'assets/images/rides/xl.webp');
      expect(van.glyph, isNull);
      expect(van.badge, isNull);

      final rocket = items[1];
      expect(rocket.image, RideCatalogJson.fallbackImage);
      expect(rocket.glyph, RideCatalogJson.fallbackGlyph);

      expect(items.first.glyph, 'bolt');
      expect(items.first.image, 'assets/images/rides/electric.webp');
    });

    test('rows without id, name or price are skipped; order is optional', () {
      final items = RideCatalogJson.parseAll([
        {'id': 'b', 'name': 'B', 'price': 10},
        {'id': 'a', 'name': 'A', 'price': 20},
        {'id': '', 'name': 'No id', 'price': 10},
        {'id': 'x', 'name': 'No price'},
        {'id': 'y', 'name': ' ', 'price': 10},
      ]);
      expect(items.map((item) => item.id), ['b', 'a']);
      expect(items.first.seats, 4);
      expect(items.first.arrival, '0 min');
    });
  });

  group('RideCatalogController', () {
    test('starts on the built-in list and switches to the server list', () async {
      final cache = MemoryRideCatalogCache();
      final controller = RideCatalogController(
        api: _apiServing([
          _row('economy', 'Movera', order: 1, badge: 'RECOMMENDED'),
          _row('van', 'Van', price: 449, order: 2, imageKey: 'xl'),
        ]),
        cache: cache,
        builtIn: _builtIn,
      );
      var notified = 0;
      controller.addListener(() => notified++);

      expect(controller.current.map((item) => item.id), ['economy']);
      expect(controller.source, RideCatalogSource.builtIn);

      final loaded = await controller.load();

      expect(loaded.map((item) => item.id), ['economy', 'van']);
      expect(controller.current, loaded);
      expect(controller.source, RideCatalogSource.server);
      expect(notified, 1);
      expect(cache.rows?.map((row) => row['id']), ['economy', 'van']);
    });

    test('falls back to the cached list when the API throws', () async {
      final controller = RideCatalogController(
        api: _apiFailing(),
        cache: MemoryRideCatalogCache([
          _row('comfort', 'Comfort', order: 1),
          _row('van', 'Van', price: 449, order: 2),
        ]),
        builtIn: _builtIn,
      );

      final loaded = await controller.load();

      expect(loaded.map((item) => item.id), ['comfort', 'van']);
      expect(controller.source, RideCatalogSource.cache);
    });

    test('falls back to the built-in list when API and cache both fail', () async {
      final controller = RideCatalogController(
        api: _apiFailing(),
        cache: _ThrowingCache(),
        builtIn: _builtIn,
      );

      final loaded = await controller.load();

      expect(loaded.map((item) => item.id), ['economy']);
      expect(controller.source, RideCatalogSource.builtIn);
    });

    test('an empty cache does not hide the built-in list', () async {
      final controller = RideCatalogController(
        api: _apiFailing(),
        cache: MemoryRideCatalogCache(const []),
        builtIn: _builtIn,
      );
      expect((await controller.load()).map((item) => item.id), ['economy']);
      expect(controller.source, RideCatalogSource.builtIn);
    });

    test('a later failure keeps the server list already shown', () async {
      var fail = false;
      final api = ApiClient(
        client: MockClient((_) async {
          if (fail) return http.Response('{"code":"SERVER_ERROR"}', 503);
          return http.Response(
            jsonEncode({
              'code': 'OK',
              'rideTypes': [_row('van', 'Van', price: 449, order: 1)],
            }),
            200,
          );
        }),
      );
      final controller = RideCatalogController(
        api: api,
        cache: MemoryRideCatalogCache(),
        builtIn: _builtIn,
      );
      await controller.load();
      fail = true;
      await controller.load();
      expect(controller.current.map((item) => item.id), ['van']);
      expect(controller.source, RideCatalogSource.server);
    });

    test('the in-process mock serves the admin ids plus Van, priced', () async {
      final controller = RideCatalogController(
        api: ApiClient(client: InProcessMockClient()),
        cache: MemoryRideCatalogCache(),
      );
      final loaded = await controller.load();

      expect(loaded.map((item) => item.id), [
        'economy',
        'comfort',
        'premium',
        'priority',
        'xl',
        'electric',
        'pet',
        'van',
        'wheelchair',
        'business',
        'airport',
        'kids',
        'women',
        'delivery',
      ]);
      final van = loaded.firstWhere((item) => item.id == 'van');
      expect(van.name, 'Van');
      expect(van.seats, 8);
      expect(van.price, 449);
      expect(van.note, 'Groups and luggage');
      expect(van.image, 'assets/images/rides/van.webp');
      expect(van.glyph, 'van');
      // Every server category ships with its own picture in the app, so the
      // admin can switch any of them on without an app release.
      for (final item in loaded) {
        final asset = item.id == 'economy' ? 'movera' : item.id;
        expect(item.image, 'assets/images/rides/$asset.webp');
      }
      expect(
        RideSelectionRepository.builtInRides.map((item) => item.id),
        loaded.map((item) => item.id),
        reason: 'the built-in fallback mirrors the admin list',
      );

      final api = ApiClient(client: InProcessMockClient());
      final quote = await api.post(
        '/api/v1/quotes',
        body: {'rideType': 'van', 'distanceMeters': 3000},
      );
      expect((quote['quote'] as Map)['totalMinor'], 44900);
    });
  });
}
