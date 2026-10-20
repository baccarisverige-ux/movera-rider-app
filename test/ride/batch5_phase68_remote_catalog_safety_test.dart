import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:movera_rider/features/ride_selection/domain/ride_selection.dart';

class _Catalog extends RideSelectionRepository {
  _Catalog(this.items);
  final List<RideCatalogItem> items;

  @override
  List<RideCatalogItem> rides() => items;
}

RideCatalogItem _ride(String id) => RideCatalogItem(
  id: id,
  image: 'asset.webp',
  name: id,
  note: 'note',
  arrival: '5 min',
  etaMin: 5,
  price: 100,
  seats: 4,
);

void main() {
  test('remote catalog replacement repairs stale selected id', () {
    final controller = RideSelectionController(
      store: _Catalog([_ride('remote-a'), _ride('remote-b')]),
    );
    addTearDown(controller.dispose);

    expect(controller.selectedRideId, 'economy');
    final selected = controller.ensureCatalogSelection();

    expect(selected?.id, 'remote-a');
    expect(controller.selectedRideId, 'remote-a');
    expect(controller.rideByIdOrNull('economy'), isNull);
  });

  test('empty remote catalog is safe and exposes no selection', () {
    final controller = RideSelectionController(store: _Catalog(const []));
    addTearDown(controller.dispose);

    expect(controller.ensureCatalogSelection(), isNull);
    expect(controller.rideByIdOrNull('economy'), isNull);
    expect(() => controller.rideById('economy'), throwsStateError);
  });
}
