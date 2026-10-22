import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
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
import 'package:movera_rider/features/notifications/application/notification_navigation.dart';
import 'package:movera_rider/features/notifications/application/notifications_controller.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:movera_rider/features/notifications/presentation/notifications.dart';
import 'package:movera_rider/features/payments/application/saved_cards_controller.dart';
import 'package:movera_rider/features/payments/presentation/add_card_page.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart';
import 'package:movera_rider/features/pickup/application/pickup_spots_controller.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';
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

      testWidgets('rider-49: an ended ride notification toast is translated', (
        tester,
      ) async {
        await pumpIn(
          tester,
          code,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openNotificationRide(
                  context,
                  'r51-ended',
                  open: (_) async => false,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(L10n.current.notificationRideEnded), findsOneWidget);
        expect(find.text('This ride has ended.'), findsNothing);
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('rider-u128: a title-only push shows no wire type', (
        tester,
      ) async {
        final store = NotificationsRepository()
          ..ingest(
            const PushPayload(
              type: 'ride.driver_arrived',
              title: 'Movera',
              messageId: 'r51-push',
              rideId: 'r51-ride',
            ),
            read: false,
          );
        await pumpIn(
          tester,
          code,
          NotificationScreen(controller: NotificationsController(store: store)),
        );
        expect(find.text('Movera'), findsWidgets);
        expect(find.text('ride.driver_arrived'), findsNothing);
      });

      testWidgets('rider-53: the card brand error is translated', (
        tester,
      ) async {
        await pumpIn(
          tester,
          code,
          AddCardPage(cards: SavedCardsController(), now: DateTime(2026, 10, 13)),
        );
        await tester.enterText(
          find.byKey(const ValueKey('add-card-number')),
          '378282246310005',
        );
        await tester.pump();
        expect(find.text(L10n.current.cardBrandsAccepted), findsOneWidget);
        expect(find.text('We accept Visa and Mastercard'), findsNothing);
      });

      testWidgets('rider-52: a refused save shows the l10n error', (
        tester,
      ) async {
        await pumpIn(
          tester,
          code,
          AddCardPage(cards: _RefusingCards(), now: DateTime(2026, 10, 13)),
        );
        await tester.enterText(
          find.byKey(const ValueKey('add-card-number')),
          '4242424242424242',
        );
        await tester.enterText(
          find.byKey(const ValueKey('add-card-expiry')),
          '1230',
        );
        await tester.enterText(find.byKey(const ValueKey('add-card-cvc')), '123');
        await tester.enterText(
          find.byKey(const ValueKey('add-card-holder')),
          'Alex Berg',
        );
        await tester.pump();
        await tester.ensureVisible(find.byKey(const ValueKey('add-card-save')));
        await tester.tap(find.byKey(const ValueKey('add-card-save')));
        await tester.pump();
        expect(find.text(L10n.current.cardCheckDetails), findsOneWidget);
        expect(find.text(CardInput.brandError), findsNothing);
      });

      test('rider-54: the dropped pin pickup label is translated', () {
        L10n.use(code);
        expect(
          droppedPinPickupAddress(const LatLng(59.3293, -18.0686)),
          code == 'fr'
              ? 'Repère placé · 59.32930° N 18.06860° O'
              : 'Placerad nål · 59.32930° N 18.06860° V',
        );
      });

      test('rider-55: pickup spot chips and the booked label are translated', () async {
        L10n.use(code);
        const at = LatLng(59.3293, 18.0686);
        final spots = await PickupSpotsController().forAddress(
          at: at,
          address: 'Klockarvägen 37, Huddinge',
          home: pickupSpotOffset(at, northM: 100),
        );
        final titles = spots.map((s) => s.title).toList();
        expect(titles, [
          L10n.current.pickupSpotMainEntrance,
          L10n.current.pickupSpotSideEntrance,
          L10n.current.pickupSpotParking,
          L10n.current.pickupSpotNearHome,
        ]);
        expect(titles, isNot(contains('Main entrance')));
        expect(
          spots.last.subtitle,
          code == 'fr' ? 'À 100 m d’ici' : '100 m härifrån',
        );
        expect(
          pickupSpotLabel('Klockarvägen 37, Huddinge', spots.first),
          code == 'fr'
              ? 'Klockarvägen 37 – Entrée principale'
              : 'Klockarvägen 37 – Huvudentré',
        );
      });

      for (final stand in ['Current location', 'Pickup location']) {
        testWidgets('rider-56: Confirm pickup spot shows "$stand" translated', (
          tester,
        ) async {
          await pumpIn(
            tester,
            code,
            ConfirmPickupSpot(
              initialPosition: const LatLng(59.19, 17.62),
              initialAddress: stand,
            ),
          );
          // The search field and the address caption.
          expect(find.text(L10n.place(stand)), findsNWidgets(2));
          expect(find.text(stand), findsNothing);
        });
      }
    });
  }
}

const _driver = MatchedDriver(
  id: 'driver_r51',
  firstName: 'Alex',
  vehicleMake: 'Volvo',
  vehicleModel: 'EX30',
);

/// Refuses every card the way [SavedCardsController.add] refuses a bad
/// one: an [ArgumentError] with English developer text.
class _RefusingCards extends SavedCardsController {
  @override
  Future<SavedCard> add({
    required String number,
    required int expMonth,
    required int expYear,
    required String holder,
    DateTime? now,
    String? id,
  }) async => throw ArgumentError(CardInput.brandError);
}
