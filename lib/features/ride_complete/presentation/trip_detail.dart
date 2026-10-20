import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_trip_entry.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';

class RideCompletedTripDetail extends StatelessWidget {
  const RideCompletedTripDetail({
    super.key,
    this.controller,
    this.rideId,
  });

  final RideCompleteController? controller;
  final String? rideId;

  @override
  Widget build(BuildContext context) {
    final trip = (controller ?? AppScope.instance.rideComplete).receipt();
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
                  text: 'Trip Details',
                  color: AppColor.title,
                  fontSize: 16,
                  fontWeight: fwSemiBold,
                ),
                12.height,
                if (trip == null) ...[
                  const MoveraEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Trip details unavailable',
                    message:
                        'Your route, payment method and price will appear here when the ride record is available.',
                    compact: true,
                  ),
                ] else ...[
                  _detailRow('Pickup location', trip.pickup),
                  8.height,
                  _detailRow('Destination', trip.destination),
                  8.height,
                  if (trip.endedEarly) ...[
                    // R-O6: the waybill says the trip ended early and how
                    // far it went; the total below is for that distance.
                    _detailRow('Ended early', _drivenLabel(trip.drivenMeters)),
                    8.height,
                  ],
                  _detailRow(
                    trip.isFinal ? 'Total payment' : 'Booked price',
                    trip.total,
                  ),
                  8.height,
                  _detailRow('Payment method', trip.method),
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
                        label: const Text('Report an issue with this receipt'),
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
                  const SnackBar(content: Text('Issue submitted for review.')),
                );
              }
            } catch (_) {
              if (sheetContext.mounted) {
                setState(() {
                  submitting = false;
                  error = 'Could not submit the issue. Please try again.';
                });
              }
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Report receipt issue',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text('Tell us what looks wrong. Your ride record will be reviewed.'),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey<String>('receipt-dispute-detail'),
                  controller: detail,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'What is wrong with the receipt?',
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
                    child: Text(submitting ? 'Submitting…' : 'Submit issue'),
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
    if (meters == null) return 'Paid by distance driven';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km driven';
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
