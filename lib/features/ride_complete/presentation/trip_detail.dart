import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/core/realtime/call_events.dart';
import 'package:movera_rider/features/ride_complete/application/server_receipt.dart';
import 'package:movera_rider/features/ride_complete/domain/ride_dispute_not_served.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_trip_entry.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/keyboard_anchor.dart';
import 'package:movera_rider/features/ride_complete/presentation/server_receipt_lines.dart';

class RideCompletedTripDetail extends StatefulWidget {
  const RideCompletedTripDetail({
    super.key,
    this.controller,
    this.rideId,
    this.receiptLoader,
    this.receiptRetryDelays = defaultReceiptRetryDelays,
  });

  /// Owner 2026-11-10 "Yes, auto-update": while the server has no receipt
  /// yet (`receipt_not_ready`: a cash trip before the payment is captured)
  /// it is read again after each of these waits (about 2 min in all), and at
  /// once on a `payment_updated` event of the trip.
  static const defaultReceiptRetryDelays = <Duration>[
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  final List<Duration> receiptRetryDelays;

  final RideCompleteController? controller;
  final String? rideId;

  /// Reads the server's receipt (`GET /trips/{tripId}/receipt`); tests
  /// inject one. Defaults to [ServerReceipt.load].
  final Future<ServerReceipt?> Function(String rideId)? receiptLoader;

  @override
  State<RideCompletedTripDetail> createState() =>
      _RideCompletedTripDetailState();
}

class _RideCompletedTripDetailState extends State<RideCompletedTripDetail> {
  /// Owner 2026-11-10: the summary always shows the amount paid. The
  /// server's receipt `total` (contract Receipt.total, zone currency) is
  /// the final amount; the phone's booked price is only a stand-in until
  /// it is read, and the only amount when there is no local copy at all.
  ServerReceipt? _server;

  RideCompleteController? get controller => widget.controller;
  String? get rideId => widget.rideId;

  Timer? _retry;
  int _attempt = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    RidePaymentEvents.listen(_onPaymentEvent);
    _loadReceipt();
  }

  @override
  void dispose() {
    RidePaymentEvents.cancel(_onPaymentEvent);
    _retry?.cancel();
    super.dispose();
  }

  void _onPaymentEvent(String tripId) {
    if (_server != null || tripId != rideId?.trim()) return;
    _retry?.cancel();
    _loadReceipt();
  }

  Future<void> _loadReceipt() async {
    final id = rideId?.trim();
    if (id == null || id.isEmpty || _loading) return;
    _loading = true;
    final receipt = await (widget.receiptLoader ?? ServerReceipt.load)(id);
    _loading = false;
    if (!mounted) return;
    if (receipt != null) {
      _retry?.cancel();
      setState(() => _server = receipt);
      return;
    }
    // Not ready yet (payment not captured): read again, a bounded number
    // of times; the booked price stays until then.
    final delays = widget.receiptRetryDelays;
    if (_attempt >= delays.length) return;
    _retry?.cancel();
    _retry = Timer(delays[_attempt++], _loadReceipt);
  }

  @override
  Widget build(BuildContext context) {
    final ctl = controller ?? AppScope.instance.rideComplete;
    final local = ctl.receipt(rideId: rideId);
    final trip = ctl.receiptWithServerTotal(local, _server?.total);
    final hasRoute = local != null;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: screenHorizPadding),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResSize.w * 20,
              vertical: ResSize.h * 9,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xffFAFAFA),
              border: Border.all(color: AppColor.border, width: 0.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextWidget(
                  text: context.l10n.tripDetails,
                  color: AppColor.title,
                  fontSize: 16,
                  fontWeight: fwSemiBold,
                ),
                12.height,
                if (trip == null) ...[
                  MoveraEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: context.l10n.tripDetailsUnavailable,
                    message: context.l10n.tripDetailsUnavailableBody,
                    compact: true,
                  ),
                ] else ...[
                  if (hasRoute) ...[
                    // B4 (finder 2026-11-07): the stand-in labels in the app
                    // language and no trailing country.
                    _detailRow(
                      context.l10n.pickupLocation,
                      L10n.place(trip.pickup),
                    ),
                    8.height,
                    _detailRow(
                      context.l10n.destination,
                      L10n.place(trip.destination),
                    ),
                    8.height,
                  ],
                  if (trip.endedEarly) ...[
                    // R-O6: the waybill says the trip ended early and how
                    // far it went; the total below is for that distance.
                    _detailRow(
                      context.l10n.endedEarly,
                      _drivenLabel(trip.drivenMeters),
                    ),
                    8.height,
                  ],
                  _detailRow(
                    trip.isFinal
                        ? context.l10n.totalPayment
                        : context.l10n.bookedPrice,
                    trip.total,
                  ),
                  8.height,
                  if (hasRoute) ...[
                    _detailRow(
                      context.l10n.paymentMethod,
                      // rider-u182: Wallet and Card too, not only Cash.
                      L10n.isCashLabel(trip.method)
                          ? context.l10n.payCash
                          : paymentLabelFor(trip.method),
                    ),
                    8.height,
                  ],
                  // v0.18.10 (owner G8): the server's receipt: ended early
                  // and by whom, an earlier fee, the tip, refunds.
                  if (rideId != null && rideId!.trim().isNotEmpty)
                    ServerReceiptLines(
                      // The receipt read above: one read, same tip.
                      key: ValueKey(_server),
                      rideId: rideId!,
                      loader: (_) async => _server,
                      showEndedEarly: !trip.endedEarly,
                    ),
                  // RC5: a Ride check on this trip, with its answers.
                  RideCheckTripEntry(rideId: rideId, topSpacing: 4),
                  if (rideId != null && rideId!.trim().isNotEmpty) ...[
                    const Divider(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey<String>('receipt-report-issue'),
                        onPressed: () => _openDispute(context),
                        icon: const Icon(Icons.report_gmailerrorred_outlined),
                        label: Text(context.l10n.reportReceiptIssue),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDispute(BuildContext context) async {
    final id = rideId?.trim();
    if (id == null || id.isEmpty) return;
    final controller = this.controller ?? AppScope.instance.rideComplete;
    final detail = TextEditingController();
    var submitting = false;
    String? error;
    await MoveraSheet.show<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> submit() async {
            if (submitting) return;
            setState(() {
              submitting = true;
              error = null;
            });
            try {
              await controller.submitDispute(
                rideId: id,
                reason: 'receipt_issue',
                detail: detail.text,
              );
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.issueSubmitted)),
                );
              }
            } catch (failure) {
              if (sheetContext.mounted) {
                setState(() {
                  submitting = false;
                  error = failure is RideDisputeNotServed
                      ? context.l10n.reportNotOnServer
                      : context.l10n.issueSubmitFailed;
                });
              }
            }
          }

          // rider-u183: MoveraSheet.show already lifts the sheet over the
          // keyboard; padding by the inset here as well pushed Submit out
          // of reach while the rider typed. It scrolls on a short screen.
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.reportReceiptIssueTitle,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(context.l10n.reportReceiptIssueBody),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey<String>('receipt-dispute-detail'),
                  controller: detail,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: context.l10n.reportReceiptIssueHint,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    key: const ValueKey<String>('receipt-dispute-error'),
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 14),
                KeyboardAnchor(
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey<String>('receipt-dispute-submit'),
                      onPressed: submitting ? null : submit,
                      child: Text(
                        submitting
                            ? context.l10n.submitting
                            : context.l10n.submitIssue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    detail.dispose();
  }

  /// "4.2 km driven", or the rule when no distance was tracked.
  static String _drivenLabel(int? meters) {
    if (meters == null) return L10n.current.paidByDistance;
    final km = meters / 1000;
    // rider-r5-53: the app language's decimal mark ('4,2 km körda').
    return L10n.current.kmDriven(
      L10n.formatDecimal(km, digits: km < 10 ? 1 : 0),
    );
  }

  static Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: TextWidget(
            text: label,
            color: AppColor.title,
            fontSize: 14,
            fontWeight: fwMedium,
          ),
        ),
        12.width,
        Expanded(
          flex: 6,
          child: TextWidget(
            text: value,
            color: AppColor.subtitle,
            fontSize: 14,
            fontWeight: fwMedium,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
