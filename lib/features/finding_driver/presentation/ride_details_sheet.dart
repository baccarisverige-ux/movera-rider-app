import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/features/ride_selection/presentation/ride_labels.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';

/// The route and the money of the current ride, read-only. Changing the
/// route happens on the route screen (the three dots on the ride card).
class RideDetailsSheet extends StatelessWidget {
  const RideDetailsSheet({
    super.key,
    required this.pickupAddress,
    required this.destinationAddress,
    this.stops = const <RouteStop>[],
    required this.rideType,
    required this.price,
    this.currency = Money.defaultCurrency,
    required this.paymentMethod,
    required this.notes,
    this.allowCancel = true,
    required this.onCancelTrip,
    this.cancelLabel,
    this.onMovePickup,
    this.onEditPickup,
    this.onEditDestination,
    this.onAddStop,
  });

  final String pickupAddress;
  final String destinationAddress;
  final List<RouteStop> stops;
  final String rideType;
  final double price;

  /// ISO-4217 code of [price].
  final String currency;
  final String paymentMethod;
  final RideNotes notes;
  final bool allowCancel;
  final VoidCallback onCancelTrip;

  /// Owner 2026-11-23 (screen 3): the red row's words; on board "Avsluta
  /// resan här" (end early), else "Avboka resan".
  final String? cancelLabel;

  /// Owner 2026-11-23: "Flytta upphämtning" as a row of the menu where the
  /// pickup may move (null hides it).
  final VoidCallback? onMovePickup;

  /// v0.18.143 (approved mockup screen 2): the pencil on the pickup, only
  /// while the ride is still searched (null hides it).
  final VoidCallback? onEditPickup;

  /// The pencil on the destination (the route screen).
  final VoidCallback? onEditDestination;

  /// The "+" under the destination (the route screen with a new stop).
  final VoidCallback? onAddStop;

  /// Opens the sheet; each action gets the sheet's context (to close it
  /// before the next screen). v0.18.143 (owner 2026-11-20): the same sheet
  /// while searching, while the driver is coming and during the trip.
  static Future<void> open(
    BuildContext context, {
    required String pickupAddress,
    required String destinationAddress,
    List<RouteStop> stops = const <RouteStop>[],
    required String rideType,
    required double price,
    String currency = Money.defaultCurrency,
    required String paymentMethod,
    required RideNotes notes,
    bool allowCancel = true,
    required void Function(BuildContext sheet) onCancelTrip,
    String? cancelLabel,
    void Function(BuildContext sheet)? onMovePickup,
    void Function(BuildContext sheet)? onEditPickup,
    void Function(BuildContext sheet)? onEditDestination,
    void Function(BuildContext sheet)? onAddStop,
  }) => MoveraSheet.show<void>(
    context: context,
    builder: (sheet) => RideDetailsSheet(
      pickupAddress: pickupAddress,
      destinationAddress: destinationAddress,
      stops: stops,
      rideType: rideType,
      price: price,
      currency: currency,
      paymentMethod: paymentMethod,
      notes: notes,
      allowCancel: allowCancel,
      onCancelTrip: () => onCancelTrip(sheet),
      cancelLabel: cancelLabel,
      onMovePickup: onMovePickup == null ? null : () => onMovePickup(sheet),
      onEditPickup: onEditPickup == null ? null : () => onEditPickup(sheet),
      onEditDestination: onEditDestination == null
          ? null
          : () => onEditDestination(sheet),
      onAddStop: onAddStop == null ? null : () => onAddStop(sheet),
    ),
  );

  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _accent = Color(0xFF2D5878);
  static const Color _line = Color(0xFFE7EBEE);

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + inset),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Owner 2026-11-23 (menu-open): the title on the left, a soft
            // round close button on the right.
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.rideDetails,
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ),
                  Material(
                    color: const Color(0xFFF1F5F7),
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: context.l10n.close,
                    ),
                  ),
                ],
              ),
            ),
            _RouteRow(
              key: const ValueKey('ride-details-pickup'),
              kind: _RowKind.pickup,
              address: pickupAddress,
              onEdit: onEditPickup,
              editKey: const ValueKey('ride-details-edit-pickup'),
            ),
            for (var i = 0; i < stops.length; i++) ...[
              _connector(),
              _RouteRow(
                key: ValueKey('ride-details-stop-$i'),
                kind: _RowKind.stop,
                label: context.l10n.stopNumber('${i + 1}'),
                address: stops[i].address,
              ),
            ],
            _connector(),
            _RouteRow(
              key: const ValueKey('ride-details-destination'),
              kind: _RowKind.destination,
              address: destinationAddress,
              onEdit: onEditDestination,
              editKey: const ValueKey('ride-details-edit-destination'),
            ),
            if (onAddStop != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('ride-details-add-stop'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF055B95),
                    textStyle: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: onAddStop,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(context.l10n.addAStop),
                ),
              ),
            const SizedBox(height: 8),
            if (onMovePickup != null) ...[
              _divider(),
              InkWell(
                key: const ValueKey('ride-details-move-pickup'),
                onTap: onMovePickup,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.open_with_rounded,
                        size: 20,
                        color: Color(0xFF055B95),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.l10n.movePickup,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF055B95),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF9AA3A9),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            _divider(),
            _kv(rideNameFor(rideType), formatMajor(price, currency)),
            _divider(),
            // Pay in car shown in the app language (rider-u231).
            _kv(context.l10n.navPayment, paymentLabelFor(paymentMethod)),
            if (!notes.isEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in notes.selected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F6FB),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        RideNotes.labelFor(label),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _accent,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            // Owner 2026-11-23: cancelling is the last row, red text with
            // a chevron (same action and confirm as before).
            if (allowCancel) ...[
              _divider(),
              InkWell(
                key: const ValueKey('ride-details-cancel'),
                onTap: onCancelTrip,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          cancelLabel ?? context.l10n.cancelTrip,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: const Color(0xFFB42318),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF9AA3A9),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF111614),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  context.l10n.close,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, color: _line);

  Widget _connector() => Container(
    width: 2,
    height: 16,
    margin: const EdgeInsets.only(left: 10),
    color: _line,
  );

  Widget _kv(String left, String right, {bool muted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: _muted,
              ),
            ),
          ),
          Text(
            right,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: muted ? _muted : _ink,
            ),
          ),
        ],
      ),
    );
  }
}

enum _RowKind { pickup, stop, destination }

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    super.key,
    required this.kind,
    required this.address,
    this.label,
    this.onEdit,
    this.editKey,
  });

  final _RowKind kind;
  final String address;
  final String? label;
  final VoidCallback? onEdit;
  final Key? editKey;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      _RowKind.pickup => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF061B44), width: 4),
        ),
      ),
      _RowKind.stop => Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: RideDetailsSheet._ink, width: 2),
        ),
      ),
      _RowKind.destination => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: const Color(0xFF055B95),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 22, child: Center(child: icon)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null)
                  Text(
                    label!,
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: RideDetailsSheet._muted,
                    ),
                  ),
                Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: RideDetailsSheet._ink,
                  ),
                ),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              key: editKey,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: context.l10n.changeRoute,
            ),
        ],
      ),
    );
  }
}
