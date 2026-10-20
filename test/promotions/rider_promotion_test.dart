import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/promotions/application/rider_promotion_controller.dart';
import 'package:movera_rider/features/promotions/presentation/promotion_ticket.dart';

void main() {
  const json = {
    'id': 'p1',
    'title': '30% off your next 5 rides',
    'percentOff': 30,
    'ridesLeft': 4,
    'ridesTotal': 5,
    'endsAt': '2026-11-30T23:59:00Z',
  };

  test('parses the server promotion', () {
    final p = RiderPromotion.fromJson(json)!;
    expect(p.title, '30% off your next 5 rides');
    expect(p.ridesLeft, 4);
    expect(p.endsAt, DateTime.utc(2026, 11, 30, 23, 59));
  });

  test('parses the categories the promotion applies to', () {
    final p = RiderPromotion.fromJson({
      ...json,
      'rideTypes': ['comfort', 'priority', 7, 'premium'],
    })!;
    expect(p.rideTypes, ['comfort', 'priority', 'premium']);
    expect(p.appliesTo('comfort'), isTrue);
    expect(p.appliesTo('economy'), isFalse);
    // No list from the server means every category.
    final all = RiderPromotion.fromJson(json)!;
    expect(all.rideTypes, isEmpty);
    expect(all.appliesTo('economy'), isTrue);
  });

  test('nothing from the server means no promotion', () {
    expect(RiderPromotion.fromJson(null), isNull);
    expect(RiderPromotion.fromJson({'id': 'x'}), isNull);
    expect(RiderPromotion.fromJson({...json, 'title': '  '}), isNull);
  });

  test('used up or ended promotions are not active', () {
    final p = RiderPromotion.fromJson(json)!;
    expect(p.isActiveAt(DateTime.utc(2026, 10, 13)), isTrue);
    expect(p.isActiveAt(DateTime.utc(2026, 12, 1)), isFalse);
    final used = RiderPromotion.fromJson({...json, 'ridesLeft': 0})!;
    expect(used.isActiveAt(DateTime.utc(2026, 10, 13)), isFalse);
  });

  test('controller reads the active promotion through the API', () async {
    final controller = RiderPromotionController(
      ApiClient(),
      clock: () => DateTime.utc(2026, 10, 13),
    );
    await controller.refresh();
    expect(controller.active?.title, isNotEmpty);
  });

  testWidgets('ticket shows title and rides left, without a close button', (
    tester,
  ) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: PromotionTicket(promotion: RiderPromotion.fromJson(json)!),
          ),
        ),
      ),
    );
    expect(find.text('30% off your next 5 rides'), findsOneWidget);
    expect(find.text('4 left'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });
}
