import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  RouteChangeQuote quote({double newPrice = 369}) => RouteChangeQuote(
    pickupAddress: 'Sergels torg 1',
    pickupPoint: const GeoPoint(59.33, 18.06),
    destinationAddress: 'Arlanda',
    destinationPoint: const GeoPoint(59.65, 17.93),
    stops: const [],
    oldPriceKr: 259,
    newPriceKr: newPrice,
  );

  Future<RouteChangeDecision?> pump(
    WidgetTester tester, {
    required String paymentMethod,
    double newPrice = 369,
    required Future<void> Function() act,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    RouteChangeDecision? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await RouteChangeSheet.confirm(
                    context,
                    quote: quote(newPrice: newPrice),
                    paymentMethod: paymentMethod,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await act();
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('Cash: the price is shown and one confirm is enough',
      (tester) async {
    final result = await pump(
      tester,
      paymentMethod: 'Cash',
      act: () async {
        expect(find.byKey(const ValueKey('route-change-price')), findsOneWidget);
        expect(find.text('369 kr'), findsOneWidget);
        expect(find.textContaining('in the car'), findsOneWidget);
        expect(find.text('Confirm change'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('route-change-confirm')));
      },
    );
    expect(result?.confirmed, isTrue);
    expect(result?.refundTo, isNull);
  });

  testWidgets('Apple Pay: a payment step confirms the charge', (tester) async {
    final result = await pump(
      tester,
      paymentMethod: 'Apple Pay',
      act: () async {
        expect(find.textContaining('charged to Apple Pay'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('route-change-confirm')));
        await tester.pumpAndSettle();
        expect(find.text('Confirm payment'), findsOneWidget);
        expect(find.byKey(const ValueKey('route-change-payment')), findsOneWidget);
        expect(find.text('+110 kr'), findsOneWidget);
        expect(find.text('Confirm and pay 110 kr'), findsOneWidget);
        // A charge never asks where the money goes.
        expect(find.byKey(const ValueKey('refund-to-wallet')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('route-change-pay')));
      },
    );
    expect(result?.confirmed, isTrue);
    expect(result?.refundTo, isNull);
  });

  testWidgets('a cheaper route on a card asks where the refund goes; wallet by default',
      (tester) async {
    final result = await pump(
      tester,
      paymentMethod: 'Visa •••• 4242',
      newPrice: 130,
      act: () async {
        await tester.tap(find.byKey(const ValueKey('route-change-confirm')));
        await tester.pumpAndSettle();
        expect(find.text('Choose your refund'), findsOneWidget);
        expect(find.text('Refund amount'), findsOneWidget);
        expect(find.text('129 kr'), findsOneWidget);
        expect(find.byKey(const ValueKey('refund-to-wallet')), findsOneWidget);
        expect(find.byKey(const ValueKey('refund-to-original')), findsOneWidget);
        expect(find.textContaining('2 to 3 business days'), findsOneWidget);
        expect(find.text('Confirm refund to Movera Wallet'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('route-change-pay')));
      },
    );
    expect(result?.confirmed, isTrue);
    expect(result?.refundTo, RefundDestination.wallet);
  });

  testWidgets('the rider can choose the original payment method instead',
      (tester) async {
    final result = await pump(
      tester,
      paymentMethod: 'Apple Pay',
      newPrice: 130,
      act: () async {
        await tester.tap(find.byKey(const ValueKey('route-change-confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('refund-to-original')));
        await tester.pumpAndSettle();
        expect(find.text('Confirm refund to Apple Pay'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('route-change-pay')));
      },
    );
    expect(result?.confirmed, isTrue);
    expect(result?.refundTo, RefundDestination.originalMethod);
  });

  testWidgets('Keep current route resolves false', (tester) async {
    final result = await pump(
      tester,
      paymentMethod: 'Apple Pay',
      act: () async => tester.tap(find.text('Keep current route')),
    );
    expect(result?.confirmed, isFalse);
  });
}
