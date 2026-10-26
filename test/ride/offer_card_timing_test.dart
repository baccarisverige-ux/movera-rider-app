import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/finding_driver/domain/search_copy.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The "raise your offer" card appears after 45 s on a real backend and
/// after 5 s in demo builds. It used to share the 60 s "taking longer"
/// timer, so in the demo (driver found at 25 s) it never appeared at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  RideSnapshot snap() => RideSnapshot(
    status: RideStatus.findingDriver,
    savedAt: DateTime.now(),
    pickupAddress: 'A',
    destinationAddress: 'B',
    pickupLat: 59.3,
    pickupLng: 18.0,
    destinationLat: 59.4,
    destinationLng: 18.1,
    rideType: 'Movera',
    price: 259,
    paymentMethod: 'Apple Pay',
    rideId: 'r1',
  );

  (FindingDriverController, MockRideRealtime) started({
    Duration? priceBumpAfter,
  }) {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final controller = FindingDriverController(
      realtime: rt,
      ride: RideSession()..rideId = 'r1',
      store: FindingDriverRepository(),
      priceBumpAfter: priceBumpAfter,
    );
    controller.start(snapshot: snap(), onTick: (_) {}, onMatched: () {});
    addTearDown(() {
      controller.dispose();
      rt.dispose();
    });
    return (controller, rt);
  }

  test('the real app offers a higher price after 45 s, before the '
      '"taking longer" copy at 60 s', () {
    final (controller, _) = started(priceBumpAfter: SearchCopy.priceBumpAfter);
    expect(SearchCopy.priceBumpAfter, const Duration(seconds: 45));

    controller.debugAdvance(44);
    expect(controller.showPriceBump, isFalse);

    controller.debugAdvance(1);
    expect(controller.showPriceBump, isTrue);
    expect(
      controller.isDelayed,
      isFalse,
      reason: 'the search copy still waits for the 60 s mark',
    );

    controller.debugAdvance(15);
    expect(controller.isDelayed, isTrue);
    expect(controller.showPriceBump, isTrue);
  });

  test('demo builds offer it after 5 s, before the demo driver arrives', () {
    // Widget and unit tests run with mock transport, like the demo.
    final (controller, rt) = started();
    expect(controller.priceBumpAfter, SearchCopy.demoPriceBumpAfter);
    expect(SearchCopy.demoPriceBumpAfter, const Duration(seconds: 5));
    expect(
      SearchCopy.demoPriceBumpAfter,
      lessThan(MockRideRealtime().assignAfter),
      reason: 'the demo driver must not arrive before the card can be seen',
    );

    controller.debugAdvance(4);
    expect(controller.showPriceBump, isFalse);
    controller.debugAdvance(1);
    expect(controller.showPriceBump, isTrue);
    rt.holdAssignment();
  });

  test('Keep waiting hides the card for the rest of the search', () {
    final (controller, _) = started(priceBumpAfter: SearchCopy.priceBumpAfter);
    controller.debugAdvance(45);
    expect(controller.showPriceBump, isTrue);

    controller.dismissPriceBump();
    expect(controller.showPriceBump, isFalse);
    controller.debugAdvance(30);
    expect(controller.showPriceBump, isFalse);
  });
}
