import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/shared/design_system/movera_hit_area.dart';

/// Saved places redesign v4 (owner 2026-11-27,
/// saved-places-mockup-v4-2026-11-27): white only, Poppins, thin outlined
/// icons in ink (never green or blue), no grey tiles, underline fields,
/// hairline dividers, a dark ink pill as the main button.
abstract final class SpStyle {
  static const Color ink = Color(0xFF12201C);
  static const Color muted = Color(0xFF8A8A8A);
  static const Color hairline = Color(0xFFF0F0F0);
  static const Color chipBorder = Color(0xFFE6E6E6);
  static const double side = 24;

  static TextStyle text({
    double size = 16,
    FontWeight weight = FontWeight.w400,
    Color color = ink,
    double? spacing,
  }) => GoogleFonts.poppins(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: spacing,
  );

  /// The 28 px page title.
  static Widget title(String value) => Text(
    value,
    style: text(size: 28, weight: FontWeight.w500, spacing: -0.5),
  );

  /// FAVORITER / ANDRA PLATSER.
  static Widget section(String value) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 6),
    child: Text(
      value.toUpperCase(),
      style: text(size: 11, color: muted, spacing: 1.3),
    ),
  );

  /// A field label above an underline field (Namn, the type question).
  static Widget label(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      value,
      style: text(size: 12, weight: FontWeight.w500, color: muted),
    ),
  );

  /// The underline field look.
  static InputDecoration underline({
    String? hint,
    Widget? prefix,
    Widget? suffix,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: text(color: muted),
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 24),
    suffixIcon: suffix,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(vertical: 14),
    enabledBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: ink),
    ),
    disabledBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: chipBorder),
    ),
    focusedBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: ink, width: 1.5),
    ),
    border: const UnderlineInputBorder(borderSide: BorderSide(color: ink)),
  );

  /// The thin back chevron, with a 44 px named tap area (UI-11).
  static Widget back(BuildContext context, String label, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(left: 12, top: 4),
        child: MoveraHitArea(
          label: label,
          onTap: onTap,
          child: const Icon(Icons.chevron_left, color: ink, size: 28),
        ),
      );

  /// The main button: a dark ink pill.
  static Widget pill({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
  }) => SizedBox(
    width: double.infinity,
    height: 56,
    child: ElevatedButton(
      key: key,
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: ink.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        shape: const StadiumBorder(),
        textStyle: text(weight: FontWeight.w500, color: Colors.white),
      ),
      child: Text(label),
    ),
  );

  /// A list row: icon, name over address, optional trailing.
  static Widget row({
    Key? key,
    required IconData icon,
    required String name,
    String? address,
    Widget? trailing,
    VoidCallback? onTap,
    bool divider = true,
  }) => InkWell(
    key: key,
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 72),
      decoration: divider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: hairline)),
            )
          : null,
      child: Row(
        children: [
          Icon(icon, color: ink, size: 22, weight: 300),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text(),
                ),
                if (address != null && address.isNotEmpty)
                  Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text(size: 13, color: muted),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    ),
  );
}
