import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

/// Phase 133: support.dart's 16 menu entries all pushed with no guard, and
/// each lives in a different StatelessWidget with nowhere to store an
/// in-flight flag. [guardedPush] closes that gap without new state: a
/// route's [ModalRoute.isCurrent] flips to false the instant a push
/// happens, before any animation, so a same-frame double-tap is caught.
void main() {
  testWidgets('a double-tap only pushes once', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var pushes = 0;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => guardedPush(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) {
                      pushes++;
                      return const Scaffold(body: Text('pushed'));
                    },
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    final button = find.text('go');
    await tester.tap(button, warnIfMissed: false);
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(pushes, 1);
    expect(find.text('pushed'), findsOneWidget);
  });

  testWidgets('a tap after the pushed route pops can push again', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var pushes = 0;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => guardedPush(
                  context,
                  MaterialPageRoute<void>(
                    builder: (routeContext) {
                      pushes++;
                      return Scaffold(
                        body: TextButton(
                          onPressed: () => Navigator.pop(routeContext),
                          child: const Text('back'),
                        ),
                      );
                    },
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(pushes, 2);
  });
}
