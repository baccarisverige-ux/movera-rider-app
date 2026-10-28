import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/domain/booking_mode.dart';

void main() {
  test('ride catalog has fourteen Movera types', () {
    expect(RideSelectionController().rides().length, 14);
    // Tests run as Android: Google Pay, Card, Cash (no Apple Pay, and
    // the wallet only with a balance). PayPal, Swish and Klarna were removed.
    expect(RideSelectionController().payments().map((p) => p.brand), [
      'google',
      'cards',
      'cash',
    ]);
  });

  test('book now and book later share the same categories', () {
    final now = RideSelectionController(bookingMode: BookingMode.now);
    final later = RideSelectionController(bookingMode: BookingMode.scheduled);
    expect(now.rides().map((ride) => ride.id).toList(), [
      'economy',
      'comfort',
      'premium',
      'priority',
      'xl',
      'electric',
      'pet',
      'van',
      'wheelchair',
      'business',
      'airport',
      'child_seat',
      'women',
      'delivery',
    ]);
    expect(
      later.rides().map((ride) => ride.id),
      now.rides().map((ride) => ride.id),
    );
  });
}
