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
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/driver_profile/application/driver_profile_data.dart';
import 'package:movera_rider/features/driver_profile/presentation/driver_on_way_card.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v0.18.155 wiring (owner 2026-11-20 "Add card like that", "Now build
/// all"): the waiting screen shows the new driver card where the old
/// driver block was; a tap opens the profile sheet; with the zone's
/// `driverProfile.on` off the old block stays; a failed profile read keeps
/// the card on the trip's own data.
const staging = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://api.staging.movera.example',
);

const profileJson = {
  'driverId': 'drv_1',
  'firstName': 'Ali',
  'verified': true,
  'photoUrl': null,
  'languages': ['sv', 'ar', 'en'],
  'city': 'Stockholm',
  'sinceMonth': '2023-03',
  'years': 3,
  'tripCount': 1284,
  'rating': 4.92,
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

const driver = MatchedDriver(
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

Future<void> pumpWaiting(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  L10n.use('sv');
  addTearDown(() => L10n.use('en'));
  AppScope.instance.ride.restoreFromBackend(
    RideStatus.driverAssigned,
    id: 'trp_1',
  );
  await tester.pumpWidget(
    MoveraScreenUtilInit(
      builder: (_, __) => MaterialApp(
        locale: const Locale('sv'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WaitingForDriver(
          pickupAddress: 'Sveavägen 1',
          destinationAddress: 'Arlanda',
          pickupPosition: const LatLng(59.33, 18.07),
          destinationPosition: const LatLng(59.34, 18.06),
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'cash',
          driver: driver,
          realtime: _Feed(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle(const Duration(milliseconds: 250));
}

void _serve(int code) {
  DriverProfiles.debugApi = ApiClient(
    env: staging,
    client: MockClient(
      (r) async => http.Response(
        code == 200 ? jsonEncode(profileJson) : '{"error":"x"}',
        code,
      ),
    ),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    DriverProfiles.clear();
    DriverProfiles.reads = 0;
    DriverProfiles.debugApi = null;
    DriverProfileSettings.current = DriverProfileSettings.defaults;
  });

  testWidgets('driver on the way, profile on: the new card with name, '
      'car, plate, Call and Message', (tester) async {
    _serve(200);
    await pumpWaiting(tester);
    expect(find.byType(DriverOnWayCard), findsOneWidget);
    expect(find.byType(WaitingDriverCard), findsNothing);
    final card = find.byKey(const ValueKey('driver-on-way-card'));
    for (final t in ['Ali', 'ABC 123', 'Toyota Corolla · Vit']) {
      expect(
        find.descendant(of: card, matching: find.textContaining(t)),
        findsWidgets,
      );
    }
    expect(find.byKey(const ValueKey('waiting-call')), findsOneWidget);
    expect(find.byKey(const ValueKey('waiting-chat')), findsOneWidget);
  });

  testWidgets('a tap on the card opens the profile sheet with its data', (
    tester,
  ) async {
    _serve(200);
    await pumpWaiting(tester);
    await tester.tap(find.byKey(const ValueKey('driver-on-way-open-profile')));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('driver-profile-sheet')), findsOneWidget);
    expect(find.text('Vad resenärer säger'), findsOneWidget);
    expect(find.text('Utmärkt service'), findsOneWidget);
    expect(find.text('Svenska · العربية · English'), findsOneWidget);
    expect(DriverProfiles.reads, 1);
  });

  testWidgets('profile off in the zone: the old block, no new card', (
    tester,
  ) async {
    DriverProfileSettings.current = const DriverProfileSettings(
      on: false,
      reviews: false,
    );
    await pumpWaiting(tester);
    expect(find.byType(WaitingDriverCard), findsOneWidget);
    expect(find.byType(DriverOnWayCard), findsNothing);
  });

  testWidgets('profile read fails: the card keeps the trip data, no crash', (
    tester,
  ) async {
    _serve(500);
    await pumpWaiting(tester);
    await tester.tap(find.byKey(const ValueKey('driver-on-way-open-profile')));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('driver-profile-sheet')), findsNothing);
    Navigator.of(tester.element(find.byType(Navigator).last)).maybePop();
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(find.byType(DriverOnWayCard), findsOneWidget);
    expect(find.text('ABC 123'), findsOneWidget);
    expect(DriverProfiles.reads, 1);
  });
}
