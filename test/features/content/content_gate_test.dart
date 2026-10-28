import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/content/rider_content_controller.dart';
import 'package:movera_rider/features/content/presentation/content_banners.dart';
import 'package:movera_rider/features/content/presentation/content_gate.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.10.0 §19: the update block, the terms, the update messages
/// and the banners on screen.
void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.invalid',
  );
  final now = DateTime.utc(2026, 10, 28, 12);

  Map<String, Object?> item(String slot, {Map<String, Object?>? extra}) => {
    'slot': slot,
    'zoneId': 'Z001',
    'version': 3,
    'publishedAt': '2026-10-28T08:00:00Z',
    'title': 'Titel $slot',
    'text': {'sv': 'Text sv', 'fr': 'Texte fr', 'en': 'Text en'},
    ...?extra,
  };

  Map<String, Object?> versions(String min, String rec) => {
    'versions': {
      'rider': {'min': min, 'recommended': rec},
      'driver': {'min': '1.0.0', 'recommended': '1.0.0'},
    },
  };

  Future<RiderContentController> controller(
    List<Map<String, Object?>> items, {
    ValueNotifier<bool>? onTrip,
    int acceptStatus = 204,
  }) async {
    final c = RiderContentController(
      api: ApiClient(
        env: staging,
        client: MockClient(
          (r) async => r.method == 'POST'
              ? http.Response(
                  acceptStatus == 204 ? '' : '{"code":"unavailable"}',
                  acceptStatus,
                )
              : http.Response(jsonEncode({'items': items}), 200),
        ),
      ),
      store: MemoryRiderContentStore(),
      appVersion: '1.5.0',
      onTrip: onTrip,
      clock: () => now,
    );
    await c.start('Z001');
    return c;
  }

  Future<List<int>> pumpGate(
    WidgetTester tester,
    RiderContentController c, {
    String code = 'sv',
  }) async {
    L10n.use(code);
    final sos = <int>[];
    var store = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(code),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ContentGate(
          controller: c,
          onCallEmergency: () => sos.add(1),
          onOpenStore: () => store++,
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 120),
              ContentBanners(controller: c),
              TextButton(onPressed: () {}, child: const Text('Boka')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    return sos;
  }

  testWidgets('below min: full screen with store and 112, app blocked', (
    tester,
  ) async {
    final c = await tester.runAsync(
      () =>
          controller([item('app-versions', extra: versions('2.0.0', '2.0.0'))]),
    );
    final sos = await pumpGate(tester, c!);
    expect(find.text('Uppdatera appen'), findsOneWidget);
    expect(find.byKey(const Key('content-open-store')), findsOneWidget);
    await tester.tap(find.byKey(const Key('content-sos')));
    expect(sos, [1]);
    await tester.tap(find.text('Boka'), warnIfMissed: false);
    expect(find.byKey(const Key('content-update-required')), findsOneWidget);
  });

  testWidgets('below min during a trip: a small message, block after', (
    tester,
  ) async {
    final trip = ValueNotifier(true);
    final c = await tester.runAsync(
      () => controller([
        item('app-versions', extra: versions('2.0.0', '2.0.0')),
      ], onTrip: trip),
    );
    await pumpGate(tester, c!);
    expect(find.text('Uppdatera appen efter resan.'), findsOneWidget);
    expect(find.byKey(const Key('content-update-required')), findsNothing);
    trip.value = false;
    await tester.pump();
    expect(find.byKey(const Key('content-update-required')), findsOneWidget);
  });

  testWidgets('below recommended: a message the rider can close', (
    tester,
  ) async {
    final c = await tester.runAsync(
      () =>
          controller([item('app-versions', extra: versions('1.0.0', '1.9.0'))]),
    );
    await pumpGate(tester, c!, code: 'fr');
    expect(
      find.text('Une nouvelle version de Movera est disponible.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('content-update-close')));
    await tester.pump();
    expect(find.byKey(const Key('content-update-notice')), findsNothing);
  });

  testWidgets('terms with reaccept: the text and "Jag godkänner"', (
    tester,
  ) async {
    final c = await tester.runAsync(
      () => controller([
        item('legal', extra: {'reaccept': true}),
      ]),
    );
    await pumpGate(tester, c!);
    expect(find.text('Text sv'), findsOneWidget);
    expect(find.text('Jag godkänner'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('content-terms-accept')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byKey(const Key('content-terms')), findsNothing);
  });

  testWidgets('terms: a failed accept keeps the screen with a message', (
    tester,
  ) async {
    final c = await tester.runAsync(
      () => controller([
        item('legal', extra: {'reaccept': true}),
      ], acceptStatus: 503),
    );
    await pumpGate(tester, c!, code: 'en');
    expect(find.text('I accept'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('content-terms-accept')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byKey(const Key('content-terms')), findsOneWidget);
    expect(find.text('Could not save your answer. Try again.'), findsOneWidget);
  });

  testWidgets('terms are not shown during a trip', (tester) async {
    final c = await tester.runAsync(
      () => controller([
        item('legal', extra: {'reaccept': true}),
      ], onTrip: ValueNotifier(true)),
    );
    await pumpGate(tester, c!);
    expect(find.byKey(const Key('content-terms')), findsNothing);
  });

  testWidgets('banners: title and text in the rider language', (tester) async {
    final c = await tester.runAsync(
      () => controller([item('rider-banner-2'), item('rider-banner-1')]),
    );
    await pumpGate(tester, c!, code: 'fr');
    expect(find.text('Texte fr'), findsNWidgets(2));
    expect(find.byKey(const Key('content-banners')), findsOneWidget);
  });

  test('store page per platform', () {
    expect(storeUrl(TargetPlatform.android), contains('com.movera.rider'));
    expect(storeUrl(TargetPlatform.iOS), startsWith('https://apps.apple.com'));
  });
}
