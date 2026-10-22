import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/auth/presentation/widgets/movera_wordmark.dart';

// Owner round 3: one Movera wordmark, the same on every sign-in screen.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('the pin keeps the approved proportions at any size', () {
    for (final size in [13.0, 27.0, 46.0]) {
      final l = MoveraWordmark.layout(size);
      // Top of the pin on the x-height, tip 0.17 em under the baseline.
      expect(
        l.pinRect.top,
        closeTo(l.baseline - MoveraPin.xHeight * size, 0.01),
      );
      expect(
        l.pinRect.bottom,
        closeTo(l.baseline + MoveraPin.tipBelowBaseline * size, 0.01),
      );
      expect(l.pinRect.width / l.pinRect.height, closeTo(32 / 42, 0.001));
      // The same air on both sides of the pin.
      expect(l.pinRect.left - l.mLeft, greaterThan(0));
      expect(l.veraLeft - l.pinRect.right, closeTo(MoveraPin.gap * size, 0.01));
    }
  });

  test('a bigger wordmark is the small one scaled, not another drawing', () {
    final small = MoveraWordmark.layout(23);
    final big = MoveraWordmark.layout(46);
    expect(big.pinRect.height / small.pinRect.height, closeTo(2, 0.01));
    expect(big.pinRect.width / small.pinRect.width, closeTo(2, 0.01));
    expect(big.size.width / small.size.width, closeTo(2, 0.05));
  });

  test(
    'the pin path has a real hole and the pin colour is the sign-in ink',
    () {
      final path = MoveraPin.withHole();
      expect(path.fillType, PathFillType.evenOdd);
      expect(path.contains(const Offset(16, 16)), isFalse, reason: 'the hole');
      expect(path.contains(const Offset(16, 28)), isTrue, reason: 'the body');
      expect(path.contains(const Offset(16, 41)), isTrue, reason: 'the tip');
      expect(AuthColors.ink, const Color(0xFF111214));
      expect(AuthColors.green, const Color(0xFF147A50));
    },
  );

  testWidgets('the widget lays "M", the pin and "vera" out as measured', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: MoveraWordmark(size: 40))),
      ),
    );
    final l = MoveraWordmark.layout(40);
    final box = tester.getRect(find.byType(MoveraWordmark));
    expect(box.size.width, closeTo(l.size.width, 0.01));
    expect(box.size.height, 40);
    final pin = tester.getRect(
      find.descendant(
        of: find.byType(MoveraWordmark),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(pin.left - box.left, closeTo(l.pinRect.left, 0.01));
    expect(pin.top - box.top, closeTo(l.pinRect.top, 0.01));
    expect(find.text('M'), findsOneWidget);
    expect(find.textContaining('era', findRichText: true), findsOneWidget);
    // "era" is green, the rest ink.
    final rich = tester.widget<RichText>(
      find.textContaining('era', findRichText: true),
    );
    final colours = <String, Color?>{};
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        colours[span.text!] = span.style?.color;
      }
      return true;
    });
    expect(colours['v'], AuthColors.ink);
    expect(colours['era'], AuthColors.green);
  });

  testWidgets(
    'the small green dot sits in the hole, and can wait for the balloon',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: MoveraWordmark(size: 40))),
        ),
      );
      final dot = find.byKey(const ValueKey('movera-dot'));
      expect(tester.widget<AnimatedScale>(dot).scale, 1);
      final l = MoveraWordmark.layout(40);
      final box = tester.getRect(find.byType(MoveraWordmark));
      final rect = tester.getRect(dot);
      // Centred on the pin's head, well inside the hole.
      final pinScale = l.pinRect.height / MoveraPin.designSize.height;
      expect(
        rect.center - box.topLeft,
        offsetMoreOrLessEquals(
          l.pinRect.topLeft + MoveraPin.headCentre * pinScale,
          epsilon: 0.01,
        ),
      );
      expect(rect.width / 2, closeTo(MoveraPin.dotRadius * pinScale, 0.01));
      expect(MoveraPin.dotRadius, lessThan(MoveraPin.holeRadius));
      expect(MoveraPin.dotColor, AuthColors.green);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: MoveraWordmark(size: 40, showDot: false)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(dot).scale, 0);
      expect(MoveraWordmark.dotPop.inMilliseconds, inInclusiveRange(150, 400));
    },
  );
}
