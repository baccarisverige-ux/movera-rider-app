import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/app_start.dart';

/// Owner job "Fast start behind the intro" (REMINDERS 144/145): what starts
/// with the intro (position search, map load) starts before the boot steps
/// and the first screen, and never makes them wait.
void main() {
  test('early work starts first, the first screen comes after the boot '
      'steps, and nothing waits for the early work', () async {
    final log = <String>[];
    final bootGate = Completer<void>();
    final start = runAppStart(
      early: () {
        log.add('early');
        // Like a slow GPS: never finishes during the start.
        unawaited(Completer<void>().future);
      },
      boot: () async {
        log.add('boot');
        await bootGate.future;
        log.add('boot done');
      },
      firstScreen: () => log.add('first screen'),
    );
    await pumpEventQueue();
    expect(log, ['early', 'boot'], reason: 'early work after the boot steps');
    bootGate.complete();
    await start.timeout(const Duration(seconds: 1));
    expect(log, ['early', 'boot', 'boot done', 'first screen']);
  });
}
