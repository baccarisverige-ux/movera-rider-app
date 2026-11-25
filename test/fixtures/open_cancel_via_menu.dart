import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner 2026-11-23: on screens 2 and 3 the top-left ✕ is gone; cancelling
/// (before pickup) and ending (on board) are the last red row of the ⋯
/// menu (the driver card's, else the ride card's). Opens that row the way
/// a rider does. On the searching screen, which keeps its ✕, the ✕.
Future<void> openCancelViaMenu(WidgetTester tester) async {
  final close = find.byIcon(Icons.close_rounded);
  if (close.evaluate().isNotEmpty) {
    await tester.tap(close.first);
    return;
  }
  // A driver-arrived popup still open is closed first (as the rider does).
  final arrived = find.byKey(const ValueKey('driver-arrived-on-way'));
  if (arrived.evaluate().isNotEmpty) {
    Navigator.of(tester.element(arrived)).pop();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  final key = find.byKey(const ValueKey('waiting-more'));
  if (key.evaluate().isNotEmpty) {
    // The driver card's ⋯ (an InkWell): pressed as the rider would, also
    // when a small test view keeps it below the fold.
    tester.widget<InkWell>(key.first).onTap!();
  } else {
    final more = find.byIcon(Icons.more_horiz_rounded).first;
    await tester.ensureVisible(more);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(more);
  }
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(find.byKey(const ValueKey('ride-details-cancel')));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
