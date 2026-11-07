import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/application/rider_trip_watch.dart';

/// SUP3-R1: the booked rides (Upcoming, the Home chrono) are read again on
/// rider_trip_changed (also with a ride on screen), when the app comes to
/// the front and with Home's 8 s check.
void main() {
  RiderTripWatch watch({required bool home, required List<String> log}) =>
      RiderTripWatch(
        showsHome: () => home,
        adopt: () async => log.add('adopt'),
        bookedOnTheWay: () async => false,
        refreshBooked: () async => log.add('refresh'),
        pollEvery: const Duration(hours: 1),
      );

  test('rider_trip_changed reads the booked rides, also with a ride on '
      'screen', () async {
    final log = <String>[];
    watch(home: false, log: log).onConfigEvent({'kind': 'rider_trip_changed'});
    await Future<void>.delayed(Duration.zero);
    expect(log, contains('refresh'));
    expect(log, isNot(contains('adopt')));
  });

  test('another config event reads nothing', () async {
    final log = <String>[];
    watch(home: true, log: log).onConfigEvent({'kind': 'config_published'});
    await Future<void>.delayed(Duration.zero);
    expect(log, isEmpty);
  });

  test('coming to the front reads the booked rides once', () async {
    final log = <String>[];
    final w = watch(home: false, log: log)..start();
    addTearDown(w.stop);
    w.start(); // already polling: no second read
    await Future<void>.delayed(Duration.zero);
    expect(log.where((e) => e == 'refresh'), hasLength(1));
  });

  test("Home's check reads the booked rides, then adopts", () async {
    final log = <String>[];
    await watch(home: true, log: log).check();
    expect(log, ['refresh', 'adopt']);
  });
}
