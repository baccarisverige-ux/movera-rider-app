import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/movera_scroll_behavior.dart';

/// Owner 2026-11-24: every rider screen, under iOS, stops at its edges. Each
/// kind of scroll view the app uses is pulled past its top and its end; the
/// content must not move away from the edge (no band under a bottom bar, no
/// content under the status bar).
void main() {
  Widget rows() => Column(
    children: List.generate(
      30,
      (i) => SizedBox(height: 50, child: Text('r$i')),
    ),
  );
  final kinds = <String, Widget Function(ScrollController)>{
    'ListView': (c) => ListView(controller: c, children: [rows()]),
    'SingleChildScrollView': (c) =>
        SingleChildScrollView(controller: c, child: rows()),
    'CustomScrollView': (c) => CustomScrollView(
      controller: c,
      slivers: [SliverToBoxAdapter(child: rows())],
    ),
    'GridView': (c) => GridView.count(
      controller: c,
      crossAxisCount: 1,
      childAspectRatio: 8,
      children: List.generate(30, (i) => Text('r$i')),
    ),
    'AlwaysScrollable ListView': (c) => ListView(
      controller: c,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [rows()],
    ),
  };

  for (final e in kinds.entries) {
    testWidgets('${e.key} with a bottom bar clamps on iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final c = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const MoveraScrollBehavior(),
          home: Scaffold(
            body: e.value(c),
            bottomNavigationBar: const SizedBox(
              key: Key('nav'),
              height: 60,
              child: ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      );
      final screenH =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final g = await tester.startGesture(const Offset(200, 200));
      await g.moveBy(const Offset(0, 400));
      await tester.pump();
      expect(c.offset, 0, reason: 'pulled past its top');
      await g.up();
      await tester.pumpAndSettle();
      c.jumpTo(c.position.maxScrollExtent);
      await tester.pump();
      final g2 = await tester.startGesture(const Offset(200, 300));
      await g2.moveBy(const Offset(0, -400));
      await tester.pump();
      expect(c.offset, c.position.maxScrollExtent, reason: 'pushed past end');
      expect(
        tester.getBottomLeft(find.byKey(const Key('nav'))).dy,
        closeTo(screenH, 0.5),
      );
      await g2.up();
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('DraggableScrollableSheet never passes its max on iOS', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final dc = DraggableScrollableController();
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const MoveraScrollBehavior(),
        home: Scaffold(
          body: DraggableScrollableSheet(
            controller: dc,
            initialChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (context, sc) =>
                ListView(controller: sc, children: [rows()]),
          ),
        ),
      ),
    );
    final g = await tester.startGesture(const Offset(200, 500));
    for (var i = 0; i < 60; i++) {
      await g.moveBy(const Offset(0, -20));
      await tester.pump();
      expect(dc.size, lessThanOrEqualTo(0.9 + 1e-6));
    }
    await g.moveBy(const Offset(0, 2000));
    await tester.pump();
    expect(dc.size, greaterThanOrEqualTo(0.0));
    await g.up();
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
