import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/driver_profile/application/driver_profile_data.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-23: screen 3 (on trip; PROPOSAL-screen3-2026-11-23.html).
/// Shared harness with screen 2: ("driver on the way") as approved in
/// PROPOSAL-screen2-2026-11-23.html — sheet style, B2 driver card with EU
/// plate, inline driver message with the server's quick replies, games
/// row, arrived popup C1, ⋯ menu, profile P1v2, chat v2.
const _driver = MatchedDriver(
  id: 'drv_1',
  firstName: 'Ali',
  rating: 4.92,
  tripCount: 1284,
  vehicleMake: 'Toyota',
  vehicleModel: 'Corolla',
  vehicleColor: 'Vit',
  plate: 'ABC 123',
  yearsOnMovera: 3,
);

const _profileJson = {
  'driverId': 'drv_1',
  'firstName': 'Ali',
  'verified': true,
  'photoUrl': null,
  'languages': ['sv', 'en'],
  'city': 'Stockholm',
  'sinceMonth': '2023-03',
  'years': 3,
  'tripCount': 1284,
  'rating': 4.8,
  'compliments': [
    {'code': 'great_service', 'count': 42},
    {'code': 'clean_car', 'count': 18},
  ],
  'milestones': [
    {'code': 'trips_1000', 'reachedAt': '2026-03'},
  ],
  'latestReview': {
    'text': 'Punktlig och trygg.',
    'name': 'Sara',
    'month': '2026-11',
  },
};

class _Feed extends RideRealtime {
  final events = StreamController<RideRealtimeEvent>.broadcast();
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => events.stream;
  @override
  Future<void> reconnectAndResync(String rideId) async {}
  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}
  @override
  void unsubscribe() {}
  @override
  void cancelRide() {}
  @override
  void dispose() {}
}

Widget _app(Widget home, {bool reduceMotion = false}) => MediaQuery(
  data: MediaQueryData(
    size: const Size(390, 844),
    disableAnimations: reduceMotion,
  ),
  child: MoveraScreenUtilInit(
    builder: (_, __) => MaterialApp(
      locale: const Locale('sv'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpWaiting(
  WidgetTester tester, {
  RideStatus status = RideStatus.driverAssigned,
  bool routeChange = true,
}) async {
  _phone(tester);
  AppScope.instance.ride.restoreFromBackend(status, id: 'trp_1');
  await tester.pumpWidget(
    _app(
      WaitingForDriver(
        pickupAddress: 'Sveavägen 1',
        destinationAddress: 'Arlanda',
        pickupPosition: const LatLng(59.33, 18.07),
        destinationPosition: const LatLng(59.34, 18.06),
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'cash',
        driver: _driver,
        realtime: _Feed(),
        routeChangeSupported: routeChange,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle(const Duration(milliseconds: 250));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.use('sv');
    MessagesRepository.clearAllSessions();
    DriverProfiles.clear();
    DriverProfiles.debugApi = ApiClient(
      env: const AppEnv(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://api.staging.movera.example',
      ),
      client: MockClient(
        (_) async => http.Response(jsonEncode(_profileJson), 200),
      ),
    );
    DriverProfileSettings.current = DriverProfileSettings.defaults;
  });
  tearDown(() => L10n.use('en'));

  testWidgets('on trip: driver card with B2 buttons, games row, and no '
      'bottom end button when the ⋯ menu has it', (tester) async {
    await _pumpWaiting(tester, status: RideStatus.tripInProgress);
    expect(find.byKey(const ValueKey('driver-on-way-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('waiting-more')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('active-trip-cancel'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('search-games-row'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('on trip: ⋯ opens Resedetaljer with "Avsluta resan här" as the '
      'last red row; it opens the same end confirm', (tester) async {
    await _pumpWaiting(tester, status: RideStatus.tripInProgress);
    await tester.ensureVisible(find.byKey(const ValueKey('waiting-more')));
    await tester.tap(find.byKey(const ValueKey('waiting-more')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final end = find.byKey(const ValueKey('ride-details-cancel'));
    expect(end, findsOneWidget);
    expect(
      find.descendant(of: end, matching: find.text('Avsluta resan här')),
      findsOneWidget,
    );
    await tester.tap(end);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Behåll resan'), findsOneWidget);
    expect(find.byKey(const ValueKey('cancel-ride-confirm')), findsOneWidget);
  });

  // Owner 2026-11-23: the driver card's ⋯ ALWAYS opens the ride details
  // menu, whose last red row cancels / ends; the top-left ✕ is gone.
  for (final (name, status, routeChange, label) in [
    ('on the way', RideStatus.driverAssigned, true, 'Avboka resan'),
    ('arrived', RideStatus.driverWaiting, true, 'Avboka resan'),
    ('on trip', RideStatus.tripInProgress, true, 'Avsluta resan här'),
    (
      'on the way, route changes off',
      RideStatus.driverAssigned,
      false,
      'Avboka resan',
    ),
    (
      'on trip, route changes off',
      RideStatus.tripInProgress,
      false,
      'Avsluta resan här',
    ),
  ]) {
    testWidgets('$name: no top-left ✕; ⋯ reaches "$label"', (tester) async {
      await _pumpWaiting(tester, status: status, routeChange: routeChange);
      // The arrived popup (if any) is closed first.
      final arrivedPop = find.byKey(const ValueKey('driver-arrived-on-way'));
      if (arrivedPop.evaluate().isNotEmpty) {
        Navigator.of(tester.element(arrivedPop)).pop();
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
      }
      expect(find.bySemanticsLabel('Avbryt resan'), findsNothing);
      expect(find.bySemanticsLabel('Avsluta resan'), findsNothing);
      expect(
        find.byKey(const ValueKey('active-trip-cancel'), skipOffstage: false),
        findsNothing,
      );
      final more = find.byKey(const ValueKey('waiting-more'));
      expect(more, findsOneWidget);
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      final row = find.byKey(const ValueKey('ride-details-cancel'));
      expect(
        find.descendant(of: row, matching: find.text(label)),
        findsOneWidget,
      );
      await tester.tap(row);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Behåll resan'), findsOneWidget);
    });
  }
}
