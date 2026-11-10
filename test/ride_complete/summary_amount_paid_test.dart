import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/application/server_receipt.dart';
import 'package:movera_rider/features/ride_complete/presentation/trip_detail.dart';

/// Owner 2026-11-10 (Tunis phone test): after the trip the summary always
/// shows the final amount paid from the server receipt (contract
/// Receipt.total) in the zone currency, plus the tip line when one was given.
void main() {
  Future<void> pump(WidgetTester tester, Map<String, Object?> json) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RideCompletedTripDetail(
                controller: RideCompleteController(),
                rideId: json['tripId'] as String,
                receiptLoader: (_) async => ServerReceipt.tryParse(json),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('TND: 3 decimals, with a tip', (tester) async {
    await pump(tester, {
      'tripId': 'trp_tn',
      'total': {'amountMinor': 12350, 'currency': 'TND'},
      'tip': {
        'amount': {'amountMinor': 2000, 'currency': 'TND'},
        'method': 'card',
      },
    });
    expect(find.text('Total payment'), findsOneWidget);
    expect(find.text('12,350 DT'), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-tip')), findsOneWidget);
    expect(find.text('2,000 DT'), findsOneWidget);
    expect(find.text('Trip details unavailable'), findsNothing);
  });

  testWidgets('SEK: 2 decimals, no tip line without a tip', (tester) async {
    await pump(tester, {
      'tripId': 'trp_se',
      'total': {'amountMinor': 12675, 'currency': 'SEK'},
    });
    expect(find.text('126,75 kr'), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-tip')), findsNothing);
  });

  testWidgets('EUR with a tip', (tester) async {
    await pump(tester, {
      'tripId': 'trp_fi',
      'total': {'amountMinor': 741, 'currency': 'EUR'},
      'tip': {
        'amount': {'amountMinor': 150, 'currency': 'EUR'},
        'method': 'card',
      },
    });
    expect(find.text('7,41 €'), findsOneWidget);
    expect(find.text('1,50 €'), findsOneWidget);
  });
}
