import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/trip_detail.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// rider-r5-53: the ended-early "km driven" line uses the app language's
/// decimal mark.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() {
    L10n.use('en');
    LastCompletedRide.clear();
  });

  testWidgets('4,2 km in Swedish', (tester) async {
    L10n.use('sv');
    LastCompletedRide.remember(
      RideSnapshot(
        status: RideStatus.tripInProgress,
        savedAt: DateTime.now(),
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.33,
        pickupLng: 18.06,
        destinationLat: 59.40,
        destinationLng: 18.10,
        rideType: 'Movera',
        price: 319,
        paymentMethod: 'Cash',
        rideId: 'r5-53',
      ),
      charged: const Money(27340),
      endedEarly: true,
      drivenMeters: 4200,
    );
    await tester.pumpWidget(MoveraScreenUtilInit(
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RideCompletedTripDetail(
              rideId: 'r5-53',
              controller: RideCompleteController(
                feedback: RideFeedbackRepository(
                  api: ApiClient(client: InProcessMockClient()),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('4,2 km'), findsOneWidget);
  });
}
