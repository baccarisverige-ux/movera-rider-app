import 'package:flutter/material.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/support/domain/support_details.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// A small "Need help?" before sign-in (owner 2026-10-29: "It's not help
/// page !! It's only written need help ? When clic user can see info").
/// A tap shows a small box with Movera's support e-mail, phone and company
/// details, or "Contact details coming soon" while they are not filled in.
class NeedHelpLink extends StatelessWidget {
  const NeedHelpLink({super.key, this.details = moveraSupportDetails});

  final SupportDetails details;

  void _show(BuildContext context) {
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('auth-need-help-box'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(l10n.authNeedHelp, style: AuthText.cardTitle()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: details.isEmpty
              ? [
                  Text(
                    l10n.authHelpComingSoon,
                    key: const ValueKey('auth-need-help-soon'),
                    style: AuthText.cardSub(),
                  ),
                ]
              : [
                  if (details.email.trim().isNotEmpty)
                    _row(l10n.email, details.email.trim()),
                  if (details.phone.trim().isNotEmpty)
                    _row(l10n.phone, details.phone.trim()),
                  if (details.company.trim().isNotEmpty)
                    _row(l10n.authHelpCompany, details.company.trim()),
                ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('auth-need-help-close'),
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: AuthColors.ink),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  static Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AuthText.label()),
        SelectableText(value, style: AuthText.input()),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      key: const ValueKey('auth-need-help'),
      onPressed: () => _show(context),
      style: TextButton.styleFrom(
        foregroundColor: AuthColors.muted,
        minimumSize: const Size(0, 36),
      ),
      child: Text(
        context.l10n.authNeedHelp,
        style: AuthText.body(
          size: 13,
          weight: FontWeight.w600,
          color: AuthColors.muted,
        ),
      ),
    ),
  );
}
