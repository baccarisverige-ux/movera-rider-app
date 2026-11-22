import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Text entry for the device suite that works in every build mode.
///
/// `tester.enterText` does NOT work on a profile build (driver run
/// 44965447102, 2026-11-22: SIGN-IN "Enter a valid mobile number." with an
/// empty field). The integration-test binding does not register the test
/// keyboard (`registerTestTextInput => false`), so `enterText` sends the
/// new text with the client id -1. The framework takes -1 only inside an
/// `assert` (flutter/lib/src/services/text_input.dart, "In debug builds we
/// allow -1 as a magical client ID"); a profile or release build drops the
/// message without a word, and the field stays empty.
///
/// These helpers hand the value to the field itself, through the same
/// [TextInputClient] methods the keyboard's messages end in, so the field's
/// input formatters, `onChanged` and `onSubmitted` run as for typing.
/// The same file in the rider and the driver repo.
EditableTextState _editable(WidgetTester tester, Finder finder) =>
    tester.state<EditableTextState>(
      find.descendant(
        of: finder,
        matching: find.byType(EditableText),
        matchRoot: true,
      ),
    );

/// Focuses the field [finder] and replaces its text with [text].
Future<void> typeText(WidgetTester tester, Finder finder, String text) async {
  await tester.showKeyboard(finder);
  _editable(tester, finder).updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
  await tester.idle();
}

/// The keyboard's action key ([action]: send, done, ...) on [finder].
Future<void> sendTextAction(
  WidgetTester tester,
  Finder finder,
  TextInputAction action,
) async {
  _editable(tester, finder).performAction(action);
  await tester.idle();
}
