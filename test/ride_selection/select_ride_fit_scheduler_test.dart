import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_fit_scheduler.dart';

/// Owner (iPhone PWA): sliding the categories sheet up and down many times
/// started a camera flight per settle until Safari reloaded the tab.
void main() {
  late List<String> flown;
  late String key;
  Completer<void>? landing;

  var owned = true;

  RouteFitScheduler scheduler() => RouteFitScheduler(
    mayMove: () => owned,
    plan: () {
      final at = key;
      return (
        key: at,
        move: () {
          flown.add(at);
          return landing?.future ?? Future<void>.value();
        },
      );
    },
  );

  setUp(() {
    flown = [];
    key = 'mid';
    landing = null;
    owned = true;
  });

  testWidgets('repeated settles at the same stop fly once', (tester) async {
    final fits = scheduler();
    for (var i = 0; i < 5; i++) {
      fits.settled();
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(flown, ['mid']);
  });

  testWidgets('rapid settles are debounced to the last stop', (tester) async {
    final fits = scheduler();
    for (final stop in ['full', 'mid', 'low', 'full', 'mid', 'low']) {
      key = stop;
      fits.settled();
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(flown, isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    expect(flown, ['low']);
  });

  testWidgets('back at the framing already shown: no new flight', (
    tester,
  ) async {
    final fits = scheduler();
    fits.settled();
    await tester.pump(const Duration(milliseconds: 300));
    key = 'full';
    fits.settled();
    await tester.pump(const Duration(milliseconds: 100));
    key = 'mid';
    fits.settled();
    await tester.pump(const Duration(milliseconds: 300));
    expect(flown, ['mid']);
  });

  testWidgets('no new fit starts while one is flying; the latest runs after', (
    tester,
  ) async {
    final fits = scheduler();
    landing = Completer<void>();
    unawaited(fits.fit());
    await tester.pump();
    key = 'full';
    unawaited(fits.fit());
    key = 'low';
    unawaited(fits.fit());
    await tester.pump();
    expect(flown, ['mid']);
    final first = landing!;
    landing = null;
    first.complete();
    await tester.pump();
    expect(flown, ['mid', 'low']);
  });

  testWidgets('a flight that never lands stops blocking after its limit', (
    tester,
  ) async {
    final fits = scheduler();
    landing = Completer<void>();
    unawaited(fits.fit());
    await tester.pump();
    landing = null;
    key = 'full';
    unawaited(fits.fit());
    await tester.pump(const Duration(seconds: 5));
    expect(flown, ['mid', 'full']);
  });

  testWidgets('force flies an unchanged framing (a new map)', (tester) async {
    final fits = scheduler();
    unawaited(fits.fit());
    unawaited(fits.fit());
    await tester.pump();
    unawaited(fits.fit(force: true));
    await tester.pump();
    expect(flown, ['mid', 'mid']);
  });

  testWidgets('dispose cancels a pending settle', (tester) async {
    final fits = scheduler();
    fits.settled();
    fits.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(flown, isEmpty);
  });

  // Confirm and search: Set pickup's map is on top, so no path may fly.
  testWidgets('another screen owns the map: a settle does not fly', (
    tester,
  ) async {
    final fits = scheduler();
    owned = false;
    fits.settled();
    await tester.pump(const Duration(seconds: 1));
    expect(flown, isEmpty);
    owned = true;
    fits.settled();
    await tester.pump(const Duration(seconds: 1));
    expect(flown, ['mid'], reason: 'the same framing flies once it is back');
    fits.dispose();
  });

  testWidgets('another screen takes the map mid-flight: the queued '
      're-run does not fly', (tester) async {
    final fits = scheduler();
    landing = Completer<void>();
    unawaited(fits.fit());
    await tester.pump();
    key = 'top';
    unawaited(fits.fit());
    owned = false;
    landing!.complete();
    await tester.pump(const Duration(milliseconds: 10));
    expect(flown, ['mid']);
    fits.dispose();
  });

  testWidgets('another screen owns the map: a call does not fly', (
    tester,
  ) async {
    final fits = scheduler();
    owned = false;
    await fits.fit(force: true);
    expect(flown, isEmpty);
    fits.dispose();
  });
}
