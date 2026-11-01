import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/application/server_receipt.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/core/realtime/sos_availability.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';

/// Contract v0.18.10 (driver group 8 "Finish & cash"): only cash ("Pay in
/// car"), card and Apple Pay; the server says what it takes; tips go to
/// the driver; the receipt says when a trip ended early.
void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );

  test('Google Pay is gone from the zone methods', () {
    expect(ZoneDefaults.paymentMethods, ['cash', 'card', 'apple_pay']);
    expect(RideSelectionController.zoneMethodOf('google'), isNull);
    expect(BookingCoordinator.contractPaymentMethod('apple'), 'apple_pay');
  });

  test('paymentOptions: cash available, card / Apple Pay coming soon', () {
    final options = {'cash': 'available', 'card': 'coming_soon'};
    final config = RiderAppConfig(
      version: 1,
      zoneId: 'Z001',
      currency: 'SEK',
      liveCancelFees: const {},
      reservationCancelFees: const {},
      paymentOptions: options,
    );
    expect(config.paymentStatus('cash'), 'available');
    expect(config.paymentStatus('card'), 'coming_soon');
    // Not listed: the admin turned it off.
    expect(config.paymentStatus('apple_pay'), isNull);
    expect(config.paymentStatus('google_pay'), isNull);
    // An older server: cash only, the others coming soon.
    const older = RiderAppConfig(
      version: 1,
      zoneId: 'Z001',
      currency: 'SEK',
      liveCancelFees: {},
      reservationCancelFees: {},
    );
    expect(older.paymentStatus('cash'), 'available');
    expect(older.paymentStatus('apple_pay'), 'coming_soon');
  });

  test('Select Ride picks only what the server takes', () {
    final selection = RideSelectionController()
      ..setPaymentOptions({
        'cash': 'available',
        'card': 'coming_soon',
        'apple_pay': 'coming_soon',
      });
    final brands = selection.payments().map((p) => p.brand).toList();
    expect(brands, ['cash']);
    expect(
      selection.comingSoonPayments().map((p) => p.brand),
      containsAll(<String>['cards']),
    );
    expect(selection.selectedPaymentItem()?.brand, 'cash');
  });

  test('tip rules: defaults per country', () {
    final se = TipRules.forCountry('SE', 'SEK');
    expect(se.customAmount, isFalse);
    expect(se.cashAfterTrip, isFalse);
    expect(se.customMax?.amountMinor, 20000);
    final fr = TipRules.forCountry('FR', 'EUR');
    expect(fr.customMax?.amountMinor, 2000);
    expect(fr.customMax?.currency, 'EUR');
  });

  test(
    'a tip with the rating goes in the RatingRequest; alone to /tip',
    () async {
      final sent = <String, Map<String, dynamic>>{};
      final repository = RideFeedbackRepository(
        api: ApiClient(
          env: staging,
          client: MockClient((request) async {
            sent[request.url.path] =
                jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(jsonEncode({'tripId': 'trp_1'}), 201);
          }),
        ),
      );
      await repository.submit(
        rideId: 'trp_1',
        rating: 5,
        tipMinor: 2000,
        idempotencyKey: 'k-aaaaaaaaaaaaaaaa',
      );
      await repository.submit(
        rideId: 'trp_2',
        tipMinor: 200,
        tipCurrency: 'EUR',
        idempotencyKey: 'k-bbbbbbbbbbbbbbbb',
      );
      expect(sent['/api/v1/trips/trp_1/rating'], {
        'stars': 5,
        'tip': {'amountMinor': 2000, 'currency': 'SEK'},
        'tipMethod': 'cash',
      });
      expect(sent['/api/v1/trips/trp_2/tip'], {
        'amount': {'amountMinor': 200, 'currency': 'EUR'},
        'method': 'cash',
      });
    },
  );

  test('the receipt says the trip ended early and by whom', () {
    final receipt = ServerReceipt.tryParse({
      'tripId': 'trp_1',
      'endedEarly': true,
      'endedBy': 'driver',
      'tip': {
        'amount': {'amountMinor': 2000, 'currency': 'SEK'},
        'method': 'cash',
      },
      'debtIncluded': {'amountMinor': 24000, 'currency': 'SEK'},
      'refunded': {'amountMinor': 0, 'currency': 'SEK'},
    })!;
    expect(receipt.endedEarly, isTrue);
    expect(receipt.endedBy, 'driver');
    expect(receipt.tip?.amountMinor, 2000);
    expect(receipt.debtIncluded?.amountMinor, 24000);
    expect(receipt.refunded, isNull);
  });

  group('G8 checker gaps', () {
    test('Payments tab: a coming-soon method is greyed, never a default', () {
      const zone = ['cash', 'card', 'apple_pay'];
      const options = {'cash': 'available', 'apple_pay': 'coming_soon'};
      expect(
        walletMethodState('apple_pay', zone, options),
        WalletMethodState.comingSoon,
      );
      expect(
        walletMethodState('cash', zone, options),
        WalletMethodState.available,
      );
      // Not listed by the server: hidden.
      expect(
        walletMethodState('card', zone, options),
        WalletMethodState.hidden,
      );
      // An older server: as before.
      expect(
        walletMethodState('card', zone, null),
        WalletMethodState.available,
      );
    });

    test('Select Ride keeps the wallet row with paymentOptions', () {
      final selection = RideSelectionController()
        ..setPaymentOptions({'cash': 'available', 'card': 'coming_soon'})
        ..setWalletBalance(120);
      expect(selection.payments().map((p) => p.brand), contains('wallet'));
      expect(selection.payments().map((p) => p.brand), contains('cash'));
      expect(
        selection.payments().map((p) => p.brand),
        isNot(contains('cards')),
      );
    });

    test('a wallet booking is cash with walletFirst', () {
      final body = BookingCoordinator.contractTripBody(
        quoteId: 'q_1',
        categoryId: 'economy',
        paymentMethod: 'wallet',
        pickupLat: 59.33,
        pickupLng: 18.06,
        destinationLat: 59.32,
        destinationLng: 18.07,
      );
      expect(body['paymentMethod'], 'cash');
      expect(body['walletFirst'], isTrue);
    });

    test('SOS follows the server sosAvailable, else the driver rule', () {
      addTearDown(SosAvailability.resetForTest);
      expect(SosAvailability.forTrip('trp_1'), isNull);
      SosAvailability.record('trp_1', false);
      expect(SosAvailability.forTrip('trp_1'), isFalse);
      SosAvailability.record('trp_1', true);
      expect(SosAvailability.forTrip('trp_1'), isTrue);
      SosAvailability.record('trp_1', 'yes');
      expect(SosAvailability.forTrip('trp_1'), isTrue);
    });
  });
}
