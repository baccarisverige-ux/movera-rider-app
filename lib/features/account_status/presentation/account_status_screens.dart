import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/account_status/domain/rider_moderation.dart';
import 'package:movera_rider/features/auth/presentation/sign_out_flow.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// v0.18.40 §64 (fix job 10, owner G16 Q16-1, `contract.json#blockedPairs.
/// riderLevels`): the rider's level screens. Paused: title, reason, end
/// date, Contact support, Sign out. Banned: the same without a date.
class AccountStatusScreen extends StatelessWidget {
  const AccountStatusScreen({
    super.key,
    required this.moderation,
    required this.onContactSupport,
    required this.onSignOut,
  });

  final RiderModeration moderation;
  final VoidCallback onContactSupport;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final paused = moderation.level == ModerationLevel.paused;
    final until = moderation.until;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                paused ? Icons.pause_circle_outline : Icons.block,
                size: 56,
                color: const Color(0xFFB3261E),
              ),
              const SizedBox(height: 20),
              Text(
                paused ? l10n.accountPausedTitle : l10n.accountBlockedTitle,
                key: const ValueKey('account-status-title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111111),
                ),
              ),
              if (moderation.reason case final reason?) ...[
                const SizedBox(height: 12),
                Text(
                  reason,
                  key: const ValueKey('account-status-reason'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF333333),
                  ),
                ),
              ],
              if (paused && until != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.accountPausedUntil(
                    DateFormat.yMMMd(locale).add_Hm().format(until.toLocal()),
                  ),
                  key: const ValueKey('account-status-until'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111111),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                l10n.accountStatusBody,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
              const Spacer(),
              FilledButton(
                key: const ValueKey('account-status-support'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF111111),
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: onContactSupport,
                child: Text(l10n.accountStatusContactSupport),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('account-status-sign-out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF111111),
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: onSignOut,
                child: Text(l10n.accountStatusSignOut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Warning level: the rider rides; a banner says why (closable for now).
class ModerationWarningBanner extends StatelessWidget {
  const ModerationWarningBanner({
    super.key,
    required this.moderation,
    this.onClose,
  });

  final RiderModeration moderation;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('moderation-warning'),
      color: const Color(0xFFFFF4E5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.moderationWarningTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111111),
                    ),
                  ),
                  if (moderation.reason case final reason?)
                    Text(
                      reason,
                      style: const TextStyle(color: Color(0xFF333333)),
                    ),
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
          ],
        ),
      ),
    );
  }
}

/// Puts the level over the whole app: paused / banned cover every screen;
/// a warning shows the banner on top until closed.
class ModerationGate extends StatefulWidget {
  const ModerationGate({super.key, required this.child});

  final Widget child;

  @override
  State<ModerationGate> createState() => _ModerationGateState();
}

class _ModerationGateState extends State<ModerationGate> {
  RiderModeration? _closedWarning;

  Future<void> _signOut() async {
    RiderModeration.current.value = RiderModeration.none;
    await signOutAndShowSignIn(navigator: moveraNavigatorKey.currentState);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RiderModeration>(
      valueListenable: RiderModeration.current,
      builder: (context, moderation, child) {
        if (moderation.blocksRiding) {
          // Support opens on top of the level screen (its own route).
          return Stack(
            children: [
              child!,
              // Its own navigator, so Contact support opens above it.
              Positioned.fill(
                child: Navigator(
                  key: ValueKey(moderation),
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (inner) => AccountStatusScreen(
                      moderation: moderation,
                      onContactSupport: () => Navigator.of(inner).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SupportMessages(),
                        ),
                      ),
                      onSignOut: () => _signOut(),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        if (moderation.level == ModerationLevel.warning &&
            _closedWarning != moderation) {
          return Column(
            children: [
              SafeArea(
                bottom: false,
                child: ModerationWarningBanner(
                  moderation: moderation,
                  onClose: () => setState(() => _closedWarning = moderation),
                ),
              ),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: child!,
                ),
              ),
            ],
          );
        }
        return child!;
      },
      child: widget.child,
    );
  }
}
