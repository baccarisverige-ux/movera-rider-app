import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/presentation/auth_navigation.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';

/// rider-30: a number pasted in international form (+46 ...) lost its '+',
/// was cut at 14 characters, and the remaining "46..." got a second +46:
/// either refused as invalid or, spaced, accepted as a wrong number that
/// the code was sent to.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('swedishNumberFromField', () {
    test('reads the international forms as the same number', () {
      expect(swedishNumberFromField('+46 70 123 45 67'), '+46701234567');
      expect(swedishNumberFromField('+46701234567'), '+46701234567');
      expect(swedishNumberFromField('0046 70 123 45 67'), '+46701234567');
      expect(swedishNumberFromField('46 70 123 45 67'), '+46701234567');
      expect(swedishNumberFromField('46701234567'), '+46701234567');
    });

    test('keeps the national forms and never doubles the country code', () {
      expect(swedishNumberFromField('70 123 45 67'), '+46701234567');
      expect(swedishNumberFromField('070 123 45 67'), '+46701234567');
      // A cut-short paste is refused, not sent to +46 46 ...
      expect(swedishNumberFromField('46 70 123 45 6'), isNull);
    });
  });

  group('AuthPhoneField', () {
    Future<TextEditingController> pump(WidgetTester tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuthPhoneField(controller: controller, focusNode: focus),
          ),
        ),
      );
      return controller;
    }

    for (final pasted in const [
      '+46 70 123 45 67',
      '+46701234567',
      '0046 70 123 45 67',
      '46 70 123 45 67',
      '+46 (0)70 123 45 67',
    ]) {
      testWidgets('a pasted "$pasted" becomes the national number', (
        tester,
      ) async {
        final controller = await pump(tester);

        await tester.enterText(find.byType(TextField), pasted);
        await tester.pump();

        expect(swedishNumberFromField(controller.text), '+46701234567');
        expect(controller.text, isNot(contains('46 7')));
      });
    }

    testWidgets('typed national numbers are unchanged', (tester) async {
      final controller = await pump(tester);

      await tester.enterText(find.byType(TextField), '070 123 45 67');
      await tester.pump();

      expect(controller.text, '070 123 45 67');
    });
  });
}
