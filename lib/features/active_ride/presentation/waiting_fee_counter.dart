import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Where the waiting clock is at one instant (owner Q41/Q42).
class WaitingFeeState {
  const WaitingFeeState._({
    required this.freeLeft,
    required this.over,
    required this.fee,
  });

  /// The waiting clock at [now] for a driver waiting since [since], with
  /// [freeWaitMin] free minutes and then [perMin] a minute, counted by the
  /// second as the driver app charges it (rider-r5-1).
  factory WaitingFeeState.at({
    required DateTime since,
    required DateTime now,
    required int freeWaitMin,
    required Money perMin,
    DateTime? freeUntil,
  }) {
    var waited = now.difference(since);
    if (waited.isNegative) waited = Duration.zero;
    final free = freeWait(since, freeWaitMin, freeUntil);
    if (waited < free) {
      return WaitingFeeState._(
        freeLeft: free - waited,
        over: Duration.zero,
        fee: Money(0, perMin.currency),
      );
    }
    final over = waited - free;
    return WaitingFeeState._(
      freeLeft: Duration.zero,
      over: over,
      fee: Money(
        (perMin.amountMinor * over.inSeconds / 60).round(),
        perMin.currency,
      ),
    );
  }

  /// The free wait: up to the projection's `waiting.freeUntil` when the
  /// server says (rider-r4-13), else the zone's [freeWaitMin] minutes.
  static Duration freeWait(
    DateTime since,
    int freeWaitMin,
    DateTime? freeUntil,
  ) {
    if (freeUntil == null) return Duration(minutes: freeWaitMin);
    final free = freeUntil.difference(since);
    return free.isNegative ? Duration.zero : free;
  }

  /// Free waiting still left; zero once the fee runs.
  final Duration freeLeft;

  /// How long past the free wait.
  final Duration over;

  /// The waiting fee so far: [over]'s seconds at the per-minute rate.
  final Money fee;

  bool get charging => freeLeft == Duration.zero;
}

/// "m:ss".
String formatWaitClock(Duration value) {
  final seconds = value.inSeconds;
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}

/// The live waiting clock on the Waiting sheet while the driver is at the
/// pickup: the free wait counting down, then (Q42) the waiting fee counting
/// up at the category's per-minute rate from the zone's config. The fee is
/// a preview; the trip's fare lines show what is charged.
class WaitingFeeCounter extends StatefulWidget {
  const WaitingFeeCounter({
    super.key,
    required this.since,
    required this.freeWaitMin,
    required this.perMin,
    this.freeUntil,
    this.clock,
  });

  /// When the driver's waiting clock started.
  final DateTime since;
  final int freeWaitMin;

  /// The category's waiting fee per minute, in the trip's currency.
  final Money perMin;

  /// When the server ends the free wait (`waiting.freeUntil`), if it says.
  final DateTime? freeUntil;

  /// Test seam for "now".
  final DateTime Function()? clock;

  static const counterKey = ValueKey('waiting-fee-counter');

  @override
  State<WaitingFeeCounter> createState() => _WaitingFeeCounterState();
}

class _WaitingFeeCounterState extends State<WaitingFeeCounter> {
  Timer? _tick;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = WaitingFeeState.at(
      since: widget.since,
      now: _now(),
      freeWaitMin: widget.freeWaitMin,
      perMin: widget.perMin,
      freeUntil: widget.freeUntil,
    );
    final freeMin = WaitingFeeState.freeWait(
      widget.since,
      widget.freeWaitMin,
      widget.freeUntil,
    ).inMinutes;
    final rate = context.l10n.perMinRate(formatMoneyShort(widget.perMin));
    final charging = state.charging;
    const muted = Color(0xFF5C656C);
    const warm = Color(0xFFB4452B);
    final title = charging
        ? context.l10n.waitingFeeAmount(formatMoney(state.fee, whole: true))
        : context.l10n.freeWaitingLeft(formatWaitClock(state.freeLeft));
    final detail = charging
        ? context.l10n.afterFreeWait(
            formatWaitClock(state.over),
            '$freeMin',
            rate,
          )
        : context.l10n.thenWaitingFee(rate);
    return Semantics(
      container: true,
      liveRegion: charging,
      label: '$title. $detail',
      child: ExcludeSemantics(
        child: Container(
          key: WaitingFeeCounter.counterKey,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: charging ? const Color(0xFFFDF1EE) : const Color(0xFFF1F5F7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: charging
                  ? const Color(0xFFF2D3CB)
                  : const Color(0xFFE2E7EB),
            ),
          ),
          child: Row(
            children: [
              Icon(
                charging
                    ? Icons.timer_outlined
                    : Icons.hourglass_bottom_rounded,
                size: 18,
                color: charging ? warm : muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: waitingText(
                        14,
                        weight: FontWeight.w600,
                        color: charging ? warm : null,
                      ),
                    ),
                    Text(detail, style: waitingText(12, color: muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
