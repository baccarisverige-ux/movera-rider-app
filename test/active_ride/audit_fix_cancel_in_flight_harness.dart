import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// Holds every cancel/end-early POST until the test answers it, so a
/// realtime event or a back gesture can land while the request is out.
class CancelGate extends http.BaseClient {
  Completer<http.StreamedResponse>? pending;
  int sends = 0;

  bool get inFlight => pending != null;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method == 'POST') {
      sends += 1;
      final completer = Completer<http.StreamedResponse>();
      pending = completer;
      return completer.future;
    }
    return Future.value(_json(200, {'tripId': 'x', 'status': 'accepted'}));
  }

  void answer(int status, Map<String, Object?> body) {
    final completer = pending!;
    pending = null;
    completer.complete(_json(status, body));
  }

  static http.StreamedResponse _json(int status, Map<String, Object?> body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );
}

RideSnapshot waitingSnapshot(String rideId, RideStatus status) => RideSnapshot(
  status: status,
  savedAt: DateTime.now(),
  pickupAddress: 'Stockholm pickup',
  destinationAddress: 'Stockholm destination',
  pickupLat: 59.3293,
  pickupLng: 18.0686,
  destinationLat: 59.3326,
  destinationLng: 18.0649,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Apple Pay',
  rideId: rideId,
  version: 1,
);

/// Waiting over an 'audit-root' route, its cancel requests going through
/// [gate]; the session is seeded as a restore would (version 1).
Future<GlobalKey<NavigatorState>> pumpWaitingWithGate(
  WidgetTester tester, {
  required String rideId,
  required RideStatus status,
  required CancelGate gate,
}) async {
  await RideSnapshotStore.save(waitingSnapshot(rideId, status));
  AppScope.instance.ride
    ..restoreFromBackend(status, id: rideId)
    ..authoritativeVersion = 1;
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Center(child: Text('audit-root'))),
    ),
  );
  navigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => WaitingForDriver(
        pickupAddress: 'Stockholm pickup',
        destinationAddress: 'Stockholm destination',
        pickupPosition: const LatLng(59.3293, 18.0686),
        destinationPosition: const LatLng(59.3326, 18.0649),
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'Apple Pay',
        controller: ActiveRideController(api: ApiClient(client: gate)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  expect(find.byType(WaitingForDriver), findsOneWidget);
  return navigatorKey;
}

/// Confirms a cancel on Waiting (Cancel ride, Cancel request, Skip) and
/// returns once the request is held by [gate].
Future<void> confirmCancel(WidgetTester tester, CancelGate gate) async {
  await tester.tap(find.byIcon(Icons.close_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Cancel request'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Skip'));
  for (var i = 0; i < 20 && !gate.inFlight; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(gate.inFlight, isTrue, reason: 'the cancel request is in flight');
  // The frame that shows the "Cancelling…" card.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
