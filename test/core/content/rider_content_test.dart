import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/content/rider_content.dart';
import 'package:movera_rider/core/content/rider_content_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contract v0.10.0 §19 (Content) in the rider app.
void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.invalid',
  );
  final now = DateTime.utc(2026, 10, 28, 12);

  Map<String, Object?> item(
    String slot, {
    int version = 1,
    String? image,
    String? expiresAt,
    bool? reaccept,
    Map<String, Object?>? versions,
  }) => {
    'slot': slot,
    'zoneId': 'Z001',
    'version': version,
    'publishedAt': '2026-10-28T08:00:00Z',
    'title': 'T $slot',
    'text': {'sv': 'sv $slot', 'fr': 'fr $slot', 'en': 'en $slot'},
    'image': ?image,
    'expiresAt': ?expiresAt,
    'reaccept': ?reaccept,
    'versions': ?versions,
  };

  Map<String, Object?> pair(String min, String rec) => {
    'rider': {'min': min, 'recommended': rec},
    'driver': {'min': '9.9.9', 'recommended': '9.9.9'},
  };

  group('items', () {
    test('banners in slot order, expired hidden, image only if https', () {
      final content = RiderContent.fromJson({
        'items': [
          item('rider-banner-3', image: 'http://x.invalid/a.png'),
          item('rider-banner-1', image: 'https://x.invalid/a.png'),
          item('rider-banner-2', expiresAt: '2026-10-28T11:00:00Z'),
          item('help'),
          item('driver-home'),
        ],
      })!;
      final banners = content.banners(now);
      expect(banners.map((b) => b.slot), ['rider-banner-1', 'rider-banner-3']);
      expect(banners.first.image, 'https://x.invalid/a.png');
      expect(banners.last.image, isNull);
      expect(content.help(now)?.textIn('fr'), 'fr help');
    });

    test('text in the rider language, else English', () {
      final i = ContentItem.fromJson({
        ...item('help'),
        'text': {'sv': '', 'en': 'english'},
      })!;
      expect(i.textIn('sv'), 'english');
    });

    test('versions compare as x.y.z; an unknown build is never below', () {
      expect(versionBelow('1.2.3', '1.10.0'), isTrue);
      expect(versionBelow('1.10.0', '1.2.3'), isFalse);
      expect(versionBelow('1.2.3', '1.2.3'), isFalse);
      expect(versionBelow('1.2.3+4', '1.2.4'), isTrue);
      expect(versionBelow('dev', '9.0.0'), isFalse);
    });
  });

  group('decision', () {
    ContentDecision decide(
      List<Map<String, Object?>> items, {
      String app = '1.5.0',
      bool onTrip = false,
      int? accepted,
      bool closed = false,
    }) {
      final content = RiderContent.fromJson({'items': items})!;
      return ContentDecision.decide(
        content: content,
        now: now,
        appVersion: app,
        onTrip: onTrip,
        legalAtStart: content.legal(now),
        acceptedLegalVersion: accepted,
        recommendedClosed: closed,
      );
    }

    test('below min blocks; on a trip only a small message', () {
      final items = [item('app-versions', versions: pair('2.0.0', '2.1.0'))];
      expect(decide(items).blockForUpdate, isTrue);
      final trip = decide(items, onTrip: true);
      expect(trip.blockForUpdate, isFalse);
      expect(trip.tripUpdateNotice, isTrue);
    });

    test('below recommended: a closable message', () {
      final items = [item('app-versions', versions: pair('1.0.0', '1.6.0'))];
      expect(decide(items).recommendUpdate, isTrue);
      expect(decide(items).blockForUpdate, isFalse);
      expect(decide(items, closed: true).recommendUpdate, isFalse);
      expect(decide(items, app: '1.6.0').recommendUpdate, isFalse);
    });

    test('the driver pair does not count', () {
      final items = [
        item(
          'app-versions',
          versions: {
            'rider': {'min': '1.0.0', 'recommended': '1.0.0'},
            'driver': {'min': '5.0.0', 'recommended': '5.0.0'},
          },
        ),
      ];
      final d = decide(items);
      expect(d.blockForUpdate || d.recommendUpdate, isFalse);
    });

    test('terms with reaccept until accepted, never during a trip', () {
      final items = [item('legal', version: 4, reaccept: true)];
      expect(decide(items).acceptTerms?.version, 4);
      expect(decide(items, onTrip: true).acceptTerms, isNull);
      expect(decide(items, accepted: 4).acceptTerms, isNull);
      expect(decide(items, accepted: 3).acceptTerms?.version, 4);
      expect(decide([item('legal', version: 4)]).acceptTerms, isNull);
    });

    test('the update block comes before the terms', () {
      final d = decide([
        item('legal', reaccept: true),
        item('app-versions', versions: pair('2.0.0', '2.0.0')),
      ]);
      expect(d.blockForUpdate, isTrue);
      expect(d.acceptTerms, isNull);
    });
  });

  group('controller', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('reads GET /rider/content?zoneId, keeps the answer, refreshes on '
        'config_published with doc content only', () async {
      final asked = <String>[];
      var items = [item('rider-banner-1')];
      final store = MemoryRiderContentStore();
      final c = RiderContentController(
        api: ApiClient(
          env: staging,
          client: MockClient((r) async {
            asked.add(r.url.toString());
            return http.Response(jsonEncode({'items': items}), 200);
          }),
        ),
        store: store,
        appVersion: '1.0.0',
        clock: () => now,
      );
      await c.start('Z001');
      expect(asked, [
        'https://api.movera.invalid/api/v1/rider/content?zoneId=Z001',
      ]);
      expect(c.banners.single.slot, 'rider-banner-1');
      expect(store.answers['Z001'], isNotNull);

      items = [item('rider-banner-2')];
      c.onConfigEvent({'kind': 'config_published', 'doc': 'rider_app_config'});
      await pumpEventQueue();
      expect(asked, hasLength(1));
      c.onConfigEvent({'kind': 'config_published', 'doc': 'content'});
      await pumpEventQueue();
      expect(asked, hasLength(2));
      expect(c.banners.single.slot, 'rider-banner-2');
    });

    test('offline: the kept answer is used', () async {
      final store = MemoryRiderContentStore()
        ..answers['Z001'] = {
          'items': [item('help')],
        };
      final c = RiderContentController(
        api: ApiClient(
          env: staging,
          client: MockClient((_) async => throw http.ClientException('off')),
        ),
        store: store,
        clock: () => now,
      );
      await c.start('Z001');
      expect(c.help?.title, 'T help');
    });

    test('demo (no api): no content and no gates', () async {
      final c = RiderContentController(clock: () => now);
      await c.start('Z001');
      expect(c.banners, isEmpty);
      expect(c.decision.blockForUpdate, isFalse);
      expect(c.decision.acceptTerms, isNull);
    });

    test('accept POSTs /account/terms/accept {contentVersion} and is kept; '
        'terms published later show at the next start', () async {
      final posts = <Map<String, Object?>>[];
      var items = [item('legal', version: 7, reaccept: true)];
      final store = MemoryRiderContentStore();
      final onTrip = ValueNotifier(false);
      ApiClient client() => ApiClient(
        env: staging,
        client: MockClient((r) async {
          if (r.method == 'POST') {
            expect(r.url.path, '/api/v1/account/terms/accept');
            expect(r.headers['Idempotency-Key'], isNotNull);
            posts.add(jsonDecode(r.body) as Map<String, Object?>);
            return http.Response('', 204);
          }
          return http.Response(jsonEncode({'items': items}), 200);
        }),
      );
      final c = RiderContentController(
        api: client(),
        store: store,
        onTrip: onTrip,
        clock: () => now,
      );
      await c.start('Z001');
      expect(c.decision.acceptTerms?.version, 7);
      onTrip.value = true;
      expect(c.decision.acceptTerms, isNull);
      onTrip.value = false;
      expect(await c.acceptTerms(), isTrue);
      expect(posts.single, {'contentVersion': 7});
      expect(c.decision.acceptTerms, isNull);
      expect(store.accepted, 7);

      items = [item('legal', version: 8, reaccept: true)];
      c.onConfigEvent({'kind': 'config_published', 'doc': 'content'});
      await pumpEventQueue();
      expect(c.decision.acceptTerms, isNull, reason: 'not mid-session');

      final next = RiderContentController(
        api: client(),
        store: store,
        clock: () => now,
      );
      await next.start('Z001');
      expect(next.decision.acceptTerms?.version, 8);
    });
  });
}
