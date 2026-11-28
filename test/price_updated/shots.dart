// v0.18.174 price popup tests: phone frame, optional screenshots, blank maps.
// From the 2026-11-28 proof (Rules audits/impact/price-updated-proof/).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

// v0.18.174: screenshots only when OUT is given (flutter test --dart-define
// OUT=<dir> POPPINS=<dir with Poppins-*.ttf> ICONS=<MaterialIcons-Regular.otf>);
// the normal test run draws nothing and needs no font file.
const shotDir = String.fromEnvironment('OUT');

/// The app language of the run (fr by default; --dart-define LANG=sv|en for
/// the owner's screenshots in the other languages).
const testLang = String.fromEnvironment('LANG', defaultValue: 'fr');
const _poppinsDir = String.fromEnvironment('POPPINS');
const _iconsFont = String.fromEnvironment('ICONS');
const _robotoDir = String.fromEnvironment('ROBOTO');
final shotKey = GlobalKey();

/// The real screen at 393x852 points, 2x.
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(786, 1704);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget framed(Widget app) => RepaintBoundary(key: shotKey, child: app);

Future<void> shot(WidgetTester tester, String name) async {
  if (shotDir.isEmpty) return;
  await tester.pump(const Duration(milliseconds: 400));
  final b =
      shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await b.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$shotDir/$name-$testLang.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> loadFonts() async {
  if (shotDir.isEmpty) return;
  const p = _poppinsDir;
  Future<ByteData> f(String n) async =>
      ByteData.sublistView(File('$p/Poppins-$n.ttf').readAsBytesSync());
  final map = {
    'Poppins_regular': 'Regular',
    'Poppins_400': 'Regular',
    'Poppins_500': 'Medium',
    'Poppins_600': 'SemiBold',
    'Poppins_700': 'Bold',
  };
  for (final e in map.entries) {
    await (FontLoader(e.key)..addFont(f(e.value))).load();
  }
  final poppins = FontLoader('Poppins');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    poppins.addFont(f(w));
  }
  await poppins.load();
  if (_robotoDir.isNotEmpty) {
    final roboto = FontLoader('Roboto');
    for (final w in ['Regular', 'Medium']) {
      roboto.addFont(
        Future.value(
          ByteData.sublistView(
            File('$_robotoDir/Inter-$w.otf').readAsBytesSync(),
          ),
        ),
      );
    }
    await roboto.load();
  }
  const icons = _iconsFont;
  await (FontLoader('MaterialIcons')..addFont(
        Future.value(ByteData.sublistView(File(icons).readAsBytesSync())),
      ))
      .load();
}

/// No native map in a widget test: a plain map-coloured ground instead.
class BlankMaps extends GoogleMapsFlutterPlatform {
  @override
  Future<void> init(int mapId) async {}

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) => const ColoredBox(color: Color(0xFFEDEBE6), child: SizedBox.expand());

  @override
  void dispose({required int mapId}) {}
}

void useBlankMaps() {
  final maps = GoogleMapsFlutterPlatform.instance;
  GoogleMapsFlutterPlatform.instance = BlankMaps();
  addTearDown(() => GoogleMapsFlutterPlatform.instance = maps);
}
