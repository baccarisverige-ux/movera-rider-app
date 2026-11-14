import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/finding_driver/presentation/price_bump_card.dart';
import 'package:movera_rider/features/ride_complete/presentation/add_tip.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// Supervisor M2 (Rules audits/impact/pd2-pf-supervisor.md; contract
/// v0.18.89 `moneyDisplay.wholeAmounts`, owner 2026-11-14): no short form
/// on any screen, list or card. Tip chips, raise steps and the unpaid-fee
/// line keep the decimals ("20,00 kr", "5,00 €", "2.000 DT"), and the
/// chips still fit at 320 px with the text at 1.3.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('formatMoneyShort keeps the decimals in every currency', () {
    expect(formatMoneyShort(const Money(2000, 'SEK')), '20,00 kr');
    expect(formatMoneyShort(const Money(500, 'EUR')), '5,00 €');
    expect(formatMoneyShort(const Money(2000, 'TND')), '2.000 DT');
    expect(formatMoneyShort(const Money(250, 'EUR')), '2,50 €');
  });

  Future<void> pumpNarrow(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, _) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (currency, steps, chip) in [
    ('SEK', const [50, 100, 150, 200], '+50,00 kr'),
    ('TND', const [1, 2, 3], '+1.000 DT'),
  ]) {
    testWidgets('raise steps keep decimals at 320 px ×1.3 ($currency)', (
      tester,
    ) async {
      await pumpNarrow(
        tester,
        PriceBumpCard(
          currentPrice: currency == 'SEK' ? 259 : 12,
          maxPrice: currency == 'SEK' ? 466 : 20,
          steps: steps,
          currency: currency,
          onConfirm: (_) {},
          onKeepWaiting: () {},
        ),
      );
      expect(find.text(chip), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tip chips keep decimals at 320 px ×1.3 (SEK)', (tester) async {
    await pumpNarrow(tester, const RideCompletedAddTip());
    expect(find.text('10,00 kr'), findsOneWidget);
    expect(find.text('10 kr'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
