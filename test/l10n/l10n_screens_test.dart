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
import 'package:movera_rider/features/profile/presentation/personal_info.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/features/ride_complete/presentation/trip_detail.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../responsive/responsive_harness.dart';

/// Round 4: French and Swedish run longer than English. The key screens at
/// the smallest phone (320 px) with 130 % text, in fr and sv: no overflow,
/// no thrown error, and the screen really is in that language.
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
  tearDown(() => L10n.use('en'));

  const pickup = LatLng(59.3293, 18.0686);
  const destination = LatLng(59.3326, 18.0649);
  const pickupAddress = 'Sergels torg 1, 111 57 Stockholm';
  const destinationAddress = 'Odenplan 2, 113 22 Stockholm';

  ProfileController profile() =>
      ProfileController(store: ProfileRepository(storageKey: 'l10n_profile'));

  // Screen, and one string it must show in each language.
  final screens = <String, (Widget Function(), String Function(AppLocalizations))>{
    'Home': (() => const Home(), (l) => l.whereTo),
    'Home expanded': (() => const Home(), (l) => l.advancePlanAhead),
    'RoutePickerPage': (
      () => RoutePickerPage(
        pickupAddress: pickupAddress,
        destinationAddress: destinationAddress,
        stops: const ['Hötorget 1'],
        stopsSupported: true,
        initialField: 'destination',
        capture: EarlyInputCapture(),
        here: const GeoPoint(59.33, 18.06),
        homeAddress: 'Kungsgatan 12, Stockholm',
        workAddress: null,
        recent: const ['Drottninggatan 50, Stockholm'],
        onSetFavourite: (_) async => null,
        onPickOnMap: ({required pickup, required address}) async => null,
        onFinish: (_) async => null,
      ),
      (l) => l.planYourRide,
    ),
    'SelectRide': (
      () => const SelectRide(
        pickupAddress: pickupAddress,
        destinationAddress: destinationAddress,
        pickupPosition: pickup,
        destinationPosition: destination,
      ),
      (l) => l.chooseYourRide,
    ),
    'Set pickup': (
      () => SetPickupPage(
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
        payment: const SetPickupPayment(brand: 'cash', name: 'Cash', detail: ''),
        brandMark: (_) => const SizedBox(),
      ),
      (l) => l.confirmAndSearch,
    ),
    'FindingDrivers': (
      () => const FindingDrivers(
        pickupAddress: pickupAddress,
        destinationAddress: destinationAddress,
        pickupPosition: pickup,
        destinationPosition: destination,
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'Apple Pay',
      ),
      (l) => l.findingDriver,
    ),
    'WaitingForDriver': (
      () => const WaitingForDriver(
        pickupAddress: pickupAddress,
        destinationAddress: destinationAddress,
        pickupPosition: pickup,
        destinationPosition: destination,
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'Apple Pay',
      ),
      // No ride id in this harness: the honest "can't track" state.
      (l) => l.cantTrackRide,
    ),
    'Ride complete': (() => const RideCompleted(), (l) => l.done),
    'Receipt': (
      () => const Scaffold(
        body: SingleChildScrollView(child: RideCompletedTripDetail()),
      ),
      (l) => l.tripDetails,
    ),
    'Wallet & Payments': (
      () => const WalletAndPaymentsScreen(),
      (l) => l.walletAndPayments,
    ),
    'Menu': (() => const RiderMenuPage(), (l) => l.menuRideHistory),
    'Account': (
      () => AccountHomePage(controller: profile()),
      (l) => l.language,
    ),
    'Personal info': (
      () => PersonalInfoPage(controller: profile()),
      (l) => l.accountPersonalInfo,
    ),
  };

  for (final code in ['fr', 'sv']) {
    for (final entry in screens.entries) {
      final label = '${entry.key} in $code @ 320x568 text x1.3';
      testWidgets('$label lays out without overflow', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        L10n.use(code);
        final strings = lookupAppLocalizations(Locale(code));
        Object? thrown;
        final errors = await collectFlutterErrors(() async {
          try {
            await pumpMoveraScreen(
              tester,
              entry.value.$1(),
              viewport: const Size(320, 568),
              textScale: 1.3,
              useAppNavigatorKey: true,
              locale: Locale(code),
            );
            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            if (entry.key == 'Home expanded') {
              final handle = find.bySemanticsLabel(strings.homeTogglePanel);
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

            expect(
              find.textContaining(entry.value.$2(strings), findRichText: true),
              findsWidgets,
              reason: '$label is not in $code',
            );
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
