import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/legal/rider_legal.dart';

const Color kAccountInk = Color(0xFF1C2329);
// UI-6: was 0xFF7A858E (3.77:1 on white); now ≥ 4.5:1 on kAccountSoft.
const Color kAccountMuted = Color(0xFF687179);
const Color kAccountLine = Color(0xFFE8EBED);
const Color kAccountSoft = Color(0xFFF3F5F6);
const Color kAccountCta = Color(0xFF11181D);
const Color kAccountAccent = Color(0xFF2D5878);
const Color kAccountIcon = Color(0xFF3A4550);

TextStyle accountText(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = kAccountInk,
  double? height,
  double? letterSpacing,
}) {
  return GoogleFonts.poppins(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

class AccountScaffold extends StatelessWidget {
  const AccountScaffold({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAccountSoft,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    // maybePop: a page can hold Back while it is busy.
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: kAccountInk,
                    ),
                    tooltip: context.l10n.back,
                  ),
                  if (title != null)
                    Expanded(
                      child: Text(
                        title!,
                        style: accountText(17, weight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class AccountIcon extends StatelessWidget {
  const AccountIcon(this.icon, {super.key}) : asset = null;

  /// A Solar linear icon shipped as an SVG asset, same size and colour.
  const AccountIcon.asset(this.asset, {super.key}) : icon = null;

  final IconData? icon;
  final String? asset;

  @override
  Widget build(BuildContext context) {
    final asset = this.asset;
    if (asset != null) {
      return AppIconAsset(asset, size: 22, color: kAccountIcon);
    }
    return Icon(icon, size: 22, color: kAccountIcon);
  }
}

class AccountHeadline extends StatelessWidget {
  const AccountHeadline(this.title, {super.key, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: accountText(
              32,
              weight: FontWeight.w700,
              letterSpacing: -0.7,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body!,
              style: accountText(15, color: kAccountMuted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class AccountGroup extends StatelessWidget {
  const AccountGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class AccountTile extends StatelessWidget {
  const AccountTile({
    super.key,
    required this.title,
    this.body,
    this.mark,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.showDivider = true,
  });

  final String title;
  final String? body;
  final Widget? mark;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PointerInterceptor(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              child: Row(
                children: [
                  if (mark != null)
                    SizedBox(width: 26, height: 26, child: mark),
                  if (mark != null) const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: accountText(
                            16,
                            weight: FontWeight.w500,
                            color: danger
                                ? const Color(0xFFB42318)
                                : kAccountInk,
                          ),
                        ),
                        if (body != null && body!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            body!,
                            style: accountText(
                              13,
                              color: kAccountMuted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing ??
                      (onTap == null
                          ? const SizedBox.shrink()
                          : const Icon(
                              Icons.chevron_right_rounded,
                              color: kAccountMuted,
                            )),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 60, color: kAccountLine),
      ],
    );
  }
}

class AccountHero extends StatelessWidget {
  const AccountHero({super.key, required this.asset, this.height = 108});

  final String asset;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        excludeFromSemantics: true,
        asset,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => const SizedBox(height: 40),
      ),
    );
  }
}

class AccountFillButton extends StatelessWidget {
  const AccountFillButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: Material(
          color: kAccountCta,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Center(
              child: Text(
                label,
                style: accountText(
                  15,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-field editor sheet. With [emptyError] set, an empty value is not
/// saved and that message shows under the field instead (Q3). The
/// keyboard's Done key saves, like the Save button.
Future<String?> showAccountTextEditor(
  BuildContext context, {
  required String title,
  required String value,
  TextInputType keyboard = TextInputType.text,
  String? emptyError,
  int? maxLength,
}) {
  final controller = TextEditingController(text: value);
  final error = ValueNotifier<String?>(null);
  return MoveraSheet.show<String>(
    context: context,
    builder: (context) {
      return MoveraSheetDisposables(
        disposables: [controller, error],
        child: ValueListenableBuilder<String?>(
          valueListenable: error,
          builder: (context, errorText, _) {
            void save() {
              final text = controller.text.trim();
              if (text.isEmpty && emptyError != null) {
                error.value = emptyError;
                return;
              }
              Navigator.pop(context, text);
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: accountText(22, weight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    keyboardType: keyboard,
                    inputFormatters: [
                      if (maxLength != null)
                        LengthLimitingTextInputFormatter(maxLength),
                    ],
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => save(),
                    onChanged: (_) => error.value = null,
                    style: accountText(16),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: kAccountSoft,
                      errorText: errorText,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AccountFillButton(label: context.l10n.save, onTap: save),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

Future<String?> showAccountChoice(
  BuildContext context, {
  required String title,
  required List<String> options,
  required String selected,
  String Function(String option)? labelOf,
}) {
  return MoveraSheet.show<String>(
    context: context,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          8,
          12,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Text(
                title,
                style: accountText(22, weight: FontWeight.w700),
              ),
            ),
            for (final option in options)
              ListTile(
                // rider-u151: the current option is selected for screen
                // readers too, not only marked with the check.
                selected: option == selected,
                selectedColor: kAccountAccent,
                title: Text(
                  labelOf?.call(option) ?? option,
                  style: accountText(15.5, weight: FontWeight.w600),
                ),
                trailing: option == selected
                    ? const Icon(Icons.check_rounded, color: kAccountAccent)
                    : null,
                onTap: () => Navigator.pop(context, option),
              ),
          ],
        ),
      );
    },
  );
}

class AccountLegalPage extends StatefulWidget {
  const AccountLegalPage({super.key, required this.kind, this.legal});

  final String kind;

  /// Contract v0.18.5 `legal` (owner G1-B2 "Real texts from admin"): the
  /// texts of `GET /legal/{country}`. Default: the app's own controller.
  final RiderLegalController? legal;

  /// The sections of the Terms or the Privacy notice (owner round 3: the
  /// full texts, written from what the app does; company details in square
  /// brackets are filled in before launch).
  static List<LegalSection> sections(
    AppLocalizations l, {
    required bool terms,
  }) {
    if (terms) {
      return [
        LegalSection(l.termsS1Title, l.termsS1Body),
        LegalSection(l.termsS2Title, l.termsS2Body),
        LegalSection(l.termsS3Title, l.termsS3Body),
        LegalSection(l.termsS4Title, l.termsS4Body),
        LegalSection(l.termsS5Title, l.termsS5Body),
        LegalSection(l.termsS6Title, l.termsS6Body),
        LegalSection(l.termsS7Title, l.termsS7Body),
        LegalSection(l.termsS8Title, l.termsS8Body),
        LegalSection(l.termsS9Title, l.termsS9Body),
        LegalSection(l.termsS10Title, l.termsS10Body),
        LegalSection(l.termsS11Title, l.termsS11Body),
        LegalSection(l.termsS12Title, l.termsS12Body),
        // Contract v0.16.0 (owner 2026-10-29): crash reports are automatic.
        LegalSection(l.termsS14Title, l.termsS14Body),
        LegalSection(l.termsS13Title, l.termsS13Body),
      ];
    }
    return [
      LegalSection(l.privacyS1Title, l.privacyS1Body),
      LegalSection(l.privacyS2Title, l.privacyS2Body),
      LegalSection(l.privacyS3Title, l.privacyS3Body),
      LegalSection(l.privacyS4Title, l.privacyS4Body),
      LegalSection(l.privacyS5Title, l.privacyS5Body),
      LegalSection(l.privacyS6Title, l.privacyS6Body),
      LegalSection(l.privacyS7Title, l.privacyS7Body),
      LegalSection(l.privacyS8Title, l.privacyS8Body),
      LegalSection(l.privacyS9Title, l.privacyS9Body),
      LegalSection(l.privacyS10Title, l.privacyS10Body),
      LegalSection(l.privacyS11Title, l.privacyS11Body),
      LegalSection(l.privacyS12Title, l.privacyS12Body),
    ];
  }

  @override
  State<AccountLegalPage> createState() => _AccountLegalPageState();
}

class _AccountLegalPageState extends State<AccountLegalPage> {
  late final RiderLegalController _legal =
      widget.legal ?? AppScope.instance.legal;

  @override
  void initState() {
    super.initState();
    // The texts may have changed since the last read.
    if (_legal.api != null) unawaited(_legal.load());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _legal,
      builder: (context, _) {
        final texts = _legal.texts;
        if (texts != null) return _server(context, texts);
        // The demo (no server) keeps its built-in sample texts.
        if (_legal.api == null) return _builtIn(context);
        return AccountScaffold(
          child: Center(
            child: _legal.failed
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.l10n.apiUnreachable,
                          key: const ValueKey('legal-failed'),
                          textAlign: TextAlign.center,
                          style: accountText(15, color: kAccountMuted),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => unawaited(_legal.load()),
                          child: Text(context.l10n.tryAgain),
                        ),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(),
          ),
        );
      },
    );
  }

  /// The server's texts: title, then the paragraphs (blank-line separated).
  Widget _server(BuildContext context, LegalTexts texts) {
    final doc = texts.of(widget.kind);
    final code = L10n.code;
    return AccountScaffold(
      child: ListView(
        key: const ValueKey('legal-server-text'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          AccountHeadline(doc.titleIn(code)),
          for (final paragraph in doc.paragraphsIn(code)) ...[
            const SizedBox(height: 14),
            Text(
              paragraph,
              style: accountText(15, color: kAccountMuted, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _builtIn(BuildContext context) {
    final kind = widget.kind;
    final terms = kind == 'terms';
    final l = context.l10n;
    return AccountScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          AccountHeadline(
            terms ? l.accountTerms : l.accountPrivacyNotice,
            body: terms ? l.legalTermsBody : l.legalPrivacyBody,
          ),
          const SizedBox(height: 8),
          Text(
            l.legalUpdatedOn,
            style: accountText(
              12.5,
              color: kAccountMuted,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            terms ? l.legalTermsIntro : l.legalPrivacyIntro,
            style: accountText(15, color: kAccountMuted, height: 1.5),
          ),
          for (final (i, section) in AccountLegalPage.sections(
            l,
            terms: terms,
          ).indexed) ...[
            const SizedBox(height: 22),
            Semantics(
              header: true,
              child: Text(
                '${i + 1}. ${section.title}',
                style: accountText(16, weight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              section.body,
              style: accountText(15, color: kAccountMuted, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// One numbered part of a legal text.
class LegalSection {
  const LegalSection(this.title, this.body);

  final String title;
  final String body;
}
