import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/review_changes.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/reservations/presentation/scheduled_ride_terms.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/presentation/emergency_contacts_page.dart';
import 'package:movera_rider/features/safety/presentation/how_movera_protects_page.dart';
import 'package:movera_rider/features/safety/presentation/pin_verification_page.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_page.dart';
import 'package:movera_rider/features/safety/presentation/safety_hub.dart';
import 'package:movera_rider/features/safety/presentation/safety_tips_page.dart';
import 'package:movera_rider/features/safety/presentation/trip_share_page.dart';
import 'package:movera_rider/features/saved_places/presentation/add_place.dart';
import 'package:movera_rider/features/saved_places/presentation/pickup_location.dart';
import 'package:movera_rider/features/saved_places/presentation/saved_places.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';
import 'package:movera_rider/features/support/domain/support.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../responsive/responsive_harness.dart';

/// Round 4 finish: Safety, Support, the reservation screens, Saved places,
/// chat and scheduling in French and Swedish, at the smallest phone
/// (320 px) with 130 % text: no overflow, no thrown error, and the screen
/// really is in that language.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.idle);
  });
  tearDown(() => L10n.use('en'));

  final ride = SupportRide(
    id: 'rsv_l10n',
    title: 'Arlanda Express',
    when: DateTime(2026, 10, 3, 14, 5),
    price: 522,
    image: 'missing.png',
  );

  SafetyController safety() => SafetyController(
    session: SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
    ),
  );

  ReservationDraft draft({double price = 522}) => ReservationDraft(
    scheduledPickupAt: DateTime(2030, 9, 23, 6, 55),
    estimatedDropoffAt: DateTime(2030, 9, 23, 7, 26),
    pickup: const ReservationPlace(
      label: 'Klockarvägen 37',
      subtitle: 'Södertälje',
    ),
    destination: const ReservationPlace(
      label: 'Arlanda Express',
      subtitle: 'Stockholm',
    ),
    categoryId: 'economy',
    categoryName: 'Movera',
    categoryImage: 'missing.png',
    price: price,
    paymentMethod: 'Cash',
    note: 'Bags · Pet',
  );

  Future<ReservationController> reservations() async {
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_l10n',
      ),
    );
    await c.create(draft());
    return c;
  }

  // Screen, and one string it must show in each language.
  final screens =
      <String, (Future<Widget> Function(), String Function(AppLocalizations))>{
        'Safety': (() async => const SafetyHub(), (l) => l.safetyPreferences),
        'Emergency contacts': (
          () async => EmergencyContactsPage(controller: safety()),
          (l) => l.contactsEmptyTitle,
        ),
        'PIN verification': (
          () async => PinVerificationPage(controller: safety()),
          (l) => l.pinToggle,
        ),
        'Share trip status': (
          () async => TripSharePage(controller: safety()),
          (l) => l.shareAuto,
        ),
        'RideCheck': (
          () async => RideCheckPage(controller: safety()),
          (l) => l.rcPageIntro,
        ),
        'Safety tips': (
          () async => const SafetyTipsPage(),
          (l) => l.tipWellLitTitle,
        ),
        'How Movera protects you': (
          () async => const HowMoveraProtectsPage(),
          (l) => l.protectMaskedTitle,
        ),
        'Help': (
          () async => SupportHome(loadRides: () async => [ride]),
          (l) => l.supportBrowseTopics,
        ),
        'Help articles': (
          () async => const HelpArticles(),
          (l) => l.helpAboutTitle,
        ),
        'Select an issue': (
          () async => SelectIssue(ride: ride),
          (l) => l.issueChargedTwice,
        ),
        'Support message': (
          () async => SupportChat(ride: ride),
          (l) => l.supportWelcomeRide,
        ),
        'Support cases': (
          () async => const SupportMessages(),
          (l) => l.supportNoActiveCases,
        ),
        'Saved places': (
          () async => const SavedPlaces(),
          (l) => l.spAddAnother,
        ),
        'Add place': (() async => const AddPlace(), (l) => l.spAddNewAddress),
        'Pickup location': (
          () async => const RiderSearchPickupLocation(),
          (l) => l.spYourLastTrip,
        ),
        'Chat': (() async => const Chat(), (l) => l.chatNoMessages),
        'Schedule a ride': (
          () async => const ScheduleRide(),
          (l) => l.schedWherePickup,
        ),
        'Upcoming ride': (
          () async => UpcomingReservationPage(
            reservationId: 'rsv_l10n',
            controller: await reservations(),
          ),
          (l) => l.resUpcomingRide,
        ),
        'Ride scheduled': (
          () async => RideScheduledPage(
            reservationId: 'rsv_l10n',
            controller: await reservations(),
          ),
          (l) => l.resScheduledTitle,
        ),
        'Review changes': (
          () async {
            final c = await reservations();
            return ReviewChangesPage(
              original: c.byId('rsv_l10n')!,
              draft: draft(price: 589),
              controller: c,
            );
          },
          (l) => l.resReviewChanges,
        ),
        'Scheduled ride terms': (
          () async => const ScheduledRideTermsPage(),
          (l) => l.resTermsTitle,
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
        final screen = await tester.runAsync(entry.value.$1);
        final errors = await collectFlutterErrors(() async {
          try {
            await pumpMoveraScreen(
              tester,
              screen!,
              viewport: const Size(320, 568),
              textScale: 1.3,
              useAppNavigatorKey: true,
              locale: Locale(code),
            );
            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 100));
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
