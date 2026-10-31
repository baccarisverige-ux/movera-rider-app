import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // rider-u235: one in-process backend per test, seeded with the ride, so a
  // cancel only passes when the server row really becomes cancelled (an
  // unseeded mock answers 404, which the cancel paths treat as confirmed).
  late InProcessMockClient server;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    server = InProcessMockClient();
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.idle);
  });

  Future<void> seed(String id, RideStatus status, String serverStatus) async {
    server.rides[id] = {'id': id, 'status': serverStatus};
    AppScope.instance.ride.restoreFromBackend(status, id: id);
    await RideSnapshotStore.save(
      RideSnapshot(
        status: status,
        savedAt: DateTime.now(),
        pickupAddress: 'Sveavägen 1',
        destinationAddress: 'Hornsgatan 2',
        pickupLat: 59.34,
        pickupLng: 18.05,
        destinationLat: 59.31,
        destinationLng: 18.04,
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'Apple Pay',
        rideId: id,
      ),
    );
  }

  testWidgets('G5 live: a charged cancel shows "Cancellation fee 35 kr" on '
      'Home', (tester) async {
    const rideId = 'g5-cancel-fee';
    await seed(rideId, RideStatus.driverAssigned, 'accepted');
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1))
      ..primeResume(status: RideStatus.driverAssigned);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('journey-home')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.waitingForDriver),
        builder: (_) => WaitingForDriver(
          pickupAddress: 'Sveavägen 1',
          destinationAddress: 'Hornsgatan 2',
          pickupPosition: const LatLng(59.34, 18.05),
          destinationPosition: const LatLng(59.31, 18.04),
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          rideId: rideId,
          realtime: realtime,
          controller: ActiveRideController(
            api: ApiClient(
              // Live: the stream's cancelled_by_rider took the app Home
              // while the cancel answer was on its way.
              client: _FeeOnCancel(
                server,
                () => nav.currentState!.popUntil((r) => r.isFirst),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driver/ride details are not suitable'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel ride'));
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('journey-home'), findsOneWidget);
    expect(find.textContaining('Cancellation fee'), findsOneWidget);
    expect(find.textContaining('35'), findsOneWidget);
    realtime.dispose();
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });
}

/// The live server's cancel answer: a 35 kr cancel fee, owed.
class _FeeOnCancel extends http.BaseClient {
  _FeeOnCancel(this.inner, this.beforeAnswer);
  final http.Client inner;
  final void Function() beforeAnswer;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    if (request.method != 'POST' || !request.url.path.endsWith('/cancel')) {
      return response;
    }
    beforeAnswer();
    await Future<void>.delayed(const Duration(seconds: 1));
    final text = await response.stream.bytesToString();
    final json = jsonDecode(text) as Map<String, dynamic>;
    final projection = (json['projection'] ?? json['ride'] ?? json) as Map;
    projection['cancellation'] = {
      'actor': 'rider',
      'reasonCode': 'something_else',
      'fee': {'amountMinor': 3500, 'currency': 'SEK'},
      'feeKind': 'cancel',
      'feeStatus': 'owed',
    };
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(json))),
      response.statusCode,
      headers: response.headers,
    );
  }
}
