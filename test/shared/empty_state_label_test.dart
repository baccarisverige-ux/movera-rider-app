import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';

/// D7 (V39-4b): the screen-reader label joins title and message with ". "
/// only when the title does not already end a sentence.
void main() {
  Future<String?> labelOf(WidgetTester tester, String title) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoveraEmptyState(
            icon: Icons.inbox,
            title: title,
            message: 'Try again later.',
          ),
        ),
      ),
    );
    final node = tester.getSemantics(find.byType(MoveraEmptyState));
    return node.label;
  }

  testWidgets('no double stop after . ! ? (any language)', (tester) async {
    for (final title in [
      'Nothing here.',
      'Inga resor än!',
      'Pas de trajet ?',
      'Nothing yet…',
      '没有行程。',
    ]) {
      final label = await labelOf(tester, title);
      expect(label, '$title Try again later.', reason: title);
    }
  });

  testWidgets('a title without a stop gets ". "', (tester) async {
    expect(await labelOf(tester, 'No trips'), 'No trips. Try again later.');
  });
}
