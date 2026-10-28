import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/content/rider_content_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingStore implements RiderContentStore {
  @override
  Future<int?> acceptedLegalVersion() async => throw StateError('x');
  @override
  Future<Map<String, Object?>?> read(String zoneId) async =>
      throw StateError('x');
  @override
  Future<void> write(String zoneId, Map<String, Object?> answer) async =>
      throw StateError('x');
  @override
  Future<void> writeAcceptedLegalVersion(int version) async =>
      throw StateError('x');
}

void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.invalid',
  );
  final now = DateTime.utc(2026, 1, 1, 12);

  Map<String, Object?> item(
    String slot, {
    int version = 1,
    bool? reaccept,
    Map<String, Object?>? text,
  }) => {
    'slot': slot,
    'zoneId': 'Z001',
    'version': version,
    'publishedAt': '2026-01-01T00:00:00Z',
    'title': 'T $slot',
    'text': text ?? {'en': 'en $slot'},
    'reaccept': ?reaccept,
  };

  ApiClient api(Future<http.Response> Function(http.Request r) handler) =>
      ApiClient(env: staging, client: MockClient(handler));

  group('PrefsRiderContentStore', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('round-trips answers and the accepted version', () async {
      const store = PrefsRiderContentStore();
      expect(await store.read('Z001'), isNull);
      expect(await store.acceptedLegalVersion(), isNull);
      await store.write('Z001', {'items': <Object?>[]});
      expect(await store.read('Z001'), {'items': <Object?>[]});
      await store.writeAcceptedLegalVersion(1);
      expect(await store.acceptedLegalVersion(), 1);
    });

    test('a kept value that is not a map reads as null', () async {
      SharedPreferences.setMockInitialValues({
        PrefsRiderContentStore.keyOf('Z001'): '[1]',
      });
      expect(await const PrefsRiderContentStore().read('Z001'), isNull);
    });
  });

  group('RiderContentController', () {
    test('store failures are logged, never thrown', () async {
      var fail = false;
      final c = RiderContentController(
        api: api((r) async {
          if (r.method == 'POST') {
            if (fail) throw http.ClientException('off');
            return http.Response('', 204);
          }
          return http.Response(
            jsonEncode({
              'items': [item('legal', reaccept: true)],
            }),
            200,
          );
        }),
        store: _FailingStore(),
        clock: () => now,
      );
      await c.start('Z001');
      expect(c.decision.acceptTerms?.version, 1);
      fail = true;
      expect(await c.acceptTerms(), isFalse);
      expect(c.decision.acceptTerms?.version, 1);
      fail = false;
      expect(await c.acceptTerms(), isTrue);
      expect(c.decision.acceptTerms, isNull);
      expect(await c.acceptTerms(), isTrue, reason: 'nothing to accept');
    });

    test('a non ContentList answer keeps the old content', () async {
      var body = jsonEncode({
        'items': [item('help')],
      });
      final c = RiderContentController(
        api: api((_) async => http.Response(body, 200)),
        store: MemoryRiderContentStore(),
        clock: () => now,
      );
      await c.start('Z001');
      expect(c.help?.title, 'T help');
      body = jsonEncode({'nope': 1});
      await c.refresh();
      expect(c.help?.title, 'T help');
    });

    test('an answer for a zone left meanwhile is dropped', () async {
      final c = RiderContentController(
        api: api((r) async {
          final zone = r.url.queryParameters['zoneId']!;
          if (zone == 'Z001') await Future<void>.delayed(Duration.zero);
          return http.Response(
            jsonEncode({
              'items': [
                item('help', text: {'en': zone}),
              ],
            }),
            200,
          );
        }),
        store: MemoryRiderContentStore(),
        clock: () => now,
      );
      final first = c.start('Z001');
      await c.start('Z002');
      await first;
      expect(c.help?.text['en'], 'Z002');
    });

    test('closing the recommended update notifies and dispose is safe', () {
      final c = RiderContentController(clock: () => now);
      var calls = 0;
      c.addListener(() => calls++);
      c.closeRecommendedUpdate();
      expect(calls, 1);
      expect(c.now, now);
      c.dispose();
    });
  });

  test('help text falls back to any non-empty language', () async {
    final c = RiderContentController(
      api: api(
        (_) async => http.Response(
          jsonEncode({
            'items': [
              item('help', text: {'sv': ' ', 'fr': 'fr'}),
            ],
          }),
          200,
        ),
      ),
      store: MemoryRiderContentStore(),
      clock: () => now,
    );
    await c.start('Z001');
    expect(c.help?.textIn('de'), 'fr');
  });
}
