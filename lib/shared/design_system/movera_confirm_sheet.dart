import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';

/// Asks before a destructive or replacing action (FLOW-5, FLOW-15), the way
/// Wallet asks before removing a card. Resolves true only when the rider
/// taps [confirmLabel]; dismissing the sheet or tapping Cancel is false.
/// [cancelLabel] defaults to the app language's Cancel (rider-j8-11).
Future<bool> confirmMoveraAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
}) async {
  TextStyle style(double size, FontWeight weight, Color color) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color);
  const ink = Color(0xFF11181D);
  const muted = Color(0xFF5C656C);
  final confirmed = await MoveraSheet.show<bool>(
    context: context,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: style(18, FontWeight.w700, ink),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: style(13, FontWeight.w400, muted),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const ValueKey('movera-confirm-action'),
                onPressed: () => Navigator.of(sheetContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  confirmLabel,
                  style: style(15, FontWeight.w600, Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: TextButton(
                key: const ValueKey('movera-confirm-cancel'),
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: Text(
                  cancelLabel ?? sheetContext.l10n.cancel,
                  style: style(15, FontWeight.w500, ink),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return confirmed == true;
}
