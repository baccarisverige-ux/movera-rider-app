import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/l10n/l10n.dart';

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
            Row(
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: Text(
                    context.l10n.rideDetails,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: context.l10n.close,
                ),
              ],
            ),
            _RouteRow(
              key: const ValueKey('ride-details-pickup'),
              kind: _RowKind.pickup,
              address: pickupAddress,
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
            ),
            const SizedBox(height: 16),
            _kv(rideType, formatMajor(price, currency)),
            const SizedBox(height: 8),
            _kv(context.l10n.navPayment, paymentMethod),
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
            const SizedBox(height: 20),
            if (allowCancel) ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: TextButton(
                  onPressed: onCancelTrip,
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFF4F5F6),
                    foregroundColor: const Color(0xFFB42318),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    context.l10n.cancelTrip,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF11181D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
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

  Widget _connector() => Container(
    width: 2,
    height: 16,
    margin: const EdgeInsets.only(left: 10),
    color: _line,
  );

  Widget _kv(String left, String right, {bool muted = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            left,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: _ink,
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
  });

  final _RowKind kind;
  final String address;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      _RowKind.pickup => const Icon(
        Icons.radio_button_checked,
        size: 18,
        color: Color(0xFF079A60),
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
      _RowKind.destination => const Icon(
        Icons.square,
        size: 14,
        color: Color(0xFF1769E8),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: RideDetailsSheet._ink,
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
