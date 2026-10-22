import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';
import 'package:movera_rider/features/ride_booking/data/ride_projection.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// X3: the reservation cancel fee is the zone's rule for the ride's
/// category (`RiderAppConfig.cancelFees.reservation`), not one global fee.
/// RC-07: money is converted with the currency's own exponent (TND has 3).
final _pickup = DateTime.utc(2026, 10, 20, 12);

Reservation _ride({
  String category = 'premium',
  double price = 420,
  String currency = 'SEK',
}) => Reservation(
  reservationId: 'r-$category',
  createdAt: DateTime.utc(2026, 10, 19),
  scheduledPickupAt: _pickup,
  pickup: const ReservationPlace(label: 'A'),
  destination: const ReservationPlace(label: 'B'),
  categoryId: category,
  categoryName: category,
  categoryImage: '',
  price: price,
  currency: currency,
  paymentMethod: 'cash',
  status: ReservationStatus.driverAssigned,
);

DateTime _before(int minutes) => _pickup.subtract(Duration(minutes: minutes));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('X3 reservation fee per category', () {
    final config = SeedRiderConfigRepository.seed;

    ReservationController controller({RiderAppConfig? with_}) =>
        ReservationController(
          environment: AppEnv.current,
          config: with_ ?? config,
        );

    test('premium 90 min before pickup is late: 25% of 420 kr', () {
      final terms = controller().cancelTermsFor(
        _ride(),
        now: _before(90),
      );
      expect(terms.fee, const Money(10500));
      expect(terms.window, const Duration(minutes: 120));
      expect(terms.freeUntil, _before(120));
      expect(terms.lateFee, const Money(10500));
    });

    test('premium percent is clamped to the rule min and max', () {
      final cheap = controller().cancelTermsFor(
        _ride(price: 100),
        now: _before(30),
      );
      expect(cheap.fee, const Money(8000));
      final dear = controller().cancelTermsFor(
        _ride(price: 4000),
        now: _before(30),
      );
      expect(dear.fee, const Money(30000));
    });

    test('economy at 90 min is still free; its window is 60 min', () {
      final terms = controller().cancelTermsFor(
        _ride(category: 'economy', price: 259),
        now: _before(90),
      );
      expect(terms.isFree, isTrue);
      expect(terms.freeForNow, isTrue);
      expect(terms.lateFee, const Money(5000));
      expect(
        controller()
            .cancelTermsFor(_ride(category: 'movera', price: 259), now: _before(30))
            .fee,
        const Money(5000),
        reason: 'movera is read as economy',
      );
    });

    test('a category without a rule keeps the single admin rule', () {
      final terms = controller().cancelTermsFor(
        _ride(category: 'van', price: 300),
        now: _before(30),
      );
      expect(terms.fee, ScheduledRideRules.defaults.lateCancelFee);
      expect(terms.window, const Duration(minutes: 60));
    });

    test('rider-r4-14: the kronor admin rule never prices a euro ride', () {
      final terms = controller().cancelTermsFor(
        _ride(category: 'airport', price: 40.75, currency: 'EUR'),
        now: _before(30),
      );
      expect(terms.fee, isNull);
      expect(terms.lateFee.currency, 'EUR');
    });

    test('the config is read through the repository on refresh', () async {
      final premiumFree = RiderAppConfig.fromJson({
        'version': 13,
        'currency': 'SEK',
        'cancelFees': {
          'reservation': {
            'premium': {'freeMin': 30, 'type': 'fixed', 'value': 2000},
          },
        },
      })!;
      final reservations = ReservationController(
        environment: AppEnv.current,
        configLoader: () async => premiumFree,
      );
      // Before the document is read: the single rule (60 min, 50 kr).
      expect(
        reservations.cancelTermsFor(_ride(), now: _before(45)).fee,
        const Money(5000),
      );
      await reservations.refreshRules();
      expect(reservations.cancelTermsFor(_ride(), now: _before(45)).isFree,
          isTrue);
      expect(
        reservations.cancelTermsFor(_ride(), now: _before(20)).fee,
        const Money(2000),
      );
    });

    test('a pickup Movera missed without a driver stays free', () {
      final ride = Reservation(
        reservationId: 'missed',
        createdAt: DateTime.utc(2026, 10, 19),
        scheduledPickupAt: _pickup,
        pickup: const ReservationPlace(label: 'A'),
        destination: const ReservationPlace(label: 'B'),
        categoryId: 'premium',
        categoryName: 'Premium',
        categoryImage: '',
        price: 420,
        paymentMethod: 'cash',
        status: ReservationStatus.scheduled,
      );
      expect(
        controller().cancelTermsFor(ride, now: _pickup.add(const Duration(minutes: 1))).isFree,
        isTrue,
      );
    });
  });

  group('RC-07 currency exponent', () {
    test('fromLegacyMajor uses the ISO exponent', () {
      final tnd = Money.fromLegacyMajor(1.5, 'TND');
      expect(tnd, const Money(1500, 'TND'));
      expect(tnd.major, 1.5);
      expect(tnd.majorString, '1.500');
      expect(Money.fromLegacyMajor(12.5, 'TND').amountMinor, 12500);
      expect(Money.fromLegacyMajor(1.5, 'SEK'), const Money(150));
      expect(Money.fromLegacyMajor(2.35, 'eur'), const Money(235, 'EUR'));
      expect(formatMoney(Money.fromLegacyMajor(19.5, 'TND')), '19,500 DT');
    });

    test('a TND reservation fee is worked out in millimes', () {
      final tunis = RiderAppConfig.fromJson({
        'version': 1,
        'currency': 'TND',
        'cancelFees': {
          'reservation': {
            'premium': {
              'freeMin': 120,
              'type': 'percent',
              'value': 25,
              'min': {'amountMinor': 24000, 'currency': 'TND'},
              'max': {'amountMinor': 90000, 'currency': 'TND'},
            },
          },
        },
      })!;
      final terms = ReservationController(
        environment: AppEnv.current,
        config: tunis,
      ).cancelTermsFor(_ride(price: 300.5, currency: 'TND'), now: _before(90));
      // 25% of 300.500 DT, half-up to a millime: 75.125 DT (not 7.512).
      expect(terms.fee, const Money(75125, 'TND'));
      expect(formatMoney(terms.fee!), '75,125 DT');
    });

    test('a projection total in TND reads back in dinars', () {
      double? price(Map<String, dynamic> money) => RideProjection.toSnapshot({
        'tripId': 't1',
        'status': 'searching',
        'pickup': {'address': 'A', 'lat': 36.8, 'lng': 10.18},
        'destination': {'address': 'B', 'lat': 36.85, 'lng': 10.2},
        ...money,
      })?.price;
      expect(
        price({
          'total': {'amountMinor': 12500, 'currency': 'TND'},
        }),
        12.5,
      );
      expect(price({'totalMinor': 12500, 'currency': 'TND'}), 12.5);
      expect(price({'totalMinor': 25900}), 259);
    });
  });
}
