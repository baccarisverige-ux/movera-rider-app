import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/home/data/home_repository.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-17 ("Yes, like the example"): From fills with the current
/// address as soon as it is known, and recents show their distance.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const here = GeoPoint(59.3326, 18.0649); // Sergels torg

  Widget picker({
    String? pickup,
    ValueListenable<String?>? pickupUpdates,
    List<String> recent = const [],
    Map<String, GeoPoint> recentPoints = const {},
  }) => MaterialApp(
    home: RoutePickerPage(
      pickupAddress: pickup,
      pickupUpdates: pickupUpdates,
      destinationAddress: '',
      stops: const [],
      stopsSupported: true,
      initialField: 'destination',
      capture: EarlyInputCapture(),
      here: here,
      homeAddress: null,
      workAddress: null,
      recent: recent,
      recentPoints: recentPoints,
      onPickOnMap: ({required pickup, required address}) async => null,
      onFinish: (_) async => null,
    ),
  );

  testWidgets('a current address found after opening fills From', (
    tester,
  ) async {
    final live = ValueNotifier<String?>(null);
    await tester.pumpWidget(picker(pickupUpdates: live));
    await tester.pump();
    live.value = 'Drottninggatan 5, 111 51 Stockholm';
    await tester.pump();
    final from = tester.widget<TextField>(
      find.byKey(const ValueKey('route-picker-field-pickup')),
    );
    expect(from.controller!.text, contains('Drottninggatan 5'));
  });

  testWidgets('recents show km from here; old ones without a point do not', (
    tester,
  ) async {
    await tester.pumpWidget(
      picker(
        pickup: 'Sergels torg 1, Stockholm',
        recent: const [
          'Odenplan 1, 113 22 Stockholm',
          'Arlanda Terminal 5, 190 45 Stockholm-Arlanda',
          'Gamla stan 3, 111 29 Stockholm',
        ],
        recentPoints: const {
          'Odenplan 1, 113 22 Stockholm': GeoPoint(59.3430, 18.0496),
          'Arlanda Terminal 5, 190 45 Stockholm-Arlanda': GeoPoint(
            59.6498,
            17.9238,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1.4 km'), findsOneWidget);
    expect(find.text('36 km'), findsOneWidget);
    expect(find.text('Gamla stan 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('a recent keeps its point across a restart', () async {
    final places = HomePlacesController(store: HomeAddressRepository());
    await places.load();
    places.remember('Odenplan 1', point: const GeoPoint(59.343, 18.0496));
    places.remember('Typed street 2');
    await places.persist();
    final again = HomePlacesController(store: HomeAddressRepository());
    await again.load();
    expect(again.recentAddresses, ['Typed street 2', 'Odenplan 1']);
    expect(again.recentPoints['Odenplan 1']?.latitude, 59.343);
    expect(again.recentPoints['Odenplan 1']?.longitude, 18.0496);
    expect(again.recentPoints['Typed street 2'], isNull);
  });
}
