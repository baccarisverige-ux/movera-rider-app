import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';

/// rider-u77: the sign-in buttons excluded the InkWell's semantics, which
/// is where the tap action lived, so TalkBack and VoiceOver announced a
/// button that a double-tap could not press.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, Widget button) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: button)),
    ),
  );

  SemanticsNode node(WidgetTester tester, String label) =>
      tester.getSemantics(find.bySemanticsLabel(label));

  void screenReaderTap(WidgetTester tester, String label) {
    tester.semantics.tap(find.semantics.byLabel(label));
  }

  testWidgets('Continue can be pressed with a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      AuthPrimaryButton(label: 'Continue', onPressed: () => taps++),
    );

    final button = node(tester, 'Continue');
    expect(button.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    screenReaderTap(tester, 'Continue');
    await tester.pump();
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('a disabled or busy button offers no tap', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      const AuthPrimaryButton(label: 'Verify', onPressed: null),
    );
    expect(
      node(tester, 'Verify').getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );

    await pump(
      tester,
      AuthPrimaryButton(label: 'Verify', busy: true, onPressed: () {}),
    );
    expect(
      node(tester, 'Verify').getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets('Continue with Apple can be pressed with a screen reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      AuthProviderButton(
        label: 'Apple',
        leading: const SizedBox(),
        onPressed: () => taps++,
      ),
    );

    final button = node(tester, 'Continue with Apple');
    expect(button.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    screenReaderTap(tester, 'Continue with Apple');
    await tester.pump();
    expect(taps, 1);
    semantics.dispose();
  });
}
