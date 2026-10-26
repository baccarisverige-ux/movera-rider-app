import 'package:flutter/material.dart';
import 'package:movera_rider/features/safety/presentation/safety_marks.dart';
import 'package:movera_rider/features/safety/presentation/safety_ui.dart';
import 'package:movera_rider/l10n/l10n.dart';

class HowMoveraProtectsPage extends StatelessWidget {
  const HowMoveraProtectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = [
      (l10n.safetyPinTitle, l10n.protectPinBody),
      (l10n.safetyContactsTitle, l10n.protectContactsBody),
      (l10n.protectSharingTitle, l10n.protectSharingBody),
      (l10n.rideCheckTitle, l10n.protectRideCheckBody),
      (l10n.protectMaskedTitle, l10n.protectMaskedBody),
    ];
    return SafetyScaffold(
      title: l10n.safetyProtectsTitle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Center(child: SafetyMark(SafetyMarks.protect, size: 96)),
          const SizedBox(height: 16),
          Text(
            l10n.safetyProtectsSubtitle,
            textAlign: TextAlign.center,
            style: SafetyUi.text(15, color: SafetyUi.muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: SafetyUi.cardDecoration(),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[i].$1,
                          style: SafetyUi.text(16, weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          items[i].$2,
                          style: SafetyUi.text(
                            13.5,
                            color: SafetyUi.muted,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i != items.length - 1)
                    const Divider(height: 1, color: SafetyUi.line),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
