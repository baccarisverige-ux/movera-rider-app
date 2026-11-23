import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/finding_driver/presentation/price_bump_card.dart';

/// Owner 2026-11-23, approved raise-bid design R2: one card with a slider
/// from the fare to the zone ceiling, the zone's steps on the track, a
/// price bubble, "At most X", a black pill confirm; logic unchanged.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpCard(
    WidgetTester tester, {
    required List<int> confirmed,
    double current = 263,
    double max = 526,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: PriceBumpCard(
                currentPrice: current,
                maxPrice: max,
                steps: const [50, 100, 150, 200],
                onConfirm: confirmed.add,
                onKeepWaiting: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  Slider slider(WidgetTester t) => t.widget<Slider>(find.byType(Slider));

  testWidgets('one contained card: title, slider fare..ceiling, at most, '
      'nothing chosen and confirm disabled', (tester) async {
    final confirmed = <int>[];
    await pumpCard(tester, confirmed: confirmed);
    expect(find.byKey(const ValueKey('price-bump-card')), findsOneWidget);
    expect(find.text('Raise your offer'), findsOneWidget);
    expect(slider(tester).min, 263);
    expect(slider(tester).max, 526);
    expect(slider(tester).value, 263);
    expect(find.textContaining('At most 526,00 kr'), findsOneWidget);
    for (final label in ['263', '+50', '+100', '+150', '+200', '526']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.byType(TextField), findsNothing);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('price-bump-confirm')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Keep waiting'), findsOneWidget);
  });

  testWidgets('a step label snaps there; bubble shows price + difference', (
    tester,
  ) async {
    final confirmed = <int>[];
    await pumpCard(tester, confirmed: confirmed);
    await tester.tap(find.text('+50'));
    await tester.pump();
    expect(slider(tester).value, 313);
    expect(find.byKey(const ValueKey('price-bump-bubble')), findsOneWidget);
    expect(find.text('+50 kr'), findsOneWidget);
    await tester.tap(find.text('Confirm 313,00 kr'));
    await tester.pump();
    expect(confirmed, [50]);
  });

  testWidgets('dragging snaps near a step, any other whole krona is kept', (
    tester,
  ) async {
    final confirmed = <int>[];
    await pumpCard(tester, confirmed: confirmed);
    slider(tester).onChanged!(362.8);
    await tester.pump();
    expect(slider(tester).value, 363); // snapped to +100
    slider(tester).onChanged!(340.3);
    await tester.pump();
    expect(slider(tester).value, 340);
    expect(find.text('+77 kr'), findsOneWidget);
    await tester.tap(find.text('Confirm 340,00 kr'));
    await tester.pump();
    expect(confirmed, [77]);
  });
}
