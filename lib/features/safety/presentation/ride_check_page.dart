import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_demo_page.dart';
import 'package:movera_rider/features/safety/presentation/safety_marks.dart';
import 'package:movera_rider/features/safety/presentation/safety_ui.dart';
import 'package:movera_rider/shared/design_system/adaptive_switch_colors.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/l10n/l10n.dart';

class RideCheckPage extends StatefulWidget {
  const RideCheckPage({super.key, required this.controller});
  final SafetyController controller;

  @override
  State<RideCheckPage> createState() => _RideCheckPageState();
}

class _RideCheckPageState extends State<RideCheckPage> {
  SafetyController get _ctl => widget.controller;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onChange);
  }

  @override
  void dispose() {
    _ctl.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final policy = _ctl.rideCheckPolicy;
    final on = policy.enabled;
    final t = policy.triggers;
    // rider-u209: the app language's decimal mark ("2,5" in fr and sv).
    String kmLabel(double km) =>
        L10n.formatDecimal(km, digits: km == km.roundToDouble() ? 0 : 1);
    final km = kmLabel(t.offRouteKm);
    final finishKm = kmLabel(t.finishFarFromDropoffKm);
    return SafetyScaffold(
      title: context.l10n.rideCheckTitle,
      solarBack: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Center(child: SafetyMark(SafetyMarks.rideCheck, size: 96)),
          const SizedBox(height: 16),
          Text(
            context.l10n.rcPageIntro,
            textAlign: TextAlign.center,
            style: SafetyUi.text(15, color: SafetyUi.muted, height: 1.45),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: SafetyUi.cardDecoration(),
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.rcAlertsToggle,
                    style: SafetyUi.text(15.5, weight: FontWeight.w500),
                  ),
                ),
                Switch.adaptive(
                  value: on,
                  activeThumbColor: adaptiveSwitchThumbColor(
                    context,
                    SafetyUi.accent,
                  ),
                  activeTrackColor: adaptiveSwitchTrackColor(
                    context,
                    SafetyUi.accent,
                  ),
                  onChanged: (value) => runSafetyChange(
                    context,
                    _ctl,
                    () => _ctl.setRideCheck(value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: SafetyUi.cardDecoration(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.rcLooksFor,
                  style: SafetyUi.text(15, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.rcSetByMovera,
                  style: SafetyUi.text(12.5, color: SafetyUi.muted),
                ),
                const SizedBox(height: 6),
                _TriggerLine(
                  title: context.l10n.rcFinishedFarTitle,
                  body: context.l10n.rcFinishedFarBody(finishKm),
                  on: t.droppedFarEnabled,
                ),
                _TriggerLine(
                  title: context.l10n.rcTriggerLongStop,
                  body: context.l10n.rcLongStopBody('${t.longStopMinutes}'),
                  on: t.longStopEnabled,
                ),
                _TriggerLine(
                  title: context.l10n.rcTriggerOffRoute,
                  body: context.l10n.rcOffRouteBody(
                    km,
                    '${t.longerThanExpectedPercent}',
                  ),
                  on: t.offRouteEnabled,
                ),
                _TriggerLine(
                  title: context.l10n.rcTriggerPossibleCrash,
                  body: context.l10n.rcCrashBody,
                  on: t.possibleCrashEnabled,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: SafetyUi.cardDecoration(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.rcWhatHappens,
                  style: SafetyUi.text(15, weight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.rcWhatHappensBody1,
                  style: SafetyUi.text(13.5, color: SafetyUi.muted, height: 1.45),
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.rcWhatHappensBody2,
                  style: SafetyUi.text(13.5, color: SafetyUi.muted, height: 1.45),
                ),
              ],
            ),
          ),
          if (_demo) ...[
            const SizedBox(height: 18),
            Container(
              key: const ValueKey<String>('ride-check-demo'),
              decoration: SafetyUi.cardDecoration(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.rcTryDemo,
                    style: SafetyUi.text(15, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.rcTryDemoBody,
                    style: SafetyUi.text(12.5, color: SafetyUi.muted),
                  ),
                  const SizedBox(height: 6),
                  _DemoLine(
                    title: context.l10n.rcDemoDroppedFar,
                    onTap: () => _playDemo(RideCheckTrigger.droppedFar),
                  ),
                  _DemoLine(
                    title: context.l10n.rcTriggerLongStop,
                    onTap: () => _playDemo(RideCheckTrigger.longStop),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Demo builds only, like the wallet's demo top-up.
  bool get _demo {
    try {
      return AppScope.instance.environment.allowsMockTransport;
    } catch (_) {
      return false;
    }
  }

  void _playDemo(RideCheckTrigger trigger) {
    Navigator.push(
      context,
      RightToLeftTransition(RideCheckDemoPage(trigger: trigger)),
    );
  }
}

class _DemoLine extends StatelessWidget {
  const _DemoLine({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: SafetyUi.text(14, weight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              context.l10n.rcPlay,
              style: SafetyUi.text(
                13,
                weight: FontWeight.w600,
                color: SafetyUi.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TriggerLine extends StatelessWidget {
  const _TriggerLine({required this.title, required this.body, required this.on});

  final String title;
  final String body;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SafetyUi.text(14, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: SafetyUi.text(13, color: SafetyUi.muted, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            on ? context.l10n.on : context.l10n.off,
            style: SafetyUi.text(
              13,
              weight: FontWeight.w600,
              color: on ? SafetyUi.accent : SafetyUi.muted,
            ),
          ),
        ],
      ),
    );
  }
}
