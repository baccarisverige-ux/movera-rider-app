import 'package:flutter/material.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

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
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: kAccountInk,
                    ),
                    tooltip: 'Back',
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
                  AccountFillButton(label: 'Save', onTap: save),
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
                title: Text(
                  option,
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

class AccountLegalPage extends StatelessWidget {
  const AccountLegalPage({super.key, required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final terms = kind == 'terms';
    return AccountScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          AccountHeadline(
            terms ? 'Terms' : 'Privacy notice',
            body: terms
                ? 'How Movera rides and reservations work.'
                : 'What we keep, and how you control it.',
          ),
          const SizedBox(height: 20),
          Text(
            terms
                ? 'Book now and scheduled rides are separate. A reservation keeps the same ID if you edit it. Cancel before pickup according to the waiting window on the reservation.'
                : 'Movera stores the name, phone, email, and places you save so we can run your trips. You can change communication preferences any time. Location is used for pickup, tracking, and safety tools while a ride is active.',
            style: accountText(15, color: kAccountMuted, height: 1.5),
          ),
          const SizedBox(height: 16),
          // FLOW-16: these paragraphs are a summary, not the legal text.
          Text(
            terms
                ? 'This is a short summary. The full Movera terms will be '
                      'published here before the service launches.'
                : 'This is a short summary. The full Movera privacy notice '
                      'will be published here before the service launches.',
            style: accountText(13, color: kAccountMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
