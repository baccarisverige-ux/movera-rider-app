import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

/// NAV-13: pushed pages support the iOS edge swipe-back; a page that opts
/// out with PopScope(canPop: false) keeps it disabled.
void main() {
  Future<void> openPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(RightToLeftTransition<void>(page)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> edgeSwipe(WidgetTester tester) async {
    final gesture = await tester.startGesture(const Offset(4, 300));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('iOS: edge swipe goes back from a pushed page', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await openPage(tester, const Scaffold(body: Text('menu-page')));
    expect(find.text('menu-page'), findsOneWidget);
    await edgeSwipe(tester);
    expect(find.text('menu-page'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS: a page that blocks pop keeps the swipe disabled', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await openPage(
      tester,
      const PopScope(canPop: false, child: Scaffold(body: Text('ride-page'))),
    );
    await edgeSwipe(tester);
    expect(find.text('ride-page'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
