import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:movera_rider/app/app.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global UAT gate: drives booking, wallet, reservations, and profile
/// through their real controllers on the in-process mock backend, in one
/// flow, so a regression in any of them fails CI instead of only a live
/// manual pass. See docs/UAT_CHECKLIST.md.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('global UAT: boot, book, top up wallet, reserve, update profile', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MoveraApp());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MaterialApp), findsOneWidget);

    // Booking: quote then submit reaches Finding on the mock backend.
    final api = ApiClient(client: InProcessMockClient());
    final quote = await api.post(
      '/api/v1/quotes',
      body: {'rideType': 'economy'},
    );
    final q = quote['quote'] as Map;
    expect(q['id'], q['quoteId']);
    expect(q['currency'], 'SEK');
    final rideId = await AppScope.instance.booking.submitFinding(
      pickupAddress: 'Home',
      destinationAddress: 'Arlanda Airport',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.65,
      destinationLng: 17.92,
      rideType: 'Movera',
      price: 349,
      paymentMethod: 'Wallet',
    );
    expect(rideId, isNotEmpty);

    // Wallet: a top-up through WalletController (mock gateway create and
    // confirm, then the balance repository the UI reads), then the debit
    // for the Wallet-paid ride booked above once it completes.
    final walletController = AppScope.instance.walletController;
    final startingBalance = await walletController.loadBalance();
    final topUp = await walletController.topUp(
      previous: startingBalance,
      amount: 200,
      idempotencyKey: 'uat-topup',
    );
    expect(topUp, isA<TopUpCredited>());
    expect(await walletController.loadBalance(), startingBalance + 200);
    final charged = await walletController.chargeCompletedRide(
      RideSnapshot(
        status: RideStatus.tripCompleted,
        savedAt: DateTime.now(),
        pickupAddress: 'Home',
        destinationAddress: 'Arlanda Airport',
        pickupLat: 59.3,
        pickupLng: 18.0,
        destinationLat: 59.65,
        destinationLng: 17.92,
        rideType: 'Movera',
        price: 349,
        paymentMethod: 'Wallet',
        rideId: rideId,
      ),
      rideId: rideId,
    );
    expect(charged, startingBalance + 200 - 349);
    expect(await walletController.loadBalance(), startingBalance + 200 - 349);

    // Reservations: create a scheduled reservation, then cancel it.
    final reservations = AppScope.instance.reservations;
    final created = await reservations.create(
      ReservationDraft(
        scheduledPickupAt: DateTime.now().add(const Duration(days: 1)),
        pickup: const ReservationPlace(label: 'Home'),
        destination: const ReservationPlace(label: 'Arlanda Express'),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 522,
        paymentMethod: 'Wallet',
      ),
    );
    expect(
      reservations.upcoming().any(
        (r) => r.reservationId == created.reservationId,
      ),
      isTrue,
    );
    final cancelled = await reservations.cancel(
      created.reservationId,
      reason: 'Global UAT',
    );
    expect(cancelled.status, ReservationStatus.cancelled);
    expect(
      reservations.cancelled().any(
        (r) => r.reservationId == created.reservationId,
      ),
      isTrue,
    );

    // Profile: hydrate then persist a name change through the real store.
    final profile = AppScope.instance.profile;
    await profile.hydrate();
    final updatedName = '${profile.displayName()} (UAT)';
    await profile.update(profile.profile.copyWith(name: updatedName));
    expect(profile.displayName(), updatedName);
  });
}
