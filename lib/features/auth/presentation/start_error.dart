import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
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
    this.supportBuilder,
  });

  final VoidCallback onRetry;
  final VoidCallback onSignedOut;

  /// Null: the app's controller.
  final AuthController? auth;

  /// "Contact support" opens the in-app support messages (owner
  /// 2026-10-29: "Open the in-app support chat"); null: SupportMessages.
  final Widget Function()? supportBuilder;

  @override
  State<StartError> createState() => _StartErrorState();
}

class _StartErrorState extends State<StartError> {
  bool _signingOut = false;

  void _contact() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => widget.supportBuilder?.call() ?? const SupportMessages(),
    ),
  );

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
            ],
          ),
        ),
      ),
    );
  }
}
