import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colours and type for the sign-in flow ("Moving to a new era").
///
/// Owner round 3, "ink and green": black text and buttons on white and the
/// cool pale ground; green only for "era", the accent word of a headline
/// and the resend timer. Kept local to the auth feature so the rest of the
/// app's theme is untouched.
abstract final class AuthColors {
  static const ground = Color(0xFFEEF1E8);

  /// The sign-in black: text, the wordmark, buttons, the pin.
  static const ink = Color(0xFF111214);
  static const muted = Color(0xFF65716B);
  // UI-6: was 0xFF89948E (3.14:1 on white); now ≥ 4.5:1 on [ground].
  static const faint = Color(0xFF676F6B);
  static const green = Color(0xFF147A50);
  static const deepGreen = Color(0xFF123F32);
  static const field = Color(0xFFF1F4F2);
  static const line = Color(0xFFE1E7E3);

  /// Underline of a resting input.
  static const underline = Color(0xFFD5DCD7);
  static const stepIdle = Color(0xFFDDE5DF);
  static const stepDone = Color(0xFF9BBEAA);

  /// Quiet grey for notes and chips (was a green tint).
  static const noteGround = Color(0xFFF3F4F5);
  static const noteText = Color(0xFF3A3F3C);
  static const error = Color(0xFFB3261E);

  /// A disabled primary button: the same black, very light.
  static const disabled = Color(0xFFF0F0F1);
  static const disabledText = Color(0xFFA6A7A9);
}

abstract final class AuthText {
  static TextStyle headline(double size) => GoogleFonts.urbanist(
    fontSize: size,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.1,
    color: AuthColors.ink,
  );

  static TextStyle lede() =>
      GoogleFonts.urbanist(fontSize: 15, height: 1.45, color: AuthColors.muted);

  static TextStyle cardTitle() => GoogleFonts.urbanist(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: AuthColors.ink,
  );

  static TextStyle cardSub() => GoogleFonts.urbanist(
    fontSize: 13.5,
    height: 1.4,
    color: AuthColors.muted,
  );

  static TextStyle label() => GoogleFonts.urbanist(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: AuthColors.ink,
  );

  static TextStyle input() => GoogleFonts.urbanist(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AuthColors.ink,
  );

  static TextStyle small() =>
      GoogleFonts.urbanist(fontSize: 12, height: 1.45, color: AuthColors.faint);

  /// Body text in the sign-in font, for the few places that style inline.
  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = AuthColors.ink,
    double? height,
  }) => GoogleFonts.urbanist(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
  );
}
