import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget host({required bool inTrip}) {
    return MaterialApp(
      home: Scaffold(
        body: WaitingRideDetailsCard(
          rideType: 'Movera',
          pickupAddress: 'Sveavägen 1, Stockholm',
          destinationAddress: 'Hornsgatan 2, Stockholm',
          inTrip: inTrip,
          paymentMethod: 'Apple Pay',
          price: 259,
          onMore: () {},
        ),
      ),
    );
  }

  testWidgets('pre-trip details remain pickup-focused', (tester) async {
    await tester.pumpWidget(host(inTrip: false));

    expect(find.text('Meet at Sveavägen 1, Stockholm'), findsOneWidget);
    expect(find.text('To Hornsgatan 2, Stockholm'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'in-trip details switch to the destination and never regress to pickup copy',
    (tester) async {
      await tester.pumpWidget(host(inTrip: true));

      expect(find.text('To Hornsgatan 2, Stockholm'), findsOneWidget);
      expect(find.text('Meet at Sveavägen 1, Stockholm'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
