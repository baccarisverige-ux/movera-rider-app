import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../responsive/responsive_harness.dart';

/// R-UI UI-02: when the destination lookup failed (offline, timeout, 5xx)
/// Plan your ride stayed busy for good — no message, and every later tap on
/// a suggestion, recent or saved place was ignored.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a failed lookup says so and the next pick still works', (
    tester,
  ) async {
    var calls = 0;
    await pumpMoveraScreen(
      tester,
      RoutePickerPage(
        pickupAddress: 'Sveavägen 1, Stockholm',
        destinationAddress: '',
        stops: const [],
        stopsSupported: true,
        initialField: 'destination',
        capture: EarlyInputCapture(),
        here: const GeoPoint(59.33, 18.06),
        homeAddress: null,
        workAddress: null,
        recent: const [
          'Drottninggatan 50, Stockholm',
          'Stureplan 4, Stockholm',
        ],
        onSetFavourite: (_) async => null,
        onPickOnMap: ({required pickup, required address}) async => null,
        onFinish: (_) async {
          calls++;
          if (calls == 1) throw TimeoutException('geocode timed out');
          return null;
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.textContaining('Drottninggatan', findRichText: true).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(calls, 1);
    expect(
      find.text("Couldn't reach Movera. Check your connection and try again."),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(
      find.textContaining('Stureplan', findRichText: true).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 2, reason: 'the picker is usable again after a failure');
  });
}
