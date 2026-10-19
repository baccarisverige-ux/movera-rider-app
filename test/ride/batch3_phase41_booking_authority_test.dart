import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';

void main() {
  test('booking availability requires a fresh signed authoritative fare', () {
    final controller = RideSelectionController();
    final expiry = DateTime.now().add(const Duration(minutes: 5));
    controller.authoritativeQuotes['economy'] = RideQuote(
      id: 'q-41',
      rideType: 'economy',
      totalMinor: 12500,
      currency: 'SEK',
      expiresAt: expiry,
      signedPayload: 'signed-q-41',
    );
    controller.quoteIds['economy'] = 'q-41';
    controller.quoteExpiresAt['economy'] = expiry;
    controller.offeredPrices['economy'] = 125;

    expect(controller.quoteIsAvailable('economy'), isTrue);
    expect(controller.authoritativePriceFor('economy'), 125);

    // Any rider-visible amount that no longer equals the signed quote must
    // invalidate booking authority rather than silently submit another fare.
    controller.offeredPrices['economy'] = 124;
    expect(controller.quoteIsAvailable('economy'), isFalse);
    expect(controller.authoritativePriceFor('economy'), isNull);

    controller.dispose();
  });

  test('unsigned or wrong-category quotes cannot authorize booking', () {
    final controller = RideSelectionController();
    final expiry = DateTime.now().add(const Duration(minutes: 5));
    controller.authoritativeQuotes['economy'] = RideQuote(
      id: 'q-unsigned',
      rideType: 'premium',
      totalMinor: 12500,
      currency: 'SEK',
      expiresAt: expiry,
    );
    controller.quoteIds['economy'] = 'q-unsigned';
    controller.quoteExpiresAt['economy'] = expiry;
    controller.offeredPrices['economy'] = 125;

    expect(controller.quoteIsAvailable('economy'), isFalse);
    controller.dispose();
  });
}
