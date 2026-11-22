import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/staging/type_text.dart';

/// Driver profile run 44965447102 (2026-11-22): `tester.enterText` left the
/// phone field empty on a profile build (the framework drops its client id
/// -1 outside debug), so SIGN-IN failed. The device suite types through
/// [typeText] / [sendTextAction], which do not depend on the build mode.
void main() {
  testWidgets('typeText: formatters and onChanged run, the text is set', (
    tester,
  ) async {
    final controller = TextEditingController();
    final changed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            key: const ValueKey('field'),
            controller: controller,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: changed.add,
          ),
        ),
      ),
    );
    await typeText(tester, find.byKey(const ValueKey('field')), '+46 70x1');
    await tester.pump();
    expect(controller.text, '46701');
    expect(changed, ['46701']);
    // A second entry replaces the first.
    await typeText(tester, find.byType(EditableText), '12');
    expect(controller.text, '12');
  });

  testWidgets('sendTextAction: the action key reaches onSubmitted', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            textInputAction: TextInputAction.send,
            onSubmitted: sent.add,
          ),
        ),
      ),
    );
    await typeText(tester, find.byType(TextField), 'hello');
    await sendTextAction(tester, find.byType(TextField), TextInputAction.send);
    await tester.pump();
    expect(sent, ['hello']);
  });
}
