import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/application/server_receipt.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G23: once the server receipt is read, the hero shows its total (contract
/// Receipt.total, the final amount in the zone currency), as "Total
/// payment", the same amount the trip details show.
class _QuietRealtime implements RideRealtime {
  final StreamController<RideRealtimeEvent> _controller =
      StreamController<RideRealtimeEvent>.broadcast(sync: true);

  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => _controller.stream;
  @override
  Future<void> reconnectAndResync(String rideId) async {}
  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}
  @override
  void unsubscribe() {}
  @override
  void cancelRide() {}
  @override
  void researchAfterDriverCancel() {}
  @override
  void dispose() => _controller.close();
}

RideSnapshot _tunisRide() => RideSnapshot(
  status: RideStatus.tripCompleted,
  savedAt: DateTime.now(),
  pickupAddress: 'Avenue Habib Bourguiba',
  destinationAddress: 'La Marsa',
  pickupLat: 36.8,
  pickupLng: 10.18,
  destinationLat: 36.88,
  destinationLng: 10.32,
  rideType: 'Movera',
  price: 11.5,
  currency: 'TND',
  paymentMethod: 'Cash',
  rideId: 'trp_g23',
);

Future<void> _pump(
  WidgetTester tester,
  Future<ServerReceipt?> Function(String) loader,
) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final realtime = _QuietRealtime();
  addTearDown(realtime.dispose);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(1200, 2400),
      builder: (_, _) => MaterialApp(
        home: RideCompleted(
          status: RideStatus.paymentFinalized,
          rideId: 'trp_g23',
          realtime: realtime,
          persistOnDemandState: false,
          showConnectionBanner: false,
          receiptLoader: loader,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LastCompletedRide.clear();
    LastCompletedRide.remember(_tunisRide());
  });
  tearDown(LastCompletedRide.clear);

  testWidgets('the server total replaces the booked price in the hero', (
    tester,
  ) async {
    await _pump(
      tester,
      (id) async => ServerReceipt.tryParse({
        'tripId': id,
        'total': {'amountMinor': 12350, 'currency': 'TND'},
      }),
    );
    final hero = find.byKey(const ValueKey('completion-hero-amount'));
    expect(tester.widget<Text>(hero).data, '12.350 DT');
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('completion-hero-amount-label')),
          )
          .data,
      L10n.current.totalPayment,
    );
    // The details further down show the same final amount.
    expect(find.text('12.350 DT'), findsNWidgets(2));
  });
}
