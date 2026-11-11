import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/application/rider_trip_watch.dart';

/// R09 N5: with a ride on screen the 8 s check read the booked-driver list
/// (`GET /rider/trips?kind=scheduled&status=…`) also for a rider with no
/// booked ride at all.
void main() {
  RiderTripWatch watch(List<String> log, {required bool booked}) =>
      RiderTripWatch(
        showsHome: () => false,
        adopt: () async => log.add('adopt'),
        bookedOnTheWay: () async {
          log.add('banner');
          return true;
        },
        refreshBooked: () async => log.add('refresh'),
        hasBooked: () => booked,
        pollEvery: const Duration(hours: 1),
      );

  test('no booked ride: the banner check is not sent', () async {
    final log = <String>[];
    final w = watch(log, booked: false);
    await w.check();
    await w.check();
    expect(log, isEmpty);
    expect(w.bookedDriverOnTheWay.value, isFalse);
  });

  test('a booked ride: the banner check runs', () async {
    final log = <String>[];
    final w = watch(log, booked: true);
    await w.check();
    expect(log, ['banner']);
    expect(w.bookedDriverOnTheWay.value, isTrue);
  });

  test('rider_trip_changed still reads the booked list', () async {
    final log = <String>[];
    watch(log, booked: false).onConfigEvent({'kind': 'rider_trip_changed'});
    await Future<void>.delayed(Duration.zero);
    expect(log, ['refresh']);
  });
}
