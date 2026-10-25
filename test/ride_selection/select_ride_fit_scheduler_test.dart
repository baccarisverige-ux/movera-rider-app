import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_fit_scheduler.dart';

/// Owner (iPhone PWA): sliding the categories sheet up and down many times
/// started a camera flight per settle until Safari reloaded the tab.
void main() {
  late List<String> flown;
  late String key;
  Completer<void>? landing;

  RouteFitScheduler scheduler() => RouteFitScheduler(
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

  test('Select ride routes settles through the scheduler', () {
    final src = File(
      'lib/features/ride_selection/presentation/select_ride.dart',
    ).readAsStringSync();
    expect(src, contains('_fits.settled();'));
    expect(src, contains('_fitRoute(force: true)'));
    // The web overlay waits for the settle instead of flipping mid-drag.
    expect(src, contains('if (_sheetDragging) return;'));
  });
}
