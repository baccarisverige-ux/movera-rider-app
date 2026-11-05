import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/calls/domain/trip_call_session.dart';
import 'package:movera_rider/features/calls/presentation/call_screen.dart';

import 'in_app_call_test.dart' show FakeApi, FakeEngine;

/// Job 8 screenshot check (2026-11-05): on the failed call screen Mute / End
/// / Speaker still looked active.
Widget _app(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('failed call: Mute / End / Speaker look disabled', (
    tester,
  ) async {
    final bad = TripCallSession.outgoing(
      api: FakeApi()..startError = StateError('x'),
      engine: FakeEngine(),
      tripId: 't1',
      side: 'rider',
    );
    await tester.runAsync(bad.start);
    await tester.pumpWidget(_app(TripCallScreen(session: bad)));
    await tester.pump();
    for (final key in ['call-mute', 'call-end', 'call-speaker']) {
      final button = find.byKey(ValueKey<String>(key));
      expect(tester.widget<IconButton>(button).onPressed, isNull);
      final material = tester.widget<Material>(
        find.ancestor(of: button, matching: find.byType(Material)).first,
      );
      expect(material.color, TripCallScreen.disabledColor, reason: key);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
