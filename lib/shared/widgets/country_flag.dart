import 'package:flutter/material.dart';

/// A small country flag picture (owner 2026-11-03, LT-3: "small flag
/// pictures instead of emoji"). The emoji flags made the web app download
/// a 700 kB colour-emoji font at start; these are tiny PNGs in
/// assets/flags/ (from the MIT-licensed flag-icons set), loaded only when a
/// flag is on screen. A code without a picture shows its two letters.
class CountryFlag extends StatelessWidget {
  const CountryFlag(this.iso, {super.key, this.width = 24});

  /// ISO 3166-1 alpha-2 (`SE`), any case.
  final String iso;

  /// Width in logical pixels; the flag is 4:3.
  final double width;

  /// The asset path of [iso]'s flag.
  static String assetOf(String iso) =>
      'assets/flags/${iso.trim().toLowerCase()}.png';

  @override
  Widget build(BuildContext context) {
    final height = width * 3 / 4;
    return Semantics(
      label: iso.toUpperCase(),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Image.asset(
          assetOf(iso),
          key: ValueKey('country-flag-${iso.toUpperCase()}'),
          width: width,
          height: height,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => SizedBox(
            width: width,
            height: height,
            child: Center(
              child: Text(
                iso.toUpperCase(),
                style: TextStyle(fontSize: height * 0.6, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
