import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/active_ride/presentation/rider_in_trip_panel.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/driver_profile/application/driver_profile_data.dart';
import 'package:movera_rider/features/driver_profile/presentation/driver_on_way_card.dart';
import 'package:movera_rider/l10n/l10n.dart';

import 'driver_profile_wiring_test.dart' show driver, profileJson, staging;

/// Owner 2026-11-23 (mockup "Option A" + "During the trip — new card"):
/// the card's message button says "Chatt" so Ring + Chatt + ⋯ fit in one
/// row at 390 px; the same card shows during the trip (switch off: the old
/// block).
Widget _app(Widget child) {
  L10n.use('sv');
  return MoveraScreenUtilInit(
    builder: (_, __) => MaterialApp(
      locale: const Locale('sv'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void _noop() {}

Widget _inTrip() => SingleChildScrollView(
  child: RiderInTripPanel(
    destinationAddress: 'Sveavägen 1',
    rideType: 'Movera',
    paymentMethod: 'cash',
    price: 259,
    driver: driver,
    rideId: 'trp_1',
    onOpenProfile: _noop,
    onCall: _noop,
    onMore: _noop,
    onCancel: _noop,
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    tearDownSetup();
  });
  tearDown(() {
    L10n.use('en');
    DriverProfileSettings.current = DriverProfileSettings.defaults;
    DriverProfiles.debugApi = null;
  });

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('390x844 sv: the chat button reads "Chatt" in full', (
    tester,
  ) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: DriverOnWayCard(
            driver: driver,
            rideId: 'trp_1',
            onOpenProfile: _noop,
            onCall: _noop,
            onMore: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Owner 2026-11-23 (B2): the label sits under the round button.
    final label = find.descendant(
      of: find.byKey(const ValueKey('driver-on-way-card')),
      matching: find.text('Chatt'),
    );
    expect(tester.widget<Text>(label).data, 'Chatt');
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: label, matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      paragraph.size.width,
      greaterThanOrEqualTo(
        paragraph.getMaxIntrinsicWidth(double.infinity) - 0.5,
      ),
    );
    expect(tester.takeException(), isNull);
    // The spoken label stays the full word, as before.
    expect(find.bySemanticsLabel('Meddelande'), findsOneWidget);
  });

  testWidgets('in trip, profile on: the new card; a tap opens the sheet', (
    tester,
  ) async {
    await phone(tester);
    DriverProfiles.debugApi = ApiClient(
      env: staging,
      client: MockClient(
        (r) async => http.Response(jsonEncode(profileJson), 200),
      ),
    );
    await tester.pumpWidget(_app(_inTrip()));
    await tester.pumpAndSettle();
    expect(find.byType(DriverOnWayCard), findsOneWidget);
    expect(find.byType(WaitingDriverCard), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('driver-on-way-open-profile')),
    );
    await tester.tap(find.byKey(const ValueKey('driver-on-way-open-profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('driver-profile-sheet')), findsOneWidget);
  });

  testWidgets('in trip, profile off: the old driver block', (tester) async {
    await phone(tester);
    DriverProfileSettings.current = const DriverProfileSettings(
      on: false,
      reviews: false,
    );
    await tester.pumpWidget(_app(_inTrip()));
    await tester.pumpAndSettle();
    expect(find.byType(WaitingDriverCard), findsOneWidget);
    expect(find.byType(DriverOnWayCard), findsNothing);
  });
}

void tearDownSetup() {
  DriverProfiles.clear();
  DriverProfileSettings.current = DriverProfileSettings.defaults;
}
