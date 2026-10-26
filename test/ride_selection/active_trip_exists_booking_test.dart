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

/// Owner, live test 2026-10-26: Select ride said "We could not book this
/// ride. Check the fare and try again." The server had refused the booking
/// because the rider still had a ride going (409 active_trip_exists), so
/// the fare was never the problem and trying again could not help.
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

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

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

  Future<_RideGoingClient> bookMovera(
    WidgetTester tester,
    ActiveTripRepository activeTrips,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = _RideGoingClient();
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
          activeTrips: activeTrips,
        ),
        settings: const RouteSettings(name: AppRoutes.selectRide),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(SelectRide), findsOneWidget);

    await tester.tap(find.text('Select Movera'));
    await tester.pump();
    for (
      var i = 0;
      i < 30 && find.byType(SetPickupPage).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Confirm and search'));
    for (var i = 0; i < 30 && transport.rideCreateCalls == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(transport.rideCreateCalls, 1);
    return transport;
  }

  testWidgets('the ride already going is opened, not the fare message', (
    tester,
  ) async {
    final activeTrips = _ActiveTrips(_searching());
    await bookMovera(tester, activeTrips);
    for (
      var i = 0;
      i < 30 && find.byType(FindingDrivers).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(activeTrips.calls, 1);
    expect(find.byType(FindingDrivers), findsOneWidget);
    final finding = tester.widget<FindingDrivers>(find.byType(FindingDrivers));
    expect(
      finding.destinationAddress,
      'Hamngatan 1',
      reason: 'the ride going is shown, not the one the rider tried to book',
    );
    expect(AppScope.instance.ride.rideId, 'trp_already_going');
    expect((await RideSnapshotStore.read())?.rideId, 'trp_already_going');
    expect(
      find.text('You already have a ride going. Here it is.'),
      findsOneWidget,
    );
    expect(
      find.text('We could not book this ride. Check the fare and try again.'),
      findsNothing,
    );
  });

  testWidgets('when the ride going cannot be read, the rider is told why', (
    tester,
  ) async {
    final activeTrips = _ActiveTrips(null);
    await bookMovera(tester, activeTrips);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(activeTrips.calls, 1);
    expect(find.byType(FindingDrivers), findsNothing);
    expect(find.byType(SelectRide), findsOneWidget);
    expect(
      find.text('You already have a ride going. Try again in a moment.'),
      findsOneWidget,
    );
    expect(
      find.text('We could not book this ride. Check the fare and try again.'),
      findsNothing,
    );
  });
}
