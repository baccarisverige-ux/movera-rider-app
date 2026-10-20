import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';

/// Bouton principal compatible Ocean Premium et Eco Chic.
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
                    colors: [AuthColors.green, AuthColors.deepGreen],
                  )
                : null,
            color: active ? null : AuthColors.disabled,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AuthColors.deepGreen.withValues(alpha: 0.22),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
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
                            style: GoogleFonts.poppins(
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

/// Boutons de connexion Apple et Google.
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
    return Semantics(
      button: true,
      enabled: onPressed != null && !busy,
      label: 'Continue with $label',
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
                        color: AuthColors.deepGreen,
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
                              style: GoogleFonts.poppins(
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

/// Conteneur des champs avec bordures adaptées au thème.
class AuthInputShell extends StatefulWidget {
  const AuthInputShell({
    super.key,
    required this.focusNode,
    required this.child,
    this.leading,
    this.hasError = false,
  });

  final FocusNode focusNode;
  final Widget child;
  final Widget? leading;
  final bool hasError;

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

    final borderColor = widget.hasError
        ? AuthColors.error
        : focused
        ? AuthColors.deepGreen
        : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: focused || widget.hasError ? Colors.white : AuthColors.field,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: AuthColors.green.withValues(alpha: 0.14),
                  spreadRadius: 4,
                ),
              ]
            : null,
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

/// Champ téléphone France / Suède.
class AuthPhoneField extends StatelessWidget {
  const AuthPhoneField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onSubmitted,
    this.hasError = false,
    this.autofocus = false,
    this.countryCode = 'SE',
    this.onCountryChanged,
  });

  final String countryCode;
  final ValueChanged<String>? onCountryChanged;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onSubmitted;
  final bool hasError;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return AuthInputShell(
      focusNode: focusNode,
      hasError: hasError,
      leading: Container(
        padding: const EdgeInsets.only(right: 12),
        margin: const EdgeInsets.only(right: 12),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AuthColors.line)),
        ),
        child: Row(
          children: [
            PopupMenuButton<String>(
              tooltip: 'Choose country',
              onSelected: onCountryChanged,
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'FR', child: Text('🇫🇷 France  +33')),
                PopupMenuItem(value: 'SE', child: Text('🇸🇪 Sweden  +46')),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  countryCode == 'FR'
                      ? const Text('🇫🇷', style: TextStyle(fontSize: 20))
                      : const _SwedishFlag(),
                  const SizedBox(width: 8),
                  Text(
                    countryCode == 'FR' ? '+33' : '+46',
                    style: AuthText.input(),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.telephoneNumberNational],
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
          LengthLimitingTextInputFormatter(14),
        ],
        onSubmitted: onSubmitted,
        style: AuthText.input().copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        cursorColor: AuthColors.deepGreen,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: countryCode == 'FR' ? '6 12 34 56 78' : '70 123 45 67',
          hintStyle: AuthText.input().copyWith(
            color: AuthColors.faint,
            fontWeight: FontWeight.w400,
          ),
          semanticCounterText: '',
        ),
      ),
    );
  }
}

/// Drapeau suédois.
class _SwedishFlag extends StatelessWidget {
  const _SwedishFlag();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sweden',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          width: 22,
          height: 14,
          child: CustomPaint(painter: _SwedishFlagPainter()),
        ),
      ),
    );
  }
}

class _SwedishFlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF006AA7),
    );

    final yellow = Paint()..color = const Color(0xFFFECC00);

    canvas.drawRect(Rect.fromLTWH(w * 5 / 16, 0, w * 2 / 16, h), yellow);

    canvas.drawRect(Rect.fromLTWH(0, h * 0.4, w, h * 0.2), yellow);
  }

  @override
  bool shouldRepaint(_SwedishFlagPainter oldDelegate) => false;
}

/// Champ texte pour prénom, nom, etc.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofillHints,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

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
        inputFormatters: [LengthLimitingTextInputFormatter(40)],
        style: AuthText.input(),
        cursorColor: AuthColors.deepGreen,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: AuthText.input().copyWith(
            color: AuthColors.faint,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Note d'information avec accent du thème.
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
          Icon(icon, size: 18, color: AuthColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
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

/// Message d'erreur accessible.
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
                style: GoogleFonts.poppins(
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

/// Séparateur entre connexion téléphone et Apple / Google.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AuthColors.line, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or continue with', style: AuthText.small()),
        ),
        const Expanded(child: Divider(color: AuthColors.line, height: 1)),
      ],
    );
  }
}
