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

/// Phase 139 moved Select Ride's pre-map placeholder out of select_ride.dart.
/// These pin the behaviour the rider sees (the list order, owner round 2,
/// replaced the filter chips) so a later change cannot silently alter it.
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

  testWidgets(
    'owner round 2: everyday rides first, then the premium ones, each in '
    'catalog order; the two headings show once the sheet is fully up',
    (tester) async {
      // Tall enough that the lazily built list shows every ride at once.
      final selection = await openSelectRide(tester, height: 2400);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(seconds: 1));

      final catalog = selection.rides().toList();
      final names = catalog.map((r) => r.name).toList();
      expect(names.toSet().length, names.length, reason: 'names must be unique');
      const premium = {'premium', 'business', 'electric', 'pet', 'kids'};
      final expected = [
        for (final r in catalog)
          if (!premium.contains(r.id)) r.name,
        for (final r in catalog)
          if (premium.contains(r.id)) r.name,
      ];
      expect(catalog.any((r) => premium.contains(r.id)), isTrue);
      expect(catalog.any((r) => !premium.contains(r.id)), isTrue);

      // No filter chips any more (owner round 2).
      expect(find.text('Faster'), findsNothing);
      expect(find.text('Cheaper'), findsNothing);

      // Fully up: both headings, above their groups.
      await tester.tap(find.byKey(const ValueKey('select-ride-sheet-handle')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final order = listedOrder(tester, names);
      expect(order, hasLength(names.length));
      expect(order, expected);
      final list = find.byKey(const ValueKey('select-ride-list'));
      final forYou = find.byKey(const ValueKey('select-ride-heading-Rides for you'));
      final premiumHeading = find.byKey(const ValueKey('select-ride-heading-Premium'));
      expect(forYou, findsOneWidget);
      expect(premiumHeading, findsOneWidget);
      final firstPremium = expected.firstWhere(
        (name) => premium.contains(catalog.firstWhere((r) => r.name == name).id),
      );
      final firstPremiumY = tester
          .getTopLeft(
            find.descendant(of: list, matching: find.text(firstPremium)).last,
          )
          .dy;
      final headingY = tester.getTopLeft(premiumHeading.first).dy;
      expect(headingY, lessThan(firstPremiumY));
      expect(tester.getTopLeft(forYou).dy, lessThan(headingY));
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
