import 'package:flutter/material.dart';

/// A saved card's brand named as text (owner branding rule: no other
/// company's logo; Visa/Mastercard are written, not drawn).
class CardBrandLabel extends StatelessWidget {
  const CardBrandLabel(this.brand, {super.key, this.color});

  /// The card brand id, e.g. `visa` or `mastercard`.
  final String brand;
  final Color? color;

  static String nameOf(String brand) => switch (brand.toLowerCase()) {
    'mastercard' => 'Mastercard',
    'visa' => 'Visa',
    _ => brand.isEmpty ? '' : brand[0].toUpperCase() + brand.substring(1),
  };

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        nameOf(brand),
        maxLines: 1,
        style: TextStyle(
          color: color ?? const Color(0xFF11181D),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
