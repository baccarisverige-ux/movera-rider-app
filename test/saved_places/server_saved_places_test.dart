import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/home/data/home_repository.dart';
import 'package:movera_rider/features/saved_places/data/server_saved_places.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BASE B13 (contract v0.18.26 §47; owner 2026-11-03 "Phone-only data: Yes,
/// all to server"): the rider's saved places live on the server. Before this
/// change they were only on the phone: a new phone or a reinstall lost them.
void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );

  late List<String> calls;
  late List<Map<String, dynamic>> server;
  late bool imported;
  var next = 0;

  Map<String, dynamic> stored(Map<String, dynamic> body, [String? id]) => {
    'placeId': id ?? 'plc_${++next}',
    'label': body['label'],
    'kind': body['kind'],
    if (body['type'] != null) 'type': body['type'],
    'place': body['place'],
    'createdAt': '2026-11-04T12:00:00Z',
    'updatedAt': '2026-11-04T12:00:00Z',
  };

  Map<String, dynamic> save(Map<String, dynamic> body) {
    if (body['kind'] != 'other') {
      final old = server.indexWhere((p) => p['kind'] == body['kind']);
      if (old >= 0) {
        return server[old] = stored(body, server[old]['placeId'] as String);
      }
    }
    final row = stored(body);
    server.add(row);
    return row;
  }

  ServerSavedPlaces sync() {
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;
      Object answer = {'items': server, 'nextCursor': null};
      var code = 200;
      final path = request.url.path;
      if (request.method == 'POST' && path.endsWith('/import')) {
        if (!imported) {
          for (final item in body['items'] as List) {
            save(item as Map<String, dynamic>);
          }
          imported = true;
        }
      } else if (request.method == 'POST') {
        answer = save(body);
        code = 201;
      } else if (request.method == 'PUT') {
        final id = path.split('/').last;
        final i = server.indexWhere((p) => p['placeId'] == id);
        answer = server[i] = stored(body, id);
      } else if (request.method == 'DELETE') {
        server.removeWhere((p) => p['placeId'] == path.split('/').last);
        return http.Response('', 204);
      }
      return http.Response(
        jsonEncode(answer),
        code,
        headers: {'content-type': 'application/json'},
      );
    });
    return ServerSavedPlaces(
      api: ApiClient(client: client, env: staging),
    );
  }

  setUp(() {
    calls = [];
    server = [];
    imported = false;
    next = 0;
  });

  test('uploads the phone places once, then shows the server list', () async {
    SharedPreferences.setMockInitialValues({
      'movera_home_address': 'Sveavägen 1',
      'movera_saved_places': jsonEncode([
        {
          'id': 'place_legacy_0',
          'title': 'gym',
          'type': 'gym',
          'address': 'Odengatan 3',
        },
      ]),
    });
    final first = sync();
    await first.sync();
    first.reset();
    expect(calls.first, 'POST /api/v1/rider/places/import');
    expect(server.map((p) => p['kind']), ['home', 'other']);
    expect(server.last['type'], 'gym');
    final local = await HomeAddressRepository().load();
    expect(local.home, 'Sveavägen 1');
    // The phone copy now carries the server's id.
    expect(local.places.single['id'], server.last['placeId']);

    // A second start reads, it does not upload again.
    calls.clear();
    final second = sync();
    await second.sync();
    second.reset();
    expect(calls, ['GET /api/v1/rider/places']);
  });

  test(
    'a phone change is sent: new place POST, edit PUT, delete DELETE',
    () async {
      SharedPreferences.setMockInitialValues({
        'movera_saved_places_uploaded': '1',
      });
      server.add(
        stored({
          'label': 'Work',
          'kind': 'work',
          'place': {'address': 'Kungsgatan 5'},
        }),
      );
      final s = sync();
      await s.sync();
      final store = HomeAddressRepository();

      calls.clear();
      var local = await store.load();
      await store.save(
        HomeAddressSnapshot(
          home: 'Rue de Rivoli 2',
          work: null,
          recent: local.recent,
          places: [
            {
              'id': 'place_x',
              'title': 'Mall',
              'type': 'mall',
              'address': 'Mall street',
            },
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await s.idle;
      expect(
        calls,
        containsAll([
          'DELETE /api/v1/rider/places/plc_1',
          'POST /api/v1/rider/places',
        ]),
      );
      expect(server.map((p) => p['kind']).toSet(), {'home', 'other'});

      calls.clear();
      local = await store.load();
      final mall = local.places.single;
      expect(mall['id'], startsWith('plc_'));
      await store.save(
        HomeAddressSnapshot(
          home: local.home,
          work: null,
          recent: local.recent,
          places: [
            {...mall, 'address': 'Mall street 2'},
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await s.idle;
      expect(calls.where((c) => c.startsWith('PUT')), [
        'PUT /api/v1/rider/places/${mall['id']}',
      ]);
      s.reset();
    },
  );

  test('the plan sends nothing when the phone matches the server', () {
    final known = [
      const ServerPlace(
        placeId: 'plc_1',
        kind: 'home',
        label: 'Home',
        address: 'A',
      ),
      const ServerPlace(
        placeId: 'plc_2',
        kind: 'other',
        label: 'Gym',
        address: 'B',
        type: 'gym',
      ),
    ];
    final local = HomeAddressSnapshot(
      home: 'A',
      places: [
        {'id': 'plc_2', 'title': 'Gym', 'type': 'gym', 'address': 'B'},
      ],
    );
    expect(planChanges(known, local).isEmpty, isTrue);
  });
}
