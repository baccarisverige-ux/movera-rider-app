import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/add_tip.dart';

import 'zone_config_fakes.dart';

/// Owner Q5: the tip buttons are the trip zone's `tips` (enabled ones
/// only), in the zone's currency, and the tip is sent in that currency.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(LastCompletedRide.clear);
  tearDown(LastCompletedRide.clear);

  RideSnapshot finished(String currency, double lat, double lng) => RideSnapshot(
    status: RideStatus.tripCompleted,
    rideId: 'ride_tip_$currency',
    pickupAddress: 'Pickup',
    destinationAddress: 'Drop-off',
    pickupLat: lat,
    pickupLng: lng,
    destinationLat: lat + 0.02,
    destinationLng: lng + 0.02,
    rideType: 'Economy',
    price: 24,
    paymentMethod: 'Card',
    savedAt: DateTime(2026, 10, 20, 9),
    currency: currency,
  );

  Future<void> pumpTips(
    WidgetTester tester,
    RideCompleteController controller, {
    ValueChanged<int?>? onTip,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: RideCompletedAddTip(controller: controller, onTipChanged: onTip),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a Paris trip offers 1 €, 2 € and 5 €', (tester) async {
    LastCompletedRide.remember(finished('EUR', 48.86, 2.34));
    final configs = EditedZoneConfigs();
    int? tip;
    await pumpTips(
      tester,
      RideCompleteController(config: configs),
      onTip: (minor) => tip = minor,
    );

    for (final label in ['1 €', '2 €', '5 €']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('kr'), findsNothing);
    expect(configs.asked, contains('FR-PC'));

    await tester.tap(find.text('5 €'));
    await tester.pump();
    expect(find.text('5 € selected.'), findsOneWidget);
    expect(tip, 500);
  });

  testWidgets('a Tunis trip offers 1 DT, 2 DT and 3 DT', (tester) async {
    LastCompletedRide.remember(finished('TND', 36.80, 10.18));
    int? tip;
    await pumpTips(
      tester,
      RideCompleteController(config: EditedZoneConfigs()),
      onTip: (minor) => tip = minor,
    );

    for (final label in ['1 DT', '2 DT', '3 DT']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('2 DT'));
    await tester.pump();
    expect(tip, 2000, reason: 'dinars have three decimals');
  });

  testWidgets('admin-edited tips: a disabled one is hidden, a new one shown', (
    tester,
  ) async {
    LastCompletedRide.remember(finished('SEK', 59.33, 18.06));
    final configs = EditedZoneConfigs({
      'Z001': {
        'tips': [
          {'amount': wireMoney(1000, 'SEK'), 'enabled': false},
          {'amount': wireMoney(2000, 'SEK'), 'enabled': true},
          {'amount': wireMoney(5000, 'SEK'), 'enabled': true},
        ],
      },
    });
    await pumpTips(tester, RideCompleteController(config: configs));

    expect(find.text('10 kr'), findsNothing);
    expect(find.text('20 kr'), findsOneWidget);
    expect(find.text('50 kr'), findsOneWidget);
    expect(find.text('30 kr'), findsNothing);
  });

  test('the tip is sent in the trip currency, the rating as whole stars', () async {
    final bodies = <Map<String, dynamic>>[];
    final api = ApiClient(
      client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({'code': 'OK', 'status': 'accepted'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    LastCompletedRide.remember(finished('EUR', 48.86, 2.34));
    final controller = RideCompleteController(
      feedback: RideFeedbackRepository(api: api),
      config: EditedZoneConfigs(),
    );

    await controller.submitFeedback(
      rideId: 'ride_tip_EUR',
      rating: 4,
      tipMinor: 200,
      idempotencyKey: 'tip-key-0123456789abcdef',
    );

    expect(bodies.single['tipMinor'], 200);
    expect(bodies.single['currency'], 'EUR');
    expect(bodies.single['rating'], isA<int>());
    expect(bodies.single['rating'], 4);
  });
}
