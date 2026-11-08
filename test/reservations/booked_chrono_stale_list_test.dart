import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';

/// SUP3-R1: the Upcoming list (the Home chrono's data) is read from the
/// server once, at app start (bootstrap.dart reservations.hydrate). A
/// reload during the booked trip (iOS PWA restart) reads it while the trip
/// is in_trip; the trip then completes; after Done the rider is back on
/// Home and the chrono opens the device-local "live ride" of the finished
/// booked trip (ReservationLiveRide) because nothing re-read the list
/// (contract bookedRideSeen.riderTripEvent: "reads ... (and its Upcoming
/// list) again on it").
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );
  var serverStatus = 'in_trip';
  final pickup = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
  Map<String, Object?> trip() => {
    'tripId': 'trp_b1',
    'kind': 'scheduled',
    'status': serverStatus,
    'version': 9,
    'categoryId': 'economy',
    'scheduledAt': pickup.toIso8601String(),
    'createdAt': '2026-11-07T10:00:00Z',
    'pickup': {'address': 'Sergels torg', 'lat': 59.3326, 'lng': 18.0649},
    'dropoff': {'address': 'Medborgarplatsen', 'lat': 59.3143, 'lng': 18.0735},
    'stops': <Object>[],
    'fare': {'amountMinor': 24200, 'currency': 'SEK'},
    'paymentMethod': 'cash',
    'driver': {'driverId': 'drv_1', 'firstName': 'Ali'},
  };

  testWidgets('after the booked trip completed, Home does not reopen it', (
    tester,
  ) async {
    final reads = <String>[];
    final api = ApiClient(
      client: MockClient((request) async {
        reads.add('${request.method} ${request.url.path}');
        final body = request.url.path.endsWith('/rider/trips')
            ? {
                'items': [trip()],
                'nextCursor': null,
              }
            : trip();
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      env: staging,
    );
    final controller = ReservationController(
      store: ApiReservationRepository(api: api),
      environment: staging,
    );
    await tester.runAsync(controller.hydrate); // app start, mid-trip
    serverStatus = 'completed'; // the trip ends; rider taps Done -> Home
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HomeReservationChrono(
            controller: controller,
            openRoute: <T>(Future<T?> Function() open) async {
              opened++;
              return null;
            },
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();
    expect(
      opened,
      0,
      reason: 'chrono opened the finished booked ride; reads: $reads',
    );
    expect(
      controller.upcoming(),
      isEmpty,
      reason: 'stale cache still lists it as upcoming',
    );
  });
}
