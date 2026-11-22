import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_sheet.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/finding_driver/presentation/ride_details_sheet.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v0.18.143 screenshots of the change-route screens next to the approved
/// mockup (Rules plan/inspiration-ride-change-2026-11-20). Opt-in:
/// `CHANGE_SHOTS=<dir> flutter test <this>`;
/// without it every test is skipped, so CI never writes files.
final String? _dir = Platform.environment['CHANGE_SHOTS'];

const _map = DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF9EDCF7), Color(0xFFDDF2DF), Color(0xFFF4F6F4)],
    ),
  ),
);

Future<void> _fonts() async {
  final flutterRoot = File(
    Platform.resolvedExecutable,
  ).parent.parent.parent.parent.parent.parent.path;
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(File(path).readAsBytesSync());
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    roboto.addFont(bytes('/usr/share/fonts/opentype/inter/Inter-$w.otf'));
  }
  await roboto.load();
  // GoogleFonts asks for Poppins by these family names; Inter stands in.
  for (final (family, w) in [
    ('Poppins_regular', 'Regular'),
    ('Poppins_500', 'Medium'),
    ('Poppins_600', 'SemiBold'),
    ('Poppins_700', 'Bold'),
  ]) {
    await (FontLoader(
      family,
    )..addFont(bytes('/usr/share/fonts/opentype/inter/Inter-$w.otf'))).load();
  }
  await (FontLoader('MaterialIcons')..addFont(
        bytes(
          '$flutterRoot/bin/cache/artifacts/material_fonts/'
          'MaterialIcons-Regular.otf',
        ),
      ))
      .load();
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  final render =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (_dir != null) await _fonts();
  });
  tearDownAll(() => L10n.use('en'));
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<GlobalKey> pump(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto'),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 47, bottom: 34),
            ),
            child: body,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  for (final language in ['sv', 'en']) {
    testWidgets('2 ride details ($language)', (tester) async {
      L10n.use(language);
      final key = await pump(
        tester,
        Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: _map),
              Align(
                alignment: Alignment.bottomCenter,
                child: Material(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: RideDetailsSheet(
                    pickupAddress: 'Klockarvägen 37',
                    destinationAddress: 'Arlanda Airport',
                    rideType: 'Movera',
                    price: 600,
                    currency: 'SEK',
                    paymentMethod: 'Cash',
                    notes: const RideNotes(),
                    onCancelTrip: () {},
                    onEditPickup: () {},
                    onEditDestination: () {},
                    onAddStop: () {},
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (_dir != null) await _shot(tester, key, '2-ride-details-$language');
    }, skip: _dir == null);

    testWidgets('3 change route, pickup open while searching ($language)', (
      tester,
    ) async {
      L10n.use(language);
      final key = await pump(
        tester,
        RoutePickerPage(
          pageTitle: L10n.current.changeRoute,
          pickupAddress: 'Klockarvägen 37',
          destinationAddress: 'T-Centralen',
          stops: const [],
          stopsSupported: true,
          pickupLocked: false,
          driverOnTheWay: false,
          initialField: 'pickup',
          finishLabel: L10n.current.done,
          capture: EarlyInputCapture(),
          here: const GeoPoint(59.33, 18.06),
          homeAddress: null,
          workAddress: null,
          recent: const [],
          onSetFavourite: (_) async => null,
          onPickOnMap: ({required pickup, required address}) async => null,
          onFinish: (_) async => null,
        ),
      );
      if (_dir != null) await _shot(tester, key, '3-change-route-$language');
    }, skip: _dir == null);

    testWidgets('4 your price has changed ($language)', (tester) async {
      L10n.use(language);
      final key = await pump(
        tester,
        Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: _map),
              Align(
                alignment: Alignment.bottomCenter,
                child: Material(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: RouteChangeSheet(
                    whileSearching: true,
                    paymentMethod: 'Cash',
                    quote: RouteChangeQuote(
                      pickupAddress: 'Klockarvägen 37',
                      pickupPoint: const GeoPoint(59.6, 17.9),
                      destinationAddress: 'T-Centralen',
                      destinationPoint: const GeoPoint(59.33, 18.06),
                      stops: const [],
                      oldPriceKr: 600,
                      newPriceKr: 280,
                      currency: 'SEK',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (_dir != null) await _shot(tester, key, '4-price-changed-$language');
    }, skip: _dir == null);
  }
}
