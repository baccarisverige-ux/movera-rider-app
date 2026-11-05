import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/preview/preview_mode.dart';

// Contract v0.18.25 previewSession (BASE B7, owner P1 a / P2 b).
void main() {
  const preview = PreviewMode(token: 'a.b.c', zoneId: 'Z001', draft: true);

  test('reads the admin hand-off from the URL fragment', () {
    final mode = PreviewMode.parse(
      Uri.parse('https://x.test/live/#movera-preview=a.b.c&zone=Z002&draft=1'),
    );
    expect(mode.active, isTrue);
    expect(mode.token, 'a.b.c');
    expect(mode.zoneId, 'Z002');
    expect(mode.draft, isTrue);
    expect(
      PreviewMode.parse(Uri.parse('https://x.test/#/home')).active,
      isFalse,
    );
    expect(
      PreviewMode.parse(
        Uri.parse('https://x.test/#movera-preview=<bad>'),
      ).active,
      isFalse,
    );
  });

  test('no write leaves the app; reads go out with the draft', () async {
    final sent = <http.BaseRequest>[];
    final api = ApiClient(
      client: MockClient((request) async {
        sent.add(request);
        return http.Response('{}', 200);
      }),
      env: const AppEnv(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://api.test',
      ),
      tokens: PreviewTokenStore('a.b.c'),
      preview: preview,
    );
    final before = PreviewMode.blocked.value;
    for (final call in <Future<Object?> Function()>[
      () => api.post('/api/v1/trips', body: {'quoteId': 'q1'}),
      () => api.post('/api/v1/trips/t1/tip', body: {}),
      () => api.patch('/api/v1/rider/profile', body: {}),
      () => api.put('/api/v1/rider/saved-places/p1', body: {}),
      () => api.delete('/api/v1/rider/saved-places/p1'),
    ]) {
      await expectLater(
        call(),
        throwsA(
          isA<ApiError>()
              .having((e) => e.reason, 'reason', PreviewMode.blockedReason)
              .having((e) => e.message, 'message', 'Preview – not sent'),
        ),
      );
    }
    expect(sent, isEmpty);
    expect(PreviewMode.blocked.value, before + 5);

    await api.get('/api/v1/rider/config?zoneId=Z001');
    expect(sent.single.url.query, 'zoneId=Z001&draft=1');
    expect(sent.single.headers['Authorization'], 'Bearer a.b.c');
  });

  testWidgets('banner says Preview, then Preview – not sent after a stop', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PreviewBanner())),
    );
    expect(find.text('Preview'), findsOneWidget);
    PreviewMode.blocked.value++;
    await tester.pump();
    expect(find.text('Preview – not sent'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Preview'), findsOneWidget);
  });
}
