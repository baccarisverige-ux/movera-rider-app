// B1 + B8 (finder 2026-11-07, fail-before on main 10f02b32): on Choose your
// ride (selected tile using the wallet) and on the in-trip summary line the
// wallet text ended in "…" at 320-390 px, so the amount the rider pays
// ("vous payez 176 kr") was cut off. Every wallet text must show whole, in
// en, fr and sv, at 320, 375 and 390 px.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/presentation/rider_in_trip_panel.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quotes 226 kr for every ride type, at once.
class _Quotes implements QuoteRepository {
  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int durationSeconds = 600,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) => Future<RideQuote>.value(
    RideQuote(
      id: 'q-$rideType',
      rideType: rideType,
      totalMinor: 22600,
      currency: 'SEK',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      signedPayload: 'sig',
    ),
  );
}

void _noop() {}

/// Every paragraph under [of] shows its whole text (no "…", no lost line).
void expectWhole(WidgetTester tester, Finder of, String where) {
  final paragraphs = find.descendant(of: of, matching: find.byType(RichText));
  expect(paragraphs, findsWidgets, reason: where);
  for (final element in paragraphs.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '$where: "${paragraph.text.toPlainText()}" is cut off',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => L10n.use('en'));

  for (final lang in const ['fr', 'sv', 'en']) {
    for (final width in const [320.0, 375.0, 390.0]) {
      testWidgets('B1: Choose your ride wallet line is whole ($lang, '
          '${width.toInt()} px)', (tester) async {
        L10n.use(lang);
        SharedPreferences.setMockInitialValues({
          WalletStore.balanceKeyFor('SEK'): 50.0,
        });
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final selection = RideSelectionController(quotes: _Quotes());
        addTearDown(selection.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: SelectRide(
              pickupAddress: 'Pickup',
              destinationAddress: 'Destination',
              pickupPosition: const LatLng(59.3293, 18.0686),
              destinationPosition: const LatLng(59.3429, 18.0496),
              pickupAlreadyConfirmed: true,
              selection: selection,
            ),
          ),
        );
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final line = find.byKey(const ValueKey('select-ride-wallet-line'));
        expect(line, findsWidgets);
        expectWhole(tester, line.first, '$lang ${width.toInt()} px');
        expect(
          find.descendant(of: line.first, matching: find.textContaining('176')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 1));
      });

      testWidgets('B8: in-trip pay line keeps the wallet part ($lang, '
          '${width.toInt()} px)', (tester) async {
        L10n.use(lang);
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RiderInTripPanel(
                  destinationAddress: 'Odenplan',
                  rideType: 'Movera',
                  paymentMethod: 'cash',
                  walletAmountMinor: 5000,
                  price: 226,
                  driver: null,
                  rideId: 'ride-b8',
                  onOpenProfile: _noop,
                  onCall: _noop,
                  onCancel: _noop,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final line = find.byKey(const ValueKey<String>('trip-summary-line'));
        expectWhole(tester, line, '$lang ${width.toInt()} px');
        // The wallet part (−50 kr) is in the line: it was the cut part.
        expect(tester.widget<Text>(line).data, contains('50'));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
