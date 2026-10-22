import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/features/active_ride/presentation/rider_in_trip_panel.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/auth/presentation/widgets/balloon_brand_intro.dart';
import 'package:movera_rider/features/destination_search/domain/place_suggestion.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_journey_section.dart';
import 'package:movera_rider/features/home/presentation/widgets/saved_places_row.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
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

  RideSnapshot snapshot(String id, {String payment = 'Cash'}) => RideSnapshot(
    status: RideStatus.tripInProgress,
    savedAt: DateTime.now().subtract(const Duration(minutes: 12)),
    pickupAddress: 'Sveavägen 1',
    destinationAddress: 'Arlanda Airport',
    pickupLat: 59.3293,
    pickupLng: 18.0686,
    destinationLat: 59.65,
    destinationLng: 17.93,
    rideType: 'Movera',
    price: 259,
    paymentMethod: payment,
    rideId: id,
  );

  /// Opens [ride]'s History detail sheet from its [tab].
  Future<void> openHistoryDetail(
    WidgetTester tester,
    String code,
    Reservation ride,
    String tab,
  ) async {
    await pumpIn(
      tester,
      code,
      RideHistory(
        reservations: ReservationController(
          store: LocalReservationRepository(storage: MemoryReservationStorage()),
        ),
        onDemandReader: () async => [ride],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(tab).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Arlanda Airport').first);
    await tester.pumpAndSettle();
  }

  // The 12-hour clock only shows in English; fr and sv are 24-hour.
  testWidgets('rider-48: chat times use the 24-hour clock', (tester) async {
    await pumpIn(
      tester,
      'en',
      Scaffold(
        body: RiderMessageBubble(
          message: ChatMessage(
            text: 'On my way',
            fromRider: true,
            sentAt: DateTime(2026, 10, 12, 15, 5),
          ),
        ),
      ),
    );
    expect(find.textContaining('15:05'), findsOneWidget);
    expect(find.textContaining('PM'), findsNothing);
  });

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

      testWidgets('rider-u83: distances and CO2 use the decimal comma', (
        tester,
      ) async {
        await pumpIn(
          tester,
          code,
          Scaffold(
            body: SingleChildScrollView(
              child: HomeJourneySection(
                onDestinationTap: noop,
                onOpenSchedule: noop,
                ridesLoader: () async => const [],
                clock: () => DateTime(2026, 10, 12, 9),
                changes: const Stream<void>.empty(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('0,0 kg'), findsOneWidget);
        expect(formatDistanceKm(1.24), '1,2 km');
      });

      testWidgets('rider-u112: a server-ended ride shows its reason translated', (
        tester,
      ) async {
        final ride = OnDemandRideHistoryStore.recordFor(
          snapshot('r51-no-driver'),
          terminalStatus: RideStatus.noDriverFound,
        )!;
        L10n.use(code);
        await openHistoryDetail(tester, code, ride, L10n.current.resCancelled);
        expect(
          find.text(L10n.current.reasonLine(L10n.current.termNoDriverFound)),
          findsOneWidget,
        );
      });

      testWidgets('rider-38: History detail names the Wallet in the language', (
        tester,
      ) async {
        final ride = OnDemandRideHistoryStore.recordFor(
          snapshot('r51-wallet', payment: 'Movera Wallet'),
          terminalStatus: RideStatus.tripCompleted,
        )!;
        L10n.use(code);
        await openHistoryDetail(tester, code, ride, L10n.current.resCompleted);
        expect(
          find.text(L10n.current.paymentMethodLine(L10n.current.moveraWallet)),
          findsOneWidget,
        );
      });

      testWidgets('rider-42: a place added from Home is named in the language', (
        tester,
      ) async {
        await pumpIn(
          tester,
          code,
          Scaffold(
            body: SavedPlacesRow(
              homeAddress: null,
              workAddress: null,
              savedPlaces: const [
                SavedPlaceData(
                  title: 'restaurant',
                  type: 'restaurant',
                  address: 'Sveavägen 1',
                ),
              ],
              onUseSavedPlace: (address, {required target, customType}) {},
              onAddPlace: noop,
            ),
          ),
        );
        expect(find.text(L10n.current.placeRestaurant), findsOneWidget);
        expect(find.text('restaurant'), findsNothing);
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
