import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(find.text('Max kr 50 off per ride'), findsOneWidget);
    expect(find.text('Your prices with this promotion'), findsOneWidget);
    // Comfort: struck-through original, bold discounted price.
    final struck = tester.widget<Text>(find.text('kr 339'));
    expect(struck.style?.decoration, TextDecoration.lineThrough);
    // Comfort's discounted price comes before Priority's original kr 289.
    final bold = tester.widget<Text>(find.text('kr 289').first);
    expect(bold.style?.fontWeight, FontWeight.w700);
    // Movera is not in the promotion: full price, "Not included".
    expect(find.text('kr 259'), findsOneWidget);
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
    expect(find.textContaining('kr 3'), findsNothing);
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
}
