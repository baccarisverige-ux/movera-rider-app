import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    show GoogleMapsFlutterPlatform;
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/calls/presentation/call_window_gate.dart';
import 'package:movera_rider/features/history/data/ride_history_repositories.dart';
import 'package:movera_rider/features/history/presentation/past_ride_route_map.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/fake_maps_platform.dart';

/// Supervisor SF-S1 (Rules audits/impact/a04-s13-v21-supervisor.md): when
/// the DRIVER ends the trip before the drop-off the trip is `completed`
/// (server src/trips/ride/finish.ts `endedBy: "driver"`), so the server sends
/// `callOpenUntil` and allows the call; the driver's History shows
/// "Call rider". The rider's past ride must then show "Call driver" too.
/// The server's `callOpenUntil` alone decides; the rider's own early end
/// (`cancelled_by_rider`) has no window because the server sends none.
const _button = ValueKey<String>('call-driver-after-trip');

const _demo = AppEnv(
  flavor: AppFlavor.demo,
  apiBaseUrl: 'https://api.demo.movera.invalid',
);

Map<String, dynamic> _trip({required String status, required String endedBy}) =>
    {
      'id': 'trp_sf',
      'status': status,
      'version': 9,
      'updatedAt': DateTime.now()
          .subtract(const Duration(minutes: 10))
          .toUtc()
          .toIso8601String(),
      'categoryId': 'economy',
      'paymentMethodId': 'cash',
      'price': 120,
      'currency': 'SEK',
      'pickupAddress': 'Odenplan',
      'pickupLat': 59.3430,
      'pickupLng': 18.0490,
      'destinationAddress': 'Solna centrum',
      'destinationLat': 59.3590,
      'destinationLng': 18.0000,
      'finish': {
        'endedEarly': true,
        'endedBy': endedBy,
        'total': {'amountMinor': 9000, 'currency': 'SEK'},
      },
    };

/// The past ride as History builds it from GET /rider/trips.
Future<Reservation> _fromServer(Map<String, dynamic> trip) async {
  final mock = InProcessMockClient()..rides['trp_sf'] = trip;
  final rides = await ApiRideHistoryRepository(
    api: ApiClient(client: mock, env: _demo),
  ).loadOnDemand();
  return rides.single;
}

void _window(DateTime? callOpenUntil, List<String> asked) {
  CallDriverAfterTrip.readTrip = (id) async {
    asked.add(id);
    return {
      'tripId': id,
      'status': 'completed',
      'callOpenUntil': ?callOpenUntil?.toUtc().toIso8601String(),
    };
  };
}

Future<void> _open(WidgetTester tester, Reservation ride) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RideHistory(
        reservations: ReservationController(
          store: LocalReservationRepository(
            storage: MemoryReservationStorage(),
          ),
        ),
        onDemandReader: () async => [ride],
        receiptLoader: (_) async => null,
        pathLoader: (_) async => null,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Completed'));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Solna centrum').first);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GoogleMapsFlutterPlatform previousPlatform;
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.use('en');
    previousPlatform = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = FakeMapsPlatform();
    CustomGoogleMap.debugWaitForMaps = false;
  });
  tearDown(() {
    CallDriverAfterTrip.readTrip = null;
    L10n.use('en');
    GoogleMapsFlutterPlatform.instance = previousPlatform;
    CustomGoogleMap.debugWaitForMaps = null;
    PastRideRouteMap.debugLive = null;
  });

  testWidgets('the driver ended early, callOpenUntil in the future → '
      'Call driver shows', (tester) async {
    final ride = await tester.runAsync(
      () => _fromServer(_trip(status: 'completed', endedBy: 'driver')),
    );
    expect(ride!.status, ReservationStatus.completed);
    final asked = <String>[];
    _window(DateTime.now().add(const Duration(minutes: 50)), asked);
    await _open(tester, ride);
    expect(asked, ['trp_sf']);
    expect(find.byKey(_button), findsOneWidget);
    expect(find.text('Call driver'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a past ride marked ended early: the server window decides, '
      'callOpenUntil in the future → Call driver shows', (tester) async {
    final asked = <String>[];
    _window(DateTime.now().add(const Duration(minutes: 50)), asked);
    await _open(
      tester,
      Reservation(
        reservationId: 'ondemand-trp_sf',
        createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
        scheduledPickupAt: DateTime.now().subtract(const Duration(minutes: 10)),
        pickup: ReservationPlace(label: 'Odenplan', lat: 59.3430, lng: 18.0490),
        destination: ReservationPlace(
          label: 'Solna centrum',
          lat: 59.3590,
          lng: 18.0000,
        ),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 120,
        paymentMethod: 'Cash',
        status: ReservationStatus.completed,
        endedEarly: true,
      ),
    );
    expect(asked, ['trp_sf']);
    expect(find.byKey(_button), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the rider ended early, no callOpenUntil → no Call driver', (
    tester,
  ) async {
    final ride = await tester.runAsync(
      () => _fromServer(_trip(status: 'cancelledByRider', endedBy: 'rider')),
    );
    expect(ride!.status, ReservationStatus.completed);
    expect(ride.endedEarly, isTrue);
    _window(null, <String>[]);
    await _open(tester, ride);
    expect(find.byKey(_button), findsNothing);
    expect(find.text('Call driver'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the driver ended early, the window already passed → '
      'no Call driver', (tester) async {
    final ride = await tester.runAsync(
      () => _fromServer(_trip(status: 'completed', endedBy: 'driver')),
    );
    _window(DateTime.now().subtract(const Duration(minutes: 1)), <String>[]);
    await _open(tester, ride!);
    expect(find.byKey(_button), findsNothing);
    expect(find.text('Call driver'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
