import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:movera_rider/features/ride_selection/domain/ride_selection.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

class _Catalog extends RideSelectionRepository {
  _Catalog(this.items);

  final List<RideCatalogItem> items;

  @override
  List<RideCatalogItem> rides() => items;
}

class _ImmediateQuoteRepository implements QuoteRepository {
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
  }) {
    return Future<RideQuote>.value(
      RideQuote(
        id: 'journey-quote-$rideType',
        rideType: rideType,
        totalMinor: 29900,
        currency: 'SEK',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        signedPayload: 'journey-signature',
      ),
    );
  }
}

RideCatalogItem _remoteRide(String id, String name) => RideCatalogItem(
  id: id,
  image: 'assets/images/rides/movera.webp',
  name: name,
  note: 'Remote catalog category',
  arrival: '7 min',
  etaMin: 7,
  price: 299,
  seats: 4,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> openSelectRide(
    WidgetTester tester,
    RideSelectionController selection,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(selection.dispose);

    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('catalog-home')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.selectRide),
        builder: (_) => SelectRide(
          pickupAddress: 'Stockholm Central',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.6519, 17.9186),
          pickupAlreadyConfirmed: true,
          selection: selection,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('empty catalog is honest and cannot start a booking', (
    tester,
  ) async {
    final selection = RideSelectionController(store: _Catalog(const []));
    await openSelectRide(tester, selection);

    expect(find.byType(SelectRide), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(SelectRide)))?.settings.name,
      AppRoutes.selectRide,
    );
    expect(selection.ensureCatalogSelection(), isNull);
    expect(find.text('No rides available'), findsOneWidget);
    expect(find.byType(FindingDrivers), findsNothing);

    await tester.tap(find.text('No rides available'));
    await tester.pump();

    expect(
      find.text('No ride category is available. Try again.'),
      findsWidgets,
    );
    expect(find.byType(FindingDrivers), findsNothing);
  });

  testWidgets('catalog without movera selects the first authoritative item', (
    tester,
  ) async {
    final selection = RideSelectionController(
      store: _Catalog([_remoteRide('remote-only', 'Remote Only')]),
      quotes: _ImmediateQuoteRepository(),
    );
    await openSelectRide(tester, selection);

    expect(find.byType(SelectRide), findsOneWidget);
    expect(selection.selectedRideId, 'remote-only');
    expect(find.text('Remote Only'), findsWidgets);
    expect(find.text('Movera'), findsNothing);
    expect(find.byType(FindingDrivers), findsNothing);
  });
}
