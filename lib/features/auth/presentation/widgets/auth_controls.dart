import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/domain/phone_country.dart';
import 'package:movera_rider/features/auth/presentation/widgets/phone_country_picker.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Black call to action. [onPressed] null shows the disabled state: the same
/// black, very light (owner round 3).
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.showArrow = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final active = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      // rider-u77: excludeSemantics drops the InkWell's tap action, so the
      // button carries its own for screen readers.
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: SizedBox(
        height: 56,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: active
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1C1C1E), Color(0xFF050506)],
                  )
                : null,
            color: active ? null : AuthColors.disabled,
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: enabled ? onPressed : null,
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: GoogleFonts.urbanist(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: active
                                  ? Colors.white
                                  : AuthColors.disabledText,
                            ),
                          ),
                          if (showArrow && active) ...[
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White outlined button used for Apple and Google.
class AuthProviderButton extends StatelessWidget {
  const AuthProviderButton({
    super.key,
    required this.label,
    required this.leading,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final Widget leading;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: context.l10n.continueWith(label),
      // rider-u77: see AuthPrimaryButton.
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: SizedBox(
        height: 52,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AuthColors.line),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: busy ? null : onPressed,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AuthColors.ink,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 20, height: 20, child: leading),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.urbanist(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AuthColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Underlined input (owner round 3): a thin grey line that turns ink while
/// focused and red on error. No box, no fill.
class AuthInputShell extends StatefulWidget {
  const AuthInputShell({
    super.key,
    required this.focusNode,
    required this.child,
    this.leading,
    this.hasError = false,
    this.leadingFlush = false,
  });

  final FocusNode focusNode;
  final Widget child;
  final Widget? leading;
  final bool hasError;

  /// The [leading] widget runs to the shell's left edge (a tap target
  /// with its own padding).
  final bool leadingFlush;

  @override
  State<AuthInputShell> createState() => _AuthInputShellState();
}

class _AuthInputShellState extends State<AuthInputShell> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_changed);
  }

  @override
  void didUpdateWidget(AuthInputShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_changed);
      widget.focusNode.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 52,
      padding: EdgeInsets.only(
        left: widget.leadingFlush && widget.leading != null ? 0 : 2,
        right: 2,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: authUnderlineColor(focused: focused, error: widget.hasError),
            width: focused ? 1.6 : 1.2,
          ),
        ),
      ),
      child: Row(
        children: [
          if (widget.leading != null) widget.leading!,
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

/// The underline of an input: ink while focused, red on error, grey at rest.
Color authUnderlineColor({required bool focused, required bool error}) => error
    ? AuthColors.error
    : focused
    ? AuthColors.ink
    : AuthColors.underline;

/// Keeps only the national part of a number pasted in international form.
///
/// rider-30: the field sits after the country's dial code, so a number
/// pasted as +46 70 ..., 0046 70 ... or (zone countries) 46 70 ... keeps
/// only its national part instead of getting a second dial code.
/// Owner decision 7: a pasted number of another country (+33 6 ...)
/// switches the field to that country through [onCountry].
class NationalNumberFormatter extends TextInputFormatter {
  NationalNumberFormatter({PhoneCountry? country, this.onCountry})
    : country = country ?? PhoneCountries.sweden;

  final PhoneCountry country;
  final ValueChanged<PhoneCountry>? onCountry;

  static final _international = RegExp(r'^\s*(?:\+|00)');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final digits = text.replaceAll(RegExp(r'\D'), '');
    final prefix = _international.firstMatch(text);
    PhoneCountry? dialled;
    String? national;
    if (prefix != null) {
      final rest = digits.substring(text.trimLeft().startsWith('00') ? 2 : 0);
      dialled = PhoneCountries.ofInternational(rest, preferred: country);
      // Only once the whole number is there (a paste or autofill): a lone
      // '+' being typed is dropped by the digit filter as before.
      if (dialled == null || rest.length < dialled.dial.length + 4) {
        return newValue;
      }
      national = _after(text, prefix.end, dialled.dial.length);
    } else {
      final length = mobileLengthOf(country);
      if (length == null ||
          !digits.startsWith(country.dial) ||
          digits.length < country.dial.length + length) {
        return newValue;
      }
      national = _after(text, 0, country.dial.length);
    }
    if (dialled != null && dialled.iso != country.iso) {
      final picked = dialled;
      scheduleMicrotask(() => onCountry?.call(picked));
    }
    return TextEditingValue(
      text: national,
      selection: TextSelection.collapsed(offset: national.length),
    );
  }

  /// [text] from [start] with the first [count] digits and a following
  /// "(0)" removed.
  static String _after(String text, int start, int count) {
    var i = start;
    var seen = 0;
    while (i < text.length && seen < count) {
      if (RegExp(r'\d').hasMatch(text[i])) seen++;
      i++;
    }
    return text
        .substring(i)
        .replaceFirst(RegExp(r'^\s*\(0\)\s*'), '')
        .trimLeft();
  }
}

/// The phone field: the country button (flag and dial code, opens the
/// country sheet) and the national number.
class AuthPhoneField extends StatelessWidget {
  const AuthPhoneField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.country,
    this.onCountryChanged,
    this.onSubmitted,
    this.hasError = false,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Null is Sweden.
  final PhoneCountry? country;

  /// Null shows the dial code without the picker.
  final ValueChanged<PhoneCountry>? onCountryChanged;
  final ValueChanged<String>? onSubmitted;
  final bool hasError;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final current = country ?? PhoneCountries.sweden;
    final onChanged = onCountryChanged;
    // Owner round 3: three underlined parts, like the reference design:
    // flag with a chevron, the dial code, the number.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _CountryButton(
          country: current,
          onTap: onChanged == null
              ? null
              : () async {
                  final picked = await showPhoneCountryPicker(
                    context,
                    selected: current,
                  );
                  if (picked != null && picked.iso != current.iso) {
                    onChanged(picked);
                  }
                },
        ),
        const SizedBox(width: 14),
        _Underlined(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              current.dialLabel,
              key: const ValueKey('auth-phone-dial'),
              style: AuthText.input(),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: AuthInputShell(
            focusNode: focusNode,
            hasError: hasError,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                // rider-30: before the filter drops the '+'.
                NationalNumberFormatter(country: current, onCountry: onChanged),
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                LengthLimitingTextInputFormatter(18),
              ],
              onSubmitted: onSubmitted,
              style: AuthText.input().copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              cursorColor: AuthColors.ink,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: phoneHintOf(current),
                hintStyle: AuthText.input().copyWith(
                  color: const Color(0xFF9AA79F),
                  fontWeight: FontWeight.w400,
                ),
                semanticCounterText: '',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A resting underline under a static part of the phone row.
class _Underlined extends StatelessWidget {
  const _Underlined({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AuthColors.underline, width: 1.2),
        ),
      ),
      child: child,
    );
  }
}

class _CountryButton extends StatelessWidget {
  const _CountryButton({required this.country, required this.onTap});

  final PhoneCountry country;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = country.nameIn(context.l10n.localeName);
    return Semantics(
      button: onTap != null,
      label: context.l10n.phoneCountryCode(name, country.dialLabel),
      hint: onTap == null ? null : context.l10n.changeCountryCode,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('auth-phone-country'),
          onTap: onTap,
          child: _Underlined(
            child: Container(
              constraints: const BoxConstraints(minWidth: 48),
              padding: const EdgeInsets.fromLTRB(2, 0, 6, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(country.flag, style: const TextStyle(fontSize: 22)),
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: AuthColors.muted,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain text input in the same shell (names).
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofillHints,
    this.maxLength = 40,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return AuthInputShell(
      focusNode: focusNode,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textCapitalization: TextCapitalization.words,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        onSubmitted: onSubmitted,
        inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
        style: AuthText.input(),
        cursorColor: AuthColors.ink,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: AuthText.input().copyWith(
            color: const Color(0xFF9AA79F),
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Quiet grey note with an icon, for reassurance copy.
class AuthNote extends StatelessWidget {
  const AuthNote({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AuthColors.noteGround,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AuthColors.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.urbanist(
                fontSize: 12.5,
                height: 1.4,
                color: AuthColors.noteText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline error under a control. Announced to screen readers when it appears.
class AuthErrorText extends StatelessWidget {
  const AuthErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.error_outline_rounded,
                size: 16,
                color: AuthColors.error,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.urbanist(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AuthColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "or continue with" divider.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFE4EAE5), height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(context.l10n.orContinueWith, style: AuthText.small()),
        ),
        const Expanded(child: Divider(color: Color(0xFFE4EAE5), height: 1)),
      ],
    );
  }
}
