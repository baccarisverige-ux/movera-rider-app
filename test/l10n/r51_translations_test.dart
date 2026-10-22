import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/features/active_ride/presentation/rider_in_trip_panel.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/auth/presentation/widgets/balloon_brand_intro.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../responsive/responsive_harness.dart';

/// Wave 5 R5.1 (parts a and b): screens and labels that showed English,
/// raw codes or overflowed in French and Swedish.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => L10n.use('en'));

  void noop() {}

  Future<void> pumpIn(
    WidgetTester tester,
    String code,
    Widget screen, {
    Size viewport = const Size(390, 844),
    double textScale = 1,
  }) async {
    L10n.use(code);
    await pumpMoveraScreen(
      tester,
      screen,
      viewport: viewport,
      textScale: textScale,
      locale: Locale(code),
    );
    await tester.pump();
  }

  for (final code in ['fr', 'sv']) {
    group(code, () {
      testWidgets('rider-u39: in-trip pill fits a 320 px phone at 2x', (
        tester,
      ) async {
        final errors = await collectFlutterErrors(
          () => pumpIn(
            tester,
            code,
            Scaffold(
              body: SingleChildScrollView(
                child: RiderInTripPanel(
                  destinationAddress: 'Hornsgatan 2, Stockholm',
                  rideType: 'Movera',
                  paymentMethod: 'Cash',
                  price: 259,
                  driver: null,
                  rideId: 'r51-trip',
                  status: RideStatus.approachingDropoff,
                  onOpenProfile: noop,
                  onCall: noop,
                  onMore: noop,
                  onCancel: noop,
                ),
              ),
            ),
            viewport: const Size(320, 900),
            textScale: 2,
          ),
        );
        expect(errors, isEmpty);
        expect(
          find.text(L10n.current.nearDestinationUpper),
          findsOneWidget,
        );
      });

      testWidgets('rider-u65: driver card Message fits a 360 px phone at 2x', (
        tester,
      ) async {
        final errors = await collectFlutterErrors(
          () => pumpIn(
            tester,
            code,
            Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: WaitingDriverCard(
                  driver: _driver,
                  rideId: 'r51-card',
                  onOpenProfile: noop,
                  onCall: noop,
                  onMore: noop,
                ),
              ),
            ),
            viewport: const Size(360, 900),
            textScale: 2,
          ),
        );
        expect(errors, isEmpty);
        expect(find.text(L10n.current.message), findsOneWidget);
      });

      testWidgets('rider-31: Sign in hero tagline is translated', (
        tester,
      ) async {
        await pumpIn(
          tester,
          code,
          const Scaffold(
            body: BalloonBrandIntro(progress: AlwaysStoppedAnimation(1)),
          ),
        );
        final tagline = L10n.current.brandTaglineSentence;
        expect(tagline, isNot('Moving to a new era.'));
        expect(find.text(tagline), findsOneWidget);
        expect(find.bySemanticsLabel('Movera. $tagline'), findsOneWidget);
      });
    });
  }
}

const _driver = MatchedDriver(
  id: 'driver_r51',
  firstName: 'Alex',
  vehicleMake: 'Volvo',
  vehicleModel: 'EX30',
);
