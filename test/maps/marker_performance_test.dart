import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/marker_store.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart';

void main() {
  test('MarkerStore ignores sub-threshold GPS and heading jitter', () {
    final store = MarkerStore(minimumMoveMeters: 5, minimumHeadingDegrees: 5);
    const start = GeoPoint(59.329300, 18.068600);
    const tiny = GeoPoint(59.329301, 18.068601);

    final first = store.upsert('driver', start, heading: 20);
    final second = store.upsert('driver', tiny, heading: 22);

    expect(identical(first, second), isTrue);
    expect(store['driver']?.point.latitude, start.latitude);
  });

  test('MarkerStore accepts meaningful movement or rotation', () {
    final store = MarkerStore(minimumMoveMeters: 1, minimumHeadingDegrees: 3);
    const start = GeoPoint(59.3293, 18.0686);
    const moved = GeoPoint(59.3295, 18.0686);

    final first = store.upsert('driver', start, heading: 0);
    final second = store.upsert('driver', moved, heading: 0);
    final third = store.upsert('driver', moved, heading: 10);

    expect(identical(first, second), isFalse);
    expect(identical(second, third), isFalse);
  });

  test('vehicle marker descriptor is cached for the same scale', () {
    final first = MoveraVehicleMarker.createIcon(scale: 0.65);
    final second = MoveraVehicleMarker.createIcon(scale: 0.65);

    expect(identical(first, second), isTrue);
  });

  test('rider puck descriptor is cached by expanded state', () {
    final first = MoveraRiderPuckMarker.createIcon();
    final second = MoveraRiderPuckMarker.createIcon();

    expect(identical(first, second), isTrue);
  });
}
