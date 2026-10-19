import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/features/wallet/domain/wallet_split.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CODE-6, ARCH-5 and FLOW-3: the wallet split is worked out in öre, is
/// sent with the booking, shown the same way after booking and charged,
/// and the rider's opt-out survives saving a payment method.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LastCompletedRide.clear();
    FindingDriverController.active = null;
    AppScope.instance.ride.restoreFromBackend(RideStatus.idle);
    AppScope.instance.ride.rideId = null;
  });

  group('CODE-6: the parts add up to the total', () {
    test('kr 150 with kr 100.50 in the wallet', () {
      final c = RideSelectionController(flags: const FeatureFlags())
        ..setWalletBalance(100.5);
      final split = c.walletSplitFor(15000);
      expect(split.walletMinor, 10050);
      expect(split.remainderMinor, 4950);
      expect(split.walletKr + split.remainderKr, split.totalKr);
      expect(split.totalKr, 150);
    });

    test('öre-precision fares and balances never drift', () {
      for (final (total, balance) in [
        (14950, 4950),
        (9999, 3333),
        (15000, 10050),
        (25949, 12551),
      ]) {
        final split = WalletSplit.of(totalMinor: total, balanceMinor: balance);
        expect(
          split.walletKr + split.remainderKr,
          roundMinorToKr(total),
          reason: '$total / $balance',
        );
        expect(split.walletMinor + split.remainderMinor, total);
      }
    });

    test('the kronor helpers come from the same öre split', () {
      final c = RideSelectionController(flags: const FeatureFlags())
        ..setWalletBalance(100.5);
      expect(c.walletAppliedKr(150), 100.5);
      expect(c.remainderKr(150), 49.5);
    });
  });

  group('ARCH-5: the wallet split is a booking intent', () {
    Future<Map<String, dynamic>> book({
      required InProcessMockClient mock,
      required bool useWalletFirst,
      required int walletAmountMinor,
    }) async {
      final api = ApiClient(client: mock);
      final quote = await api.post(
        '/api/v1/quotes',
        body: {'rideType': 'economy', 'distanceMeters': 3000},
      );
      final q = Map<String, dynamic>.from(quote['quote'] as Map);
      final total = (q['totalMinor'] as num).round();
      final booking = BookingCoordinator(api: api);
      final rideId = await booking.submitFinding(
        pickupAddress: 'Sveavägen 1',
        destinationAddress: 'Hornsgatan 2',
        pickupLat: 59.34,
        pickupLng: 18.05,
        destinationLat: 59.31,
        destinationLng: 18.04,
        rideType: 'economy',
        price: total / 100,
        paymentMethod: 'cash',
        quoteId: q['id'] as String,
        quoteSignedPayload: q['signedPayload'] as String,
        quoteExpiresAt: DateTime.parse(q['expiresAt'] as String),
        quoteTotalMinor: total,
        useWalletFirst: useWalletFirst,
        walletAmountMinor: walletAmountMinor,
      );
      final stored = await api.get('/api/v1/rides/$rideId');
      return Map<String, dynamic>.from(stored['ride'] as Map);
    }

    test('POST /rides carries it and the first snapshot keeps it', () async {
      final mock = InProcessMockClient();
      final ride = await book(
        mock: mock,
        useWalletFirst: true,
        walletAmountMinor: 5000,
      );
      expect(ride['useWalletFirst'], isTrue);
      expect(ride['walletAmountMinor'], 5000);
      final saved = await RideSnapshotStore.read();
      expect(saved!.walletAmountMinor, 5000);
    });

    test('switched off, no wallet part is sent', () async {
      final ride = await book(
        mock: InProcessMockClient(),
        useWalletFirst: false,
        walletAmountMinor: 5000,
      );
      expect(ride['useWalletFirst'], isFalse);
      expect(ride['walletAmountMinor'], 0);
    });

    test('the snapshot round-trips the wallet part', () {
      final snapshot = _snapshot(walletAmountMinor: 5000);
      final back = RideSnapshot.fromJson(snapshot.toJson())!;
      expect(back.walletAmountMinor, 5000);
      expect(RideSnapshot.fromJson(_snapshot().toJson())!.walletAmountMinor, 0);
    });

    test('a card ride with a wallet part charges that part', () async {
      SharedPreferences.setMockInitialValues({WalletStore.balanceKey: 50.0});
      final wallet = WalletController();
      final next = await wallet.chargeCompletedRide(
        _snapshot(walletAmountMinor: 5000),
        rideId: 'r-1',
      );
      expect(next, 0);
      expect(await WalletStore().loadBalance(), 0);
    });

    testWidgets('the Waiting card shows the split the rider saw', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaitingRideDetailsCard(
              rideType: 'Movera',
              pickupAddress: 'Sveavägen 1',
              paymentMethod: 'Visa •••• 4242',
              walletAmountMinor: 5000,
              price: 259,
              onMore: () {},
            ),
          ),
        ),
      );
      expect(find.text('Visa •••• 4242 209 kr · Wallet 50 kr'), findsOneWidget);
    });
  });

  group('FLOW-3: the wallet opt-out survives saving a method', () {
    test('Wallet screen-style savePayments keeps useWalletFirst off', () async {
      final wallet = WalletController();
      await wallet.saveUseWalletFirst(false);
      expect(await wallet.loadUseWalletFirst(), isFalse);
      // Exactly what _WalletScreenState._savePaymentSettings builds.
      final current = await wallet.loadPayments();
      await wallet.savePayments(
        WalletPaymentSettings(
          defaultMethod: 'apple',
          business: current.business,
          extraMethods: current.extraMethods,
        ),
      );
      expect(await wallet.loadUseWalletFirst(), isFalse);
      expect((await wallet.loadPayments()).defaultMethod, 'apple');
    });

    test('an explicit choice is still saved', () async {
      final wallet = WalletController();
      await wallet.saveUseWalletFirst(false);
      await wallet.saveUseWalletFirst(true);
      expect(await wallet.loadUseWalletFirst(), isTrue);
    });
  });
}

RideSnapshot _snapshot({int walletAmountMinor = 0}) => RideSnapshot(
  status: RideStatus.tripCompleted,
  savedAt: DateTime.now(),
  pickupAddress: 'Pickup',
  destinationAddress: 'Destination',
  pickupLat: 59.3293,
  pickupLng: 18.0686,
  destinationLat: 59.3326,
  destinationLng: 18.0649,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Visa •••• 4242',
  rideId: 'r-1',
  walletAmountMinor: walletAmountMinor,
);
