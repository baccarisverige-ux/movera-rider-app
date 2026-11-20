import 'package:flutter/material.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/presentation/safety_ui.dart';
import 'package:movera_rider/shared/design_system/adaptive_switch_colors.dart';
import 'package:movera_rider/l10n/l10n.dart';

class PinVerificationPage extends StatefulWidget {
  const PinVerificationPage({super.key, required this.controller});
  final SafetyController controller;

  @override
  State<PinVerificationPage> createState() => _PinVerificationPageState();
}

class _PinVerificationPageState extends State<PinVerificationPage> {
  SafetyController get _ctl => widget.controller;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onChange);
  }

  @override
  void dispose() {
    _ctl.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmRotate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SafetyUi.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            context.l10n.pinChangeQ,
            style: SafetyUi.text(18, weight: FontWeight.w600),
          ),
          content: Text(
            context.l10n.pinChangeBody,
            style: SafetyUi.text(14, color: SafetyUi.muted, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                context.l10n.cancel,
                style: SafetyUi.text(14, color: SafetyUi.muted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                context.l10n.pinChange,
                style: SafetyUi.text(
                  14,
                  color: SafetyUi.accent,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (ok == true && mounted) {
      await runSafetyChange(context, _ctl, _ctl.rotatePin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = _ctl.pin.pin;
    return SafetyScaffold(
      title: context.l10n.safetyPinTitle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(
            context.l10n.pinIntro,
            style: SafetyUi.text(15, color: SafetyUi.muted, height: 1.45),
          ),
          const SizedBox(height: 22),
          // R4 (owner 2026-11-20): on movera-server the PIN check before
          // Start is switched on per area by Movera (admin, per zone; owner
          // 2026-11-01), not by the rider. The switch here could only fail
          // ("Could not update PIN verification."); the page now says how
          // it works instead. The switch stays where the rider's own
          // setting is served (demo and test builds).
          if (!_ctl.serverKeepsSettings)
            Container(
              key: const ValueKey<String>('pin-decided-by-area'),
              decoration: SafetyUi.cardDecoration(),
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.pinDecidedByArea,
                      style: SafetyUi.text(14.5, height: 1.45),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              decoration: SafetyUi.cardDecoration(),
              padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.pinToggle,
                      style: SafetyUi.text(15.5, weight: FontWeight.w500),
                    ),
                  ),
                  Switch.adaptive(
                    value: _ctl.preferences.pinRequired,
                    activeThumbColor: adaptiveSwitchThumbColor(
                      context,
                      SafetyUi.accent,
                    ),
                    activeTrackColor: adaptiveSwitchTrackColor(
                      context,
                      SafetyUi.accent,
                    ),
                    onChanged: (value) => runSafetyChange(
                      context,
                      _ctl,
                      () => _ctl.setPinRequired(value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (_ctl.loading || !_ctl.hasLoaded)
              const Center(child: CircularProgressIndicator())
            else if (_ctl.pin.isAvailable)
              SafetyPinCadre(
                pin: pin,
                caption: _ctl.preferences.pinRequired
                    ? context.l10n.pinShareHint
                    : context.l10n.pinSavedHint,
              )
            else
              Text(
                context.l10n.pinUnavailable,
                style: SafetyUi.text(14, color: SafetyUi.muted),
              ),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _confirmRotate,
                style: OutlinedButton.styleFrom(
                  foregroundColor: SafetyUi.ink,
                  side: const BorderSide(color: SafetyUi.line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  context.l10n.pinChange,
                  style: SafetyUi.text(15.5, weight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
