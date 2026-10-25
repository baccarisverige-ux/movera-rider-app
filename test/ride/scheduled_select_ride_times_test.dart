import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

/// A ride booked for later shows its chosen pickup time in the list, not the
/// "N min" ETA of a ride right now.
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

  Future<void> open(WidgetTester tester, RideSelectionController selection) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Stockholm Central',
          destinationAddress: 'Odenplan',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.3429, 18.0496),
          pickupAlreadyConfirmed: true,
          selection: selection,
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a scheduled ride shows its pickup time, not a minutes ETA', (
    tester,
  ) async {
    final selection = RideSelectionController(quotes: _ImmediateQuotes());
    addTearDown(selection.dispose);
    selection.setBookingMode(BookingMode.scheduled);
    selection.scheduleFor(DateTime(2026, 10, 13, 6, 55));
    await open(tester, selection);
    expect(find.textContaining('Pickup 06:55 · Arrive '), findsWidgets);
    expect(find.textContaining(' min · Arrive '), findsNothing);
  });

  testWidgets('a ride now keeps its minutes ETA', (tester) async {
    final selection = RideSelectionController(quotes: _ImmediateQuotes());
    addTearDown(selection.dispose);
    await open(tester, selection);
    // Owner round 2, like the other ride apps: "07:14 · 8 min".
    expect(find.textContaining(RegExp(r'^\d\d:\d\d · \d+ min$')), findsWidgets);
    expect(find.textContaining('Pickup '), findsNothing);
  });
}
