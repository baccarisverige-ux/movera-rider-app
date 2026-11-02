import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/home/presentation/widgets/saved_places_row.dart';

// Owner 2026-11-02: "Home button for saved address looks good size but not
// work ! Make it all same size". Every saved-address button is the Home
// button's size, and each one does its own action when tapped.

const _places = [
  SavedPlaceData(
    title: 'gym',
    type: 'gym',
    address: 'Sveavägen 20, 111 57 Stockholm',
  ),
  SavedPlaceData(
    title: 'Mamma',
    type: 'family',
    address: 'Götgatan 5, 116 46 Stockholm',
  ),
];

Future<List<String>> _pumpRow(
  WidgetTester tester, {
  required String? home,
  required String? work,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final taps = <String>[];
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: SavedPlacesRow(
            homeAddress: home,
            workAddress: work,
            savedPlaces: _places,
            onUseSavedPlace: (address, {required target, customType}) =>
                taps.add('$target:${customType ?? ''}:$address'),
            onAddPlace: () => taps.add('add'),
          ),
        ),
      ),
    ),
  );
  return taps;
}

List<Size> _cardSizes(WidgetTester tester) => tester
    .widgetList<InkWell>(
      find.descendant(
        of: find.byType(SavedPlacesRow),
        matching: find.byType(InkWell),
      ),
    )
    .map((w) => tester.getSize(find.byWidget(w)))
    .toList();

void main() {
  for (final saved in [true, false]) {
    final label = saved ? 'with Home and Work saved' : 'with nothing saved';

    testWidgets('every saved-address button is the Home size ($label)', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        home: saved ? 'Drottninggatan 10, 111 51 Stockholm' : null,
        work: saved ? 'Kungsgatan 4, 111 43 Stockholm' : null,
      );
      final sizes = _cardSizes(tester);
      expect(sizes, hasLength(5)); // Home, Work, Add, two custom places
      for (final size in sizes) {
        expect(size, sizes.first);
      }
      final icons = [
        ...tester.widgetList<Icon>(
          find.descendant(
            of: find.byType(SavedPlacesRow),
            matching: find.byType(Icon),
          ),
        ),
      ].map((i) => i.size);
      // The custom places' icons are the Home icon's size.
      for (final s in icons) {
        expect(s, closeTo(12.3, 0.01));
      }
    });

    testWidgets('tapping each saved-address button does its action ($label)', (
      tester,
    ) async {
      final home = saved ? 'Drottninggatan 10, 111 51 Stockholm' : null;
      final work = saved ? 'Kungsgatan 4, 111 43 Stockholm' : null;
      final taps = await _pumpRow(tester, home: home, work: work);
      final cards = find.descendant(
        of: find.byType(SavedPlacesRow),
        matching: find.byType(InkWell),
      );
      for (var i = 0; i < 5; i++) {
        await tester.ensureVisible(cards.at(i));
        await tester.pumpAndSettle();
        await tester.tap(cards.at(i));
        await tester.pump();
      }
      expect(taps, [
        'home::$home',
        'work::$work',
        'add',
        'custom:gym:Sveavägen 20, 111 57 Stockholm',
        'custom:family:Götgatan 5, 116 46 Stockholm',
      ]);
    });
  }
}
