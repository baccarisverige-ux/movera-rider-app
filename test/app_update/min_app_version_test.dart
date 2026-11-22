import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/app_update/min_app_version.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';
import 'package:movera_rider/core/content/rider_content_controller.dart';
import 'package:movera_rider/features/content/presentation/content_gate.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.154 P16c (`contract.json#appUpdate`; owner 2026-11-21
/// "Yes, build it now (Recommended)"). Fails on main: no minimum per
/// platform exists, so nothing blocks and no X-App-Version is sent.
void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.invalid',
  );
  const store = 'https://apps.apple.com/app/example-fake';
  Map<String, Object?> doc(Object? android, {Object? ios, Object? url}) => {
    'minimumVersion': '9.0.0',
    'latestVersion': '9.0.0',
    'minVersion': {'android': android, 'ios': ios},
    'storeUrls': {'android': url, 'ios': null},
  };

  setUp(() {
    MinAppVersion.reset();
    MinAppVersion.running = '1.4.0';
    MinAppVersion.platform = 'android';
  });
  tearDown(MinAppVersion.reset);

  group('rule', () {
    test('below blocks; equal, above, another platform and off do not', () {
      MinAppVersion.accept(doc('1.4.1'));
      expect(MinAppVersion.required, isTrue);
      MinAppVersion.accept(doc('1.4.0'));
      expect(MinAppVersion.required, isFalse);
      MinAppVersion.accept(doc('1.3.9'));
      expect(MinAppVersion.required, isFalse);
      MinAppVersion.accept(doc(null, ios: '5.0.0'));
      expect(MinAppVersion.required, isFalse);
      MinAppVersion.accept(null);
      expect(MinAppVersion.required, isFalse);
    });

    test('the older keys and bad values never block', () {
      MinAppVersion.accept({'minimumVersion': '9.0.0'});
      expect(MinAppVersion.required, isFalse);
      for (final bad in ['1.5', 'v2.0.0', 2]) {
        MinAppVersion.accept(doc(bad));
        expect(MinAppVersion.required, isFalse, reason: '$bad');
      }
    });

    test('a dev or web build is never blocked and sends no header', () {
      MinAppVersion.accept(doc('9.0.0'));
      expect(MinAppVersion.headers, {
        'X-App-Version': '1.4.0',
        'X-App-Platform': 'android',
      });
      MinAppVersion.running = null;
      expect(MinAppVersion.required, isFalse);
      expect(MinAppVersion.headers, isEmpty);
      MinAppVersion.running = '1.0.0';
      MinAppVersion.platform = null;
      expect(MinAppVersion.required, isFalse);
      expect(MinAppVersion.headers, isEmpty);
    });

    test('the store link: the zone\'s for this platform, else built-in', () {
      MinAppVersion.platform = 'android';
      MinAppVersion.accept(doc('2.0.0', url: store));
      expect(
        MinAppVersion.storeUri('https://fallback.example/r'),
        Uri.parse(store),
      );
      MinAppVersion.platform = 'ios';
      expect(
        MinAppVersion.storeUri('https://fallback.example/r'),
        Uri.parse('https://fallback.example/r'),
      );
    });
  });

  group('wire', () {
    test('GET /rider/config: the zone\'s appUpdate becomes the rule', () async {
      final api = ApiClient(
        env: staging,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'version': 4,
              'zoneId': 'Z001',
              'currency': 'SEK',
              'appUpdate': doc('1.5.0'),
            }),
            200,
          ),
        ),
      );
      final repo = ApiRiderConfigRepository(
        api: api,
        cache: MemoryRiderConfigCache(),
        homeZoneId: 'Z001',
      );
      await repo.refresh('Z001');
      expect(MinAppVersion.rule.value.minVersion['android'], '1.5.0');
      expect(MinAppVersion.required, isTrue);
      repo.dispose();
    });

    test('calls carry the two headers; a 426 raises the block', () async {
      final seen = <Map<String, String>>[];
      final api = ApiClient(
        env: staging,
        client: MockClient((request) async {
          seen.add(request.headers);
          return http.Response(
            jsonEncode({
              'code': 'upgrade_required',
              'message': 'Update Movera to continue.',
              'requestId': 'r1',
              'retryable': false,
              'reason': 'app_update_required',
            }),
            426,
          );
        }),
      );
      await expectLater(
        api.post('/api/v1/trips', body: {'quoteId': 'q1'}),
        throwsA(isA<ApiError>()),
      );
      expect(seen.single['X-App-Version'], '1.4.0');
      expect(seen.single['X-App-Platform'], 'android');
      expect(MinAppVersion.required, isTrue);
    });
  });

  group('screen', () {
    Future<int Function()> pumpGate(
      WidgetTester tester,
      ValueNotifier<bool> onTrip,
    ) async {
      L10n.use('en');
      var opened = 0;
      final c = RiderContentController(onTrip: onTrip);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => ContentGate(
            controller: c,
            onCallEmergency: () {},
            onOpenStore: () => opened++,
            child: child!,
          ),
          home: const Scaffold(body: Text('Home')),
        ),
      );
      await tester.pump();
      return () => opened;
    }

    const screen = Key('min-version-required');

    testWidgets('below: "Update Movera to continue"; Update opens the store', (
      tester,
    ) async {
      MinAppVersion.accept(doc('1.5.0'));
      final opened = await pumpGate(tester, ValueNotifier(false));
      expect(find.byKey(screen), findsOneWidget);
      expect(find.text('Update Movera to continue'), findsOneWidget);
      expect(find.byKey(const Key('content-sos')), findsOneWidget);
      await tester.tap(find.byKey(const Key('min-version-update')));
      expect(opened(), 1);
    });

    testWidgets('never during a live ride: a small line, the block after', (
      tester,
    ) async {
      MinAppVersion.accept(doc('1.5.0'));
      final onTrip = ValueNotifier(true);
      await pumpGate(tester, onTrip);
      expect(find.byKey(screen), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      onTrip.value = false;
      await tester.pump();
      expect(find.byKey(screen), findsOneWidget);
    });

    testWidgets('it goes away only when a document says the version is OK', (
      tester,
    ) async {
      MinAppVersion.accept(doc('1.5.0'));
      await pumpGate(tester, ValueNotifier(false));
      expect(find.byKey(screen), findsOneWidget);
      MinAppVersion.accept(doc('1.4.0'));
      await tester.pump();
      expect(find.byKey(screen), findsNothing);
    });
  });
}
