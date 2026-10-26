import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_top_actions.dart';
import 'package:movera_rider/features/home/presentation/widgets/where_to_card.dart';
import 'package:movera_rider/features/notifications/presentation/notifications.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../responsive/responsive_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.idle);
  });

  // UI-11: the app's own ScreenUtil setup, not a test-only design size.
  Future<void> pumpScaled(WidgetTester tester, Widget screen) async {
    await pumpMoveraScreen(tester, screen, textScale: 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  const pickup = LatLng(59.3293, 18.0686);
  const destination = LatLng(59.3326, 18.0649);

  final screens = <String, Widget Function()>{
    'Wallet': () => const WalletHome(),
    'Profile': () => AccountHomePage(
      controller: ProfileController(
        store: ProfileRepository(storageKey: 'a11y_text_scale_profile'),
      ),
    ),
    'Completion': () => const RideCompleted(),
    'Notifications': () => const NotificationScreen(),
    'Empty state': () => const Scaffold(
      body: MoveraEmptyState(
        icon: Icons.inbox_outlined,
        title: 'Nothing here yet',
        message: 'Saved methods will show up after you add one.',
      ),
    ),
    'Home chips': () => Scaffold(
      body: Column(
        children: [
          PremiumTopActions(onMenuTap: () {}, onAccountTap: () {}),
          WhereToCard(
            destinationAddress: null,
            onDestinationTap: () {},
            onOpenSchedule: () {},
          ),
        ],
      ),
    ),
    'Finding Driver': () => const FindingDrivers(
      pickupAddress: 'Stockholm pickup',
      destinationAddress: 'Stockholm destination',
      pickupPosition: pickup,
      destinationPosition: destination,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
    ),
    'Waiting for Driver': () => const WaitingForDriver(
      pickupAddress: 'Stockholm pickup',
      destinationAddress: 'Stockholm destination',
      pickupPosition: pickup,
      destinationPosition: destination,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
    ),
    'Select ride': () => const SelectRide(
      pickupAddress: 'Stockholm pickup',
      destinationAddress: 'Stockholm destination',
      pickupPosition: pickup,
      destinationPosition: destination,
    ),
    'Support': () => const SupportHome(),
    'History': () =>
        RideHistory(onDemandReader: () async => const <Reservation>[]),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key} at 200% text does not overflow', (tester) async {
      await pumpScaled(tester, entry.value());
      expect(
        tester.takeException(),
        isNull,
        reason: '${entry.key} overflowed or threw at 200% text scale',
      );

      // Dispose the tested surface before draining delayed initialization work.
      // SelectRide intentionally arms an 80 ms map-init callback; the overflow
      // assertion above remains strict while this prevents a legitimate timer
      // from leaking past the end of the widget test.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  }
}
