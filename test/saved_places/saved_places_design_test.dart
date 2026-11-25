import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/server_clock.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/home/data/home_repository.dart';
import 'package:movera_rider/features/home/presentation/widgets/places_popup.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_top_actions.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/saved_places/application/quick_save.dart';
import 'package:movera_rider/features/saved_places/data/server_saved_places.dart';
import 'package:movera_rider/features/saved_places/presentation/place_save_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saved-places design (owner 2026-11-18 "Build"; Rules
/// decisions/session-2026-11-18-saved-places-design.md): one test per
/// behaviour of the rider part.

class _Quotes implements QuoteRepository {
  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int? durationSeconds,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) async => RideQuote(
    id: 'q-$rideType',
    rideType: rideType,
    totalMinor: 25900,
    currency: 'SEK',
    expiresAt: ServerClock.now().add(const Duration(minutes: 5)),
    signedPayload: 'signature',
  );
}

Widget _app(Widget home) => MaterialApp(home: home);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

RideSelectionController _selection() => RideSelectionController(
  catalog: RideCatalogController(
    api: ApiClient(
      client: MockClient(
        (_) async => http.Response(jsonEncode({'code': 'X'}), 500),
      ),
    ),
    cache: MemoryRideCatalogCache(),
  ),
  quotes: _Quotes(),
  flags: FeatureFlags(),
);

SelectRide _categories(
  RideSelectionController selection, {
  String? preferred,
  String? offer,
  bool later = false,
}) => SelectRide(
  pickupAddress: 'Storgatan 12, Södertälje',
  destinationAddress: 'Viksbergsvägen 9, Södertälje',
  pickupPosition: const LatLng(59.1955, 17.6253),
  destinationPosition: const LatLng(59.2100, 17.6000),
  selection: selection,
  preferredCategoryId: preferred,
  offerSaveAddress: offer,
  bookingMode: later ? BookingMode.scheduled : BookingMode.now,
  lockBookingMode: later,
  initialScheduledFor: later
      ? DateTime.now().add(const Duration(days: 1))
      : null,
);

/// The categories list (the sheet of cars) is on screen.
final _categorySheet = find.byKey(
  const ValueKey('select-ride-sheet'),
  skipOffstage: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('step 1 / 8: Home capsule', () {
    testWidgets('menu + places pin; no profile button', (tester) async {
      var menu = 0, places = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: PremiumTopActions(
                onMenuTap: () => menu++,
                onPlacesTap: () => places++,
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.person_rounded), findsNothing);
      expect(find.byKey(const ValueKey('home-places-down')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-places')));
      await tester.tap(find.byKey(const ValueKey('home-menu')));
      expect((menu, places), (1, 1));
    });
  });

  group('step 2: places pop-up', () {
    Future<Future<PlacesPopupChoice?>> open(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (c) {
              ctx = c;
              return const Scaffold();
            },
          ),
        ),
      );
      final result = PlacesPopup.open(
        ctx,
        places: popupPlaces(
          home: 'Storgatan 12, Södertälje',
          work: 'Hamngatan 5, Södertälje',
          others: const [(title: 'Gym', type: 'gym', address: 'Genetaleden 7')],
        ),
        recent: [for (var i = 0; i < 12; i++) 'Gata $i, Södertälje'],
      );
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('lists saved places, add, recents and the bar; arrow up', (
      tester,
    ) async {
      await _phone(tester);
      await open(tester);
      expect(find.text('Saved Places'), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(find.byIcon(Icons.work_outline), findsOneWidget);
      expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
      expect(find.byKey(const ValueKey('places-popup-add')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-places-up')), findsOneWidget);
      expect(find.byKey(const ValueKey('places-popup-later')), findsOneWidget);
      // Scrolls to the last recent address.
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('places-popup-recent-11')),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(
        find.byKey(const ValueKey('places-popup-recent-11')),
        findsOneWidget,
      );
    });

    testWidgets('a saved place, a recent, Where to and Senare answer', (
      tester,
    ) async {
      await _phone(tester);
      for (final (key, check) in <(String, bool Function(Object?))>[
        (
          'places-popup-place-home-Home',
          (c) => c is PickSavedPlace && c.place.kind == 'home',
        ),
        (
          'places-popup-recent-0',
          (c) => c is PickRecent && c.address == 'Gata 0, Södertälje',
        ),
        ('places-popup-where-to', (c) => c is PickWhereTo),
        ('places-popup-later', (c) => c is PickLater),
      ]) {
        final result = await open(tester);
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(check(await result), isTrue, reason: key);
      }
    });
  });

  group('step 3 / 5 / 6: categories with a fixed category', () {
    testWidgets(
      'available: Set pickup opens with it, Change category goes back',
      (tester) async {
        await _phone(tester);
        final selection = _selection();
        addTearDown(selection.dispose);
        await tester.pumpWidget(
          _app(_categories(selection, preferred: 'comfort')),
        );
        // Step 5 "skip": the categories are never drawn on this path.
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          expect(_categorySheet, findsNothing, reason: 'frame $i');
        }
        expect(find.byType(SetPickupPage), findsOneWidget);
        expect(selection.selectedRideId, 'comfort');
        final link = find.byKey(const ValueKey('set-pickup-change-category'));
        expect(link, findsOneWidget);
        // The link sits in the sheet's ride header, folded in the test
        // phone's short view; its action is what is checked here.
        tester.widget<TextButton>(link).onPressed!();
        await _settle(tester, 20);
        expect(find.byType(SetPickupPage), findsNothing);
        // "Byt kategori": now the categories show.
        expect(_categorySheet, findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      },
    );

    testWidgets('step 7: a Senare ride skips the categories the same way', (
      tester,
    ) async {
      await _phone(tester);
      final selection = _selection();
      addTearDown(selection.dispose);
      await tester.pumpWidget(
        _app(_categories(selection, preferred: 'comfort', later: true)),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(_categorySheet, findsNothing, reason: 'frame $i');
      }
      expect(selection.selectedRideId, 'comfort');
      expect(find.byType(SetPickupPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });

    test(
      'step 7: Where to / Senare find a saved place\'s fixed category',
      () async {
        final save = PlaceQuickSave(supported: () => true);
        await save.save('Genetaleden 7', 'gym');
        await save.fixCategory('Genetaleden 7', 'gym', 'premium');
        await save.save('Storgatan 12', 'home');
        await save.fixCategory('Storgatan 12', 'home', 'comfort');
        expect(await save.categoryForAddress('genetaleden 7 '), 'premium');
        expect(await save.categoryForAddress('Storgatan 12'), 'comfort');
        expect(await save.categoryForAddress('Elsewhere 1'), isNull);
      },
    );

    testWidgets('not offered here: categories stay, only what is offered', (
      tester,
    ) async {
      await _phone(tester);
      final selection = _selection();
      addTearDown(selection.dispose);
      await tester.pumpWidget(_app(_categories(selection, preferred: 'gone')));
      await _settle(tester, 20);
      expect(find.byType(SetPickupPage), findsNothing);
      expect(_categorySheet, findsOneWidget);
      expect(find.byType(SelectRide), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('no fixed category: the categories screen as before', (
      tester,
    ) async {
      await _phone(tester);
      final selection = _selection();
      addTearDown(selection.dispose);
      await tester.pumpWidget(_app(_categories(selection)));
      await _settle(tester, 20);
      expect(find.byType(SetPickupPage), findsNothing);
      expect(find.byType(PlaceSaveSheet), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('step 3b / 4 / 4b: the S3 save sheet', () {
    testWidgets('on the categories screen from a recent address at once', (
      tester,
    ) async {
      // Owner 2026-11-18: no 2 s wait; as soon as the screen is open.
      await _phone(tester);
      final selection = _selection();
      addTearDown(selection.dispose);
      await tester.pumpWidget(
        _app(_categories(selection, offer: 'Viksbergsvägen 9, Södertälje')),
      );
      await _settle(tester, 5);
      expect(find.text('Save this address?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });

    // Owner 2026-11-18 (phone test of #651): by default ~2 s after the
    // screen opens, on top, in every car-sheet position, screen dimmed 20 %.
    for (final (pos, drag) in <(String, Offset?)>[
      ('down', const Offset(0, 500)),
      ('middle', null),
      ('up', const Offset(0, -600)),
    ]) {
      testWidgets('by default on top with the car sheet $pos', (tester) async {
        // The car sheet is moved first; the S3 sheet waits 2 s for it here.
        PlaceSaveSheet.debugExtraDelay = const Duration(seconds: 2);
        addTearDown(() => PlaceSaveSheet.debugExtraDelay = null);
        await _phone(tester);
        final selection = _selection();
        addTearDown(selection.dispose);
        await tester.pumpWidget(
          _app(_categories(selection, offer: 'Viksbergsvägen 9, Södertälje')),
        );
        await _settle(tester, 3);
        if (drag != null) {
          await tester.dragFrom(const Offset(195, 600), drag);
        }
        await _settle(tester, 6);
        expect(find.text('Save this address?'), findsNothing);
        await _settle(tester, 16); // ~2.5 s after open + slide
        expect(find.text('Save this address?'), findsOneWidget);
        // On top: a tap on its title reaches the S3 sheet, not the cars.
        final hit = tester.hitTestOnBinding(
          tester.getCenter(find.text('Save this address?')),
        );
        final sheetBox = tester.renderObject(
          find.byKey(const ValueKey('place-save-sheet')),
        );
        expect(hit.path.any((e) => e.target == sheetBox), isTrue);
        final dim = tester.widget<ColoredBox>(
          find.byKey(const ValueKey('place-save-dim')),
        );
        expect(dim.color.a, closeTo(0.20, 0.001));
        expect(dim.color.r + dim.color.g + dim.color.b, 0);
        await tester.binding.setSurfaceSize(null);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      });
    }

    Future<void> pumpSheet(
      WidgetTester tester, {
      bool supported = true,
      PlaceQuickSave? quickSave,
    }) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Colors.grey)),
                Positioned.fill(
                  child: PlaceSaveSheet(
                    address: 'Viksbergsvägen 9, Södertälje',
                    delay: const Duration(milliseconds: 10),
                    quickSave:
                        quickSave ?? PlaceQuickSave(supported: () => supported),
                    categories: () => const [
                      (id: 'economy', name: 'Movera'),
                      (id: 'comfort', name: 'Comfort'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('5 s with no action closes it, nothing saved', (tester) async {
      await pumpSheet(tester);
      expect(find.text('Save this address?'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Save this address?'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.text('Save this address?'), findsNothing);
      final snap = await HomeAddressRepository().load();
      expect(snap.places, isEmpty);
      expect(snap.home, isNull);
    });

    testWidgets('a chip tap stops the timer; the question closes after 5 s', (
      tester,
    ) async {
      await pumpSheet(tester);
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.byKey(const ValueKey('place-save-type-gym')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 3));
      // The first timer would have closed it by now.
      expect(find.text('Saved as Gym'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Saved as Gym'), findsNothing);
      // Saved as Gym stays saved; no category was fixed.
      final snap = await HomeAddressRepository().load();
      expect(snap.places.single['type'], 'gym');
    });

    testWidgets('a failed save restarts the timer; closes after 5 s', (
      tester,
    ) async {
      await pumpSheet(tester, quickSave: _FailingSave());
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.byKey(const ValueKey('place-save-type-gym')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Saved as Gym'), findsNothing);
      expect(find.text('Save this address?'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Save this address?'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.text('Save this address?'), findsNothing);
      final snap = await HomeAddressRepository().load();
      expect(snap.places, isEmpty);
      expect(snap.home, isNull);
    });

    testWidgets(
      'type chips; a tap saves, then asks a category, which is kept',
      (tester) async {
        await pumpSheet(tester);
        for (final t in PlaceQuickSave.types) {
          expect(find.byKey(ValueKey('place-save-type-$t')), findsOneWidget);
        }
        await tester.tap(find.byKey(const ValueKey('place-save-type-gym')));
        await tester.pumpAndSettle();
        expect(find.text('Saved as Gym'), findsOneWidget);
        expect(
          find.text('Always choose a category for this place?'),
          findsOneWidget,
        );
        var snap = await HomeAddressRepository().load();
        expect(snap.places.single['type'], 'gym');
        await tester.tap(
          find.byKey(const ValueKey('place-save-category-comfort')),
        );
        await tester.pumpAndSettle();
        snap = await HomeAddressRepository().load();
        expect(
          snap.categories![placeCategoryKey(
            'gym',
            'Viksbergsvägen 9, Södertälje',
          )],
          'comfort',
        );
        expect(find.text('Saved as Gym'), findsNothing);
      },
    );

    testWidgets('Undo puts the places back', (tester) async {
      await pumpSheet(tester);
      await tester.tap(find.byKey(const ValueKey('place-save-type-home')));
      await tester.pumpAndSettle();
      expect((await HomeAddressRepository().load()).home, isNotNull);
      await tester.tap(find.byKey(const ValueKey('place-save-undo')));
      await tester.pumpAndSettle();
      expect((await HomeAddressRepository().load()).home, isNull);
    });

    testWidgets('an older server: no category question', (tester) async {
      await pumpSheet(tester, supported: false);
      await tester.tap(find.byKey(const ValueKey('place-save-type-work')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Saved as Work'), findsOneWidget);
      expect(
        find.text('Always choose a category for this place?'),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Saved as Work'), findsNothing);
    });

    for (final (how, act) in <(String, Future<void> Function(WidgetTester))>[
      ('the X', (t) => t.tap(find.byKey(const ValueKey('place-save-close')))),
      (
        'a swipe down',
        (t) => t.fling(
          find.text('Save this address?'),
          const Offset(0, 300),
          1000,
        ),
      ),
      ('a tap outside', (t) => t.tapAt(const Offset(195, 100))),
    ]) {
      testWidgets('$how closes it and saves nothing', (tester) async {
        await pumpSheet(tester);
        expect(find.text('Save this address?'), findsOneWidget);
        await act(tester);
        await tester.pumpAndSettle();
        expect(find.text('Save this address?'), findsNothing);
        final snap = await HomeAddressRepository().load();
        expect(snap.home, isNull);
        expect(snap.work, isNull);
        expect(snap.places, isEmpty);
      });
    }
  });

  group('contract v0.18.129: preferredCategoryId on the wire', () {
    ServerPlace gym({bool field = true, String? category}) => ServerPlace.from({
      'placeId': 'p1',
      'kind': 'other',
      'label': 'Gym',
      'type': 'gym',
      'place': {'address': 'Genetaleden 7'},
      if (field) 'preferredCategoryId': category,
    })!;

    HomeAddressSnapshot local(String? category) => HomeAddressSnapshot(
      places: const [
        {'id': 'p1', 'title': 'Gym', 'type': 'gym', 'address': 'Genetaleden 7'},
      ],
      categories: {
        if (category != null)
          placeCategoryKey('other', 'Genetaleden 7'): category,
      },
    );

    test('a new server: a changed category is a PUT with the field', () {
      final plan = planChanges([gym()], local('comfort'), sendCategory: true);
      expect(plan.updates.single.body['preferredCategoryId'], 'comfort');
    });

    test('an older server: the field is never sent', () {
      final old = gym(field: false);
      expect(old.hasCategoryField, isFalse);
      final plan = planChanges([old], local('comfort'));
      expect(plan.isEmpty, isTrue);
    });

    test('the server category reaches the phone copy', () {
      final snap = snapshotFor([gym(category: 'premium')]);
      expect(snap.categories, {
        placeCategoryKey('other', 'Genetaleden 7'): 'premium',
      });
      expect(snapshotFor([gym(field: false)]).categories, isNull);
    });
  });
}

class _FailingSave extends PlaceQuickSave {
  _FailingSave() : super(supported: () => true);

  @override
  Future<HomeAddressSnapshot> save(String address, String type) async =>
      throw Exception('save failed');
}
