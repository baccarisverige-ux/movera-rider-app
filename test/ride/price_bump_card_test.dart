import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/finding_driver/presentation/price_bump_card.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    required List<int> confirmed,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PriceBumpCard(
              currentPrice: 259,
              maxPrice: 466,
              steps: const [50, 100, 150, 200],
              onConfirm: confirmed.add,
              onKeepWaiting: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Set new price stays disabled until a higher offer is chosen', (
    tester,
  ) async {
    final confirmed = <int>[];
    await pumpCard(tester, confirmed: confirmed);
    final confirm = find.text('Set new price');
    expect(confirm, findsOneWidget);
    await tester.tap(confirm);
    await tester.pump();
    expect(confirmed, isEmpty);
  });

  testWidgets('preset chip confirms the increase on the same ride', (
    tester,
  ) async {
    final confirmed = <int>[];
    await pumpCard(tester, confirmed: confirmed);
    await tester.tap(find.text('+100 kr'));
    await tester.pump();
    expect(find.text('Confirm 359 kr'), findsOneWidget);
    await tester.tap(find.text('Confirm 359 kr'));
    await tester.pump();
    expect(confirmed, [100]);
  });

  testWidgets('typed price confirms the extra kr', (tester) async {
    final confirmed = <int>[];
    await pumpCard(tester, confirmed: confirmed);
    await tester.enterText(find.byType(TextField), '340');
    await tester.pump();
    expect(find.text('Confirm 340 kr'), findsOneWidget);
    await tester.tap(find.text('Confirm 340 kr'));
    await tester.pump();
    expect(confirmed, [81]);
  });

  testWidgets('typed price at or below current does not confirm', (
    tester,
  ) async {
    final confirmed = <int>[];
    await pumpCard(tester, confirmed: confirmed);
    await tester.enterText(find.byType(TextField), '259');
    await tester.pump();
    expect(find.text('Set new price'), findsOneWidget);
    await tester.tap(find.text('Set new price'));
    await tester.pump();
    expect(confirmed, isEmpty);
  });

  testWidgets('rider-r4-17: a typed total on a fare with cents lights only '
      'the step it really raises by', (tester) async {
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
    bool lit(String chip) =>
        tester.widget<Text>(find.text(chip)).style?.color == Colors.white;
    await tester.enterText(find.byType(TextField), '27'); // +2,40 €
    await tester.pump();
    expect(lit('+2 €'), isFalse);
    await tester.tap(find.text('+2 €'));
    await tester.pump();
    expect(lit('+2 €'), isTrue);
  });
}
