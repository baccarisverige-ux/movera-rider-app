import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/booking/data/booking_repository.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/active_trip_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner decision "Confirm and search" (2026-11-07, "Chargement sur le
/// bouton"): Set pickup stays on screen with a spinner on its button while
/// the quote, route and booking run, then Finding replaces it directly; the
/// old "Choose your ride" screen never shows in between. Errors end as
/// before: back on Choose your ride with the same message.
///
/// PROOF (problem 3): the booking POST is held open so the screen shown
/// between "Confirm and search" and Finding can be seen.
class _SlowBookClient extends InProcessMockClient {
  int rideCreateCalls = 0;
  final Completer<void> release = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method.toUpperCase() == 'POST' &&
        request.url.path == '/api/v1/rides') {
      rideCreateCalls += 1;
      await release.future;
    }
    return super.send(request);
  }
}

/// Owner, live test 2026-10-26: Select ride said "We could not book this
/// ride. Check the fare and try again." The server had refused the booking
/// because the rider still had a ride going (409 active_trip_exists), so
/// the fare was never the problem and trying again could not help.
class _RefusedClient extends InProcessMockClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method.toUpperCase() == 'POST' &&
        request.url.path == '/api/v1/rides') {
      final body = utf8.encode(
        jsonEncode({
          'code': 'validation_failed',
          'message': 'Refused.',
          'requestId': 'req_test',
          'retryable': false,
        }),
      );
      return http.StreamedResponse(
        Stream.value(body),
        422,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    return super.send(request);
  }
}

class _RideGoingClient extends InProcessMockClient {
  int rideCreateCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method.toUpperCase() == 'POST' &&
        request.url.path == '/api/v1/rides') {
      rideCreateCalls += 1;
      final body = utf8.encode(
        jsonEncode({
          'code': 'conflict',
          'message': 'You already have a ride going.',
          'requestId': 'req_test',
          'retryable': false,
          'reason': 'active_trip_exists',
        }),
      );
      return http.StreamedResponse(
        Stream.value(body),
        409,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    return super.send(request);
  }
}

class _ActiveTrips implements ActiveTripRepository {
  _ActiveTrips(this.trip);
  final RideSnapshot? trip;
  int calls = 0;

  @override
  Future<RideSnapshot?> fetchActive() async {
    calls += 1;
    return trip;
  }
}

RideSnapshot _searching() => RideSnapshot(
  rideId: 'trp_already_going',
  status: RideStatus.findingDriver,
  savedAt: DateTime.now(),
  pickupAddress: 'Södertälje C',
  destinationAddress: 'Hamngatan 1',
  pickupLat: 59.1954,
  pickupLng: 17.6252,
  destinationLat: 59.3326,
  destinationLng: 18.0649,
  rideType: 'Movera',
  price: 349,
  paymentMethod: 'Apple Pay',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
  });

  bool chooseVisible() =>
      find.text('Choose your ride').hitTestable().evaluate().isNotEmpty;
  bool on<T>() => find.byType(T).evaluate().isNotEmpty;

  /// Select ride, then Set pickup, then a tap on Confirm and search.
  Future<void> confirmAndSearch(
    WidgetTester tester,
    InProcessMockClient transport, {
    ActiveTripRepository? activeTrips,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(client: transport);
    final selection = RideSelectionController(
      quotes: ApiQuoteRepository(api: api),
      flags: const FeatureFlags(),
    );
    addTearDown(selection.dispose);
    final booking = BookingController(
      store: BookingRepository(coordinator: BookingCoordinator(api: api)),
    );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          navigatorKey: moveraNavigatorKey,
          home: const Scaffold(body: Center(child: Text('home'))),
        ),
      ),
    );
    moveraNavigatorKey.currentState!.push(
      RideStageTransition(
        SelectRide(
          pickupAddress: 'Stockholm Central',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: const LatLng(59.3300, 18.0590),
          destinationPosition: const LatLng(59.6519, 17.9186),
          pickupAlreadyConfirmed: true,
          selection: selection,
          booking: booking,
          activeTrips: activeTrips ?? _NoTrip(),
        ),
        settings: const RouteSettings(name: AppRoutes.selectRide),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.text('Select Movera'));
    await tester.pump();
    for (var i = 0; i < 30 && !on<SetPickupPage>(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Confirm and search'));
  }

  testWidgets('problem 3: after Confirm and search, Choose your ride is not '
      'shown again before Finding', (tester) async {
    final transport = _SlowBookClient();
    await confirmAndSearch(tester, transport);
    var chooseSeen = false;
    for (var i = 0; i < 30 && transport.rideCreateCalls == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      chooseSeen |= chooseVisible();
    }
    expect(transport.rideCreateCalls, 1);
    // The booking request is on its way (real network: ~0.5-1.5 s).
    await tester.pump(const Duration(milliseconds: 300));
    final setPickupOnScreen = on<SetPickupPage>();
    final findingOnScreen = on<FindingDrivers>();
    final spinner = find
        .byKey(const ValueKey('set-pickup-confirm-waiting'))
        .evaluate()
        .isNotEmpty;
    // ignore: avoid_print
    print(
      'PROOF during POST: setPickup=$setPickupOnScreen '
      'finding=$findingOnScreen chooseYourRideVisible=${chooseVisible()} '
      'spinner=$spinner',
    );
    expect(
      chooseVisible(),
      isFalse,
      reason: 'the old Choose your ride screen shows while the ride is booked',
    );
    expect(
      chooseSeen,
      isFalse,
      reason: 'Choose your ride showed before the POST',
    );
    expect(setPickupOnScreen, isTrue, reason: 'Set pickup stays while booking');
    expect(spinner, isTrue, reason: 'a spinner on Confirm and search');
    transport.release.complete();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      chooseSeen |= chooseVisible();
    }
    // ignore: avoid_print
    print(
      'PROOF after POST: setPickup=${on<SetPickupPage>()} '
      'finding=${on<FindingDrivers>()} chooseYourRideSeen=$chooseSeen',
    );
    expect(chooseSeen, isFalse);
    expect(on<FindingDrivers>(), isTrue, reason: 'Finding is pushed');
    expect(
      on<SetPickupPage>(),
      isFalse,
      reason: 'Set pickup is removed under Finding',
    );
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a refused booking ends as before: back on Choose your ride '
      'with the same message', (tester) async {
    await confirmAndSearch(tester, _RefusedClient());
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print(
      'refused: setPickup=${on<SetPickupPage>()} '
      'chooseYourRide=${chooseVisible()}',
    );
    expect(on<SetPickupPage>(), isFalse);
    expect(on<FindingDrivers>(), isFalse);
    expect(chooseVisible(), isTrue);
    expect(
      find.text('We could not book this ride. Check the fare and try again.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a ride already going (409) opens that ride, with no Set '
      'pickup left under it', (tester) async {
    final trips = _ActiveTrips(_searching());
    await confirmAndSearch(tester, _RideGoingClient(), activeTrips: trips);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print(
      '409: setPickup=${on<SetPickupPage>()} '
      'finding=${on<FindingDrivers>()} trips=${trips.calls}',
    );
    expect(trips.calls, 1);
    expect(on<FindingDrivers>(), isTrue);
    expect(on<SetPickupPage>(), isFalse);
    expect(
      find.text('You already have a ride going. Here it is.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
  });
}

class _NoTrip implements ActiveTripRepository {
  @override
  Future<RideSnapshot?> fetchActive() async => null;
}
