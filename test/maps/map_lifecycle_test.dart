import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/maps/map_lifecycle.dart';
import 'package:movera_rider/core/maps/marker_store.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';

void main() {
  test('map park and resume', () {
    final life = MapLifecycleController();
    life.created();
    expect(life.isLive, isTrue);
    life.park();
    life.resume();
    expect(life.isLive, isTrue);
    life.dispose();
    expect(life.isLive, isFalse);
  });

  test('marker store updates same id', () {
    final store = MarkerStore();
    store.upsert('user', const GeoPoint(59.3, 18.0));
    store.upsert('user', const GeoPoint(59.31, 18.01), heading: 90);
    expect(store['user']?.heading, 90);
    expect(store.values.length, 1);
  });

  test('realtime backoff grows', () {
    final rt = RealtimeConnection();
    expect(rt.nextBackoff().inSeconds, 1);
    expect(rt.nextBackoff().inSeconds, 2);
    rt.markConnected();
    expect(rt.nextBackoff().inSeconds, 1);
  });
  test('nested parking resumes only once at the outer boundary', () {
    final guard = MapParkingGuard();

    expect(guard.enter(), isTrue);
    expect(guard.isParked, isTrue);
    expect(guard.depth, 1);

    expect(guard.enter(), isFalse);
    expect(guard.depth, 2);

    expect(guard.exit(), isFalse);
    expect(guard.isParked, isTrue);
    expect(guard.depth, 1);

    expect(guard.exit(), isTrue);
    expect(guard.isParked, isFalse);
    expect(guard.depth, 0);

    // A stale extra cleanup cannot trigger a second Home resume.
    expect(guard.exit(), isFalse);
  });
}
