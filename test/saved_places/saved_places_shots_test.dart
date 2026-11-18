import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/home/presentation/widgets/places_popup.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_top_actions.dart';
import 'package:movera_rider/features/saved_places/application/quick_save.dart';
import 'package:movera_rider/features/saved_places/presentation/place_save_sheet.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Screenshots of the saved-places design next to the approved mock-ups
/// (owner 2026-11-18). Opt-in: `PLACES_SHOTS=<dir> flutter test <this>`;
/// without it every test is skipped, so CI never writes files.
final String? _dir = Platform.environment['PLACES_SHOTS'];

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
    // The mock-ups are in Swedish.
    L10n.use('sv');
  });
  tearDownAll(() => L10n.use('en'));
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<GlobalKey> pump(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Real soft shadows, as on a phone (tests draw them flat by default).
    debugDisableShadows = false;
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
            child: Scaffold(body: body),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  Widget capsule({bool open = false}) => Stack(
    children: [
      const Positioned.fill(child: _map),
      Positioned(
        top: 50,
        right: 16,
        child: PremiumTopActions(
          onMenuTap: () {},
          onPlacesTap: () {},
          placesOpen: open,
        ),
      ),
    ],
  );

  testWidgets('home capsule (P3)', skip: _dir == null, (tester) async {
    final key = await pump(tester, capsule());
    await _shot(tester, key, 'home-capsule');
  });

  testWidgets('places pop-up (P2-3)', skip: _dir == null, (tester) async {
    final key = await pump(
      tester,
      Builder(
        builder: (context) => Stack(
          children: [
            Positioned.fill(child: capsule()),
            Center(
              child: TextButton(
                onPressed: () => PlacesPopup.open(
                  context,
                  places: popupPlaces(
                    home: 'Storgatan 12, Södertälje',
                    work: 'Hamngatan 5, Södertälje',
                    others: const [
                      (
                        title: 'Gym',
                        type: 'gym',
                        address: 'Nordic Wellness, Genetaleden 7',
                      ),
                    ],
                  ),
                  recent: const [
                    'Södertälje Centrum, Stationsplan, Södertälje',
                    'Södertälje sjukhus, Rosenborgsgatan 6–10',
                    'Tom Tits Experiment, Storgatan 33, Södertälje',
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _shot(tester, key, 'places-popup');
  });

  for (final saved in [false, true]) {
    testWidgets(
      'S3 save sheet ${saved ? 'after Hem' : 'on open'}',
      skip: _dir == null,
      (tester) async {
        final key = await pump(
          tester,
          Stack(
            children: [
              const Positioned.fill(child: _map),
              Positioned.fill(
                child: PlaceSaveSheet(
                  address: 'Viksbergsvägen 9, Södertälje',
                  delay: const Duration(milliseconds: 10),
                  quickSave: PlaceQuickSave(supported: () => true),
                  categories: () => const [
                    (id: 'economy', name: 'Movera'),
                    (id: 'comfort', name: 'Comfort'),
                    (id: 'premium', name: 'Premium'),
                    (id: 'priority', name: 'Priority'),
                    (id: 'xl', name: 'Movera XL'),
                  ],
                ),
              ),
            ],
          ),
        );
        if (saved) {
          await tester.tap(find.byKey(const ValueKey('place-save-type-home')));
          await tester.pumpAndSettle();
        }
        await _shot(tester, key, saved ? 's3-after-home' : 's3-on-open');
      },
    );
  }
}
