import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_bottom_nav_item.dart';
import 'package:movera_rider/shared/design_system/motion/movera_motion.dart';

/// One entry of [LiquidGlassNavRow].
class LiquidGlassNavEntry {
  const LiquidGlassNavEntry({
    required this.iconAsset,
    required this.label,
    required this.onTap,
  });

  final String iconAsset;
  final String label;
  final VoidCallback onTap;
}

/// Home's bottom tabs with a "liquid glass" selection: a soft capsule rests
/// under the selected tab; on a tap or a drag a small clear glass lens lifts,
/// slides to the new tab (stretching with its speed and magnifying the icons
/// it passes over), then springs back into the capsule.
///
/// The lens stays close to the icon size: a little wider than the icon and
/// label, never the whole bar. It plays both when the sheet is down (floating
/// bar, [floatingFraction] 1) and up (docked bar, 0). With reduce motion on,
/// the selection simply moves and the tab opens at once.
///
/// Every tab except Home opens a page over Home, so the tapped tab only shows
/// as selected while its page opens; when Home is shown again the lens glides
/// back to [selectedIndex].
class LiquidGlassNavRow extends StatefulWidget {
  const LiquidGlassNavRow({
    super.key,
    required this.entries,
    this.selectedIndex = 0,
    this.floatingFraction = 0,
    this.hitSlop = 0,
    this.itemHeight = 52,
  });

  final List<LiquidGlassNavEntry> entries;
  final int selectedIndex;

  /// 1 = sheet down (floating pill bar), 0 = sheet up (docked bar).
  final double floatingFraction;
  final double hitSlop;
  final double itemHeight;

  /// How long the tapped tab's lens travels before its page opens.
  static const Duration openDelay = Duration(milliseconds: 320);

  /// How long after a tab runs Home is checked to still be showing.
  static const Duration coverCheck = Duration(milliseconds: 700);

  @override
  State<LiquidGlassNavRow> createState() => LiquidGlassNavRowState();
}

@visibleForTesting
class LiquidGlassNavRowState extends State<LiquidGlassNavRow>
    with SingleTickerProviderStateMixin {
  // Slightly bouncy, like the system tab bar: settles in about half a second.
  static const SpringDescription _spring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 27,
  );

  /// Position of the selection, in tab slots (0 = first tab).
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  )..addListener(_tick);

  int? _pending;
  Timer? _openTimer;
  Timer? _coverTimer;
  bool _dragging = false;
  bool _wasActive = true;
  double _slotWidth = 1;

  @visibleForTesting
  double get position => _position.value;

  /// 0 = resting capsule, 1 = glass lens fully lifted. The lens is up while
  /// dragging, and while the spring travels it fades with the distance left
  /// and the speed, so it melts back into the capsule as the spring settles.
  @visibleForTesting
  double get lift {
    if (_dragging) return 1;
    if (!_position.isAnimating) return 0;
    final distance = (_position.value - _target).abs();
    return (distance * 3 + _position.velocity.abs() / 4).clamp(0.0, 1.0);
  }

  bool get _reduced => MoveraMotion.reduced(context);

  void _tick() {
    if (mounted) setState(() {});
  }

  double get _target => (_pending ?? widget.selectedIndex).toDouble();

  void _springTo(int index, {double velocity = 0}) {
    if (_reduced) {
      _position.value = index.toDouble();
      return;
    }
    _position.animateWith(
      SpringSimulation(_spring, _position.value, index.toDouble(), velocity),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Home's route is covered while a tab page is open (tickers off). When it
    // shows again, glide back from the tab that was opened to the selection.
    final active = TickerMode.valuesOf(context).enabled;
    if (active && !_wasActive && _pending != null) {
      _pending = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _springTo(widget.selectedIndex);
      });
    }
    _wasActive = active;
  }

  @override
  void didUpdateWidget(LiquidGlassNavRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && _pending == null) {
      _springTo(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _openTimer?.cancel();
    _coverTimer?.cancel();
    _position.dispose();
    super.dispose();
  }

  void _select(int index, {double velocity = 0}) {
    final entry = widget.entries[index];
    if (index == widget.selectedIndex) {
      _pending = null;
      _springTo(index, velocity: velocity);
      entry.onTap();
      return;
    }
    HapticFeedback.selectionClick();
    _pending = index;
    _springTo(index, velocity: velocity);
    if (_reduced) {
      entry.onTap();
      _returnIfNotCovered(index);
      return;
    }
    _openTimer?.cancel();
    _openTimer = Timer(LiquidGlassNavRow.openDelay, () {
      if (!mounted || _pending != index) return;
      entry.onTap();
      _returnIfNotCovered(index);
    });
  }

  /// A tab that opens nothing over Home (a notice, or a flow that is off)
  /// must not stay selected: once the page would have covered Home, glide
  /// back to [LiquidGlassNavRow.selectedIndex] if Home is still showing.
  void _returnIfNotCovered(int index) {
    _coverTimer?.cancel();
    _coverTimer = Timer(LiquidGlassNavRow.coverCheck, () {
      if (!mounted || _pending != index) return;
      if (!TickerMode.valuesOf(context).enabled) return;
      _pending = null;
      _springTo(widget.selectedIndex);
    });
  }

  double _slotAt(double dx) =>
      (dx / _slotWidth - 0.5).clamp(0, widget.entries.length - 1).toDouble();

  void _dragStart(DragStartDetails details) {
    if (_reduced) return;
    _position.stop();
    _dragging = true;
    _position.value = _slotAt(details.localPosition.dx);
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    _position.value = _slotAt(details.localPosition.dx);
  }

  void _dragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final velocity = details.velocity.pixelsPerSecond.dx / _slotWidth;
    final index = _position.value.round().clamp(0, widget.entries.length - 1);
    _select(index, velocity: velocity);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.entries.length;
    final floating = widget.floatingFraction.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        _slotWidth = constraints.maxWidth / count;
        final pos = _position.value;
        final velocity = _position.isAnimating ? _position.velocity : 0.0;
        // Stretch along the motion, squash across it (jelly), capped.
        final stretch = (velocity.abs() / 8).clamp(0.0, 0.22);
        final lift = this.lift;

        // Resting capsule: the selected tab's grey pill (sheet down only).
        final capsuleWidth = _slotWidth - 5;
        // Lens: only a little bigger than the icon and label.
        final lensWidth = math.min(_slotWidth * 0.86, 68.0);
        final lensHeight = widget.itemHeight + 4;
        final centre = (pos + 0.5) * _slotWidth;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _dragStart,
          onHorizontalDragUpdate: _dragUpdate,
          onHorizontalDragEnd: _dragEnd,
          // The glass is the press feedback: no grey ink splash under it.
          child: Theme(
            data: Theme.of(context).copyWith(
              splashFactory: NoSplash.splashFactory,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: centre - capsuleWidth / 2,
                  width: capsuleWidth,
                  top: widget.hitSlop,
                  height: widget.itemHeight,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (floating * (1 - lift)).clamp(0.0, 1.0),
                      child: DecoratedBox(
                        key: const ValueKey('liquid-glass-capsule'),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F2),
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < count; i++)
                      Expanded(
                        child: Transform.scale(
                          // The lens magnifies what it passes over.
                          scale:
                              1 +
                              0.14 * lift * math.max(0, 1 - (pos - i).abs()),
                          child: PremiumBottomNavItem(
                            iconAsset: widget.entries[i].iconAsset,
                            label: widget.entries[i].label,
                            active: (pos - i).abs() < 0.5,
                            floatingFraction: widget.floatingFraction,
                            hitSlop: widget.hitSlop,
                            drawActiveBackground: false,
                            onTap: () => _select(i),
                          ),
                        ),
                      ),
                  ],
                ),
                if (lift > 0.01)
                  Positioned(
                    left: centre - lensWidth / 2,
                    width: lensWidth,
                    top: widget.hitSlop - 2,
                    height: lensHeight,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: lift,
                        child: Transform.scale(
                          scaleX: (1 + stretch) * (0.92 + 0.08 * lift),
                          scaleY: (1 - stretch * 0.5) * (0.92 + 0.08 * lift),
                          child: const _GlassLens(
                            key: ValueKey('liquid-glass-lens'),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The clear glass bubble: a light blur, a bright rim, a faint rainbow edge
/// and a soft shadow, drawn over the tabs.
class _GlassLens extends StatelessWidget {
  const _GlassLens({super.key});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(28);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 0.8, sigmaY: 0.8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.70),
                  const Color(0xFFE8ECEF).withValues(alpha: 0.45),
                  const Color(0xFFDDE3E7).withValues(alpha: 0.55),
                ],
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 1,
                ),
              ),
              child: CustomPaint(painter: _RainbowRim(radius: 28)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RainbowRim extends CustomPainter {
  const _RainbowRim({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = SweepGradient(
        colors: [
          const Color(0x00FFFFFF),
          const Color(0x5500C2FF),
          const Color(0x55FF4FD8),
          const Color(0x55FFD24F),
          const Color(0x00FFFFFF),
          const Color(0x4400C2FF),
          const Color(0x00FFFFFF),
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1.2), Radius.circular(radius - 1)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RainbowRim oldDelegate) => oldDelegate.radius != radius;
}
