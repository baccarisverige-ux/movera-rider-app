import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The small panel animations (search radar, driver on the way, on trip).
abstract final class SlotMotion {
  /// Off in widget tests (test/flutter_test_config.dart) so `pumpAndSettle`
  /// still settles; the animations' own tests turn it on.
  static bool enabled = true;

  /// True when the slot should move: motion on and "reduce motion" off.
  static bool moves(BuildContext context) =>
      enabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
}

/// One 240 x 96 picture slot: a looping painter on a shared clock, the
/// edges faded into the white panel, the map's small car picture loaded
/// once. Still when [SlotMotion.moves] is false.
class SlotScene extends StatefulWidget {
  const SlotScene({
    super.key,
    required this.painter,
    required this.fadeStops,
    this.fullWidth = false,
  });

  static const double width = 240;
  static const double height = 96;
  static const String carAsset = 'assets/images/rides/car_map_left.png';

  /// Builds the frame for [seconds] since start (the car may still load).
  final CustomPainter Function(double seconds, ui.Image? car) painter;

  /// Owner 2026-11-23 (approved radar-longer): fill the whole card width and
  /// fade only at the top and bottom (no left/right fade).
  final bool fullWidth;

  /// Where the soft fade to the edges starts and ends (0..1 of the ellipse).
  final List<double> fadeStops;

  @override
  State<SlotScene> createState() => _SlotSceneState();
}

class _SlotSceneState extends State<SlotScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3600),
  );
  ui.Image? _car;

  @override
  void initState() {
    super.initState();
    _loadCar();
  }

  Future<void> _loadCar() async {
    try {
      final data = await rootBundle.load(SlotScene.carAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _car = frame.image);
    } catch (_) {
      // No picture: the rest of the slot still shows.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!SlotMotion.moves(context)) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _car?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget scene(double width) => ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: SlotScene.height,
        // Clip: the radar sweep is larger than the slot.
        child: ClipRect(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => widget.fullWidth
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0xFF000000),
                      Color(0xFF000000),
                      Color(0x00000000),
                    ],
                    stops: [0, 0.22, 0.7, 1],
                  ).createShader(rect)
                : RadialGradient(
                    colors: const [
                      Color(0xFF000000),
                      Color(0xFF000000),
                      Color(0x00000000),
                    ],
                    stops: [0, ...widget.fadeStops],
                    radius: 0.5 * math.sqrt2,
                    transform: _EllipseTransform(rect.width / rect.height),
                  ).createShader(rect),
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _clock,
                builder: (context, _) => CustomPaint(
                  size: Size(width, SlotScene.height),
                  painter: widget.painter(_clock.value * 3600, _car),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!widget.fullWidth) return scene(SlotScene.width);
    return LayoutBuilder(
      builder: (context, c) => scene(
        c.hasBoundedWidth ? c.maxWidth : SlotScene.width,
      ),
    );
  }
}

/// Stretches a circle on the short side into an ellipse across the box.
class _EllipseTransform extends GradientTransform {
  const _EllipseTransform(this.aspect);
  final double aspect;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final c = bounds.center;
    return Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(aspect, 1, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
  }
}

/// Draws the map's small car picture centred at [at], facing [angle]
/// (radians, the way it drives), [width] wide.
void drawSlotCar(
  Canvas canvas,
  ui.Image img,
  Offset at,
  double angle, {
  double width = 12,
}) {
  final h = width * 62 / 114;
  canvas.save();
  canvas.translate(at.dx, at.dy);
  // The picture faces left.
  canvas.rotate(angle + math.pi);
  canvas.drawImageRect(
    img,
    Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    Rect.fromLTWH(-width / 2, -h / 2, width, h),
    Paint()..filterQuality = FilterQuality.medium,
  );
  canvas.restore();
}
