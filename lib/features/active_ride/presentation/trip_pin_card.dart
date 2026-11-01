import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// G6 (contract v0.18.8 `arrivedWaiting.pin`): the trip PIN the rider
/// tells the driver before the trip starts. Big, spaced digits so it can
/// be read out loud or shown through the car window.
class TripPinCard extends StatelessWidget {
  const TripPinCard({super.key, required this.pin});

  final String pin;

  @override
  Widget build(BuildContext context) {
    final digits = pin.split('').join(' ');
    return Semantics(
      container: true,
      label: '${context.l10n.tripPinTellDriver}: $digits',
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('trip-pin-card'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E7EB)),
        ),
        child: Column(
          children: [
            Text(
              context.l10n.tripPinTellDriver,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF5C656C),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                digits,
                style: GoogleFonts.poppins(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                  color: const Color(0xFF11181D),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
