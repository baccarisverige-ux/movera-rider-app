import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/bootstrap.dart';

/// Crash fix (rider TestFlight "Zone mismatch", Rules LAUNCH-RULE.md
/// 2026-11-24): `WidgetsFlutterBinding.ensureInitialized()` ran in the start
/// zone and runApp inside a second zone (`runZonedGuarded`), so Flutter
/// reported "Zone mismatch" and the crash catcher sent it as a crash. The
/// test binding skips Flutter's own zone check, so this test pins the cause.
void main() {
  test('the first screen runs in the zone that made the binding', () {
    final start = Zone.current;
    Zone? shown;
    runFirstScreen(() => shown = Zone.current);
    expect(identical(shown, start), isTrue);
  });
}
