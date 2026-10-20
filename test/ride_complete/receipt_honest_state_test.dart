import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/data/driver_repository.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/presentation/trip_detail.dart';

void main() {
  Future<void> pumpTripDetail(
    WidgetTester tester, {
    RideCompleteController? controller,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: RideCompletedTripDetail(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('fresh completion has no seeded receipt data', () {
    final controller = RideCompleteController();

    expect(controller.receipt(), isNull);
  });

  testWidgets('trip details show an honest unavailable state by default', (
    tester,
  ) async {
    await pumpTripDetail(tester);

    expect(find.text('Trip Details'), findsOneWidget);
    expect(find.text('Trip details unavailable'), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(
      find.textContaining('route, payment method and price'),
      findsOneWidget,
    );

    expect(find.text('I11/Street 15 - h350'), findsNothing);
    expect(find.text('Skypulse solution'), findsNothing);
    expect(find.text(r'$10.12'), findsNothing);
    expect(find.text('Cash'), findsNothing);
  });

  testWidgets('explicit real receipt data still renders unchanged', (
    tester,
  ) async {
    const receipt = TripReceipt(
      pickup: 'Stockholm Central',
      destination: 'Arlanda Terminal 5',
      total: '522 kr',
      method: 'Cash',
    );
    final controller = RideCompleteController(
      trips: const TripReceiptRepository(receipt: receipt),
    );

    expect(controller.receipt(), same(receipt));

    await pumpTripDetail(tester, controller: controller);

    expect(find.text('Stockholm Central'), findsOneWidget);
    expect(find.text('Arlanda Terminal 5'), findsOneWidget);
    expect(find.text('522 kr'), findsOneWidget);
    expect(find.text('Total payment'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Trip details unavailable'), findsNothing);
  });
}
