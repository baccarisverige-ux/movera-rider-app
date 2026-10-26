import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/finding_driver/presentation/ride_details_sheet.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const stops = [
    RouteStop(
      address: 'Hötorget 1, Stockholm',
      latitude: 59.33,
      longitude: 18.06,
    ),
    RouteStop(
      address: 'Odenplan 2, Stockholm',
      latitude: 59.34,
      longitude: 18.05,
    ),
  ];

  testWidgets('shows pickup, stops in order and destination as plain rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RideDetailsSheet(
              pickupAddress: 'Sergels torg 1, Stockholm',
              destinationAddress: 'Arlanda, Stockholm',
              stops: stops,
              rideType: 'Movera',
              price: 259,
              paymentMethod: 'Apple Pay',
              notes: RideNotes.empty,
              onCancelTrip: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ride-details-pickup')), findsOneWidget);
    expect(find.byKey(const ValueKey('ride-details-stop-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('ride-details-stop-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ride-details-destination')),
      findsOneWidget,
    );
    expect(find.textContaining('Hötorget'), findsOneWidget);
    expect(find.text('Stop 2'), findsOneWidget);
    // The route is changed on the route screen, not here.
    expect(find.text('Change'), findsNothing);
    expect(find.text('Remove'), findsNothing);
    expect(find.text('Add stop'), findsNothing);
  });
}
