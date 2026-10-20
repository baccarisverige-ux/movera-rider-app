import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/in_process_mock_client.dart';

/// RC-12: the demo server's replay cache is per method + path + key, holds
/// a copy of the first answer, refuses a different body and forgets old
/// entries.
void main() {
  var now = DateTime.utc(2026, 10, 20, 9);
  late InProcessMockClient server;

  setUp(() {
    now = DateTime.utc(2026, 10, 20, 9);
    server = InProcessMockClient(clock: () => now);
  });

  Future<http.Response> post(String path, Map<String, Object?> body, String key) async {
    final request = http.Request('POST', Uri.parse('https://mock.local$path'))
      ..headers['Idempotency-Key'] = key
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    return http.Response.fromStream(await server.send(request));
  }

  const quoteBody = {
    'rideType': 'movera',
    'pickupLat': 59.3293,
    'pickupLng': 18.0686,
    'destinationLat': 59.3326,
    'destinationLng': 18.0649,
  };

  test('the same key on another path is not a replay', () async {
    final first = await post('/api/v1/quotes', quoteBody, 'key-shared-000001');
    final other = await post(
      '/api/v1/locations/reverse-geocode',
      {'latitude': 59.33, 'longitude': 18.06},
      'key-shared-000001',
    );
    expect(first.statusCode, 200);
    expect(other.statusCode, 200);
    expect(jsonDecode(other.body), isNot(jsonDecode(first.body)));
    expect(server.idempotency.length, 2);
  });

  test('a replay returns the first answer, a different body is 409', () async {
    final first = await post('/api/v1/quotes', quoteBody, 'key-quote-0000001');
    final again = await post('/api/v1/quotes', quoteBody, 'key-quote-0000001');
    expect(jsonDecode(again.body), jsonDecode(first.body));
    final changed = await post(
      '/api/v1/quotes',
      {...quoteBody, 'destinationLat': 59.40},
      'key-quote-0000001',
    );
    expect(changed.statusCode, 409);
    expect((jsonDecode(changed.body) as Map)['code'], 'conflict');
  });

  test('old entries are forgotten', () async {
    await post('/api/v1/quotes', quoteBody, 'key-old-000000001');
    expect(server.idempotency.length, 1);
    now = now.add(InProcessMockClient.idempotencyTtl + const Duration(minutes: 1));
    await post('/api/v1/quotes', quoteBody, 'key-new-000000001');
    expect(server.idempotency.length, 1);
  });
}
