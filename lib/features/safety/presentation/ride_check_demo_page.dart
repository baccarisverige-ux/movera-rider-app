import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_card.dart';
import 'package:movera_rider/features/safety/presentation/safety_ui.dart';

/// Demo builds only (Safety › RideCheck › Try it): plays a made-up trip
/// that hits [trigger] and shows the Ride check card the rider would see.
class RideCheckDemoPage extends StatefulWidget {
  const RideCheckDemoPage({super.key, required this.trigger, this.controller});

  final RideCheckTrigger trigger;
  final RideCheckController? controller;

  /// The demo trip's ride id, one per scenario.
  static String rideIdFor(RideCheckTrigger trigger) =>
      'demo-ridecheck-${trigger.wire}';

  @override
  State<RideCheckDemoPage> createState() => _RideCheckDemoPageState();
}

class _RideCheckDemoPageState extends State<RideCheckDemoPage> {
  late final RideCheckController _ctl =
      widget.controller ?? RideCheckController.shared;
  late final String _rideId = RideCheckDemoPage.rideIdFor(widget.trigger);
  RideCheckOpenResult? _result;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onChange);
    unawaited(_play());
  }

  @override
  void dispose() {
    _ctl.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _play() async {
    final result = await _ctl.playDemo(widget.trigger, rideId: _rideId);
    if (mounted) setState(() => _result = result);
  }

  String get _title => switch (widget.trigger) {
    RideCheckTrigger.droppedFar => 'Driver finished far from drop-off',
    RideCheckTrigger.longStop => 'Long stop',
    _ => widget.trigger.label,
  };

  String _scenario(RideCheckTriggerSettings t) => switch (widget.trigger) {
    RideCheckTrigger.droppedFar =>
      'Your driver tapped Finish more than '
          '${_km(t.finishFarFromDropoffKm)} km from '
          '${RideCheckController.demoPlan.destinationLabel}. '
          'RideCheck opens right after the trip ends.',
    RideCheckTrigger.longStop =>
      'Mid-trip, the car stood still for more than ${t.longStopMinutes} min, '
          'not at a planned stop or in traffic. '
          'RideCheck opens right away, during the trip.',
    _ => 'RideCheck opens on the trip.',
  };

  String? get _status {
    if (_ctl.sessionFor(_rideId) != null) return null;
    return switch (_result) {
      null => 'Starting the demo trip…',
      RideCheckOpenResult.shown => 'Answered. Play it again any time.',
      RideCheckOpenResult.riderOff =>
        'RideCheck alerts are off. Turn them on to see the demo.',
      RideCheckOpenResult.triggerOff => 'Movera has turned this check off.',
      RideCheckOpenResult.busy => 'Another RideCheck is open. Answer it first.',
      _ => "The demo didn't open RideCheck.",
    };
  }

  @override
  Widget build(BuildContext context) {
    // Admin's numbers, read the same way live trips read them.
    final t = _ctl.policy.triggers;
    final status = _status;
    return Stack(
      fit: StackFit.expand,
      children: [
        SafetyScaffold(
          title: 'RideCheck demo',
          solarBack: true,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Container(
                decoration: SafetyUi.cardDecoration(),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: SafetyUi.text(15, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _scenario(t),
                      style: SafetyUi.text(
                        13.5,
                        color: SafetyUi.muted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              if (status != null) ...[
                const SizedBox(height: 18),
                Text(
                  status,
                  textAlign: TextAlign.center,
                  style: SafetyUi.text(13.5, color: SafetyUi.muted),
                ),
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      key: const ValueKey<String>('ride-check-demo-again'),
                      onPressed: () {
                        setState(() => _result = null);
                        unawaited(_play());
                      },
                      child: Text(
                        'Play again',
                        style: SafetyUi.text(
                          14,
                          weight: FontWeight.w600,
                          color: SafetyUi.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        Positioned.fill(
          child: RideCheckLayer(rideId: _rideId, controller: _ctl),
        ),
      ],
    );
  }
}

String _km(double km) =>
    km == km.roundToDouble() ? km.toStringAsFixed(0) : km.toStringAsFixed(1);
