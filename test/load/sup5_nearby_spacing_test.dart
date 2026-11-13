import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_selection/application/nearby_cars_controller.dart';
import 'package:movera_rider/features/ride_selection/domain/nearby_car.dart';

class _Source implements NearbyCarsSource {
  final asked = <GeoPoint>[];

  @override
  Future<NearbyCarsAnswer> near(GeoPoint point) async {
    asked.add(point);
    return const NearbyCarsAnswer(
      cars: <NearbyCar>[],
      refresh: Duration(seconds: 6),
    );
  }
}

const _sergels = GeoPoint(59.3326, 18.0649);

/// G31 phone run 1, route-picker -> select-ride RELOAD: GET
/// /rider/nearby-vehicles twice within 4 s. NearbyCarsController asked at
/// once on every resume / watch (nearby_cars_controller.dart watch() and
/// resume() called _fetch() straight away), so any pause + resume (a page
/// covering Select ride, the app away and back, a map park) or a small
/// pickup move read again right after the last read.
void main() {
  testWidgets('a pause and resume 1 s after a read waits until 5 s after it', (
    tester,
  ) async {
    final source = _Source();
    final cars = NearbyCarsController(source: source);
    cars.watch(_sergels);
    await tester.pump();
    expect(source.asked, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    cars.pause();
    cars.resume();
    await tester.pump();
    // Before the fix: 2 (the second read 1 s after the first).
    expect(source.asked, hasLength(1));
    await tester.pump(const Duration(seconds: 4));
    expect(source.asked, hasLength(2));
    cars.dispose();
  });

  testWidgets('a small pickup move 1 s after a read waits too; a new area '
      'is asked at once', (tester) async {
    final source = _Source();
    final cars = NearbyCarsController(source: source);
    cars.watch(_sergels);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    cars.watch(const GeoPoint(59.3330, 18.0649)); // ~45 m
    await tester.pump();
    expect(source.asked, hasLength(1));
    await tester.pump(const Duration(seconds: 4));
    expect(source.asked, hasLength(2));
    cars.watch(const GeoPoint(59.1955, 17.6253)); // another town
    await tester.pump();
    expect(source.asked, hasLength(3));
    cars.dispose();
  });
}
