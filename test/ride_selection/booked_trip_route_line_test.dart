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
import 'package:movera_rider/core/maps/quoted_route.dart';
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

/// v0.18.169 (contract.json#riderTripRouteLine, review SHOULD 1): on a
/// fresh booking the trip view's line the booking saved reaches Finding
/// drivers, so its map and every later save keep it.
const _line = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

class _LineClient extends InProcessMockClient {
  int rideCreateCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await super.send(request);
    if (request.method.toUpperCase() != 'POST' ||
        request.url.path != '/api/v1/rides') {
      return response;
    }
    rideCreateCalls += 1;
    final json =
        jsonDecode(await response.stream.bytesToString())
            as Map<String, dynamic>;
    final ride = json['ride'];
    if (ride is Map) {
      ride['routePolyline'] = _line;
    } else {
      json['routePolyline'] = _line;
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(json))),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

class _NoActiveTrip implements ActiveTripRepository {
  @override
  Future<RideSnapshot?> fetchActive() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    QuotedRoutes.clear();
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
  });

  testWidgets('a fresh booking opens Finding drivers with the trip line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = _LineClient();
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
          activeTrips: _NoActiveTrip(),
        ),
        settings: const RouteSettings(name: AppRoutes.selectRide),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.text('Select Movera'));
    await tester.pump();
    for (
      var i = 0;
      i < 30 && find.byType(SetPickupPage).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Confirm and search'));
    for (
      var i = 0;
      i < 40 && find.byType(FindingDrivers).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(transport.rideCreateCalls, 1);
    expect(find.byType(FindingDrivers), findsOneWidget);
    final finding = tester.widget<FindingDrivers>(find.byType(FindingDrivers));
    expect(finding.routePolyline, _line);

    FindingDriverController.active?.dispose();
    FindingDriverController.active = null;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
