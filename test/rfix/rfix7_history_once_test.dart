import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/history/application/on_demand_history_controller.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R7 (owner 2026-11-20, "Yes, all 7 as drafts"): History > Completed
/// listed a booked ride twice (21:25 and 21:23, both 235 kr) and its
/// detail said "Booked price 235,00 kr" though it was booked at 204 kr.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Reservation ride(
    String id, {
    required DateTime at,
    ReservationStatus status = ReservationStatus.completed,
    double price = 235,
  }) => Reservation(
    reservationId: id,
    createdAt: at.subtract(const Duration(hours: 1)),
    scheduledPickupAt: at,
    pickup: const ReservationPlace(label: 'Drottninggatan 1'),
    destination: const ReservationPlace(label: 'Solna Centrum'),
    categoryId: 'economy',
    categoryName: 'Movera',
    categoryImage: 'assets/images/rides/movera.webp',
    price: price,
    paymentMethod: 'Cash',
    status: status,
  );

  final pickup = DateTime(2026, 11, 19, 21, 25);
  final ended = DateTime(2026, 11, 19, 21, 23);

  test('a booked ride that was driven is listed once: the trip record', () {
    const controller = OnDemandHistoryController();
    // The booked-rides list (GET /rider/trips?kind=scheduled) and the trip
    // list (GET /rider/trips) both hold trip trp_1.
    final rides = controller.combine(
      [ride('trp_1', at: pickup)],
      [ride('ondemand-trp_1', at: ended)],
      completed: true,
    );
    expect(rides.map((r) => r.reservationId), ['ondemand-trp_1']);
  });

  test(
    'other rides stay: a booked ride not in the trip list, another trip',
    () {
      const controller = OnDemandHistoryController();
      final rides = controller.combine(
        [
          ride('trp_1', at: pickup),
          ride('trp_2', at: pickup.subtract(const Duration(days: 1))),
        ],
        [
          ride('ondemand-trp_1', at: ended),
          ride('ondemand-trp_3', at: ended.subtract(const Duration(days: 2))),
        ],
        completed: true,
      );
      expect(rides.map((r) => r.reservationId), [
        'ondemand-trp_1',
        'trp_2',
        'ondemand-trp_3',
      ]);
      // A cancelled booked ride is one ride too.
      final cancelled = controller.combine(
        [ride('trp_9', at: pickup, status: ReservationStatus.cancelled)],
        [
          ride(
            'ondemand-trp_9',
            at: ended,
            status: ReservationStatus.cancelled,
          ),
        ],
        completed: false,
      );
      expect(cancelled.map((r) => r.reservationId), ['ondemand-trp_9']);
    },
  );

  testWidgets('a finished trip says "Final price", not "Booked price"', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RideHistory(
          reservations: ReservationController(
            store: LocalReservationRepository(
              storage: MemoryReservationStorage(),
            ),
          ),
          onDemandReader: () async => [ride('ondemand-trp_1', at: ended)],
          receiptLoader: (_) async => null,
          pathLoader: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-ride-trp_1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-ride-trp_1')));
    await tester.pumpAndSettle();
    final price = tester.widget<Text>(
      find.byKey(const ValueKey('history-detail-price')),
    );
    expect(price.data, 'Movera · Final price 235,00 kr');
    expect(find.textContaining('Booked price'), findsNothing);
  });

  testWidgets('a cancelled ride still says "Booked price"', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RideHistory(
          reservations: ReservationController(
            store: LocalReservationRepository(
              storage: MemoryReservationStorage(),
            ),
          ),
          onDemandReader: () async => [
            ride(
              'ondemand-trp_4',
              at: ended,
              status: ReservationStatus.cancelled,
              price: 204,
            ),
          ],
          receiptLoader: (_) async => null,
          pathLoader: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelled'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('history-ride-trp_4')));
    await tester.pumpAndSettle();
    final price = tester.widget<Text>(
      find.byKey(const ValueKey('history-detail-price')),
    );
    expect(price.data, 'Movera · Booked price 204,00 kr');
  });

  test('the words in sv and fr', () {
    expect(
      lookupAppLocalizations(
        const Locale('sv'),
      ).historyFinalPrice('Movera', '235,00 kr'),
      'Movera · Slutpris 235,00 kr',
    );
    expect(
      lookupAppLocalizations(
        const Locale('fr'),
      ).historyFinalPrice('Movera', '235,00 kr'),
      'Movera · Prix final 235,00 kr',
    );
  });
}
