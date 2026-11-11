import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/features/active_ride/presentation/booked_driver_banner.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:movera_rider/features/reservations/data/config_scheduled_ride_rules_source.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/application/rider_trip_watch.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';

/// v0.18.32 fix job 2 "Rider sees booked ride" + P21 / B-n
/// (contract.json#bookedRideSeen).
void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );

  Map<String, Object?> trip(String status, {int version = 2}) => {
    'tripId': 'trp_1',
    'kind': 'scheduled',
    'status': status,
    'version': version,
    'categoryId': 'economy',
    'scheduledAt': '2026-11-05T08:00:00Z',
    'createdAt': '2026-11-05T05:00:00Z',
    'pickup': {'address': 'Sergels torg', 'lat': 59.3326, 'lng': 18.0649},
    'dropoff': {'address': 'Medborgarplatsen', 'lat': 59.3143, 'lng': 18.0735},
    'stops': <Object>[],
    'fare': {'amountMinor': 24200, 'currency': 'SEK'},
    'paymentMethod': 'cash',
    if (status != 'requested')
      'driver': {'driverId': 'drv_1', 'firstName': 'Ali'},
  };

  ApiClient client(
    http.Response Function(http.Request request) answer,
    List<http.Request> seen,
  ) => ApiClient(
    client: MockClient((request) async {
      seen.add(request);
      return answer(request);
    }),
    env: staging,
  );

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  test('L3: a 409 version_mismatch on cancel takes the projection version and '
      'retries once (no stale 409 for the rider)', () async {
    final seen = <http.Request>[];
    var cancels = 0;
    final repo = ApiReservationRepository(
      api: client((request) {
        if (request.url.path.endsWith('/cancel')) {
          cancels++;
          return cancels == 1
              ? json({
                  'code': 'version_mismatch',
                  'message': 'The trip changed since you last saw it.',
                  'retryable': false,
                  'projection': trip('accepted', version: 5),
                }, 409)
              : json(trip('cancelled_by_rider', version: 6));
        }
        return json(trip('requested'));
      }, seen),
    );
    final cancelled = await repo.cancelReservation('trp_1');
    expect(cancelled.status, ReservationStatus.cancelled);
    final bodies = [
      for (final r in seen.where((r) => r.url.path.endsWith('/cancel')))
        jsonDecode(r.body)['expectedVersion'],
    ];
    expect(bodies, [2, 5]);
  });

  test('L3: the booked-ride rules come from the rider config; the PROPOSED '
      '/rider/scheduled-rides/rules is never called', () async {
    final raw =
        jsonDecode(
              File(
                'contracts/fixtures/config/rider_app_config.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    (raw['booking'] as Map)['freeChangeBeforeMin'] = 45;
    final config = RiderAppConfig.fromJson(raw)!;
    final rules = await ConfigScheduledRideRulesSource(
      () async => config,
    ).fetch();
    expect(rules!.freeCancelMinutesBeforePickup, 45);
    expect(rules.showDriverOnAccept, isFalse);
  });

  test('Q5: a booked trip whose driver drives to the pickup is the active '
      'trip, shown like a regular ride', () async {
    final seen = <http.Request>[];
    final active = await ApiActiveTripRepository(
      api: client((_) => json(trip('driver_to_pickup', version: 7)), seen),
    ).fetchActive();
    expect(active, isNotNull);
    expect(active!.rideId, 'trp_1');
  });

  test(
    'P21: rider_trip_changed on Home reads the active trip at once',
    () async {
      var adopted = 0;
      final watch = RiderTripWatch(
        showsHome: () => true,
        adopt: () async => adopted++,
        bookedOnTheWay: () async => false,
      );
      watch.onConfigEvent({'kind': 'config_published', 'doc': 'zones'});
      await Future<void>.delayed(Duration.zero);
      expect(adopted, 0);
      watch.onConfigEvent({'kind': 'rider_trip_changed', 'tripId': 'trp_1'});
      await Future<void>.delayed(Duration.zero);
      expect(adopted, 1);
    },
  );

  test('P21: Home polls every 8 s while in front, and stops in the '
      'background', () {
    fakeAsync((async) {
      var adopted = 0;
      final watch = RiderTripWatch(
        showsHome: () => true,
        adopt: () async => adopted++,
        bookedOnTheWay: () async => false,
      );
      expect(watch.pollEvery, const Duration(seconds: 8));
      watch.start();
      async.elapse(const Duration(seconds: 17));
      expect(adopted, 2);
      watch.stop();
      async.elapse(const Duration(seconds: 30));
      expect(adopted, 2);
    });
  });

  testWidgets('Q1: on a live ride the booked driver shows as a banner, the '
      'live ride stays', (tester) async {
    final watch = RiderTripWatch(
      showsHome: () => false,
      adopt: () async => fail('a live ride is never replaced'),
      // R09 N5: the rider has a booked ride.
      hasBooked: () => true,
      bookedOnTheWay: () async => true,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: BookedDriverBanner(watch: watch)),
      ),
    );
    expect(find.byKey(const ValueKey('booked-driver-banner')), findsNothing);
    await watch.check();
    await tester.pump();
    expect(find.text('Your booked driver is on the way'), findsOneWidget);
  });
}
