import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/l10n/l10n.dart';

class DriverProfilePage extends StatelessWidget {
  const DriverProfilePage({super.key, required this.driver});

  final MatchedDriver driver;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, inset.top + 8, 20, 24 + inset.bottom),
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                tooltip: context.l10n.close,
              ),
              Expanded(
                child: Text(
                  context.l10n.driver,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundImage: driver.photoAsset != null
                  ? AssetImage(driver.photoAsset!)
                  : null,
              backgroundColor: const Color(0xFFF3F6FB),
              child: driver.photoAsset == null
                  ? Text(
                      driver.firstName.isEmpty ? '?' : driver.firstName[0],
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            driver.firstName,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1D252C),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (driver.tripCount != null)
                Expanded(
                  child: _stat('${driver.tripCount}', context.l10n.driverTrips),
                ),
              if (driver.ratingLabel != null)
                Expanded(
                  child: _stat(driver.ratingLabel!, context.l10n.driverRating),
                ),
              if (driver.yearsOnMovera != null)
                Expanded(
                  child: _stat(
                    '${driver.yearsOnMovera}',
                    context.l10n.driverYears,
                  ),
                ),
            ],
          ),
          if (driver.vehicleLabel.isNotEmpty || driver.plate != null) ...[
            const SizedBox(height: 24),
            Text(
              context.l10n.vehicle,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF5C656C),
              ),
            ),
            const SizedBox(height: 8),
            if (driver.plate != null)
              Text(
                driver.plate!,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (driver.vehicleLabel.isNotEmpty)
              Text(
                driver.vehicleLabel,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: const Color(0xFF5C656C),
                ),
              ),
          ],
          if (driver.languages.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              context.l10n.driverLanguages,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF5C656C),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              driver.languages.join(', '),
              style: GoogleFonts.poppins(fontSize: 15),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1D252C),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: const Color(0xFF5C656C),
          ),
        ),
      ],
    );
  }
}
