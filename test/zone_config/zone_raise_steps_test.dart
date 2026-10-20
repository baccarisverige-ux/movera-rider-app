import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/finding_driver/presentation/price_bump_card.dart';

import 'zone_config_fakes.dart';

/// Owner Q6: the raise-offer quick steps are the zone's `raiseSteps`
/// (enabled only), in every currency: +50/100/150/200 kr, +2/4/6/8 €,
/// +2/4/6/8 DT.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpCard(
    WidgetTester tester, {
    required double price,
    required String currency,
    required List<int> steps,
    ValueChanged<Money>? onRaise,
  }) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PriceBumpCard(
              currentPrice: price,
              maxPrice: price * 2,
              currency: currency,
              steps: steps,
              onConfirm: (_) {},
              onConfirmIncrease: onRaise,
              onKeepWaiting: () {},
            ),
          ),
        ),
      ),
    );
  }

  test('each zone seed has its own steps', () {
    expect(PriceBumpCard.stepsFor(null, 'SEK'), [50, 100, 150, 200]);
    expect(PriceBumpCard.stepsFor(null, 'EUR'), [2, 4, 6, 8]);
    expect(PriceBumpCard.stepsFor(null, 'TND'), [2, 4, 6, 8]);
  });

  test('admin edits: a disabled step is hidden; another currency never shows',
      () async {
    final config = await EditedZoneConfigs({
      'FR-PC': {
        'raiseSteps': [
          {'amount': wireMoney(200, 'EUR'), 'enabled': false},
          {'amount': wireMoney(300, 'EUR'), 'enabled': true},
          {'amount': wireMoney(1000, 'EUR')},
        ],
      },
    }).forZone('FR-PC');
    expect(PriceBumpCard.stepsFor(config, 'EUR'), [3, 10]);
    // A kronor trip never takes the euro zone's steps.
    expect(PriceBumpCard.stepsFor(config, 'SEK'), [50, 100, 150, 200]);
  });

  test('a step that is not a whole unit is left out', () {
    expect(
      PriceBumpCard.wholeSteps(const [
        Money(250, 'EUR'),
        Money(400, 'EUR'),
        Money(5000, 'SEK'),
      ], 'EUR'),
      [4],
    );
  });

  testWidgets('euro steps show and raise by exactly the step', (tester) async {
    Money? raised;
    await pumpCard(
      tester,
      price: 24.6,
      currency: 'EUR',
      steps: PriceBumpCard.stepsFor(SeedRiderConfigRepository.seedFor('FR-PC'), 'EUR'),
      onRaise: (increase) => raised = increase,
    );
    for (final label in ['+2 €', '+4 €', '+6 €', '+8 €']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('+4 €'));
    await tester.pump();
    await tester.tap(find.text('Confirm 28,60 €'));
    expect(raised, const Money(400, 'EUR'));
  });

  testWidgets('dinar steps show in DT', (tester) async {
    Money? raised;
    await pumpCard(
      tester,
      price: 18,
      currency: 'TND',
      steps: PriceBumpCard.stepsFor(null, 'TND'),
      onRaise: (increase) => raised = increase,
    );
    for (final label in ['+2 DT', '+4 DT', '+6 DT', '+8 DT']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('kr'), findsNothing);
    await tester.tap(find.text('+2 DT'));
    await tester.pump();
    await tester.tap(find.text('Confirm 20,000 DT'));
    expect(raised, const Money(2000, 'TND'));
  });
}
