import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/saved_places/application/saved_places_controller.dart';
import 'package:movera_rider/features/saved_places/domain/saved_place.dart';
import 'package:movera_rider/features/saved_places/presentation/add_place.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('AddPlace Save persists and returns the saved place', (
    tester,
  ) async {
    PlaceShortcut? returned;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  returned = await Navigator.push<PlaceShortcut>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddPlace(
                        // FLOW-4: the button resolves a real address.
                        currentAddress: () async => 'Sveavägen 1, Stockholm',
                      ),
                    ),
                  );
                },
                child: const Text('Open AddPlace'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open AddPlace'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Gym');
    await tester.tap(find.text('Add location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CURRENT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(returned, isNotNull);
    expect(returned!.title, 'Gym');
    expect(returned!.subtitle, 'Sveavägen 1, Stockholm');

    final restarted = SavedPlacesController();
    await restarted.hydrate();
    expect(restarted.shortcuts(), hasLength(1));
    expect(restarted.shortcuts().single.title, 'Gym');
    expect(restarted.shortcuts().single.subtitle, 'Sveavägen 1, Stockholm');
  });

  test(
    'edit and delete are visible from Saved Places and Home immediately',
    () async {
      final places = SavedPlacesController();
      final home = HomePlacesController();
      var changeCount = 0;
      final sub = home.changes.listen((_) => changeCount += 1);
      addTearDown(sub.cancel);

      await places.save(
        const PlaceShortcut(title: 'Gym', subtitle: 'Old address', kind: 'gym'),
      );
      await home.load();
      expect(home.savedPlaces.single.title, 'Gym');
      expect(home.savedPlaces.single.address, 'Old address');

      // Editing passes the place's id (FLOW-5: without one it is a new place).
      await places.hydrate();
      await places.save(
        PlaceShortcut(
          title: 'Training',
          subtitle: 'New address',
          kind: 'gym',
          id: places.shortcuts().single.id,
        ),
      );
      await home.load();
      await places.hydrate();
      expect(places.shortcuts().single.title, 'Training');
      expect(places.shortcuts().single.subtitle, 'New address');
      expect(home.savedPlaces.single.title, 'Training');
      expect(home.savedPlaces.single.address, 'New address');

      await places.remove(places.shortcuts().single);
      await home.load();
      await places.hydrate();
      expect(places.shortcuts(), isEmpty);
      expect(home.savedPlaces, isEmpty);
      expect(changeCount, greaterThanOrEqualTo(3));
    },
  );

  test('fresh controller restores a previously saved place', () async {
    final first = SavedPlacesController();
    await first.save(
      const PlaceShortcut(
        title: 'School',
        subtitle: 'Campus road',
        kind: 'school',
      ),
    );

    final restarted = SavedPlacesController();
    await restarted.hydrate();

    expect(restarted.shortcuts(), hasLength(1));
    expect(restarted.shortcuts().single.title, 'School');
    expect(restarted.shortcuts().single.subtitle, 'Campus road');
  });
}
