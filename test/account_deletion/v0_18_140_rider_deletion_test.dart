import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/profile/data/account_repository.dart';
import 'package:movera_rider/features/profile/presentation/delete_account.dart';

/// Contract v0.18.140 (`contract.json#accountDeletion.rider`; owner button
/// 2026-11-20 "Accept, keep debt (Rec.)"): the rider's existing request works
/// with the new server: 202 now also carries requestedAt + eraseDueAt, and
/// 409 `deletion_open_trip` is shown as "finish or cancel your ride first".
void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );
  late List<http.Request> requests;
  AccountRepository repo(int status, Map<String, Object?> body) {
    requests = [];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
    return AccountRepository(
      api: ApiClient(client: client, env: staging),
    );
  }

  test('202 of a v0.18.140 server: requested, with the erase date', () async {
    final answer = await repo(202, {
      'status': 'requested',
      'requestedAt': '2026-11-20T10:00:00Z',
      'eraseDueAt': '2026-12-20T10:00:00Z',
    }).requestDeletion();
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/v1/account/deletion');
    expect(answer.status, 'requested');
    expect(answer.eraseDueAt, DateTime.utc(2026, 12, 20, 10));
  });

  test('202 of an older server (status only) still works', () async {
    final answer = await repo(202, {'status': 'requested'}).requestDeletion();
    expect(answer.status, 'requested');
    expect(answer.eraseDueAt, isNull);
  });

  test('409 deletion_open_trip is told apart from a lost connection', () async {
    await expectLater(
      repo(409, {
        'code': 'conflict',
        'reason': 'deletion_open_trip',
        'message': 'x',
        'requestId': 'r',
      }).requestDeletion(),
      throwsA(
        isA<ApiError>().having((e) => e.reason, 'reason', 'deletion_open_trip'),
      ),
    );
    expect(
      deletionOpenTrip(
        const ApiError(
          code: 'conflict',
          message: 'x',
          statusCode: 409,
          reason: 'deletion_open_trip',
        ),
      ),
      isTrue,
    );
    expect(deletionOpenTrip(StateError('offline')), isFalse);
  });
}
