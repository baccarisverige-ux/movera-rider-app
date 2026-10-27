import 'package:flutter/material.dart';
import 'package:movera_rider/features/ride_complete/data/ride_dispute_repository.dart';
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

class RideCompletedTripDetail extends StatelessWidget {
  const RideCompletedTripDetail({super.key, this.controller, this.rideId});

  final RideCompleteController? controller;
  final String? rideId;

  @override
  Widget build(BuildContext context) {
    final trip = (controller ?? AppScope.instance.rideComplete).receipt(
      rideId: rideId,
    );
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
                  _detailRow(context.l10n.pickupLocation, trip.pickup),
                  8.height,
                  _detailRow(context.l10n.destination, trip.destination),
                  8.height,
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
                  _detailRow(
                    context.l10n.paymentMethod,
                    // rider-u182: Wallet and Card too, not only Cash.
                    L10n.isCashLabel(trip.method)
                        ? context.l10n.payCash
                        : paymentLabelFor(trip.method),
                  ),
                  8.height,
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
                SizedBox(
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

  Widget _detailRow(String label, String value) {
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
