// rider-u42: on a wallet-paid ride a cheaper route change was credited to
// the wallet at once AND charged at the lower fare at completion, so the
// reduction was refunded twice.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_flow.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeChanges extends RouteChangeController {
  _FakeChanges()
    : super(api: AppScope.instance.api, geocoding: AppScope.instance.geocoding);

  @override
  Future<RouteChangeQuote> preview({
    required RideSnapshot ride,
    String? pickupAddress,
    GeoPoint? pickupPoint,
    required String destinationAddress,
    GeoPoint? destinationPoint,
    List<String> stops = const [],
    List<GeoPoint?> stopPoints = const [],
    int? maxPickupMoveMeters,
  }) async => RouteChangeQuote(
    pickupAddress: ride.pickupAddress,
    pickupPoint: GeoPoint(ride.pickupLat, ride.pickupLng),
    destinationAddress: ride.destinationAddress,
    destinationPoint: GeoPoint(ride.destinationLat, ride.destinationLng),
    stops: const [],
    oldPriceKr: ride.price,
    newPriceKr: 250,
  );

  @override
  Future<RideSnapshot> apply({
    required RideSnapshot ride,
    required RouteChangeQuote quote,
    Object? refundTo,
  }) async => ride.copyWith(price: quote.newPriceKr, stops: const []);
}

RideSnapshot _ride({
  required String paymentMethod,
  String? paymentMethodId,
  int walletAmountMinor = 0,
}) => RideSnapshot(
  status: RideStatus.tripInProgress,
  savedAt: DateTime.now(),
  pickupAddress: 'Pickup',
  destinationAddress: 'Destination',
  pickupLat: 59.3293,
  pickupLng: 18.0686,
  destinationLat: 59.3326,
  destinationLng: 18.0649,
  rideType: 'Movera',
  price: 300,
  paymentMethod: paymentMethod,
  paymentMethodId: paymentMethodId,
  walletAmountMinor: walletAmountMinor,
  rideId: 'u42-ride',
  stops: const [
    RouteStop(address: 'Stop', latitude: 59.331, longitude: 18.066),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({WalletStore.balanceKey: 500.0});
    LastCompletedRide.clear();
  });

  /// Removes the one stop (300 kr -> 250 kr), keeps the default "Movera
  /// Wallet" refund, then completes the trip. Returns the balance right
  /// after the change and after the completion charge.
  Future<(double, double)> run(WidgetTester tester, RideSnapshot ride) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    RideSnapshot? updated;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                updated = await removeRouteStop(
                  context,
                  ride: ride,
                  index: 0,
                  controller: _FakeChanges(),
                );
              },
              child: const Text('remove'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('route-change-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('refund-to-wallet')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('route-change-pay')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(updated?.price, 250);
    final afterChange = (await tester.runAsync(
      () => WalletStore().loadBalance(),
    ))!;
    await tester.runAsync(
      () => AppScope.instance.walletController.chargeCompletedRide(
        updated!.copyWith(status: RideStatus.paymentFinalized),
        rideId: 'u42-ride',
      ),
    );
    final afterCompletion = (await tester.runAsync(
      () => WalletStore().loadBalance(),
    ))!;
    return (afterChange, afterCompletion);
  }

  testWidgets(
    'wallet-paid ride: the cheaper fare is the refund, credited once',
    (tester) async {
      final (afterChange, afterCompletion) = await run(
        tester,
        _ride(paymentMethod: 'Movera Wallet', paymentMethodId: 'wallet'),
      );
      expect(
        afterChange,
        500,
        reason: 'nothing was debited yet, so nothing to credit',
      );
      expect(
        afterCompletion,
        250,
        reason: 'a 250 kr trip costs the wallet 250 kr',
      );
    },
  );

  testWidgets('wallet-first split: only the card part of the cut is credited', (
    tester,
  ) async {
    // 280 kr from the wallet, 20 kr on the card. At 250 kr the wallet part
    // is 250 (already 30 less at completion) and the card part 0, so the
    // 20 kr the card no longer pays is the one credit.
    final (afterChange, afterCompletion) = await run(
      tester,
      _ride(
        paymentMethod: 'Visa •••• 4242',
        paymentMethodId: 'card',
        walletAmountMinor: 28000,
      ),
    );
    expect(afterChange, 520);
    expect(afterCompletion, 270);
  });

  testWidgets('card ride: the refund still goes to the wallet', (tester) async {
    final (afterChange, afterCompletion) = await run(
      tester,
      _ride(paymentMethod: 'Visa •••• 4242', paymentMethodId: 'card'),
    );
    expect(afterChange, 550);
    expect(afterCompletion, 550);
  });
}
