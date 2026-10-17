import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_demo_page.dart';
import 'package:movera_rider/features/safety/presentation/safety_marks.dart';
import 'package:movera_rider/features/safety/presentation/safety_ui.dart';
import 'package:movera_rider/shared/design_system/adaptive_switch_colors.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

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
    final km = t.offRouteKm == t.offRouteKm.roundToDouble()
        ? t.offRouteKm.toStringAsFixed(0)
        : t.offRouteKm.toStringAsFixed(1);
    final finishKm =
        t.finishFarFromDropoffKm == t.finishFarFromDropoffKm.roundToDouble()
        ? t.finishFarFromDropoffKm.toStringAsFixed(0)
        : t.finishFarFromDropoffKm.toStringAsFixed(1);
    return SafetyScaffold(
      title: 'RideCheck',
      solarBack: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Center(child: SafetyMark(SafetyMarks.rideCheck, size: 96)),
          const SizedBox(height: 16),
          Text(
            'When something on a trip looks wrong, Ride check asks if '
            'everything is OK. You can call 112 from it at any time.',
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
                    'RideCheck alerts',
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
                  onChanged: _ctl.setRideCheck,
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
                  'What RideCheck looks for',
                  style: SafetyUi.text(15, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set by Movera.',
                  style: SafetyUi.text(12.5, color: SafetyUi.muted),
                ),
                const SizedBox(height: 6),
                _TriggerLine(
                  title: 'Finished far from drop-off',
                  body:
                      'Your driver finishes the trip more than $finishKm km '
                      'from your drop-off.',
                  on: t.droppedFarEnabled,
                ),
                _TriggerLine(
                  title: 'Long stop',
                  body:
                      'The car stops for more than ${t.longStopMinutes} min, '
                      'not at a '
                      'planned stop or in traffic.',
                  on: t.longStopEnabled,
                ),
                _TriggerLine(
                  title: 'Off the route',
                  body:
                      'More than $km km off the route, or the trip '
                      '${t.longerThanExpectedPercent}% longer than expected.',
                  on: t.offRouteEnabled,
                ),
                _TriggerLine(
                  title: 'Possible crash',
                  body: 'A very hard stop. The card opens at once.',
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
                  'What happens',
                  style: SafetyUi.text(15, weight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Text(
                  'The card stays until you answer. If you tap an accident, '
                  'someone hurt or feeling unsafe, the Movera safety team is '
                  'alerted with the trip, driver and rider details.',
                  style: SafetyUi.text(13.5, color: SafetyUi.muted, height: 1.45),
                ),
                const SizedBox(height: 10),
                Text(
                  'Movera never calls 112 for you: Call 112 opens your '
                  'phone. Audio you record is saved only on this phone.',
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
                    'Try it (demo)',
                    style: SafetyUi.text(15, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Plays a made-up trip and shows what you would see.',
                    style: SafetyUi.text(12.5, color: SafetyUi.muted),
                  ),
                  const SizedBox(height: 6),
                  _DemoLine(
                    title: 'Driver finished far from drop-off',
                    onTap: () => _playDemo(RideCheckTrigger.droppedFar),
                  ),
                  _DemoLine(
                    title: 'Long stop',
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
              'Play',
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
            on ? 'On' : 'Off',
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
