import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AuthColors {
  // Choix du thème au démarrage de Flutter.
  // Valeurs possibles : ocean ou eco.
  static const String theme = String.fromEnvironment(
    'MOVERA_AUTH_THEME',
    defaultValue: 'ocean',
  );

  static const bool isOcean = theme != 'eco';

  // 1 — OCEAN PREMIUM : bleu nuit, bleu et turquoise
  // 2 — ECO CHIC : crème, sauge et vert forêt

  static const Color ground = isOcean
      ? Color(0xFFF2FAF9)
      : Color(0xFFF6F4EE);

  static const Color ink = isOcean
      ? Color(0xFF061B44)
      : Color(0xFF164B40);

  static const Color muted = isOcean
      ? Color(0xFF526777)
      : Color(0xFF526B60);

  static const Color faint = isOcean
      ? Color(0xFF536772)
      : Color(0xFF586C60);

  static const Color green = isOcean
      ? Color(0xFF1DA298)
      : Color(0xFF48AA8C);

  static const Color deepGreen = isOcean
      ? Color(0xFF117C74)
      : Color(0xFF164B40);

  static const Color field = isOcean
      ? Color(0xFFEAF3F8)
      : Color(0xFFF1F5F0);

  static const Color line = isOcean
      ? Color(0xFFD0E4E7)
      : Color(0xFFD8E5D9);

  static const Color stepIdle = isOcean
      ? Color(0xFFD9E9ED)
      : Color(0xFFDEE6D9);

  static const Color stepDone = isOcean
      ? Color(0xFF71C9BE)
      : Color(0xFF93C8A7);

  static const Color noteGround = isOcean
      ? Color(0xFFE6F7EF)
      : Color(0xFFEAF4EC);

  static const Color noteText = isOcean
      ? Color(0xFF17635D)
      : Color(0xFF355C4A);

  static const Color error = Color(0xFFB3261E);

  static const Color disabled = isOcean
      ? Color(0xFFE1E9EC)
      : Color(0xFFE4E9E5);

  static const Color disabledText = isOcean
      ? Color(0xFF75838B)
      : Color(0xFF85958B);
}

abstract final class AuthText {
  static TextStyle headline(double size) => GoogleFonts.poppins(
        fontSize: size,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.1,
        color: AuthColors.ink,
      );

  static TextStyle lede() => GoogleFonts.poppins(
        fontSize: 15,
        height: 1.45,
        color: AuthColors.muted,
      );

  static TextStyle cardTitle() => GoogleFonts.poppins(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: AuthColors.ink,
      );

  static TextStyle cardSub() => GoogleFonts.poppins(
        fontSize: 13.5,
        height: 1.4,
        color: AuthColors.muted,
      );

  static TextStyle label() => GoogleFonts.poppins(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AuthColors.ink,
      );

  static TextStyle input() => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AuthColors.ink,
      );

  static TextStyle small() => GoogleFonts.poppins(
        fontSize: 12,
        height: 1.45,
        color: AuthColors.faint,
      );
}
