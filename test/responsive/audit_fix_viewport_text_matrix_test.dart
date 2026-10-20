import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'responsive_harness.dart';

/// UI-1, UI-2, UI-9, UI-10, UI-11: every main booking screen at small,
/// reference, landscape and desktop viewports and at 100/130/200% text, with
/// the production ScreenUtil setup. Any RenderFlex overflow, thrown error or
/// ErrorWidget fails the case.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.idle);
  });

  const pickup = LatLng(59.3293, 18.0686);
  const destination = LatLng(59.3326, 18.0649);
  const pickupAddress = 'Sergels torg 1, 111 57 Stockholm';
  const destinationAddress = 'Odenplan 2, 113 22 Stockholm';

  final screens = <String, Widget Function()>{
    'Home': () => const Home(),
    'Home expanded': () => const Home(),
    'RoutePickerPage': () => RoutePickerPage(
      pickupAddress: pickupAddress,
      destinationAddress: destinationAddress,
      stops: const ['Hötorget 1'],
      stopsSupported: true,
      initialField: 'destination',
      finishLabel: 'See prices',
      capture: EarlyInputCapture(),
      here: const GeoPoint(59.33, 18.06),
      homeAddress: 'Kungsgatan 12, Stockholm',
      workAddress: null,
      recent: const ['Drottninggatan 50, Stockholm', 'Stureplan 4, Stockholm'],
      onSetFavourite: (_) async => null,
      onPickOnMap: ({required pickup, required address}) async => null,
      onFinish: (_) async => null,
    ),
    'SelectRide': () => const SelectRide(
      pickupAddress: pickupAddress,
      destinationAddress: destinationAddress,
      pickupPosition: pickup,
      destinationPosition: destination,
    ),
    'Set pickup': () => SetPickupPage(
      initialPosition: pickup,
      initialAddress: pickupAddress,
      destinationAddress: destinationAddress,
      destinationPosition: destination,
      ride: const SetPickupRide(
        name: 'Movera',
        image: 'missing.png',
        seats: 4,
        etaMin: 5,
        tripMinutes: 12,
      ),
      fare: const SetPickupFare(totalKr: 259),
      payment: const SetPickupPayment(
        brand: 'cash',
        name: 'Cash',
        detail: '',
      ),
      brandMark: (_) => const SizedBox(),
    ),
    'FindingDrivers': () => const FindingDrivers(
      pickupAddress: pickupAddress,
      destinationAddress: destinationAddress,
      pickupPosition: pickup,
      destinationPosition: destination,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
    ),
    'WaitingForDriver': () => const WaitingForDriver(
      pickupAddress: pickupAddress,
      destinationAddress: destinationAddress,
      pickupPosition: pickup,
      destinationPosition: destination,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
    ),
    'RiderMenuPage': () => const RiderMenuPage(),
    'AccountHomePage': () => AccountHomePage(
      controller: ProfileController(
        store: ProfileRepository(storageKey: 'matrix_profile'),
      ),
    ),
  };

  const viewports = [
    Size(320, 568),
    Size(360, 640),
    Size(375, 667),
    Size(390, 844),
    Size(844, 390),
    Size(1280, 800),
  ];
  const textScales = [1.0, 1.3, 2.0];

  for (final entry in screens.entries) {
    for (final viewport in viewports) {
      for (final scale in textScales) {
        final label =
            '${entry.key} @ ${viewport.width.toInt()}x'
            '${viewport.height.toInt()} text x$scale';
        testWidgets('$label lays out without overflow', (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.linux;
          Object? thrown;
          final errors = await collectFlutterErrors(() async {
            try {
              await pumpMoveraScreen(
                tester,
                entry.value(),
                viewport: viewport,
                textScale: scale,
                useAppNavigatorKey: true,
              );
              for (var i = 0; i < 10; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
              if (entry.key == 'Home expanded') {
                final handle = find.bySemanticsLabel('Toggle home panel');
                expect(handle, findsWidgets);
                await tester.timedDrag(
                  handle.first,
                  const Offset(0, -900),
                  const Duration(milliseconds: 300),
                  warnIfMissed: false,
                );
                for (var i = 0; i < 15; i++) {
                  await tester.pump(const Duration(milliseconds: 100));
                }
              }
              thrown = tester.takeException();
              expect(find.byType(ErrorWidget), findsNothing);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump(const Duration(seconds: 2));
              debugDefaultTargetPlatformOverride = null;
            }
          });
          expect(thrown, isNull, reason: '$label threw');
          expect(errors, isEmpty, reason: '$label: ${errors.join('\n')}');
        });
      }
    }
  }
}
