import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/home/data/home_repository.dart';
import 'package:movera_rider/features/saved_places/application/saved_places_controller.dart';
import 'package:movera_rider/features/saved_places/domain/saved_place.dart';
import 'package:movera_rider/features/saved_places/presentation/add_place.dart';
import 'package:movera_rider/features/saved_places/presentation/saved_places.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BrokenStore extends HomeAddressRepository {
  @override
  Future<HomeAddressSnapshot> load() async => throw StateError('disk');
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(home: child),
    ),
  );
  await tester.pumpAndSettle();
}

Future<Set<String>> _savedValues() async {
  final prefs = await SharedPreferences.getInstance();
  return {for (final key in prefs.getKeys()) '${prefs.get(key)}'};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'FLOW-4: Current location never saves the words "Current location"',
    (tester) async {
      await _pump(tester, const AddPlace(kind: 'home'));
      await tester.enterText(find.byType(TextField).first, 'Home');
      await tester.tap(find.text('Add location'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CURRENT'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      // No location in the test host: the picker explains, nothing is chosen.
      expect(find.text('Pickup location'), findsOneWidget);
      expect(find.textContaining('for the address'), findsOneWidget);
      if (find.text('Save').evaluate().isNotEmpty) {
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      }
      final values = (await tester.runAsync(_savedValues))!;
      expect(values.any((v) => v.contains('Current location')), isFalse);
    },
  );

  testWidgets('FLOW-4: Current location saves the resolved street address', (
    tester,
  ) async {
    await _pump(
      tester,
      AddPlace(
        kind: 'home',
        currentAddress: () async => 'Sveavägen 1, 111 57 Stockholm',
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Home');
    await tester.tap(find.text('Add location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CURRENT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(
      prefs.getString('movera_home_address'),
      'Sveavägen 1, 111 57 Stockholm',
    );
  });

  testWidgets('FLOW-5: a new place named Home asks before replacing Home', (
    tester,
  ) async {
    final places = SavedPlacesController();
    await tester.runAsync(() async {
      await places.save(
        const PlaceShortcut(
          title: 'Home',
          subtitle: 'Sveavägen 1',
          kind: 'home',
        ),
      );
      await places.save(
        const PlaceShortcut(
          title: 'Work',
          subtitle: 'Kungsgatan 5',
          kind: 'office',
        ),
      );
    });
    // "Add another place": no kind, no initial place.
    await _pump(tester, AddPlace(controller: places));
    await tester.enterText(find.byType(TextField).first, 'Home');
    await tester.tap(find.text('Add location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kungsgatan 5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Replace your saved Home?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(prefs.getString('movera_home_address'), 'Sveavägen 1');
  });

  // rider-r4-47: a new name typed for Home was accepted and then dropped
  // (the slot keeps its name), so the field is not editable there.
  testWidgets('Home and Work keep their name in Edit saved place', (
    tester,
  ) async {
    await _pump(
      tester,
      const AddPlace(
        initial: PlaceShortcut(
          title: 'Home',
          subtitle: 'Sveavägen 1',
          kind: 'home',
        ),
      ),
    );
    final name = tester.widget<TextField>(find.byType(TextField).first);
    expect(name.enabled, isFalse);
    expect(name.controller?.text, 'Home');
  });

  test('FLOW-5: two custom places with the same name are both kept', () async {
    final places = SavedPlacesController();
    await places.save(
      const PlaceShortcut(title: 'Gym', subtitle: 'SATS Odenplan', kind: 'gym'),
    );
    await places.save(
      const PlaceShortcut(
        title: 'Gym',
        subtitle: 'Nordic Wellness Solna',
        kind: 'gym',
      ),
    );
    final gyms = places.shortcuts().where((p) => p.kind == 'gym').toList();
    expect(
      gyms.map((p) => p.subtitle),
      unorderedEquals(['SATS Odenplan', 'Nordic Wellness Solna']),
    );
    expect(gyms.map((p) => p.id).toSet(), hasLength(2));
  });

  test('FLOW-5: removing one custom place keeps the others and Home', () async {
    final places = SavedPlacesController();
    await places.save(
      const PlaceShortcut(title: 'Home', subtitle: 'Sveavägen 1', kind: 'home'),
    );
    final first = await places.save(
      const PlaceShortcut(title: 'Gym', subtitle: 'SATS Odenplan', kind: 'gym'),
    );
    await places.save(
      const PlaceShortcut(
        title: 'Gym',
        subtitle: 'Nordic Wellness Solna',
        kind: 'gym',
      ),
    );
    await places.remove(first);
    expect(
      places.shortcuts().map((p) => p.subtitle),
      unorderedEquals(['Sveavägen 1', 'Nordic Wellness Solna']),
    );
  });

  test(
    'FLOW-5: places saved before ids existed can still be edited one by one',
    () async {
      SharedPreferences.setMockInitialValues({
        'movera_saved_places':
            '[{"title":"Gym","type":"gym","address":"A"},'
            '{"title":"Gym","type":"gym","address":"B"}]',
      });
      final places = SavedPlacesController();
      await places.hydrate();
      final second = places.shortcuts().last;
      await places.save(
        PlaceShortcut(title: 'Gym', subtitle: 'C', kind: 'gym', id: second.id),
      );
      expect(places.shortcuts().map((p) => p.subtitle), ['A', 'C']);
    },
  );

  test('rider-u220: a place stored without an id, or with an id another '
      'place has, gets its own id; deleting it removes only it', () async {
    SharedPreferences.setMockInitialValues({
      'movera_saved_places':
          '[{"id":"place_legacy_1","title":"Bar","type":"other","address":"B"},'
          '{"title":"School","type":"school","address":"C"},'
          '{"id":"place_legacy_1","title":"Gym","type":"gym","address":"D"}]',
    });
    final places = SavedPlacesController();
    await places.hydrate();
    final ids = places.shortcuts().map((p) => p.id).toList();
    expect(ids.toSet(), hasLength(3));
    final home = HomePlacesController();
    await home.load();
    expect(home.savedPlaces.map((p) => p.id), ids, reason: 'Home agrees');
    await places.remove(places.shortcuts()[1]);
    expect(places.shortcuts().map((p) => p.subtitle), ['B', 'D']);
  });

  testWidgets('FLOW-15: delete asks first and keeps the place on Cancel', (
    tester,
  ) async {
    final places = SavedPlacesController();
    await tester.runAsync(
      () => places.save(
        const PlaceShortcut(
          title: 'Gym',
          subtitle: 'SATS Odenplan',
          kind: 'gym',
        ),
      ),
    );
    await _pump(tester, SavedPlaces(controller: places));

    await tester.tap(find.byTooltip('Delete Gym'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Gym?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('SATS Odenplan'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete Gym'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('SATS Odenplan'), findsNothing);
  });

  testWidgets('FLOW-15: a failed load shows an error instead of a spinner', (
    tester,
  ) async {
    await _pump(
      tester,
      SavedPlaces(controller: SavedPlacesController(store: _BrokenStore())),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('Couldn’t load your saved places. Try again.'),
      findsOneWidget,
    );
  });
}
