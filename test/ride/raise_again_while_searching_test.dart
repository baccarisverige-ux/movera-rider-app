import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
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

/// Owner, live test 2026-10-26: "while search and wait long time can't add
/// money and update trip price". The raise card showed once (at 45 s) and
/// never again after a raise or "Keep waiting", the still-looking card hid
/// it after 3 min, and a total above the ceiling left Confirm grey with no
/// reason.
RideSnapshot _snap({double price = 259, int? maxOfferMinor}) => RideSnapshot(
  status: RideStatus.findingDriver,
  savedAt: DateTime.now(),
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.3,
  pickupLng: 18.0,
  destinationLat: 59.4,
  destinationLng: 18.1,
  rideType: 'Movera',
  price: price,
  paymentMethod: 'Apple Pay',
  rideId: 'r1',
  maxOfferMinor: maxOfferMinor,
);

/// The demo's mock server, refusing every raise the way movera-server
/// refuses one above its ceiling.
class _TooHigh extends InProcessMockClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'PATCH' && request.url.path == '/api/v1/rides/r1') {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'code': 'invalid_request',
          'message': 'The fare can be raised to at most 2 times the quoted price.',
          'reason': 'raise_too_high',
        }))),
        400,
        headers: {'content-type': 'application/json'},
      );
    }
    return super.send(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  FindingDriverController started(
    InProcessMockClient client, {
    RideSnapshot? snapshot,
    Duration searchTimeout = const Duration(minutes: 3),
  }) {
    client.rides['r1'] = {
      'id': 'r1',
      'status': 'findingDriver',
      'price': snapshot?.price ?? 259,
      'pickupLat': 59.3,
      'pickupLng': 18.0,
    };
    final api = ApiClient(client: client);
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1), api: api);
    final controller = FindingDriverController(
      realtime: rt,
      ride: RideSession()..rideId = 'r1',
      store: FindingDriverRepository(),
      priceBumpAfter: const Duration(seconds: 45),
      searchTimeout: searchTimeout,
      api: api,
    );
    controller.start(
      snapshot: snapshot ?? _snap(),
      onTick: (_) {},
      onMatched: () {},
    );
    addTearDown(() {
      controller.dispose();
      rt.dispose();
    });
    return controller;
  }

  test('after a raise the rider can open the card and raise again', () async {
    final controller = started(InProcessMockClient());
    controller.debugAdvance(45);
    expect(controller.showPriceBump, isTrue);
    expect(await controller.confirmPriceIncrease(20), isTrue);
    expect(controller.currentPrice, 279);
    expect(controller.showPriceBump, isFalse);
    expect(controller.showRaiseEntry, isTrue);

    controller.openPriceBump();
    expect(controller.showPriceBump, isTrue);
    expect(controller.showRaiseEntry, isFalse);
    expect(await controller.confirmPriceIncrease(20), isTrue);
    expect(controller.currentPrice, 299);
  });

  test('after Keep waiting the card stays closed until the rider opens it, '
      'also once the search is still looking', () {
    final controller = started(
      InProcessMockClient(),
      searchTimeout: const Duration(seconds: 60),
    );
    controller.debugAdvance(45);
    controller.dismissPriceBump();
    controller.debugAdvance(30);
    expect(controller.showPriceBump, isFalse);
    expect(controller.showStillLooking, isTrue);
    expect(controller.showRaiseEntry, isTrue);

    controller.openPriceBump();
    expect(controller.showPriceBump, isTrue);
    expect(
      controller.priceBumpOpened,
      isTrue,
      reason: 'opened by the rider, it shows over the still-looking card',
    );
  });

  test('a fare at its ceiling offers no raise', () {
    final controller = started(
      InProcessMockClient(),
      snapshot: _snap(price: 466, maxOfferMinor: 46600),
    );
    controller.debugAdvance(45);
    expect(controller.canRaise, isFalse);
    expect(controller.showRaiseEntry, isFalse);
    controller.openPriceBump();
    expect(controller.priceBumpOpened, isFalse);
  });

  test('a raise above the ceiling says the most the offer can be', () async {
    final controller = started(_TooHigh());
    controller.debugAdvance(45);
    expect(await controller.confirmPriceIncrease(20), isFalse);
    expect(controller.editFeedback, startsWith('Your offer can be at most '));
  });

  testWidgets('a step above the ceiling is greyed out and a typed total '
      'above it says the most it can be', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PriceBumpCard(
            currentPrice: 147,
            maxPrice: 265,
            steps: const [20, 50, 100, 200],
            onConfirm: (_) {},
            onKeepWaiting: () {},
          ),
        ),
      ),
    ));
    await tester.tap(find.text('+200 kr'));
    await tester.pump();
    expect(find.text('Confirm 347 kr'), findsNothing);
    expect(find.byKey(const ValueKey('price-bump-max')), findsNothing);

    await tester.tap(find.text('+100 kr'));
    await tester.pump();
    expect(find.text('Confirm 247 kr'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '300');
    await tester.pump();
    expect(find.text('Your offer can be at most 265 kr.'), findsOneWidget);
    expect(find.text('Set new price'), findsOneWidget);
  });
}
