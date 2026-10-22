import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

/// Phase 139 moved Select Ride's filter ordering and pre-map placeholder out
/// of select_ride.dart. These pin the behaviour the rider sees so the move -
/// and any later change - cannot silently alter it.
class _ImmediateQuotes implements QuoteRepository {
  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int durationSeconds = 600,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) => Future<RideQuote>.value(
    RideQuote(
      id: 'q-$rideType',
      rideType: rideType,
      totalMinor: 25900,
      currency: 'SEK',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      signedPayload: 'sig',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<RideSelectionController> openSelectRide(
    WidgetTester tester, {
    bool instantRoute = false,
    double height = 844,
  }) async {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selection = RideSelectionController(quotes: _ImmediateQuotes());
    addTearDown(selection.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const Scaffold(body: Text('home'))),
    );
    Widget page(BuildContext _) => SelectRide(
      pickupAddress: 'Stockholm Central',
      destinationAddress: 'Odenplan',
      pickupPosition: const LatLng(59.3293, 18.0686),
      destinationPosition: const LatLng(59.3429, 18.0496),
      pickupAlreadyConfirmed: true,
      selection: selection,
    );
    nav.currentState!.push(
      instantRoute
          ? PageRouteBuilder<void>(
              settings: const RouteSettings(name: AppRoutes.selectRide),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (context, _, __) => page(context),
            )
          : MaterialPageRoute<void>(
              settings: const RouteSettings(name: AppRoutes.selectRide),
              builder: page,
            ),
    );
    return selection;
  }

  /// Ride names in the order the list shows them, top to bottom.
  List<String> listedOrder(WidgetTester tester, Iterable<String> names) {
    final list = find.byKey(const ValueKey('select-ride-list'));
    final positioned = <(String, double)>[];
    for (final name in names) {
      final hit = find.descendant(of: list, matching: find.text(name));
      if (hit.evaluate().isEmpty) continue;
      positioned.add((name, tester.getTopLeft(hit.first).dy));
    }
    positioned.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final p in positioned) p.$1];
  }

  /// Stable sort, independent of production code: ties keep catalog order.
  List<String> expectedOrder<T>(
    List<T> catalog,
    String Function(T) name,
    num Function(T)? key,
  ) {
    final indexed = [for (var i = 0; i < catalog.length; i++) (i, catalog[i])];
    if (key != null) {
      indexed.sort((a, b) {
        final byKey = key(a.$2).compareTo(key(b.$2));
        return byKey != 0 ? byKey : a.$1.compareTo(b.$1);
      });
    }
    return [for (final e in indexed) name(e.$2)];
  }

  testWidgets(
    'filter chips order the list: Faster by ETA, Cheaper by shown fare, '
    'Recommended back to catalog order',
    (tester) async {
      // Tall enough that the lazily built list shows every ride at once.
      final selection = await openSelectRide(tester, height: 2400);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(seconds: 1));
      // Opens at the middle stop; the filters show once the sheet is fully up.
      await tester.tap(find.byKey(const ValueKey('select-ride-sheet-handle')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final catalog = selection.rides().toList();
      final names = catalog.map((r) => r.name).toList();
      expect(names.toSet().length, names.length, reason: 'names must be unique');
      expect(find.text('Faster'), findsOneWidget);

      Future<List<String>> after(String chip) async {
        // The chip row scrolls sideways; Cheaper starts past the right edge.
        await tester.ensureVisible(find.text(chip));
        await tester.pump();
        await tester.tap(find.text(chip));
        await tester.pump(const Duration(milliseconds: 400));
        return listedOrder(tester, names);
      }

      final faster = await after('Faster');
      final cheaper = await after('Cheaper');
      final recommended = await after('Recommended');

      // Every ride must be on screen, or the comparison would be partial.
      expect(faster, hasLength(names.length));
      expect(
        faster,
        expectedOrder(catalog, (r) => r.name, (r) => r.etaMin),
      );
      // rider-r3-7 (a decision): the fare each tile shows, the live quote
      // when there is one, no longer the catalog base price.
      expect(
        cheaper,
        expectedOrder(
          catalog,
          (r) => r.name,
          (r) => selection.priceFor(r.id, r.price),
        ),
      );
      expect(recommended, expectedOrder(catalog, (r) => r.name, null));
    },
  );

  testWidgets(
    'shows the painted route placeholder until the live map mounts',
    (tester) async {
      await openSelectRide(tester, instantRoute: true);
      await tester.pump();

      // A painted surface filling the map area: full width, anchored top-left.
      int paintedMapArea() => find
          .descendant(
            of: find.byType(SelectRide),
            matching: find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter != null,
            ),
          )
          .evaluate()
          .where((e) {
            final box = e.renderObject! as RenderBox;
            return box.localToGlobal(Offset.zero) == Offset.zero &&
                box.size.width == 390;
          })
          .length;

      expect(find.byType(SelectRide), findsOneWidget);
      expect(find.byKey(const ValueKey('select-ride-map')), findsNothing);
      expect(paintedMapArea(), 1);

      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('select-ride-map')), findsOneWidget);
      expect(paintedMapArea(), 0);
    },
  );
}
