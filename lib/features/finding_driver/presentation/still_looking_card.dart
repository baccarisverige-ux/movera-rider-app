import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// ARCH-3: shown when a search has gone on for a while without a driver.
/// The request is still active on the server; the rider chooses to keep
/// searching or to cancel it (server first, like any rider cancel).
class StillLookingCard extends StatelessWidget {
  const StillLookingCard({
    super.key,
    required this.onKeepSearching,
    required this.onCancel,
  });

  final VoidCallback onKeepSearching;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('finding-still-looking'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6EAEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.stillLooking,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: MoveraTokens.ink,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.stillLookingBody,
            style: GoogleFonts.poppins(
              fontSize: 13,
              height: 1.35,
              color: const Color(0xFF5C656C),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: const Color(0xFF1D252C),
                    side: const BorderSide(color: Color(0xFFD5DCE0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    context.l10n.cancelRequest,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onKeepSearching,
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: const Color(0xFF2D5878),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    context.l10n.keepSearching,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
