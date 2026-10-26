import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/domain/search_copy.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

void main() {
  test('demo assignment normally happens before long-search price offer', () {
    final rt = MockRideRealtime();
    expect(SearchCopy.delayedAfter, const Duration(seconds: 60));
    expect(rt.assignAfter, const Duration(seconds: 25));
    expect(rt.assignAfter, lessThan(SearchCopy.delayedAfter));
    rt.dispose();
  });

  test('assignment event', () async {
    final rt = MockRideRealtime(assignAfter: Duration.zero);
    RideStatus? last;
    rt.subscribe('r1').listen((e) => last = e.status);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(last, RideStatus.driverAssigned);
    rt.dispose();
  });

  test('duplicate assignment keeps last sequence', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final seq = <int>[];
    rt.subscribe('r1').listen((e) => seq.add(e.sequence));
    rt.emit(RideStatus.driverAssigned, sequence: 2);
    rt.emit(RideStatus.driverAssigned, sequence: 2);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(seq.where((s) => s == 2).length, greaterThanOrEqualTo(1));
    rt.dispose();
  });

  test('assignment after cancellation is ignored by cancelled flag', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    rt.subscribe('r1');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(rt.lastStatus, RideStatus.findingDriver);
    rt.cancelRide();
    expect(rt.cancelled, isTrue);
    expect(rt.lastStatus, RideStatus.cancelledByRider);
    rt.assignNow();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(rt.lastStatus, RideStatus.cancelledByRider);
    expect(rt.lastDriver, isNull);
    rt.dispose();
  });

  test('stale out-of-order sequence can be emitted', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final statuses = <RideStatus>[];
    rt.subscribe('r1').listen((e) => statuses.add(e.status));
    rt.emit(RideStatus.driverAssigned, sequence: 5);
    rt.emit(RideStatus.findingDriver, sequence: 1);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(statuses, contains(RideStatus.driverAssigned));
    rt.dispose();
  });

  test('pickup communication signals use the rider realtime seam', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final events = <RideRealtimeEvent>[];
    final sub = rt.subscribe('r1').listen(events.add);
    await Future<void>.delayed(Duration.zero);

    await rt.sendSignal(
      rideId: 'r1',
      signal: RideRealtimeSignal.riderOnTheWay,
      message: "I'm on the way",
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      events.any(
        (event) =>
            event.signal == RideRealtimeSignal.riderOnTheWay &&
            event.message == "I'm on the way",
      ),
      isTrue,
    );
    await sub.cancel();
    rt.dispose();
  });

  test('reconnect resyncs last status', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    RideStatus? last;
    rt.subscribe('r1').listen((e) => last = e.status);
    rt.emit(RideStatus.findingDriver, sequence: 3);
    await rt.reconnectAndResync('r1');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(last, RideStatus.findingDriver);
    rt.dispose();
  });

  test('re-subscribe same unmatched ride does not reset matching', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    rt.subscribe('r1');
    rt.emit(RideStatus.findingDriver, sequence: 4);
    expect(rt.lastStatus, RideStatus.findingDriver);
    rt.subscribe('r1');
    expect(rt.lastStatus, RideStatus.findingDriver);
    rt.emit(RideStatus.findingDriver, sequence: 5);
    expect(rt.lastStatus, RideStatus.findingDriver);
    rt.dispose();
  });

  test('reconnect does not replace an active unmatched subscription', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final statuses = <RideStatus>[];
    rt.subscribe('r1').listen((e) => statuses.add(e.status));
    rt.emit(RideStatus.findingDriver, sequence: 2);
    await rt.reconnectAndResync('r1');
    rt.subscribe('r1');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(rt.lastStatus, RideStatus.findingDriver);
    rt.dispose();
  });
}
