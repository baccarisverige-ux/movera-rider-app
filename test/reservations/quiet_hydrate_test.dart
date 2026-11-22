import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_journey_section.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Test Lab: every `rider_trip_changed` event and every resume reads the
/// booked list again (RiderTripWatch), and the read always notified, so
/// Home's "Your month" card read the whole trip history again each time,
/// also when nothing in the list had changed. A read that changes nothing
/// notifies nobody.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );

  Map<String, Object?> trip(
    String id, {
    String status = 'accepted',
    String at = '2026-12-01T10:00:00Z',
  }) => {
    'tripId': id,
    'kind': 'scheduled',
    'status': status,
    'version': 9,
    'categoryId': 'economy',
    'scheduledAt': at,
    'createdAt': '2026-11-07T10:00:00Z',
    'pickup': {'address': 'Sergels torg', 'lat': 59.3326, 'lng': 18.0649},
    'dropoff': {'address': 'Medborgarplatsen', 'lat': 59.3143, 'lng': 18.0735},
    'stops': <Object>[],
    'fare': {'amountMinor': 24200, 'currency': 'SEK'},
    'paymentMethod': 'cash',
    'driver': {'driverId': 'drv_1', 'firstName': 'Ali'},
  };

  late List<Map<String, Object?>> server;
  late int listReads;
  var now = DateTime.utc(2026, 11, 22, 10);

  ReservationController controller() => ReservationController(
    store: ApiReservationRepository(
      api: ApiClient(
        client: MockClient((request) async {
          listReads++;
          return http.Response(
            jsonEncode({'items': server, 'nextCursor': null}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        env: staging,
      ),
    ),
    environment: staging,
    // Every refresh is past the quiet window of the one before it.
    clock: () => now = now.add(const Duration(seconds: 6)),
  );

  setUp(() {
    server = [trip('trp_1'), trip('trp_2')];
    listReads = 0;
  });

  test('hydrate notifies only when the booked list changed', () async {
    final reservations = controller();
    var notified = 0;
    reservations.addListener(() => notified++);

    await reservations.hydrate();
    expect(notified, 1, reason: 'the first read fills the list');

    await reservations.hydrate();
    await reservations.refresh();
    expect(listReads, 3);
    expect(notified, 1, reason: 'the same list again changes nothing');

    server = [trip('trp_1', status: 'driver_to_pickup'), trip('trp_2')];
    await reservations.hydrate();
    expect(notified, 2, reason: 'a status changed');

    server = [
      trip('trp_1', status: 'driver_to_pickup'),
      trip('trp_2', at: '2026-12-02T11:30:00Z'),
    ];
    await reservations.hydrate();
    expect(notified, 3, reason: 'a pickup time changed');

    server = [...server, trip('trp_3')];
    await reservations.hydrate();
    expect(notified, 4, reason: 'a ride was added');

    server = [server[0], server[2]];
    await reservations.hydrate();
    expect(notified, 5, reason: 'a ride was removed');

    await reservations.hydrate();
    expect(notified, 5);

    server = [];
    await reservations.hydrate();
    expect(notified, 6, reason: 'the last rides were removed');
  });

  test('a first read of an empty list notifies nobody', () async {
    server = [];
    final reservations = controller();
    var notified = 0;
    reservations.addListener(() => notified++);
    await reservations.hydrate();
    expect(notified, 0);
  });

  testWidgets('Your month reads the history once over three refreshes of an '
      'unchanged booked list', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final reservations = controller();
    await tester.runAsync(reservations.hydrate); // app start
    // The card listens to the reservations; here through `changes`, as
    // the default wiring needs the whole app scope.
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    reservations.addListener(() => changes.add(null));
    var historyReads = 0;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomeJourneySection(
                onDestinationTap: () {},
                onOpenSchedule: () {},
                ridesLoader: () async {
                  historyReads++;
                  return reservations.all;
                },
                clock: () => DateTime(2026, 12, 14, 12),
                changes: changes.stream,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(historyReads, 1);

    for (var i = 0; i < 3; i++) {
      await tester.runAsync(reservations.refresh); // rider_trip_changed
      await tester.pumpAndSettle();
    }
    expect(listReads, 4);
    expect(historyReads, 1);

    server = [trip('trp_1', status: 'completed'), trip('trp_2')];
    await tester.runAsync(reservations.refresh);
    await tester.pumpAndSettle();
    expect(historyReads, 2, reason: 'a real change is still read');
  });
}
