import 'package:flutter/material.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';

/// Contract v0.18.144 (`contract.json#liveLocation.adjustPickup`; approved
/// mockup screen 6): "You're 120 m from your pickup — Move the pickup to
/// where you are now? [Adjust pickup]". Shown on the searching screen and
/// while the driver comes; [onClose] hides it for this pickup.
class AdjustPickupBanner extends StatelessWidget {
  const AdjustPickupBanner({
    super.key,
    required this.meters,
    required this.onAdjust,
    required this.onClose,
    this.busy = false,
  });

  final int meters;
  final VoidCallback onAdjust;
  final VoidCallback onClose;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const Key('adjust-pickup-banner'),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2F8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: MoveraTokens.accent.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.place_rounded, color: MoveraTokens.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.liveAdjustPickupTitle('$meters'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: MoveraTokens.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.liveAdjustPickupBody,
                    style: const TextStyle(color: MoveraTokens.muted),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('adjust-pickup-button'),
                    onPressed: busy ? null : onAdjust,
                    child: Text(l10n.liveAdjustPickupButton),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('adjust-pickup-close'),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, color: MoveraTokens.muted),
            ),
          ],
        ),
      ),
    );
  }
}
