// B3 + B4 (finder 2026-11-07, fail-before on main): Set pickup showed the
// English stand-in "Pickup location" as the pickup card title in fr/sv, its
// top bar kept the trailing country ("Odenplan, Sweden"), and the receipt
// "Trip details" showed both as they were. L10n.place translates the
// stand-in and drops the country, as on Finding and Waiting.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/trip_detail.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// A reverse geocoder that never answers (no street known).
class _SilentGeocoder extends AppGeocoding {
  @override
  Future<String?> reverseGeocodeAddress(double latitude, double longitude) =>
      Completer<String?>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() {
    L10n.use('en');
    LastCompletedRide.clear();
  });

  for (final lang in const ['fr', 'sv']) {
    testWidgets('B3/B4: Set pickup card and top bar in $lang', (tester) async {
      L10n.use(lang);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: SetPickupPage(
            initialPosition: const LatLng(59.3293, 18.0686),
            initialAddress: pickupLocationFallbackLabel,
            destinationAddress: 'Odenplan, Sweden',
            destinationPosition: const LatLng(59.3429, 18.0496),
            ride: const SetPickupRide(
              name: 'Movera',
              image: 'missing.png',
              seats: 4,
              etaMin: 5,
              tripMinutes: 12,
            ),
            fare: const SetPickupFare(totalKr: 226),
            payment: const SetPickupPayment(
              brand: 'cash',
              name: 'Cash',
              detail: '',
            ),
            brandMark: (_) => const SizedBox(),
            geocoding: _SilentGeocoder(),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(pickupLocationFallbackLabel), findsNothing);
      expect(find.text(L10n.current.pickupLocation), findsWidgets);
      expect(find.text('Odenplan, Sweden'), findsNothing);
      expect(find.text('Odenplan'), findsWidgets);
    });

    testWidgets('B4: receipt trip details in $lang', (tester) async {
      L10n.use(lang);
      LastCompletedRide.remember(
        RideSnapshot(
          status: RideStatus.tripInProgress,
          savedAt: DateTime.now(),
          pickupAddress: pickupLocationFallbackLabel,
          destinationAddress: 'Odenplan, Sweden',
          pickupLat: 59.33,
          pickupLng: 18.06,
          destinationLat: 59.34,
          destinationLng: 18.05,
          rideType: 'Movera',
          price: 226,
          paymentMethod: 'Cash',
          rideId: 'b4-receipt',
        ),
        charged: const Money(22600),
      );
      await tester.pumpWidget(
        MoveraScreenUtilInit(
          builder: (_, __) => MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RideCompletedTripDetail(
                  rideId: 'b4-receipt',
                  controller: RideCompleteController(
                    feedback: RideFeedbackRepository(
                      api: ApiClient(client: InProcessMockClient()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(pickupLocationFallbackLabel), findsNothing);
      // The row label and the translated stand-in value.
      expect(find.text(L10n.current.pickupLocation), findsNWidgets(2));
      expect(find.text('Odenplan, Sweden'), findsNothing);
      expect(find.text('Odenplan'), findsOneWidget);
    });
  }
}
