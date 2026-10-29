import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/support/application/support_contact.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Owner 2026-10-29, decision 2 (the driver app's start screen, done the
/// same in the rider app): the app could not start; Try again, Sign out or
/// Contact support.
class StartError extends StatefulWidget {
  const StartError({
    super.key,
    required this.onRetry,
    required this.onSignedOut,
    this.auth,
    this.support,
  });

  final VoidCallback onRetry;
  final VoidCallback onSignedOut;

  /// Null: the app's controller.
  final AuthController? auth;

  /// Null: the build's support address (`MOVERA_SUPPORT_EMAIL`).
  final SupportContact? support;

  @override
  State<StartError> createState() => _StartErrorState();
}

class _StartErrorState extends State<StartError> {
  bool _supportFailed = false;
  bool _signingOut = false;

  Future<void> _contact() async {
    final support = widget.support ?? const SupportContact();
    final opened = await support.openEmail(
      subject: context.l10n.startCouldNotLoad,
    );
    if (mounted) setState(() => _supportFailed = !opened);
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await (widget.auth ?? AppScope.instance.auth).signOutLocally();
    } catch (_) {
      // The device forgets the session even when the store complains.
    }
    if (mounted) widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    final outline = OutlinedButton.styleFrom(
      foregroundColor: AuthColors.ink,
      side: const BorderSide(color: AuthColors.ink),
    );
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.startCouldNotLoad,
                textAlign: TextAlign.center,
                style: AuthText.cardTitle(),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.errOffline,
                textAlign: TextAlign.center,
                style: AuthText.cardSub(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey('start-retry'),
                onPressed: widget.onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AuthColors.ink,
                  foregroundColor: Colors.white,
                ),
                child: Text(context.l10n.tryAgain),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: const ValueKey('start-sign-out'),
                onPressed: _signingOut ? null : _signOut,
                style: outline,
                child: Text(context.l10n.startSignOut),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: const ValueKey('start-support'),
                onPressed: _contact,
                style: outline,
                child: Text(context.l10n.startContactSupport),
              ),
              if (_supportFailed)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    context.l10n.startSupportUnavailable,
                    key: const ValueKey('start-support-failed'),
                    textAlign: TextAlign.center,
                    style: AuthText.small(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
