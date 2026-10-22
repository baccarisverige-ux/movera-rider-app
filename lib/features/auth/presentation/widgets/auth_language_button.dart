import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/profile/application/app_language_controller.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Owner decision 7: the globe in the sign-in screens' top corner. Opens
/// a small sheet of the app languages, each in its own name.
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
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        key: const ValueKey('auth-language'),
        tooltip: context.l10n.changeLanguage,
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.language_rounded, color: AuthColors.ink, size: 22),
        onPressed: () => showAuthLanguageSheet(context, language: controller),
      ),
    );
  }
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
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AuthColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: AuthColors.ink,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded, size: 20, color: AuthColors.green),
            ],
          ),
        ),
      ),
    );
  }
}
