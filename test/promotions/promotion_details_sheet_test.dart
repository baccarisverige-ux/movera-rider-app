import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/promotions/application/rider_promotion_controller.dart';
import 'package:movera_rider/features/promotions/presentation/promotion_details_sheet.dart';

void main() {
  // Local (no Z) so the "days left" maths does not depend on the test
  // machine's time zone.
  const json = {
    'id': 'p1',
    'title': '30% off your next 5 rides',
    'percentOff': 30,
    'ridesLeft': 4,
    'ridesTotal': 5,
    'endsAt': '2026-11-30T23:59:00',
    'maxDiscountMinor': 5000,
    'rideTypes': ['comfort', 'priority', 'premium'],
    'rules': ['Applies to Comfort, Priority and Premium.'],
  };

  const categories = [
    PromotionCategory(id: 'economy', name: 'Movera'),
    PromotionCategory(id: 'comfort', name: 'Comfort'),
    PromotionCategory(id: 'priority', name: 'Priority'),
    PromotionCategory(id: 'premium', name: 'Premium'),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required RiderPromotion promotion,
    Map<String, PromotionPrice> prices = const {},
    DateTime? now,
    String currency = 'SEK',
    Money? cap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PromotionDetailsSheet(
              promotion: promotion,
              categories: categories,
              prices: prices,
              now: now ?? DateTime(2026, 10, 13, 9),
              currency: currency,
              cap: cap,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('with prices: included rows show the discount, others do not', (
    tester,
  ) async {
    await pump(
      tester,
      promotion: RiderPromotion.fromJson(json)!,
      // Q10: the zone's cap from its config, in local money.
      cap: const Money(5000, 'SEK'),
      prices: const {
        'economy': (original: 259, discounted: 259),
        'comfort': (original: 339, discounted: 289),
        'priority': (original: 289, discounted: 239),
        'premium': (original: 369, discounted: 319),
      },
    );
    expect(find.text('30% off · 4 of 5 rides left'), findsOneWidget);
    expect(find.text('4 left'), findsOneWidget);
    expect(find.text('Valid until 30 Nov 2026 · 48 days left'), findsOneWidget);
    expect(find.text('Max 50 kr off per ride'), findsOneWidget);
    expect(find.text('Your prices with this promotion'), findsOneWidget);
    // Comfort: struck-through original, bold discounted price.
    final struck = tester.widget<Text>(find.text('339 kr'));
    expect(struck.style?.decoration, TextDecoration.lineThrough);
    // Comfort's discounted price comes before Priority's original 289 kr.
    final bold = tester.widget<Text>(find.text('289 kr').first);
    expect(bold.style?.fontWeight, FontWeight.w700);
    // Movera is not in the promotion: full price, "Not included".
    expect(find.text('259 kr'), findsOneWidget);
    expect(find.text('Not included'), findsOneWidget);
    expect(find.text('Included'), findsNothing);
    expect(
      find.text('Prices show once you choose a destination.'),
      findsNothing,
    );
    expect(
      find.text('• Applies to Comfort, Priority and Premium.'),
      findsOneWidget,
    );
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('without prices: only Included / Not included and a hint', (
    tester,
  ) async {
    await pump(tester, promotion: RiderPromotion.fromJson(json)!);
    expect(find.text('Included'), findsNWidgets(3));
    expect(find.text('Not included'), findsOneWidget);
    expect(
      find.text('Prices show once you choose a destination.'),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp(r'(^|\s)3\d* kr')), findsNothing);
  });

  testWidgets('ends today and expired states', (tester) async {
    final promotion = RiderPromotion.fromJson(json)!;
    await pump(tester, promotion: promotion, now: DateTime(2026, 11, 30, 8));
    expect(find.text('Ends today'), findsOneWidget);

    await pump(tester, promotion: promotion, now: DateTime(2026, 12, 2));
    expect(find.text('Expired 30 Nov 2026'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('4 left'), findsNothing);
  });

  test('validity text counts whole days and handles a single day', () {
    final promotion = RiderPromotion.fromJson(json)!;
    expect(
      PromotionDetailsSheet.validityText(promotion, DateTime(2026, 11, 29, 23)),
      'Valid until 30 Nov 2026 · 1 day left',
    );
    expect(
      PromotionDetailsSheet.validityText(
        RiderPromotion.fromJson({...json, 'endsAt': null})!,
        DateTime(2026, 11, 29),
      ),
      'No end date',
    );
  });

  testWidgets('Q10: the cap is the zone config\'s, in local money', (
    tester,
  ) async {
    await pump(
      tester,
      promotion: RiderPromotion.fromJson(json)!,
      currency: 'EUR',
      cap: const Money(500, 'EUR'),
    );
    expect(find.text('Max 5 € off per ride'), findsOneWidget);

    await pump(
      tester,
      promotion: RiderPromotion.fromJson(json)!,
      currency: 'TND',
      cap: const Money(15000, 'TND'),
    );
    expect(find.text('Max 15 DT off per ride'), findsOneWidget);
  });

  testWidgets(
    'Q10: no cap set, no cap text (the promotion\'s own is not shown)',
    (tester) async {
      await pump(tester, promotion: RiderPromotion.fromJson(json)!);
      expect(find.textContaining('off per ride'), findsNothing);

      // A cap in another currency than the zone's is never shown.
      await pump(
        tester,
        promotion: RiderPromotion.fromJson(json)!,
        currency: 'EUR',
        cap: const Money(5000, 'SEK'),
      );
      expect(find.textContaining('off per ride'), findsNothing);
    },
  );
}
