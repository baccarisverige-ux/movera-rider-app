import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/saved_places/presentation/pickup_location.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('rider-r5-35: a lookup answering while the picker closes does '
      'not close the screen under it', (tester) async {
    final answer = Completer<PlaceResult?>();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) =>
            MaterialApp(navigatorKey: nav, home: const Text('Saved places')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('Edit place')),
    );
    await tester.pumpAndSettle();
    nav.currentState!.push(
      MaterialPageRoute<String>(
        builder: (_) =>
            RiderSearchPickupLocation(geocode: (_) => answer.future),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Odenplan');
    await tester.tap(find.byKey(const ValueKey('saved-place-search')));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 50));
    answer.complete(
      const PlaceResult(address: 'Odenplan', point: GeoPoint(59.34, 18.05)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit place'), findsOneWidget);
  });
}
