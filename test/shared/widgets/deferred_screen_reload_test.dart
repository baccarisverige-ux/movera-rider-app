import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/shared/widgets/deferred_screen.dart';

/// 2026-11-11 (owner "Yes, fix it"): on the web a publish while the page is
/// open replaces the screen parts, loadLibrary fails with "the code with hash
/// ... was not loaded", and loading again fetches the same file. Only a page
/// reload recovers. Phones keep the plain retry.
void main() {
  late int autoReloads;
  late int retryReloads;
  late bool autoResult;

  setUp(() {
    autoReloads = 0;
    retryReloads = 0;
    autoResult = true;
    DeferredScreen.reloadOnce = () {
      autoReloads += 1;
      return autoResult;
    };
    DeferredScreen.reloadNow = () {
      retryReloads += 1;
      return true;
    };
  });

  tearDown(() => DeferredScreen.isWeb = false);

  Future<int> pumpFailing(WidgetTester tester) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DeferredScreen(
          load: () async {
            loads += 1;
            throw StateError("the code with hash 'x' was not loaded");
          },
          builder: (_) => const Text('screen'),
        ),
      ),
    );
    await tester.pump();
    return loads;
  }

  testWidgets('web: a failed part reloads the page once, spinner stays', (
    tester,
  ) async {
    DeferredScreen.isWeb = true;
    await pumpFailing(tester);
    expect(autoReloads, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('deferred-screen-retry')), findsNothing);
  });

  testWidgets('web: guard says no -> Retry reloads the page, no reload loop', (
    tester,
  ) async {
    DeferredScreen.isWeb = true;
    autoResult = false;
    final loads = await pumpFailing(tester);
    expect(autoReloads, 1);
    await tester.tap(find.byKey(const ValueKey('deferred-screen-retry')));
    await tester.pump();
    expect(retryReloads, 1);
    expect(loads, 1, reason: 'Retry must not fetch the same part again');
    expect(autoReloads, 1);
  });

  testWidgets('web Retry: the spinner shows while the page reloads', (
    tester,
  ) async {
    // The reload first downloads the app shell fresh (up to a few seconds);
    // the retry icon must not stay on screen as if nothing happened.
    DeferredScreen.isWeb = true;
    autoResult = false;
    await pumpFailing(tester);
    await tester.tap(find.byKey(const ValueKey('deferred-screen-retry')));
    await tester.pump();
    expect(retryReloads, 1);
    expect(find.byKey(const ValueKey('deferred-screen-retry')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('phones: no reload, Retry loads the part again', (tester) async {
    DeferredScreen.isWeb = false;
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DeferredScreen(
          load: () async {
            loads += 1;
            if (loads == 1) throw StateError('offline');
          },
          builder: (_) => const Text('screen'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('deferred-screen-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.text('screen'), findsOneWidget);
    expect(loads, 2);
    expect(autoReloads + retryReloads, 0);
  });
}
