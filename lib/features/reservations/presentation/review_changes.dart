import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_widgets.dart';
import 'package:movera_rider/l10n/l10n.dart';

class ReviewChangesPage extends StatelessWidget {
  const ReviewChangesPage({
    super.key,
    required this.original,
    required this.draft,
    this.controller,
  });

  final Reservation original;
  final ReservationDraft draft;
  final ReservationController? controller;

  @override
  Widget build(BuildContext context) {
    final change = ReservationPriceChange(
      previous: original.price,
      next: draft.price,
      currency: original.currency,
    );
    final policy = controller?.policy;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          SizedBox(height: top + 4),
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: kReservationInk,
                ),
                tooltip: context.l10n.back,
              ),
              Expanded(
                child: Text(
                  context.l10n.resReviewChanges,
                  textAlign: TextAlign.center,
                  style: reservationText(16, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
              children: [
                const ReservationHeroArt(
                  asset: AppAssets.scheduleRideCar,
                  height: 92,
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.resReviewIntro,
                  style: reservationText(
                    14.5,
                    color: kReservationMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                _CompareCard(
                  title: context.l10n.resCurrent,
                  when: original.scheduledPickupAt,
                  pickup: original.pickup.label,
                  destination: original.destination.label,
                  category: original.categoryName,
                  price: original.price,
                  currency: original.currency,
                ),
                const SizedBox(height: 12),
                _CompareCard(
                  title: context.l10n.resUpdated,
                  when: draft.scheduledPickupAt,
                  pickup: draft.pickup.label,
                  destination: draft.destination.label,
                  category: draft.categoryName,
                  price: draft.price,
                  currency: draft.currency,
                  highlight: true,
                ),
                const SizedBox(height: 20),
                Text(
                  change.summary,
                  style: reservationText(16, weight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                _PriceLine(
                  label: context.l10n.resPreviousPrice,
                  value: ReservationFormat.kr(change.previous, change.currency),
                ),
                _PriceLine(
                  label: context.l10n.resNewPrice,
                  value: ReservationFormat.kr(change.next, change.currency),
                ),
                _PriceLine(
                  label: context.l10n.resPriceDifference,
                  value: change.unchanged
                      ? ReservationFormat.kr(0, change.currency)
                      : '${change.delta > 0 ? '+' : '−'}${ReservationFormat.kr(change.delta.abs(), change.currency)}',
                  strong: true,
                ),
                if (policy?.changeCharge == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      policy?.changeChargeSummary ??
                          context.l10n.resNoChangeCharge,
                      style: reservationText(13, color: kReservationMuted),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(22, 8, 22, 16 + bottom),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kReservationInk,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      context.l10n.resConfirmChanges,
                      style: reservationText(
                        15,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      backgroundColor: kReservationSoft,
                      foregroundColor: kReservationInk,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      context.l10n.resKeepCurrent,
                      style: reservationText(15, weight: FontWeight.w600),
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

class _CompareCard extends StatelessWidget {
  const _CompareCard({
    required this.title,
    required this.when,
    required this.pickup,
    required this.destination,
    required this.category,
    required this.price,
    this.currency = 'SEK',
    this.highlight = false,
  });

  final String title;
  final DateTime when;
  final String pickup;
  final String destination;
  final String category;
  final double price;
  final String currency;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFF7FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlight
              ? kReservationAccent.withValues(alpha: 0.35)
              : kReservationLine,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: reservationText(
              11,
              weight: FontWeight.w600,
              color: kReservationMuted,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$category  ·  ${ReservationFormat.kr(price, currency)}',
            style: reservationText(15, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${ReservationFormat.longDate(when)}  ·  ${ReservationFormat.time(when)}',
            style: reservationText(13.5, color: kReservationMuted),
          ),
          const SizedBox(height: 4),
          Text(
            '$pickup  →  $destination',
            style: reservationText(13.5, weight: FontWeight.w500, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: reservationText(
                13.5,
                color: kReservationMuted,
                weight: strong ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(value, style: reservationText(13.5, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}
