import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/profile/application/app_language_controller.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Owner decision 7: the globe in the sign-in screens' top corner. Opens
/// a small sheet of the app languages, each in its own name.
///
/// Owner round 3: an ink outline globe with the current language as two
/// letters beside it and a small chevron underneath, so it reads as a
/// control. Redraws when the language changes.
///
/// It changes the language through the app's [AppLanguageController], the
/// same choice and device storage Account > Language uses, so the screen
/// redraws at once and the choice is kept. The list is the controller's
/// languages (rider-u153: the zone's `languages.available`; the controller
/// loads the zone of the last fix at start, and all three languages when no
/// zone config says otherwise). No profile write: there is no session yet.
class AuthLanguageButton extends StatelessWidget {
  const AuthLanguageButton({super.key, this.language});

  final AppLanguageController? language;

  @override
  Widget build(BuildContext context) {
    final controller = language ?? AppScope.instance.language;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Tooltip(
        message: context.l10n.changeLanguage,
        child: Semantics(
          button: true,
          label: context.l10n.changeLanguage,
          value: controller.language.name,
          onTap: () => showAuthLanguageSheet(context, language: controller),
          excludeSemantics: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showAuthLanguageSheet(context, language: controller),
              child: SizedBox(
                key: const ValueKey('auth-language'),
                width: 56,
                height: 48,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CustomPaint(
                          size: Size(20, 20),
                          painter: _GlobePainter(),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          controller.code.toUpperCase(),
                          style: AuthText.body(
                            size: 12,
                            weight: FontWeight.w700,
                          ).copyWith(height: 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    const Icon(
                      Icons.expand_more_rounded,
                      size: 13,
                      color: AuthColors.ink,
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

/// A plain ink globe: circle, equator, meridian and one ellipse.
class _GlobePainter extends CustomPainter {
  const _GlobePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final ink = Paint()
      ..color = AuthColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r - 0.75, ink);
    canvas.drawLine(Offset(0.75, r), Offset(size.width - 0.75, r), ink);
    canvas.drawLine(Offset(r, 0.75), Offset(r, size.height - 0.75), ink);
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 0.95, height: size.height - 1.5),
      ink,
    );
  }

  @override
  bool shouldRepaint(_GlobePainter oldDelegate) => false;
}

Future<void> showAuthLanguageSheet(
  BuildContext context, {
  required AppLanguageController language,
}) async {
  final next = await MoveraSheet.show<String>(
    context: context,
    builder: (sheet) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AuthColors.stepIdle,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Semantics(
                header: true,
                child: Text(sheet.l10n.language, style: AuthText.cardTitle()),
              ),
            ),
            for (final code in language.available)
              _LanguageRow(
                code: code,
                selected: code == language.code,
                onTap: () => Navigator.of(sheet).pop(code),
              ),
          ],
        ),
      ),
    ),
  );
  if (next == null || next == language.code) return;
  await language.choose(next);
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.code,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = L10n.languageOf(code).name;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('auth-language-$code'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: selected
              ? BoxDecoration(
                  color: AuthColors.noteGround,
                  borderRadius: BorderRadius.circular(14),
                )
              : null,
          child: Row(
            children: [
              Container(
                width: 34,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: AuthColors.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  code.toUpperCase(),
                  style: AuthText.body(
                    size: 11,
                    weight: FontWeight.w600,
                    color: AuthColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name,
                  style: AuthText.body(
                    size: 15,
                    weight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: AuthColors.green,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
