import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/quoted_route.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/features/ride_booking/application/trip_route_line.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/styles/route_style.dart';
import 'package:movera_rider/shared/widgets/approximate_route_badge.dart';

/// v0.18.167 screenshots for the owner (Rules plan/inspiration-ride-change-
/// 2026-11-20/shots-route-line): the line [roadTripLine] gives the booking
/// maps with a Google quote vs without one (fallback + badge). The map
/// itself (Google tiles) does not draw in a test, so a plain background
/// stands in; the line, its colours and the badge are the app's own.
/// Opt-in: `ROUTE_SHOTS=<dir> flutter test <this>`; CI writes no files.
final String? _dir = Platform.environment['ROUTE_SHOTS'];

const _pickup = LatLng(59.3326, 18.0649); // Sergels torg
const _dropoff = LatLng(59.3143, 18.0735); // Medborgarplatsen

/// A sample road line in the shape of a Google answer (Sergels torg,
/// Skeppsbron, Slussen, Götgatan); Google is never called in a test.
const _road = <LatLng>[
  _pickup,
  LatLng(59.3312, 18.0662),
  LatLng(59.3293, 18.0671),
  LatLng(59.3270, 18.0705),
  LatLng(59.3246, 18.0739),
  LatLng(59.3217, 18.0746),
  LatLng(59.3197, 18.0724),
  LatLng(59.3181, 18.0716),
  LatLng(59.3161, 18.0722),
  _dropoff,
];

String _encode(List<LatLng> points) {
  final out = StringBuffer();
  var lat = 0;
  var lng = 0;
  void value(int v) {
    var x = v < 0 ? ~(v << 1) : v << 1;
    while (x >= 0x20) {
      out.writeCharCode((0x20 | (x & 0x1f)) + 63);
      x >>= 5;
    }
    out.writeCharCode(x + 63);
  }

  for (final p in points) {
    final la = (p.latitude * 1e5).round();
    final ln = (p.longitude * 1e5).round();
    value(la - lat);
    value(ln - lng);
    lat = la;
    lng = ln;
  }
  return out.toString();
}

class _Straight extends RoutingService {
  @override
  List<GeoPoint> line({required GeoPoint from, required GeoPoint to}) => [
    from,
    to,
  ];
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.points);
  final List<LatLng> points;

  @override
  void paint(Canvas canvas, Size size) {
    const minLat = 59.3120,
        maxLat = 59.3350,
        minLng = 18.0560,
        maxLng = 18.0830;
    Offset at(LatLng p) => Offset(
      (p.longitude - minLng) / (maxLng - minLng) * size.width,
      (maxLat - p.latitude) / (maxLat - minLat) * size.height,
    );
    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (final p in points.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = RiderRouteStyle.casing
        ..strokeWidth = 9
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    final a = at(points.first), b = at(points.last);
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(a, b, [
          RiderRouteStyle.pickup,
          RiderRouteStyle.destination,
        ])
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(a, 9, Paint()..color = RiderRouteStyle.pickup);
    canvas.drawCircle(b, 9, Paint()..color = RiderRouteStyle.destination);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.points != points;
}

Future<void> _fonts() async {
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(File(path).readAsBytesSync());
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium']) {
    roboto.addFont(bytes('/usr/share/fonts/opentype/inter/Inter-$w.otf'));
  }
  await roboto.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_dir != null) await _fonts();
  });
  tearDownAll(() => L10n.use('en'));

  for (final google in [true, false]) {
    for (final language in ['sv', 'en']) {
      final name = google ? 'google-route' : 'fallback-approximate';
      testWidgets('$name ($language)', skip: _dir == null, (tester) async {
        L10n.use(language);
        QuotedRoutes.clear();
        if (google) QuotedRoutes.remember([_pickup, _dropoff], _encode(_road));
        late TripRouteLine route;
        await tester.runAsync(() async {
          route = (await roadTripLine(
            from: _pickup,
            stops: const [],
            to: _dropoff,
            routing: _Straight(),
          ))!;
        });
        tester.view.physicalSize = const Size(390, 520);
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
              home: Scaffold(
                body: Stack(
                  children: [
                    const Positioned.fill(
                      child: ColoredBox(color: Color(0xFFEEF1EC)),
                    ),
                    Positioned.fill(
                      child: CustomPaint(painter: _LinePainter(route.points)),
                    ),
                    if (route.approximate)
                      const Positioned(
                        left: 12,
                        bottom: 12,
                        child: ApproximateRouteBadge(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('approximate-route-badge')),
          google ? findsNothing : findsOneWidget,
        );
        final render =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$_dir/$name-$language.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(png!.buffer.asUint8List());
        });
      });
    }
  }
}
