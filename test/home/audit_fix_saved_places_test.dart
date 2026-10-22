import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/home/data/home_repository.dart';
import 'package:movera_rider/features/home/presentation/widgets/saved_places_row.dart';
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

  group('rider-41: custom places are matched by id, not by kind', () {
    HomeAddressSnapshot twoGyms() => HomeAddressSnapshot(
      places: [
        {'id': 'a', 'title': 'Gym A', 'type': 'gym', 'address': 'Street A 1'},
        {'id': 'b', 'title': 'Gym B', 'type': 'gym', 'address': 'Street B 2'},
      ],
    );

    test('adding a second place of a kind keeps the first', () async {
      final store = _MemAddresses()..snapshot = twoGyms();
      final places = HomePlacesController(store: store);
      await places.load();
      places.applyResolved(
        target: 'custom',
        address: 'New street 9',
        customType: 'gym',
      );
      expect(places.savedPlaces.map((place) => place.address), [
        'Street A 1',
        'Street B 2',
        'New street 9',
      ]);
      final added = places.savedPlaces.last;
      expect(added.id, isNotNull);
      expect(added.id, isNot(anyOf('a', 'b')));
    });

    test('editing Gym B changes Gym B only', () async {
      final store = _MemAddresses()..snapshot = twoGyms();
      final places = HomePlacesController(store: store);
      await places.load();
      places.applyResolved(
        target: 'custom',
        address: 'New street 9',
        customType: 'gym',
        placeId: 'b',
      );
      await places.persist();
      expect(
        store.snapshot.places.map(
          (p) => '${p['id']}:${p['title']}:${p['address']}',
        ),
        ['a:Gym A:Street A 1', 'b:Gym B:New street 9'],
      );
    });

    test('a place stored without an id gets the same id Saved Places gives '
        'it, so it can be edited on its own', () async {
      final store = _MemAddresses()
        ..snapshot = HomeAddressSnapshot(
          places: [
            {'title': 'Gym', 'type': 'gym', 'address': 'Old 1'},
            {'title': 'Gym', 'type': 'gym', 'address': 'Old 2'},
          ],
        );
      final places = HomePlacesController(store: store);
      await places.load();
      expect(places.savedPlaces.map((place) => place.id), [
        'place_legacy_0',
        'place_legacy_1',
      ]);
      places.applyResolved(
        target: 'custom',
        address: 'New 2',
        customType: 'gym',
        placeId: 'place_legacy_1',
      );
      expect(places.savedPlaces.map((place) => place.address), [
        'Old 1',
        'New 2',
      ]);
    });
  });

  testWidgets('rider-41: a long-press on Gym B names Gym B', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SavedPlaceData? edited;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: SavedPlacesRow(
              homeAddress: null,
              workAddress: null,
              savedPlaces: const [
                SavedPlaceData(
                  id: 'a',
                  title: 'Gym A',
                  type: 'gym',
                  address: 'Street A 1',
                ),
                SavedPlaceData(
                  id: 'b',
                  title: 'Gym B',
                  type: 'gym',
                  address: 'Street B 2',
                ),
              ],
              onUseSavedPlace: (address, {required target, customType}) {},
              onEditSavedPlace: (target, {customType}) {},
              onEditCustomPlace: (place) => edited = place,
              onAddPlace: () {},
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Gym B'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Gym B'));
    expect(edited?.id, 'b');
  });
}
