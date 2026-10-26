import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/finding_driver/presentation/price_bump_card.dart';

/// rider-r5-13: a step on a fare with cents never writes '26.60' into the
/// whole-units field, which the next keystroke turned into '266'.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a step on 24,60 € keeps the field whole-unit', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PriceBumpCard(
              currentPrice: 24.6,
              maxPrice: 44,
              currency: 'EUR',
              steps: const [1, 2, 4],
              onConfirm: (_) {},
              onConfirmIncrease: (_) {},
              onKeepWaiting: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('+2 €'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isNot(contains('.')));
    expect(find.text('Confirm 26,60 €'), findsOneWidget);
  });
}
