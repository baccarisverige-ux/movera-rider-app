import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/ride_navigator.dart';
import 'package:movera_rider/core/api/mutation_attempt.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/contracts/trip_transitions.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/presentation/add_tip.dart';
import 'package:movera_rider/features/ride_complete/presentation/driver_info.dart';
import 'package:movera_rider/features/ride_complete/presentation/give_review.dart';
import 'package:movera_rider/features/ride_complete/presentation/trip_detail.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_card.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/widgets/realtime_connection_banner.dart';
import 'package:movera_rider/l10n/l10n.dart';

class RideCompleted extends StatefulWidget {
  const RideCompleted({
    super.key,
    this.status = RideStatus.tripCompleted,
    this.rideId,
    this.realtime,
    this.persistOnDemandState = true,
    this.feedbackAvailableOnCompletion = false,
    this.showConnectionBanner = true,
    this.onClose,
    this.controller,
    this.endedEarly,
  });

  /// UI-01: the rider ended the trip on board. The summary says so and
  /// shows what they pay for the distance driven, instead of dropping them
  /// on Home. R-O6 (owner decision): it is the normal trip-end screen, with
  /// rating and tip, and the waybill marks the trip "Ended early" with the
  /// km driven. Contract v0.3.1 (`ratingAllowed`) lets the rider rate it.
  final EndedEarlyTrip? endedEarly;

  final RideStatus status;
  final String? rideId;

  /// Optional transport override keeps this surface testable while production
  /// uses the same RideRealtime seam as the active-ride screen.
  final RideRealtime? realtime;
  final bool persistOnDemandState;

  /// Scheduled rides do not currently expose payment lifecycle states, but
  /// completion itself is authoritative. This flag lets that flow offer
  /// optional rating/tip without fabricating paymentProcessing,
  /// paymentFinalized, or ratingPending events.
  final bool feedbackAvailableOnCompletion;

  final bool showConnectionBanner;
  final Future<void> Function(BuildContext context)? onClose;
  final RideCompleteController? controller;

  @override
  State<RideCompleted> createState() => _RideCompletedState();
}

int _completionRank(RideStatus status) {
  switch (status) {
    case RideStatus.tripCompleted:
      return 1;
    case RideStatus.paymentProcessing:
      return 2;
    case RideStatus.paymentFinalized:
      return 3;
    case RideStatus.ratingPending:
      return 4;
    default:
      return 0;
  }
}

class _RideCompletedState extends State<RideCompleted> {
  late final RideCompleteController _controller = widget.controller ?? AppScope.instance.rideComplete;
  StreamSubscription<RideRealtimeEvent>? _completionSub;
  late RideStatus _status;
  bool _leaving = false;
  double? _rating;
  int? _tipMinor;
  String? _submitError;
  final MutationAttempt _feedbackMutation = MutationAttempt('ride-feedback');
  String? _acceptedFeedbackIntent;
  bool _walletChargeRequested = false;

  @override
  void initState() {
    super.initState();
    _status = widget.status;
    // An ended-early trip is terminal: no completion states will follow.
    if (widget.endedEarly != null) return;
    final rideId = widget.rideId?.trim();
    if (rideId == null || rideId.isEmpty) return;

    // Waiting stays subscribed until the replacement route is actually
    // disposed. If payment/rating advances during that handoff, RideSession
    // already has the newer authoritative completion state before this screen
    // gets its first frame. Start from that state instead of regressing to the
    // status captured when navigation began.
    if (widget.persistOnDemandState) {
      final session = AppScope.instance.ride;
      if (session.rideId?.trim() == rideId &&
          session.status.isCompletedSurface &&
          _completionRank(session.status) > _completionRank(_status)) {
        _status = session.status;
      }
      // rider-u179: a decline reconciled during the handoff.
      if (session.rideId?.trim() == rideId &&
          session.status == RideStatus.paymentFailed) {
        _status = RideStatus.paymentFailed;
        unawaited(_controller.markCompletedPaymentFailed(rideId));
      }
    }

    final realtime = widget.realtime ?? AppScope.instance.rideRealtime;
    _completionSub = realtime.subscribe(rideId).listen((event) {
      final status = event.status;
      // rider-u179: a declined card arrives as paymentFailed, which is not
      // a completion surface. It used to be dropped here, leaving the
      // rider on "Payment processing" and the trip filed as completed.
      // It is final for this screen.
      if (!mounted || _leaving || _status == RideStatus.paymentFailed) return;
      if (status == RideStatus.paymentFailed) {
        _onPaymentFailed(event, rideId);
        return;
      }
      if (!status.isCompletedSurface ||
          _completionRank(status) <= _completionRank(_status)) {
        return;
      }
      if (widget.persistOnDemandState) {
        AppScope.instance.ride.backendReconcile(
          status,
          id: event.tripId,
          version: event.version ?? event.sequence,
          updatedAt: event.serverTime ?? event.occurredAt,
        );
        unawaited(
          _controller.persistCompletedStatus(status, rideId: rideId),
        );
      }
      setState(() => _status = status);
      _maybeChargeWallet();
    });
    _maybeChargeWallet();
  }

  void _onPaymentFailed(RideRealtimeEvent event, String rideId) {
    if (widget.persistOnDemandState) {
      AppScope.instance.ride.backendReconcile(
        RideStatus.paymentFailed,
        id: event.tripId,
        version: event.version ?? event.sequence,
        updatedAt: event.serverTime ?? event.occurredAt,
      );
      unawaited(_controller.markCompletedPaymentFailed(rideId));
    }
    setState(() => _status = RideStatus.paymentFailed);
  }

  /// D-022: a wallet-paid on-demand ride is deducted from the local wallet
  /// balance once it reaches a charged status. The debit itself belongs to
  /// the ride's lifecycle (ActiveRideController), which also debits when
  /// the rider leaves before then (rider-u180/u181) or ended the trip
  /// early (rider-u178); WalletController guards against charging the
  /// same ride twice.
  void _maybeChargeWallet() {
    if (!widget.persistOnDemandState || _walletChargeRequested) return;
    if (_completionRank(_status) <
        _completionRank(RideStatus.paymentFinalized)) {
      return;
    }
    final rideId = widget.rideId?.trim();
    if (rideId == null || rideId.isEmpty) return;
    _walletChargeRequested = true;
    unawaited(_controller.chargeCompletedWallet(rideId));
  }

  @override
  void dispose() {
    _completionSub?.cancel();
    super.dispose();
  }

  Future<void> _closeAndHome() => _leave(submitFeedback: true);

  /// Back (top-left and system) must never submit money-affecting feedback
  /// as a side effect of leaving. Only prompt when there is a selected
  /// rating or tip that would otherwise be silently discarded; with nothing
  /// selected there is nothing to lose, so leave immediately.
  Future<void> _handleBack() async {
    if (_leaving || !mounted) return;
    // RC5: an open Ride check card has to be answered first.
    if (RideCheckController.shared.blocks(widget.rideId)) return;
    if (_rating == null && _tipMinor == null) {
      await _leave(submitFeedback: false);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.l10n.leaveWithoutSending,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          context.l10n.leaveWithoutSendingBody,
          style: GoogleFonts.poppins(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.stay),
          ),
          TextButton(
            key: const ValueKey('completion-leave-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.leave),
          ),
        ],
      ),
    );
    if (leave == true) {
      await _leave(submitFeedback: false);
    }
  }

  Future<void> _leave({required bool submitFeedback}) async {
    if (_leaving || !mounted) return;
    setState(() {
      _leaving = true;
      _submitError = null;
    });
    // rider-72: a refused feedback and a failed close are told apart. Only
    // the first keeps the rider here to try again; closing tolerates a
    // session the server already ended.
    try {
      if (submitFeedback && (_rating != null || _tipMinor != null)) {
        final id = widget.rideId;
        if (id == null || id.trim().isEmpty) {
          throw StateError('Ride ID is missing.');
        }
        final feedbackIntent =
            '$id|${_rating?.toStringAsFixed(1) ?? ''}|${_tipMinor ?? ''}';
        if (_acceptedFeedbackIntent != feedbackIntent) {
          await _controller.submitFeedback(
            rideId: id,
            rating: _rating,
            tipMinor: _tipMinor,
            idempotencyKey: _feedbackMutation.keyFor(feedbackIntent),
          );
          _acceptedFeedbackIntent = feedbackIntent;
          _feedbackMutation.succeeded(feedbackIntent);
        }
      }
    } catch (_) {
      _stayWithError();
      return;
    }
    if (!mounted) return;
    try {
      final customClose = widget.onClose;
      if (customClose != null) {
        await customClose(context);
        return;
      }
      if (widget.persistOnDemandState && widget.rideId != null) {
        await _controller.closeCompletedRide(widget.rideId!);
      } else {
        _controller.close();
      }
    } catch (error) {
      AppLog.warning(
        'ride.complete.close_failed',
        extra: {'rideId': widget.rideId, 'error': error.toString()},
      );
      _stayWithError();
      return;
    }
    if (!mounted) return;
    RideNavigator.home(context, status: RideStatus.closed);
  }

  void _stayWithError() {
    if (!mounted) return;
    setState(() {
      _leaving = false;
      _submitError = context.l10n.feedbackSaveFailed;
    });
  }

  _CompletionSpec get _spec {
    final endedEarly = widget.endedEarly;
    if (endedEarly != null) return _CompletionSpec.endedEarly(endedEarly);
    return _CompletionSpec.fromStatus(_status);
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    final endedEarly = widget.endedEarly != null;
    // R-O6: an ended-early trip is over and its price known: rate now
    // (contract.json#ratingAllowed: rider, cancelled_by_rider via end_early).
    final canRate =
        (endedEarly &&
            TripRatingRules.allows(
              TripActor.rider,
              TripStatus.cancelledByRider,
              endedBy: 'end_early',
            )) ||
        _status == RideStatus.ratingPending ||
        (widget.feedbackAvailableOnCompletion &&
            _status == RideStatus.tripCompleted);
    final showFeedbackSurface = widget.persistOnDemandState || canRate;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          await _handleBack();
        }
      },
      child: _withRideCheck(Scaffold(
        backgroundColor: const Color(0xFFF6F5F1),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(
                  children: [
                    _CircleAction(
                      icon: Icons.arrow_back_ios_rounded,
                      label: context.l10n.back,
                      onTap: _handleBack,
                    ),
                    Expanded(
                      child: Text(
                        endedEarly ? context.l10n.tripSummary : context.l10n.rideSummary,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: MoveraTokens.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              if (widget.showConnectionBanner)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: RealtimeConnectionBanner(
                    connection: AppScope.instance.realtime,
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  child: Column(
                    children: [
                      _CompletionHero(spec: spec),
                      if (showFeedbackSurface) ...[
                        const SizedBox(height: 14),
                        IgnorePointer(
                          key: const ValueKey('completion-feedback-lock'),
                          ignoring: !canRate || _leaving,
                          child: AnimatedOpacity(
                            key: const ValueKey('completion-feedback'),
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOutCubic,
                            opacity: canRate ? 1 : 0.52,
                            child: Column(
                              children: [
                                _SurfaceCard(
                                  child: RideCompletedGiveReview(
                                    onRatingChanged: (rating) => _rating = rating,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _SurfaceCard(
                                  child: RideCompletedAddTip(
                                    rideId: widget.rideId,
                                    onTipChanged: (amount) => _tipMinor = amount,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          canRate
                              ? context.l10n.ratingOptional
                              : context.l10n.ratingAfterPayment,
                          key: const ValueKey('completion-feedback-status'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: MoveraTokens.muted,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const _BelongingsReminder(),
                      const SizedBox(height: 14),
                      _SurfaceCard(
                        child: RideCompletedDriverInfo(rideId: widget.rideId),
                      ),
                      const SizedBox(height: 14),
                      _SurfaceCard(
                        child: RideCompletedTripDetail(
                          controller: _controller,
                          rideId: widget.rideId,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_submitError != null)
                        Text(
                          _submitError!,
                          key: const ValueKey('completion-submit-error'),
                          style: const TextStyle(color: Colors.red),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: MoveraTokens.buttonHeight,
                  child: FilledButton(
                    key: const ValueKey<String>('ride-completed-done'),
                    onPressed: _leaving ? null : _closeAndHome,
                    style: FilledButton.styleFrom(
                      backgroundColor: MoveraTokens.cta,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      context.l10n.done,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }

  /// RC1: "dropped far away" opens as the trip ends, over the summary.
  Widget _withRideCheck(Widget screen) => Stack(
    children: [
      screen,
      Positioned.fill(child: RideCheckLayer(rideId: widget.rideId)),
    ],
  );
}

class _CompletionHero extends StatelessWidget {
  const _CompletionHero({required this.spec});

  final _CompletionSpec spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: MoveraTokens.line),
        boxShadow: [
          BoxShadow(
            color: MoveraTokens.ink.withValues(alpha: 0.05),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F7),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Icon(
              spec.icon,
              size: 29,
              color: MoveraTokens.accent,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            spec.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: MoveraTokens.ink,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Center(
              child: Text(
                spec.message,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: MoveraTokens.muted,
                  height: 1.45,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFB),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  spec.statusIcon,
                  size: 18,
                  color: MoveraTokens.accent,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    spec.statusLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MoveraTokens.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BelongingsReminder extends StatelessWidget {
  const _BelongingsReminder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.checkBelongings,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MoveraTokens.ink,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Image.asset(
            excludeFromSemantics: true,
            AppAssets.eyeEmoji,
            width: 20,
            height: 20,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: MoveraTokens.line),
      ),
      child: child,
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: MoveraTokens.line),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: MoveraTokens.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletionSpec {
  const _CompletionSpec({
    required this.title,
    required this.message,
    required this.statusLabel,
    required this.icon,
    required this.statusIcon,
  });

  final String title;
  final String message;
  final String statusLabel;
  final IconData icon;
  final IconData statusIcon;

  factory _CompletionSpec.endedEarly(EndedEarlyTrip trip) {
    final charged = trip.charged;
    return _CompletionSpec(
      title: L10n.current.tripEndedEarly,
      message: charged == null
          ? L10n.current.endedEarlyBody
          : L10n.current.endedEarlyBodyAmount(formatMoney(charged)),
      statusLabel: charged == null
          ? L10n.current.paidByDistance
          : L10n.current.youPayAmount(formatMoney(charged)),
      icon: Icons.flag_rounded,
      statusIcon: Icons.receipt_long_rounded,
    );
  }

  factory _CompletionSpec.fromStatus(RideStatus status) {
    switch (status) {
      case RideStatus.paymentFailed:
        return _CompletionSpec(
          title: L10n.current.termPaymentTitle,
          message: L10n.current.termPaymentNote,
          statusLabel: L10n.current.paymentNotCompleted,
          icon: Icons.credit_card_off_outlined,
          statusIcon: Icons.error_outline_rounded,
        );
      case RideStatus.paymentProcessing:
        return _CompletionSpec(
          title: L10n.current.tripComplete,
          message:
              L10n.current.completeProcessingBody,
          statusLabel: L10n.current.paymentProcessing,
          icon: Icons.route_rounded,
          statusIcon: Icons.hourglass_top_rounded,
        );
      case RideStatus.paymentFinalized:
        return _CompletionSpec(
          title: L10n.current.tripComplete,
          message:
              L10n.current.completeConfirmedBody,
          statusLabel: L10n.current.paymentConfirmed,
          icon: Icons.check_rounded,
          statusIcon: Icons.verified_rounded,
        );
      case RideStatus.ratingPending:
        return _CompletionSpec(
          title: L10n.current.tripComplete,
          message:
              L10n.current.completeRateBody,
          statusLabel: L10n.current.readyForFeedback,
          icon: Icons.star_outline_rounded,
          statusIcon: Icons.rate_review_outlined,
        );
      case RideStatus.tripCompleted:
      default:
        return _CompletionSpec(
          title: L10n.current.tripComplete,
          message:
              L10n.current.completeDefaultBody,
          statusLabel: L10n.current.tripCompleted,
          icon: Icons.flag_rounded,
          statusIcon: Icons.check_circle_outline_rounded,
        );
    }
  }
}
