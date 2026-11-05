import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/emergency_contact.dart';

/// BASE B13 (contract v0.18.26 §47; owner 2026-11-04 "Yes, same as
/// drivers"): on live the rider's emergency contacts are kept on the server.
/// Before, the contract wire refused every contact change ("not on server").
void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );
  late List<String> calls;
  late Map<String, dynamic> server;

  ContractContactsRemoteDataSource remote() => ContractContactsRemoteDataSource(
    ApiClient(
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'PUT') {
          server = {
            ...jsonDecode(request.body) as Map<String, dynamic>,
            'updatedAt': '2026-11-04T12:00:00Z',
          };
        }
        return http.Response(
          jsonEncode(server),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      env: staging,
    ),
  );

  const sara = EmergencyContact(
    id: 'c1',
    userId: 'r1',
    name: 'Sara',
    phoneE164: '+46701234567',
    relationship: 'Family',
    isPrimary: true,
  );

  setUp(() {
    calls = [];
    server = {'items': <Object>[], 'updatedAt': null};
  });

  test(
    'the phone list is uploaded once, then the server list is read',
    () async {
      final r = remote();
      final first = await r.syncContacts([sara]);
      expect(first.single.name, 'Sara');
      expect(calls, [
        'GET /api/v1/rider/emergency-contacts',
        'PUT /api/v1/rider/emergency-contacts',
      ]);
      expect(server['items'], [
        {'name': 'Sara', 'phone': '+46701234567', 'relation': 'Family'},
      ]);
      calls.clear();
      final again = await r.syncContacts(const []);
      expect(again.single.phoneE164, '+46701234567');
      expect(calls, ['GET /api/v1/rider/emergency-contacts']);
    },
  );

  test('add and delete send the whole list', () async {
    final r = remote();
    await r.syncContacts(const []);
    await r.createContact(sara);
    expect((server['items'] as List).single['name'], 'Sara');
    await r.deleteContact('c1');
    expect(server['items'], isEmpty);
  });
}
