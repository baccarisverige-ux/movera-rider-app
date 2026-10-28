import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/domain/ride_check_questions.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/features/safety/presentation/safety_audio_option.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Ride check colours, from the approved mockup (rc3).
abstract final class RideCheckColors {
  static const glass = Color(0xBD080A0C);
  static const contour = Color(0xE6FFFFFF);
  static const red = Color(0xFFE5372A);
  static const dot = Color(0xFFFF4D3D);
  static const redTint = Color(0x38E5372A);
  static const redIcon = Color(0xFFFF7A6E);
  static const ink = Color(0xFF111518);
  static const fill = Color(0x14FFFFFF);
  static const fillStrong = Color(0x1AFFFFFF);
  static const line = Color(0x1FFFFFFF);
}

/// Solar icon for each row.
String rideCheckRowIcon(RideCheckRowId id) => switch (id) {
  RideCheckRowId.accident => AppAssets.solarDangerTriangle,
  RideCheckRowId.hurt => AppAssets.solarHeartPulse,
  RideCheckRowId.unsafe => AppAssets.solarShieldUser,
  RideCheckRowId.wrongPlace => AppAssets.solarMapPointRemove,
  RideCheckRowId.askedToLeave => AppAssets.solarLogout3,
  RideCheckRowId.carBrokeDown => AppAssets.solarWheel,
  RideCheckRowId.askedStop => AppAssets.solarMapPointWave,
  RideCheckRowId.askedRoute => AppAssets.solarRouting3,
  RideCheckRowId.somethingElse => AppAssets.solarChatRoundDots,
};

String _reasonIcon(RideCheckTrigger trigger) => switch (trigger) {
  RideCheckTrigger.droppedFar => AppAssets.solarMapPoint,
  RideCheckTrigger.longStop => AppAssets.solarClock,
  RideCheckTrigger.offRoute => AppAssets.solarRouting3,
  RideCheckTrigger.possibleCrash => AppAssets.solarDanger,
};

/// The reason line, as plain text and its bold part.
({String before, String bold, String after}) rideCheckReasonText(
  RideCheckTrigger trigger,
  RideCheckReason reason,
) {
  switch (trigger) {
    case RideCheckTrigger.droppedFar:
      final distance = formatRideCheckDistance(reason.distanceMeters ?? 0);
      final place = reason.destinationLabel;
      return (
        before: L10n.current.rcReasonEndedBefore,
        bold: distance,
        after: place == null
            ? L10n.current.rcReasonFromDropoff
            : L10n.current.rcReasonFromPlace(place),
      );
    case RideCheckTrigger.longStop:
      final place = reason.place;
      return (
        before: L10n.current.rcReasonStoppedBefore,
        bold: L10n.current.durMin(
          '${reason.stoppedMinutes ?? RideCheckTriggerSettings.defaultLongStopMinutes}',
        ),
        after: place == null ? '' : ' · $place',
      );
    case RideCheckTrigger.offRoute:
      final percent = reason.longerPercent;
      if (percent != null && reason.distanceMeters == null) {
        return (
          before: L10n.current.rcReasonLongerBefore,
          bold: '$percent%',
          after: L10n.current.rcReasonLongerAfter,
        );
      }
      return (
        before: L10n.current.rcReasonOffRouteBefore,
        bold: formatRideCheckDistance(reason.distanceMeters ?? 2000),
        after: L10n.current.rcReasonOffRouteAfter,
      );
    case RideCheckTrigger.possibleCrash:
      return (
        before: L10n.current.rcReasonCrashBefore,
        bold: L10n.current.rcReasonCrashBold,
        after: '',
      );
  }
}

TextStyle _text(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
  double? letterSpacing,
  double? height,
}) {
  return GoogleFonts.poppins(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}

/// Shows the Ride check card for [rideId] over the screen it is placed in
/// (the in-trip screen and the ride summary). While the card is up nothing
/// behind it can be tapped, back does nothing and there is no close or
/// swipe-away: only an answer closes it (RC5).
class RideCheckLayer extends StatefulWidget {
  const RideCheckLayer({super.key, required this.rideId, this.controller});

  final String? rideId;
  final RideCheckController? controller;

  @override
  State<RideCheckLayer> createState() => _RideCheckLayerState();
}

class _RideCheckLayerState extends State<RideCheckLayer>
    with SingleTickerProviderStateMixin {
  late final RideCheckController _ctl =
      widget.controller ?? RideCheckController.shared;
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  RideCheckSession? _shown;
  String? _shownId;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onChange);
    final id = widget.rideId?.trim();
    if (id != null && id.isNotEmpty) unawaited(_ctl.resume(id));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant RideCheckLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.rideId?.trim();
    if (id != oldWidget.rideId?.trim() && id != null && id.isNotEmpty) {
      unawaited(_ctl.resume(id));
    }
    _sync();
  }

  @override
  void dispose() {
    _ctl.removeListener(_onChange);
    _grow.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(_sync);
  }

  void _sync() {
    final session = _ctl.sessionFor(widget.rideId);
    if (session != null) {
      if (session.checkId != _shownId) {
        _shownId = session.checkId;
        _closing = false;
        final instant =
            session.trigger == RideCheckTrigger.possibleCrash ||
            (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
        if (instant) {
          _grow.value = 1;
        } else {
          _grow.forward(from: 0);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => _comeToFront());
      }
      _shown = session;
      return;
    }
    if (_shown == null || _closing) return;
    // Answered: the card folds back into the island and goes.
    _closing = true;
    final closing = _shown;
    _grow
        .animateBack(0, duration: const Duration(milliseconds: 280))
        .whenComplete(() {
          if (!mounted || !identical(_shown, closing)) return;
          if (_ctl.sessionFor(widget.rideId) != null) return;
          setState(() {
            _shown = null;
            _shownId = null;
            _closing = false;
          });
        });
  }

  /// A sheet or page opened on top of this screen would hide the card:
  /// close it so the rider sees the card.
  void _comeToFront() {
    if (!mounted || _ctl.sessionFor(widget.rideId) == null) return;
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent || !route.isActive) return;
    _ctl.takeOverRecording();
    Navigator.of(context).popUntil((other) => other == route);
  }

  @override
  Widget build(BuildContext context) {
    final session = _ctl.sessionFor(widget.rideId);
    final shown = session ?? _shown;
    if (shown == null) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final answering = session != null;
    return PopScope(
      canPop: !answering,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (answering)
            PointerInterceptor(
              child: const ModalBarrier(
                key: ValueKey<String>('ride-check-barrier'),
                dismissible: false,
                color: Color(0x00000000),
              ),
            ),
          Positioned(
            top: media.padding.top + 10,
            left: 10,
            right: 10,
            child: PointerInterceptor(
              child: IgnorePointer(
                ignoring: !answering,
                child: _GrowFromIsland(
                  animation: _grow,
                  child: RideCheckCard(
                    session: shown,
                    controller: _ctl,
                    maxHeight:
                        (media.size.height -
                                media.padding.top -
                                media.viewInsets.bottom -
                                media.padding.bottom -
                                20)
                            .clamp(160.0, double.infinity),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The island pulses as a black pill, then grows down and out into the card.
class _GrowFromIsland extends StatelessWidget {
  const _GrowFromIsland({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pill = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.4, curve: Curves.easeOut),
    );
    final grow = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.4, 1, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final g = grow.value;
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            if (g < 1)
              Opacity(
                opacity: (pill.value * (1 - g * 2)).clamp(0.0, 1.0),
                child: const _IslandPill(),
              ),
            if (g > 0)
              Opacity(
                opacity: (g * 1.6).clamp(0.0, 1.0),
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: 0.12 + 0.88 * g,
                    child: Transform.scale(
                      alignment: Alignment.topCenter,
                      scaleX: 0.5 + 0.5 * g,
                      scaleY: 1,
                      child: child,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _IslandPill extends StatelessWidget {
  const _IslandPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.white, spreadRadius: 0.6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _PulseDot(),
          const SizedBox(width: 8),
          Text(
            context.l10n.rcIsEverythingOk,
            style: _text(12.5, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// The dark-glass Ride check card (RC3): black ~74% over a strong blur,
/// 0.5 px white contour, 34 px corners.
class RideCheckCard extends StatelessWidget {
  const RideCheckCard({
    super.key,
    required this.session,
    required this.controller,
    this.maxHeight = double.infinity,
  });

  final RideCheckSession session;
  final RideCheckController controller;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(34);
    return Semantics(
      key: const ValueKey<String>('ride-check-card'),
      container: true,
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: context.l10n.rcRideCheck,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 40,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                constraints: BoxConstraints(maxHeight: maxHeight),
                decoration: BoxDecoration(
                  color: RideCheckColors.glass,
                  borderRadius: radius,
                  border: Border.all(
                    color: RideCheckColors.contour,
                    width: 0.5,
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: session.step == RideCheckStep.main
                        ? _MainStep(session: session, controller: controller)
                        : _FollowUpStep(
                            session: session,
                            controller: controller,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.heading});

  final String? heading;

  @override
  Widget build(BuildContext context) {
    final label = heading == null
        ? context.l10n.rcHeaderCaps
        : context.l10n.rcHeaderCapsWith(heading!.toUpperCase());
    return Row(
      children: [
        const AppIconAsset(
          AppAssets.solarShieldWarning,
          size: 14,
          color: Color(0xA6FFFFFF),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _text(
              11,
              weight: FontWeight.w600,
              color: const Color(0xA6FFFFFF),
              letterSpacing: 1.8,
            ),
          ),
        ),
        const _PulseDot(),
      ],
    );
  }
}

/// The small red dot that pulses while the card waits for an answer.
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _pulse.value = 0.5;
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: RideCheckColors.dot,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: RideCheckColors.dot.withValues(
                  alpha: 0.15 + 0.2 * _pulse.value,
                ),
                spreadRadius: 1.5 + 2.5 * _pulse.value,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainStep extends StatelessWidget {
  const _MainStep({required this.session, required this.controller});

  final RideCheckSession session;
  final RideCheckController controller;

  @override
  Widget build(BuildContext context) {
    final crash = session.trigger == RideCheckTrigger.possibleCrash;
    final reason = rideCheckReasonText(session.trigger, session.reason);
    final happening = session.trigger == RideCheckTrigger.droppedFar
        ? context.l10n.rcTellWhatHappened
        : context.l10n.rcTellWhatsHappening;
    return Column(
      key: const ValueKey<String>('ride-check-main'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(),
        const SizedBox(height: 8),
        Text(
          context.l10n.rcIsEverythingOk,
          style: _text(
            25,
            weight: FontWeight.w700,
            letterSpacing: -0.6,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: RideCheckColors.fill,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              AppIconAsset(
                _reasonIcon(session.trigger),
                size: 18,
                color: const Color(0xCCFFFFFF),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text.rich(
                  key: const ValueKey<String>('ride-check-reason'),
                  TextSpan(
                    style: _text(
                      13.5,
                      color: const Color(0xCCFFFFFF),
                      height: 1.3,
                    ),
                    children: [
                      TextSpan(text: reason.before),
                      TextSpan(
                        text: reason.bold,
                        style: _text(13.5, weight: FontWeight.w600),
                      ),
                      TextSpan(text: reason.after),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (crash) ...[
          _Call112Now(onTap: controller.call112),
          const SizedBox(height: 9),
          _BigButton(
            key: const ValueKey<String>('ride-check-ok'),
            label: context.l10n.rcImOk,
            icon: AppAssets.solarCheckCircle,
            onTap: controller.imOk,
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: _BigButton(
                  key: const ValueKey<String>('ride-check-call-112'),
                  label: context.l10n.rcCall112,
                  icon: AppAssets.solarPhoneCalling,
                  red: true,
                  onTap: controller.call112,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _BigButton(
                  key: const ValueKey<String>('ride-check-ok'),
                  label: context.l10n.rcImOk,
                  icon: AppAssets.solarCheckCircle,
                  onTap: controller.imOk,
                ),
              ),
            ],
          ),
        if (session.called112) ...[
          const SizedBox(height: 10),
          _AlertBanner(session: session, controller: controller),
          if (session.callError != null) ...[
            const SizedBox(height: 6),
            _Note(session.callError!),
          ],
        ],
        if (_showsRecording(session, controller)) ...[
          const SizedBox(height: 10),
          _RecordAudio(session: session, controller: controller),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 2),
          child: Text(
            happening,
            style: _text(
              12,
              weight: FontWeight.w600,
              color: const Color(0x80FFFFFF),
            ),
          ),
        ),
        for (final (index, row) in session.rows.indexed)
          _RowTile(
            row: row,
            last: index == session.rows.length - 1,
            onTap: () => controller.chooseRow(row.id),
          ),
        if (session.called112) ...[
          const SizedBox(height: 12),
          _BigButton(
            key: const ValueKey<String>('ride-check-done'),
            label: context.l10n.done,
            height: 48,
            onTap: controller.done,
          ),
        ],
        _Footer(context.l10n.rcAnswerSaved),
      ],
    );
  }
}

class _FollowUpStep extends StatelessWidget {
  const _FollowUpStep({required this.session, required this.controller});

  final RideCheckSession session;
  final RideCheckController controller;

  @override
  Widget build(BuildContext context) {
    final row = session.row!;
    final followUp = row.followUp;
    final questions = followUp.questions;
    final segments = questions.isEmpty ? 1 : questions.length;
    final on = questions.isEmpty
        ? 1
        : (session.answeredQuestions + 1).clamp(1, segments);
    return Column(
      key: ValueKey<String>('ride-check-follow-up-${row.wire}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(heading: followUp.displayHeading),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
          child: Row(
            children: [
              for (var i = 0; i < segments; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: i < on ? Colors.white : const Color(0x2EFFFFFF),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (followUp.thanksOnly) ...[
          Text(row.displayLabel, style: _question(first: true)),
          const SizedBox(height: 10),
          Text(
            rideCheckThanksLine,
            style: _text(14.5, color: const Color(0xCCFFFFFF), height: 1.4),
          ),
        ],
        for (final (index, question) in questions.indexed) ...[
          if (index > 0) const SizedBox(height: 18),
          Text(question.displayText, style: _question(first: index == 0)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (i, option) in question.options.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _OptionButton(
                    key: ValueKey<String>(
                      'ride-check-option-${question.id}-${option.id.name}',
                    ),
                    label: option.displayLabel,
                    selected: session.choices[question.id] == option.id,
                    onTap: () => controller.choose(question.id, option.id),
                  ),
                ),
              ],
            ],
          ),
          if (index == 0) ...[
            if (session.alertState != RideCheckAlertState.none) ...[
              const SizedBox(height: 12),
              _AlertBanner(session: session, controller: controller),
            ],
            if (session.showsCallNow) ...[
              const SizedBox(height: 14),
              _Call112Now(onTap: controller.call112),
              if (session.callError != null) ...[
                const SizedBox(height: 6),
                _Note(session.callError!),
              ],
            ],
          ],
        ],
        if (questions.isEmpty &&
            session.alertState != RideCheckAlertState.none) ...[
          const SizedBox(height: 12),
          _AlertBanner(session: session, controller: controller),
        ],
        if (followUp.asksForNote) ...[
          Text(context.l10n.rcWhatHappened, style: _question(first: true)),
          const SizedBox(height: 10),
          _NoteField(initial: session.note, onChanged: controller.setNote),
        ],
        if (_showsRecording(session, controller)) ...[
          const SizedBox(height: 14),
          _RecordAudio(session: session, controller: controller),
        ],
        const SizedBox(height: 14),
        _BigButton(
          key: const ValueKey<String>('ride-check-done'),
          label: context.l10n.done,
          height: 48,
          onTap: controller.done,
        ),
        _Footer(context.l10n.rcAnswersSaved),
      ],
    );
  }

  TextStyle _question({required bool first}) => _text(
    first ? 21 : 18,
    weight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.25,
  );
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.red = false,
    this.height = 52,
  });

  final String label;
  final String? icon;
  final bool red;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = red ? Colors.white : RideCheckColors.ink;
    return Semantics(
      button: true,
      label: label,
      // rider-u213: excludeSemantics drops the InkWell's own tap action.
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: red ? RideCheckColors.red : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    AppIconAsset(icon!, size: 19, color: fg),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(16, weight: FontWeight.w700, color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Call112Now extends StatelessWidget {
  const _Call112Now({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.rcCall112NowSemantics,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        key: const ValueKey<String>('ride-check-call-112-now'),
        color: RideCheckColors.red,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: Color(0x2EFFFFFF),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const AppIconAsset(
                    AppAssets.solarPhoneCalling,
                    size: 24,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.rcCall112Now,
                        style: _text(18, weight: FontWeight.w700, height: 1.2),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.rcCall112NowBody,
                        style: _text(
                          12.5,
                          color: const Color(0xEBFFFFFF),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Movera safety team alerted · Trip, driver and rider details were sent."
class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.session, required this.controller});

  final RideCheckSession session;
  final RideCheckController controller;

  @override
  Widget build(BuildContext context) {
    final live =
        controller.reportsToMovera &&
        session.alertState == RideCheckAlertState.sent;
    final (title, body) = switch (session.alertState) {
      _ when live => (context.l10n.rcSent, ''),
      RideCheckAlertState.sent || RideCheckAlertState.none => (
        context.l10n.rcAlertSentTitle,
        context.l10n.rcAlertSentBody,
      ),
      RideCheckAlertState.sending => (
        context.l10n.rcAlertSendingTitle,
        context.l10n.rcAlertSendingBody,
      ),
      RideCheckAlertState.failed => (
        context.l10n.rcAlertFailedTitle,
        context.l10n.rcAlertFailedBody,
      ),
    };
    final banner = Container(
      key: const ValueKey<String>('ride-check-alert-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: RideCheckColors.fillStrong,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const AppIconAsset(
            AppAssets.solarBellBing,
            size: 20,
            color: Colors.white,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: _text(13.5, weight: FontWeight.w600, height: 1.35),
                  ),
                  if (body.isNotEmpty)
                    Text(
                      body,
                      style: _text(
                        12.5,
                        color: const Color(0xCCFFFFFF),
                        height: 1.35,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (session.alertState != RideCheckAlertState.failed) return banner;
    return GestureDetector(onTap: controller.retryAlert, child: banner);
  }
}

/// Owner decision 10: "Record audio" is hidden for now. A recording that
/// is already running (taken over from the Safety Kit) keeps its Stop, and
/// the note about one that just ended stays, so neither is left dangling.
bool _showsRecording(
  RideCheckSession session,
  RideCheckController controller,
) =>
    SafetyAudioOption.enabled ||
    controller.recording ||
    session.recordingNote != null;

class _RecordAudio extends StatefulWidget {
  const _RecordAudio({required this.session, required this.controller});

  final RideCheckSession session;
  final RideCheckController controller;

  @override
  State<_RecordAudio> createState() => _RecordAudioState();
}

class _RecordAudioState extends State<_RecordAudio> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _syncTicker(bool recording) {
    if (recording && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!recording && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = widget.controller.recording;
    _syncTicker(recording);
    final since = widget.controller.recordingSince;
    final elapsed = since == null
        ? Duration.zero
        : DateTime.now().toUtc().difference(since.toUtc());
    final clock =
        '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    final note = widget.session.recordingNote;
    // rider-r5-30 (owner decision 10): with the option hidden, the button
    // is there only to stop a running recording; after Stop just the note
    // stays, never a "Record audio" that would start a new one.
    final showButton = SafetyAudioOption.enabled || recording;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showButton)
          Semantics(
            button: true,
            label: recording
                ? context.l10n.rcStopRecordingSemantics
                : context.l10n.rcRecordAudioSemantics,
            onTap: widget.controller.toggleRecording,
            excludeSemantics: true,
            child: Material(
              key: const ValueKey<String>('ride-check-record'),
              color: RideCheckColors.fill,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: widget.controller.toggleRecording,
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        AppIconAsset(
                          recording
                              ? AppAssets.solarStopCircle
                              : AppAssets.solarMicrophone,
                          size: 18,
                          color: recording
                              ? RideCheckColors.redIcon
                              : Colors.white,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: _text(
                                13.5,
                                color: const Color(0x99FFFFFF),
                                height: 1.3,
                              ),
                              children: [
                                TextSpan(
                                  text: recording
                                      ? context.l10n.rcRecordingClock(clock)
                                      : context.l10n.rcRecordAudio,
                                  style: _text(13.5, weight: FontWeight.w600),
                                ),
                                TextSpan(
                                  text: recording
                                      ? context.l10n.rcTapToStop
                                      : context.l10n.rcSavedOnPhone,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (note != null) ...[
          if (showButton) const SizedBox(height: 6),
          _Note(note),
        ],
      ],
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.last, required this.onTap});

  final RideCheckRow row;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: row.displayLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey<String>('ride-check-row-${row.wire}'),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
          decoration: BoxDecoration(
            border: last
                ? null
                : const Border(
                    bottom: BorderSide(color: RideCheckColors.line, width: 0.5),
                  ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: row.red
                      ? RideCheckColors.redTint
                      : RideCheckColors.fill,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: AppIconAsset(
                  rideCheckRowIcon(row.id),
                  size: 18,
                  color: row.red ? RideCheckColors.redIcon : Colors.white,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  row.displayLabel,
                  style: _text(15, weight: FontWeight.w500, height: 1.3),
                ),
              ),
              const SizedBox(width: 6),
              const AppIconAsset(
                AppAssets.solarAltArrowRight,
                size: 15,
                color: Color(0x59FFFFFF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? Colors.white : RideCheckColors.fill,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    15,
                    weight: FontWeight.w700,
                    color: selected ? RideCheckColors.ink : Colors.white,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteField extends StatefulWidget {
  const _NoteField({required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final TextEditingController _note = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey<String>('ride-check-note'),
      controller: _note,
      onChanged: widget.onChanged,
      maxLength: 280,
      minLines: 2,
      maxLines: 4,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: Colors.white,
      style: _text(14.5, height: 1.35),
      decoration: InputDecoration(
        hintText: context.l10n.rcAFewWords,
        hintStyle: _text(14.5, color: const Color(0x73FFFFFF)),
        counterStyle: _text(11, color: const Color(0x73FFFFFF)),
        filled: true,
        fillColor: RideCheckColors.fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text,
        style: _text(12, color: const Color(0xA6FFFFFF), height: 1.35),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const AppIconAsset(
            AppAssets.solarLockKeyhole,
            size: 13,
            color: Color(0x73FFFFFF),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: _text(11.5, color: const Color(0x73FFFFFF)),
            ),
          ),
        ],
      ),
    );
  }
}
