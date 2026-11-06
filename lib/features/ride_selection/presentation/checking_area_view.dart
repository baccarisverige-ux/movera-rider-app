import 'package:flutter/material.dart';
import 'package:movera_rider/core/config/rider_zones_controller.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// L-a R1/R3 (owner Q5 A, 2026-11-06): a live build before the server has
/// said where Movera runs. "Checking your area…" with no sample zones and no
/// price; when the read fails, a clear message with Retry instead of an
/// endless wait. Rebuilds with [zones].
class CheckingAreaView extends StatelessWidget {
  const CheckingAreaView({super.key, required this.zones});

  final RiderZonesController zones;

  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _accent = Color(0xFF2D5878);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: zones,
      builder: (context, _) {
        final failed = zones.failed;
        return Scaffold(
          key: const ValueKey('checking-area'),
          backgroundColor: const Color(0xFFF6F5F1),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: l10n.back,
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back, color: _ink),
                    ),
                  ),
                  const Spacer(),
                  Center(
                    child: failed
                        ? const Icon(
                            Icons.cloud_off_outlined,
                            size: 48,
                            color: _accent,
                          )
                        : const SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(color: _accent),
                          ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    failed
                        ? l10n.checkingYourAreaFailed
                        : l10n.checkingYourArea,
                    key: ValueKey(
                      failed ? 'checking-area-failed' : 'checking-area-text',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: failed ? 17 : 20,
                      fontWeight: failed ? FontWeight.w500 : FontWeight.w600,
                      color: failed ? _muted : _ink,
                    ),
                  ),
                  if (failed) ...[
                    const SizedBox(height: 20),
                    Center(
                      child: FilledButton(
                        key: const ValueKey('checking-area-retry'),
                        style: FilledButton.styleFrom(backgroundColor: _accent),
                        onPressed: zones.retry,
                        child: Text(l10n.checkingYourAreaRetry),
                      ),
                    ),
                  ],
                  const Spacer(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
