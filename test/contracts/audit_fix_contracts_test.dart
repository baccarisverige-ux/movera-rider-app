import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/payments/domain/payment_status.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/application/reservation_ride_realtime.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/ride.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoGeocoding implements GeocodingRepository {
  @override
  Future<PlaceResult?> forward(String query) async => null;

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
  });

  group('ARCH-10 trip status wire vocabulary', () {
    test('every P1 wire name parses back to its TripStatus', () {
      for (final status in TripStatus.values) {
        expect(TripStatusWire.parse(status.wireName), status);
      }
      expect(TripStatusWire.parse('driverToPickup'), isNull);
      expect(TripStatusWire.parse(null), isNull);
    });

    test('RideStatus round-trips through the trip contract', () {
      // Contract v0.3.0: no_show, failed, cancelled_by_admin and
      // cancelled_by_system each keep their own UI state.
      for (final trip in TripStatus.values) {
        final ride = RideStatusWire.fromTrip(trip);
        if (trip == TripStatus.offered) {
          // An offer to one driver is still a search for the rider.
          expect(ride, RideStatus.findingDriver);
        } else {
          expect(ride.tripStatus, trip, reason: trip.name);
        }
      }
      // Legacy Rider-shaped names still parse.
      for (final status in RideStatus.values) {
        expect(RideStatusWire.parse(status.name), status);
      }
      expect(RideStatusWire.parse('newServerState'), isNull);
    });

    test('Ride.fromDto reads a snake_case wire status', () {
      expect(
        Ride.fromDto({'id': 'r1', 'status': 'in_trip'}).status,
        RideStatus.tripInProgress,
      );
    });

    test('realtime accepts every P1 snake_case status', () async {
      for (final trip in TripStatus.values) {
        final connection = RealtimeConnection();
        final rt = ApiRideRealtime(
          api: ApiClient(
            env: AppEnv.current,
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'ride': {
                    'status': trip.wireName,
                    'version': 1,
                    'updatedAt': '2026-10-14T08:00:00Z',
                  },
                }),
                200,
              ),
            ),
          ),
          connection: connection,
          pollInterval: const Duration(days: 1),
        );
        final events = <RideRealtimeEvent>[];
        final sub = rt.subscribe('ride-wire').listen(events.add);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          events.single.status,
          RideStatusWire.fromTrip(trip),
          reason: trip.wireName,
        );
        expect(
          connection.state,
          isNot(RealtimeState.failed),
          reason: trip.wireName,
        );
        await sub.cancel();
        rt.dispose();
        connection.dispose();
      }
    });

    test('a scheduled reservation surfaces as booking requested', () async {
      final controller = ReservationController(
        store: LocalReservationRepository(
          storage: MemoryReservationStorage(),
          nextId: () => 'rsv-wire',
        ),
      );
      final created = await controller.create(
        ReservationDraft(
          scheduledPickupAt: DateTime(2026, 10, 20, 8),
          pickup: const ReservationPlace(label: 'A', lat: 59.33, lng: 18.06),
          destination: const ReservationPlace(
            label: 'B',
            lat: 59.65,
            lng: 17.92,
          ),
          categoryId: 'movera',
          categoryName: 'Movera',
          categoryImage: 'assets/images/rides/movera.webp',
          price: 349,
          paymentMethod: 'Apple Pay',
        ),
      );
      final realtime = ReservationRideRealtime(
        controller: controller,
        reservationId: created.reservationId,
      );
      addTearDown(realtime.dispose);
      final events = <RideStatus>[];
      final sub = realtime
          .subscribe(created.reservationId)
          .listen((e) => events.add(e.status));
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events, isNotEmpty);
      expect(events.first, RideStatus.bookingRequested);
    });

    test('payment status maps onto the P1 vocabulary and back', () {
      expect(PaymentStatus.processing.wireName, 'authorized');
      expect(PaymentStatus.succeeded.wireName, 'captured');
      expect(PaymentStatusWire.parse('captured'), PaymentStatus.succeeded);
      expect(PaymentStatusWire.parse('succeeded'), PaymentStatus.succeeded);
      expect(
        PaymentStatusWire.parse('requires_confirmation'),
        PaymentStatus.pending,
      );
      expect(PaymentStatusWire.parse('bogus'), isNull);
    });
  });

  group('ARCH-11 money and time contracts', () {
    test('Money is integer minor units with an ISO-4217 code', () {
      expect(
        Money.tryParse({'amountMinor': 25900, 'currency': 'sek'}),
        const Money(25900, 'SEK'),
      );
      expect(Money.tryParse({'amountMinor': 259.5, 'currency': 'SEK'}), isNull);
      expect(
        Money.tryParse({'amountMinor': 100, 'currency': 'kronor'}),
        isNull,
      );
      expect(Money.fromLegacyMajor(259.99).amountMinor, 25999);
      expect(const Money(100) + const Money(50), const Money(150));
      expect(
        () => const Money(100) + const Money(50, 'EUR'),
        throwsArgumentError,
      );
      expect(const Money(12345).toJson(), {
        'amountMinor': 12345,
        'currency': 'SEK',
      });
    });

    test('a quote with a non-ISO currency is rejected', () async {
      final repo = ApiQuoteRepository(
        api: ApiClient(
          env: AppEnv.current,
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'quote': {
                  'quoteId': 'q1',
                  'totalMinor': 25900,
                  'currency': 'kronor',
                  'signedPayload': 'sig',
                  'expiresAt': WireTime.format(
                    DateTime.now().add(const Duration(minutes: 2)),
                  ),
                },
              }),
              200,
            ),
          ),
        ),
      );
      await expectLater(
        repo.quote(rideType: 'movera', distanceMeters: 1000),
        throwsA(isA<FormatException>()),
      );
    });

    test('the mock server sends quote expiry as UTC with an offset', () async {
      final api = ApiClient(client: InProcessMockClient());
      final json = await api.post(
        '/api/v1/quotes',
        body: {'rideType': 'movera', 'distanceMeters': 1000},
      );
      final expiresAt = (json['quote'] as Map)['expiresAt'] as String;
      expect(expiresAt.endsWith('Z'), isTrue, reason: expiresAt);
    });

    test('a realtime event stamped on the device is UTC', () {
      final event = RideRealtimeEvent(
        rideId: 'r1',
        status: RideStatus.findingDriver,
        sequence: 1,
      );
      expect(event.at.isUtc, isTrue);
    });

    test('route change price prefers minor units over legacy kronor', () async {
      final api = ApiClient(
        env: AppEnv.current,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 'OK',
              'newPriceKr': 999.0,
              'newTotalMinor': 30050,
              'differenceMinor': 10050,
              'routeQuoteId': 'rq1',
              'expiresAt': '2026-10-14T10:00:00+02:00',
            }),
            200,
          ),
        ),
      );
      final quote =
          await RouteChangeController(
            api: api,
            geocoding: _NoGeocoding(),
          ).preview(
            ride: RideSnapshot(
              status: RideStatus.findingDriver,
              savedAt: DateTime(2026, 10, 14),
              pickupAddress: 'A',
              destinationAddress: 'B',
              pickupLat: 59.33,
              pickupLng: 18.06,
              destinationLat: 59.34,
              destinationLng: 18.05,
              rideType: 'Movera',
              price: 200,
              paymentMethod: 'Apple Pay',
              rideId: 'ride-money',
            ),
            destinationAddress: 'B',
          );
      expect(quote.newTotalMinor, 30050);
      expect(quote.newPriceKr, 300.5);
      expect(quote.differenceMinor, 10050);
      expect(quote.expiresAt, DateTime.utc(2026, 10, 14, 8));
      expect(quote.expiresAt!.isUtc, isTrue);
    });
  });
}
