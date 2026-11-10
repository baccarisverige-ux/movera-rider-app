import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/call_events.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/application/server_receipt.dart';
import 'package:movera_rider/features/ride_complete/presentation/trip_detail.dart';

/// Owner 2026-11-10 "Yes, auto-update": on a cash trip the server has no
/// receipt until the payment is captured (`receipt_not_ready`). The summary
/// used to read it once and never again; now it reads it again with a
/// bounded retry and at once on a `payment_updated` event, then shows the
/// final amount.
void main() {
  final receipt = {
    'tripId': 'trp_cash',
    'total': {'amountMinor': 12350, 'currency': 'TND'},
  };

  Future<void> pump(
    WidgetTester tester,
    Future<ServerReceipt?> Function(String) loader, {
    List<Duration> delays = RideCompletedTripDetail.defaultReceiptRetryDelays,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RideCompletedTripDetail(
                controller: RideCompleteController(),
                rideId: 'trp_cash',
                receiptLoader: loader,
                receiptRetryDelays: delays,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('not ready, then captured: the retry shows the final amount', (
    tester,
  ) async {
    var captured = false;
    await pump(
      tester,
      (_) async => captured ? ServerReceipt.tryParse(receipt) : null,
    );
    expect(find.text('12.350 DT'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('12.350 DT'), findsNothing);
    captured = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Total payment'), findsOneWidget);
    expect(find.text('12.350 DT'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a payment_updated event re-reads the receipt at once', (
    tester,
  ) async {
    var captured = false;
    await pump(
      tester,
      (_) async => captured ? ServerReceipt.tryParse(receipt) : null,
      delays: const [Duration(hours: 1)],
    );
    captured = true;
    RidePaymentEvents.notify('other_trip');
    await tester.pump();
    expect(find.text('12.350 DT'), findsNothing);
    RidePaymentEvents.notify('trp_cash');
    await tester.pump();
    await tester.pump();
    expect(find.text('12.350 DT'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the retry is bounded', (tester) async {
    var reads = 0;
    await pump(tester, (_) async {
      reads += 1;
      return null;
    }, delays: const [Duration(seconds: 1), Duration(seconds: 1)]);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    final settled = reads;
    await tester.pump(const Duration(minutes: 5));
    expect(reads, settled);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
