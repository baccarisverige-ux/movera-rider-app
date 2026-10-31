import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/shared/styles/route_style.dart';

/// uat-r2: every marker bitmap holds this many pixels per logical pixel (a
/// 3x phone screen); the descriptor keeps its logical size, so the map draws
/// it sharp instead of stretching a 1x image.
const double markerPixelRatio = 3;

/// The rider's own position pin (owner 2026-10-31, plan/rider-pin/SPEC.md).
///
/// Seen from above (a flat map) it is a solid blue dot ([blue], [dotDiameter]
/// across) in a thin white ring ([ringWidth]) with a very soft shadow. On a
/// tilted map it becomes a small white puck: a short cylinder whose top is a
/// white ellipse with the blue ellipse on it, its side wall light grey. The
/// ellipses flatten with the camera tilt.
///
/// The pin is a screen-fixed marker: the same size on screen at every zoom.
/// Its bitmap is drawn at the device pixel ratio and anchored at the centre
/// of its top ([anchorFor]). No cone, no pulse.
class MoveraRiderPuckMarker {
  const MoveraRiderPuckMarker._();

  /// The dot (rgb 0, 140, 250): flat, solid, no gradient.
  static const Color blue = Color(0xFF008CFA);

  /// The ring around the flat dot.
  static const Color ring = Color(0xFFFFFFFF);

  /// The top of the tilted puck.
  static const Color puckTop = Color(0xFFFAFBFC);

  /// The puck's side wall, top to bottom.
  static const Color wallLight = Color(0xFFE3E6E9);
  static const Color wallDark = Color(0xFFD5DADF);

  /// The soft shadow under the pin.
  static const Color shadow = Color(0x2E1B2733);

  /// Flat pin: blue dot and white ring, in logical points.
  static const double dotDiameter = 9;
  static const double ringWidth = 1.75;
  static const double flatDiameter = dotDiameter + 2 * ringWidth;

  /// Tilted puck at full lean: top ellipse [puckWidth] x
  /// [puckWidth] * [fullLeanRatio], blue ellipse [puckBlueWidth] wide, a
  /// [puckWall] high side wall.
  static const double puckWidth = 20;
  static const double puckBlueWidth = 16;
  static const double puckWall = 3;
  static const double fullLeanRatio = 11 / 20;

  /// Room around the pin for its shadow.
  static const double margin = 4;

  /// Owner, after the before/after: "Blue must be same in all zoom steps".
  /// Rider maps tilt with zoom, so a puck that leans with the camera would
  /// change the blue's size from one zoom step to the next: the maps show
  /// the flat pin at every zoom and tilt. The tilted puck below (SPEC)
  /// stays drawable for when the owner wants it back.
  static const bool tiltsWithCamera = false;

  /// Below this camera tilt (degrees) the map counts as flat.
  static const double puckFromTilt = 4;

  /// The tilted pin is drawn once per this many degrees of tilt.
  static const int tiltStep = 5;

  /// The tilt a bitmap is drawn for: 0 on a flat map, else [tilt] snapped
  /// to [tiltStep] (at most the map engines' 67.5 deg, as 70).
  static int tiltBucket(double tilt) {
    if (!tilt.isFinite || tilt < puckFromTilt) return 0;
    final snapped = (tilt / tiltStep).round() * tiltStep;
    return snapped.clamp(tiltStep, 70);
  }

  /// How far [tilt] has turned the dot into the puck: 0 flat, 1 full puck.
  /// The top's height/width follows the camera (cos tilt) down to
  /// [fullLeanRatio], where the puck is complete.
  static double lean(double tilt) {
    final bucket = tiltBucket(tilt);
    if (bucket == 0) return 0;
    final ratio = math.cos(bucket * math.pi / 180);
    return ((1 - ratio) / (1 - fullLeanRatio)).clamp(0.0, 1.0);
  }

  /// The pin's geometry at [tilt], in logical points.
  static ({Size size, Offset centre, Size top, Size dot, double wall}) geometry(
    double tilt,
  ) {
    final t = lean(tilt);
    final ratio = 1 - t * (1 - fullLeanRatio);
    final topW = ui.lerpDouble(flatDiameter, puckWidth, t)!;
    final dotW = ui.lerpDouble(dotDiameter, puckBlueWidth, t)!;
    final wall = puckWall * t;
    final topH = topW * ratio;
    final size = Size(topW + 2 * margin, topH + wall + 2 * margin);
    return (
      size: size,
      centre: Offset(size.width / 2, margin + topH / 2),
      top: Size(topW, topH),
      dot: Size(dotW, dotW * ratio),
      wall: wall,
    );
  }

  /// The marker anchor at [tilt]: the centre of the pin's top, which is
  /// the rider's position.
  static Offset anchorFor(double tilt) {
    final g = geometry(tilt);
    return Offset(g.centre.dx / g.size.width, g.centre.dy / g.size.height);
  }

  /// Paints the pin for [tilt] in logical points (origin top left of
  /// [geometry]'s size).
  static void paint(Canvas canvas, double tilt) {
    final g = geometry(tilt);
    final c = g.centre;
    final top = Rect.fromCenter(
      center: c,
      width: g.top.width,
      height: g.top.height,
    );
    final base = top.shift(Offset(0, g.wall));
    // Very soft shadow: under the dot, or under the puck's base.
    canvas.drawOval(
      base.shift(const Offset(0, 0.6)).inflate(0.4),
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.3),
    );
    if (g.wall > 0) {
      // The side wall: the base ellipse and the band up to the top.
      final wallPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, c.dy),
          Offset(0, base.bottom),
          const [wallLight, wallDark],
        );
      canvas
        ..drawOval(base, wallPaint)
        ..drawRect(
          Rect.fromLTRB(top.left, c.dy, top.right, base.center.dy),
          wallPaint,
        );
    }
    canvas
      ..drawOval(top, Paint()..color = g.wall > 0 ? puckTop : ring)
      ..drawOval(
        Rect.fromCenter(center: c, width: g.dot.width, height: g.dot.height),
        Paint()..color = blue,
      );
  }

  static final Map<(int, int), Future<BitmapDescriptor>> _iconCache = {};

  /// The pin bitmap for [tilt] at [pixelRatio] (the device's), with its
  /// decoded image (tests read its pixels) and its logical size.
  static Future<({BitmapDescriptor icon, ui.Image image, Size size})>
  createVisual({double tilt = 0, double pixelRatio = markerPixelRatio}) async {
    final ratio = pixelRatio.isFinite && pixelRatio > 0 ? pixelRatio : 1.0;
    final bucket = tiltBucket(tilt).toDouble();
    final size = geometry(bucket).size;
    final width = (size.width * ratio).ceil();
    final height = (size.height * ratio).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio, ratio);
    paint(canvas, bucket);
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    // Never fall back to Google's default pin for the rider's position. In
    // the unlikely event PNG encoding fails, use an invisible descriptor
    // rather than flashing a red pin.
    final icon = data == null
        ? BitmapDescriptor.bytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
          )
        // The logical size given up front (rider-u58: the web plugin does
        // not probe the bitmap) and the pixel ratio (uat-r2: sharp, not a
        // stretched 1x image).
        : BitmapDescriptor.bytes(
            data.buffer.asUint8List(),
            width: width / ratio,
            height: height / ratio,
            imagePixelRatio: ratio,
          );
    return (
      icon: icon,
      image: image,
      size: Size(width / ratio, height / ratio),
    );
  }

  /// The cached pin bitmap for [tilt] (snapped by [tiltBucket]) at
  /// [pixelRatio].
  static Future<BitmapDescriptor> createIcon({
    double tilt = 0,
    double pixelRatio = markerPixelRatio,
  }) {
    final key = (tiltBucket(tilt), (pixelRatio * 100).round());
    return _iconCache.putIfAbsent(key, () async {
      final visual = await createVisual(tilt: tilt, pixelRatio: pixelRatio);
      visual.image.dispose();
      return visual.icon;
    });
  }
}

/// The grey halo under the rider's pin (owner 2026-10-31,
/// plan/rider-pin/SPEC.md): one flat circle, no border, no pulse, slightly
/// see-through. Owner, after the before/after: "Blue must be same in all
/// zoom steps" => like the pin, the halo is the same size on screen at
/// every zoom: [radius] points, whatever the fix's accuracy.
abstract final class RiderAccuracyHalo {
  /// #7797A8 at 35 %: about #CBD6DC over a light map, roads show through.
  static const Color color = Color(0x597797A8);

  /// The halo's radius on screen, in logical points, at every zoom.
  static const double radius = 60;

  /// Metres one logical point covers at [latitude] and [zoom] (Web
  /// Mercator; Google's world is 256 points wide at zoom 0 on every
  /// platform).
  static double metersPerPoint(double latitude, double zoom) {
    final lat = latitude.clamp(-85.0, 85.0) * math.pi / 180;
    return 156543.03392 * math.cos(lat) / math.pow(2, zoom);
  }

  /// The map circle's radius in metres that is [radius] points on screen
  /// at [latitude] and [zoom].
  static double radiusMeters({
    required double latitude,
    required double zoom,
  }) => radius * metersPerPoint(latitude, zoom.isFinite ? zoom : 15);
}

/// Same top-down Movera vehicle marker used by the Driver app.
///
/// Rider nearby-driver pins intentionally render at 65% of Driver's 48 px
/// marker, i.e. 35% smaller as requested.
class MoveraVehicleMarker {
  const MoveraVehicleMarker._();

  static final Map<int, Future<BitmapDescriptor>> _iconCache =
      <int, Future<BitmapDescriptor>>{};

  static Future<BitmapDescriptor> createIcon({double scale = 0.65}) {
    final cacheKey = (scale * 1000).round();
    return _iconCache.putIfAbsent(cacheKey, () => _createIcon(scale, 0));
  }

  /// rider-u61: the web turns the car in this many degrees per bitmap.
  static const int webHeadingStep = 10;
  static final Map<int, BitmapDescriptor> _turned = {};
  static final Set<int> _turning = {};

  /// How a car heading [heading] (degrees from north) is drawn. Off the web
  /// the map turns the bitmap ([Marker.rotation]); google_maps_flutter_web
  /// ignores rotation, so there the car comes already turned (built once
  /// per [webHeadingStep] bucket) and [onReady] runs when a new one is
  /// built. Until then the upright [car] is shown.
  static ({BitmapDescriptor? icon, double rotation}) look(
    BitmapDescriptor? car,
    double heading, {
    VoidCallback? onReady,
    bool web = kIsWeb,
  }) {
    if (!web) return (icon: car, rotation: heading);
    if (!heading.isFinite) return (icon: car, rotation: 0);
    final buckets = 360 ~/ webHeadingStep;
    final bucket = ((heading % 360) / webHeadingStep).round() % buckets;
    final turned = _turned[bucket];
    if (turned != null) return (icon: turned, rotation: 0);
    if (_turning.add(bucket)) {
      _createIcon(0.65, (bucket * webHeadingStep).toDouble())
          .then((icon) {
            _turned[bucket] = icon;
            onReady?.call();
          })
          .whenComplete(() => _turning.remove(bucket));
    }
    return (icon: car, rotation: 0);
  }

  static Future<BitmapDescriptor> _createIcon(
    double scale,
    double heading,
  ) async {
    const designSize = 96.0;
    final outputSize = 48.0 * scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(markerPixelRatio, markerPixelRatio);
    if (heading != 0) {
      final centre = outputSize / 2;
      canvas
        ..translate(centre, centre)
        ..rotate(heading * math.pi / 180)
        ..translate(-centre, -centre);
    }
    canvas.scale(outputSize / designSize);

    final shadowPaint = Paint()
      ..color = const Color(0x26000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawOval(const Rect.fromLTWH(27, 68, 42, 10), shadowPaint);

    final bodyRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(31, 13, 34, 66),
      const Radius.circular(14),
    );
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF1F4F2), Color(0xFFC9D0CD)],
        stops: [0.0, 0.55, 1.0],
      ).createShader(bodyRect.outerRect);
    canvas.drawRRect(bodyRect, bodyPaint);

    canvas.drawRRect(
      bodyRect,
      Paint()
        ..color = const Color(0xFF19865C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(35, 23, 26, 18),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xFF34464E),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(36, 51, 24, 14),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF536168),
    );

    final highlight = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(35, 20), const Offset(35, 61), highlight);

    final wheelPaint = Paint()..color = const Color(0xFF222B2F);
    for (final rect in const [
      Rect.fromLTWH(27, 28, 5, 13),
      Rect.fromLTWH(64, 28, 5, 13),
      Rect.fromLTWH(27, 53, 5, 13),
      Rect.fromLTWH(64, 53, 5, 13),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        wheelPaint,
      );
    }

    canvas.drawCircle(
      const Offset(48, 10),
      3.2,
      Paint()..color = const Color(0xFF19865C),
    );

    final image = await recorder.endRecording().toImage(
      (outputSize * markerPixelRatio).round(),
      (outputSize * markerPixelRatio).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    }
    // rider-u58: with its size declared, google_maps_flutter_web does not
    // probe the bitmap with a new image load on every marker update.
    return BitmapDescriptor.bytes(
      data.buffer.asUint8List(),
      width: outputSize,
      height: outputSize,
    );
  }
}

/// The green pickup and blue destination pins at the two ends of a route.
class RouteEndpointMarker {
  const RouteEndpointMarker._();

  static final Map<bool, Future<BitmapDescriptor>> _cache =
      <bool, Future<BitmapDescriptor>>{};

  /// A round pin for the pickup, a square-dot pin for the destination.
  static Future<BitmapDescriptor> createIcon({required bool pickup}) {
    return _cache.putIfAbsent(pickup, () async {
      const size = 30.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..scale(markerPixelRatio, markerPixelRatio);
      final color = pickup
          ? RiderRouteStyle.pickup
          : RiderRouteStyle.destination;
      const center = Offset(size / 2, size / 2);
      canvas.drawCircle(
        center,
        size / 2,
        Paint()..color = color.withValues(alpha: 0.18),
      );
      canvas.drawCircle(center, 10, Paint()..color = Colors.white);
      if (pickup) {
        canvas.drawCircle(center, 7, Paint()..color = color);
        canvas.drawCircle(center, 2.6, Paint()..color = Colors.white);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: 13, height: 13),
            const Radius.circular(3),
          ),
          Paint()..color = color,
        );
        canvas.drawRect(
          Rect.fromCenter(center: center, width: 4.4, height: 4.4),
          Paint()..color = Colors.white,
        );
      }
      final image = await recorder.endRecording().toImage(
        (size * markerPixelRatio).toInt(),
        (size * markerPixelRatio).toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) {
        return BitmapDescriptor.defaultMarkerWithHue(
          pickup ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueAzure,
        );
      }
      return BitmapDescriptor.bytes(
        data.buffer.asUint8List(),
        width: size,
        height: size,
      );
    });
  }
}

/// Route pins that carry a time: a green "6 min" bubble over the pickup and
/// a blue "Arrive by 23:48" pill over the destination.
class RouteTimeMarker {
  const RouteTimeMarker._();

  static final Map<String, Future<BitmapDescriptor>> _cache =
      <String, Future<BitmapDescriptor>>{};

  /// Where the pin's point sits in the image (bottom centre), for `anchor`.
  static const Offset anchor = Offset(0.5, 0.94);

  static Future<BitmapDescriptor> createIcon({
    required bool pickup,
    required String label,
  }) {
    return _cache.putIfAbsent('$pickup|$label', () async {
      const scale = 3.0;
      final color = pickup
          ? RiderRouteStyle.pickup
          : RiderRouteStyle.destination;
      final lines = label.split('\n');
      final painters = [
        for (var i = 0; i < lines.length; i++)
          TextPainter(
            text: TextSpan(
              text: lines[i],
              style: TextStyle(
                color: Colors.white,
                fontSize: (pickup && i == 0 ? 17 : 12.5) * scale,
                fontWeight: pickup && i > 0 ? FontWeight.w500 : FontWeight.w700,
                height: 1.05,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(),
      ];
      final textW = painters.fold<double>(
        0,
        (w, p) => w > p.width ? w : p.width,
      );
      final textH = painters.fold<double>(0, (h, p) => h + p.height);
      final bubbleW = pickup
          ? (textH + 18 * scale).clamp(textW + 14 * scale, double.infinity)
          : textW + 26 * scale;
      final bubbleH = pickup ? bubbleW : textH + 16 * scale;
      const stem = 12.0 * scale;
      const dot = 7.0 * scale;
      final width = bubbleW + 8 * scale;
      final height = bubbleH + stem + dot * 2 + 4 * scale;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final cx = width / 2;
      final shadow = Paint()
        ..color = color.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      final bubble = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - bubbleW / 2, 2 * scale, bubbleW, bubbleH),
        Radius.circular(bubbleH / 2),
      );
      canvas.drawRRect(bubble.shift(const Offset(0, 3 * scale)), shadow);
      canvas.drawRRect(bubble, Paint()..color = color);
      var y = 2 * scale + (bubbleH - textH) / 2;
      for (final p in painters) {
        p.paint(canvas, Offset(cx - p.width / 2, y));
        y += p.height;
      }
      final stemTop = 2 * scale + bubbleH;
      canvas.drawRect(
        Rect.fromLTWH(cx - 1.5 * scale, stemTop, 3 * scale, stem),
        Paint()..color = color,
      );
      final dotCenter = Offset(cx, stemTop + stem + dot);
      if (pickup) {
        canvas.drawCircle(dotCenter, dot, Paint()..color = color);
        canvas.drawCircle(dotCenter, dot * 0.5, Paint()..color = Colors.white);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: dotCenter,
            width: dot * 1.8,
            height: dot * 1.8,
          ),
          Paint()..color = color,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: dotCenter,
            width: dot * 0.8,
            height: dot * 0.8,
          ),
          Paint()..color = Colors.white,
        );
      }
      final image = await recorder.endRecording().toImage(
        width.ceil(),
        height.ceil(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return RouteEndpointMarker.createIcon(pickup: pickup);
      return BitmapDescriptor.bytes(
        data.buffer.asUint8List(),
        imagePixelRatio: scale,
      );
    });
  }
}

/// Owner round 2: the free cars around the pickup, drawn with the same white
/// car as the ride list. The picture faces right; a car heading west uses the
/// mirrored one, and each is tilted a little toward its heading.
///
/// Owner round 3: the pictures are asset files, not drawn bytes. On the web
/// every marker update turned drawn bytes into a new image URL, so gliding
/// cars made the pins reload (broken boxes) and the page's memory grow.
class NearbyCarMarker {
  const NearbyCarMarker._();

  static const String rightAsset = 'assets/images/rides/car_map_right.png';
  static const String leftAsset = 'assets/images/rides/car_map_left.png';

  /// The picture's size on the map (the files are 114 x 62 px, about 3x).
  static const double width = 38;
  static const double height = 38 * 62 / 114;
  static const double maxTilt = 25;

  static Future<({BitmapDescriptor right, BitmapDescriptor left})>? _icons;

  static Future<({BitmapDescriptor right, BitmapDescriptor left})> icons() {
    return _icons ??= () async {
      const config = ImageConfiguration(size: Size(width, height));
      final right = await BitmapDescriptor.asset(
        config,
        rightAsset,
        width: width,
        height: height,
      );
      final left = await BitmapDescriptor.asset(
        config,
        leftAsset,
        width: width,
        height: height,
      );
      return (right: right, left: left);
    }();
  }

  /// Which picture a [heading] uses (null: facing right), and how much to
  /// turn it: the right-facing car is heading 90 (east), the mirrored one
  /// 270 (west); the turn toward the real heading stays within [maxTilt].
  static ({bool mirrored, double rotation}) pose(double? heading) {
    if (heading == null || !heading.isFinite) {
      return (mirrored: false, rotation: 0);
    }
    final h = heading % 360;
    final mirrored = h >= 180;
    final tilt = (h - (mirrored ? 270 : 90))
        .clamp(-maxTilt, maxTilt)
        .toDouble();
    return (mirrored: mirrored, rotation: tilt);
  }
}
