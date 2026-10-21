import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/home/data/home_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemAddresses extends HomeAddressRepository {
  HomeAddressSnapshot snapshot = HomeAddressSnapshot();

  @override
  Future<HomeAddressSnapshot> load() async => snapshot;

  @override
  Future<void> save(HomeAddressSnapshot data) async {
    snapshot = data;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('rider-40: a Home persist keeps saved places 9 and later', () async {
    final store = _MemAddresses()
      ..snapshot = HomeAddressSnapshot(
        places: [
          for (var i = 1; i <= 10; i++)
            {
              'id': 'p$i',
              'title': 'Place $i',
              'type': 'other',
              'address': 'Street $i',
            },
        ],
      );
    final places = HomePlacesController(store: store);
    await places.load();
    // Home still shows at most eight.
    expect(places.savedPlaces, hasLength(HomePlacesController.maxCustom));
    places.applyResolved(target: 'destination', address: 'Centralen');
    await places.persist();
    expect(store.snapshot.places.map((place) => place['id']), [
      for (var i = 1; i <= 10; i++) 'p$i',
    ]);
    expect(store.snapshot.places.last['address'], 'Street 10');
  });
}
