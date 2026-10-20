import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/finding_driver/presentation/price_bump_card.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mock_fare.dart';

RideSnapshot _snap() => RideSnapshot(
  status: RideStatus.findingDriver,
  savedAt: DateTime.now(),
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.3,
  pickupLng: 18.0,
  destinationLat: 59.4,
  destinationLng: 18.1,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Apple Pay',
  rideId: 'r1',
);

FindingDriverController _controller(ApiClient api, MockRideRealtime rt) {
  final controller = FindingDriverController(
    realtime: rt,
    ride: RideSession()..rideId = 'r1',
    store: FindingDriverRepository(),
    api: api,
    delayedAfter: Duration.zero,
  );
  controller.start(snapshot: _snap(), onTick: (_) {}, onMatched: () {});
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
  });

  test('raise offer sends only the increase, never a client-computed price',
      () async {
    final bodies = <Map<String, dynamic>>[];
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'code': 'OK',
              'ride': {'id': 'r1', 'status': 'searchDelayed', 'price': 279},
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'code': 'OK', 'vehicles': []}), 200);
      }),
    );
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final controller = _controller(api, rt);

    expect(await controller.confirmPriceIncrease(20), isTrue);

    // Contract v0.3.0: the raise as Money, not kronor.
    expect(bodies.single, {
      'offerIncrease': {'amountMinor': 2000, 'currency': 'SEK'},
    });
    expect(bodies.single.containsKey('price'), isFalse);
    controller.dispose();
    rt.dispose();
  });

  test('the fare shown afterwards is the one the server returned', () async {
    // The server decides the bump is worth 269, not the 279 the client would
    // have assumed from 259 + 20.
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          return http.Response(
            jsonEncode({
              'code': 'OK',
              'ride': {'id': 'r1', 'status': 'searchDelayed', 'price': 269},
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'code': 'OK', 'vehicles': []}), 200);
      }),
    );
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final controller = _controller(api, rt);

    expect(await controller.confirmPriceIncrease(20), isTrue);

    expect(controller.currentPrice, 269);
    expect(controller.offerConfirmation, 'Updated offer: 269 kr');
    expect((await RideSnapshotStore.read())?.price, 269);
    controller.dispose();
    rt.dispose();
  });

  test('an acknowledgement without a fare keeps the last confirmed price',
      () async {
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          return http.Response(jsonEncode({'code': 'OK'}), 200);
        }
        return http.Response(jsonEncode({'code': 'OK', 'vehicles': []}), 200);
      }),
    );
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final controller = _controller(api, rt);

    expect(await controller.confirmPriceIncrease(20), isTrue);

    expect(controller.currentPrice, 259);
    expect(controller.offerConfirmation, isNull);
    expect(controller.editFeedback, contains('once Movera confirms'));
    controller.dispose();
    rt.dispose();
  });

  test('the in-process mock prices the bump itself and ignores client price',
      () async {
    final backend = InProcessMockClient();
    backend.rides['r1'] = {'id': 'r1', 'status': 'findingDriver', 'price': 259};
    final api = ApiClient(client: backend);

    await api.patch('/api/v1/rides/r1', body: {'price': 9999});
    expect(mockFareKr(backend.rides['r1']!), 259);

    await api.patch('/api/v1/rides/r1', body: {'offerIncreaseKr': 20});
    expect(mockFareKr(backend.rides['r1']!), 279);

    await expectLater(
      api.patch('/api/v1/rides/r1', body: {'offerIncreaseKr': -50}),
      throwsA(anything),
    );
    expect(mockFareKr(backend.rides['r1']!), 279);
  });

  testWidgets('the bump card says the final fare is server-confirmed',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PriceBumpCard(
              currentPrice: 259,
              steps: const [20, 40],
              maxPrice: 400,
              onConfirm: (_) {},
              onKeepWaiting: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('price-bump-server-confirms')), findsNothing);
    await tester.tap(find.text('+20 kr'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('price-bump-server-confirms')),
      findsOneWidget,
    );
  });
}
