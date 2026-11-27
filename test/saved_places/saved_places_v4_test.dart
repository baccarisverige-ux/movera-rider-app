import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/home/data/home_repository.dart';
import 'package:movera_rider/features/saved_places/application/saved_places_controller.dart';
import 'package:movera_rider/features/saved_places/data/server_saved_places.dart';
import 'package:movera_rider/features/saved_places/domain/saved_place.dart';
import 'package:movera_rider/features/saved_places/presentation/add_place.dart';
import 'package:movera_rider/features/saved_places/presentation/saved_places.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemAddresses extends HomeAddressRepository {
  HomeAddressSnapshot snapshot = HomeAddressSnapshot();

  @override
  Future<HomeAddressSnapshot> load() async => snapshot;

  @override
  Future<void> save(HomeAddressSnapshot data) async => snapshot = data;
}

/// Saved places v4 (owner 2026-11-27): not a restyle only. Add place has
/// Home's 7-type picker, and each type is saved as kind other + its key;
/// Menu > Saved places keeps Home's custom-place limit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void size(WidgetTester t) {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Widget app(Widget home) => ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, _) => MaterialApp(home: home),
  );

  const types = [
    'gym',
    'mall',
    'school',
    'airport',
    'family',
    'restaurant',
    'other',
  ];
  for (final type in types) {
    testWidgets('Add place: saving type $type sends kind other + "$type"', (
      t,
    ) async {
      size(t);
      final store = _MemAddresses();
      final places = SavedPlacesController(store: store);
      PlaceShortcut? saved;
      await t.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await Navigator.of(context).push<PlaceShortcut>(
                  MaterialPageRoute(
                    builder: (_) => AddPlace(
                      controller: places,
                      currentAddress: () async => 'Sveavägen 1, Stockholm',
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey('place-type-$type')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('add-place-address')));
      await t.pumpAndSettle();
      await t.tap(find.text('Use current location'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('add-place-save')));
      await t.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.kind, type);
      final request = requestsFor(store.snapshot).single;
      expect(request['kind'], 'other');
      expect(request['type'], type);
      expect((request['place'] as Map)['address'], 'Sveavägen 1, Stockholm');
    });
  }

  testWidgets('Menu > Saved places keeps the homeMaxCustomPlaces limit', (
    t,
  ) async {
    size(t);
    final store = _MemAddresses();
    final places = SavedPlacesController(store: store);
    for (var i = 0; i < HomePlacesController.maxCustom; i++) {
      await places.save(
        PlaceShortcut(title: 'Place $i', subtitle: 'Gata $i', kind: 'gym'),
      );
    }
    await t.pumpWidget(app(SavedPlaces(controller: places)));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('saved-places-add')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('saved-places-add')));
    await t.pumpAndSettle();
    expect(find.text('You can save up to 8 custom places.'), findsOneWidget);
    expect(find.byType(AddPlace), findsNothing);
    expect(store.snapshot.places, hasLength(HomePlacesController.maxCustom));
  });

  testWidgets('Add place refuses a 9th custom place too', (t) async {
    size(t);
    final store = _MemAddresses();
    final places = SavedPlacesController(store: store);
    for (var i = 0; i < HomePlacesController.maxCustom; i++) {
      await places.save(
        PlaceShortcut(title: 'Place $i', subtitle: 'Gata $i', kind: 'gym'),
      );
    }
    await t.pumpWidget(
      app(
        AddPlace(
          controller: places,
          currentAddress: () async => 'Sveavägen 1, Stockholm',
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('place-type-gym')));
    await t.tap(find.byKey(const ValueKey('add-place-address')));
    await t.pumpAndSettle();
    await t.tap(find.text('Use current location'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('add-place-save')));
    await t.pumpAndSettle();
    expect(find.text('You can save up to 8 custom places.'), findsOneWidget);
    expect(store.snapshot.places, hasLength(HomePlacesController.maxCustom));
  });
}
