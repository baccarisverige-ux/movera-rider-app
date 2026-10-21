import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/ride_booking/data/catalog_quote_repository.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:movera_rider/features/ride_selection/presentation/ride_labels.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-77: the built-in category notes and badges in the rider's language.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(() => L10n.use('en'));

  Future<void> pumpSelectRide(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selection = RideSelectionController(
      catalog: RideCatalogController(
        api: ApiClient(
          client: MockClient(
            (_) async => http.Response(jsonEncode({'code': 'X'}), 500),
          ),
        ),
        cache: MemoryRideCatalogCache(),
      ),
      quotes: CatalogQuoteRepository(),
      flags: FeatureFlags(),
    );
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Klockarvägen 37',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.6519, 17.9186),
          selection: selection,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  testWidgets('a Swedish rider reads the notes and badges in Swedish', (
    tester,
  ) async {
    L10n.use('sv');
    await pumpSelectRide(tester);

    expect(find.text('Prisvärda och smidiga resor'), findsOneWidget);
    expect(find.text('Nyare bilar med extra benutrymme'), findsOneWidget);
    expect(find.text('REKOMMENDERAT'), findsOneWidget);
    expect(find.text('Affordable and convenient rides'), findsNothing);
    expect(find.text('RECOMMENDED'), findsNothing);
    await close(tester);
  });

  testWidgets('a French rider reads them in French', (tester) async {
    L10n.use('fr');
    await pumpSelectRide(tester);

    expect(find.text('Des courses abordables et pratiques'), findsOneWidget);
    expect(find.text('RECOMMANDÉ'), findsOneWidget);
    expect(find.text('Affordable and convenient rides'), findsNothing);
    await close(tester);
  });

  testWidgets('English stays as it was', (tester) async {
    await pumpSelectRide(tester);

    expect(find.text('Affordable and convenient rides'), findsOneWidget);
    expect(find.text('RECOMMENDED'), findsOneWidget);
    await close(tester);
  });

  test('every built-in note and badge has a translation', () {
    L10n.use('sv');
    for (final ride in RideSelectionRepository.builtInRides) {
      expect(rideNoteFor(ride.note), isNot(ride.note), reason: ride.id);
      final badge = ride.badge;
      if (badge != null) {
        expect(rideBadgeFor(badge), isNot(badge), reason: ride.id);
      }
    }
    // A text the admin wrote is shown as it is.
    expect(rideNoteFor('Electric vans only'), 'Electric vans only');
    expect(rideBadgeFor('NEW'), 'NEW');
  });
}
