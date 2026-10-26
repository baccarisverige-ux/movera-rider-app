import 'package:flutter/material.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/presentation/emergency_contacts_page.dart';
import 'package:movera_rider/features/safety/presentation/how_movera_protects_page.dart';
import 'package:movera_rider/features/safety/presentation/pin_verification_page.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_page.dart';
import 'package:movera_rider/features/safety/presentation/safety_marks.dart';
import 'package:movera_rider/features/safety/presentation/safety_tips_page.dart';
import 'package:movera_rider/features/safety/presentation/safety_ui.dart';
import 'package:movera_rider/features/safety/presentation/trip_share_page.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/l10n/l10n.dart';

class SafetyHub extends StatefulWidget {
  const SafetyHub({super.key, this.controller});

  final SafetyController? controller;

  @override
  State<SafetyHub> createState() => _SafetyHubState();
}

class _SafetyHubState extends State<SafetyHub> {
  late final SafetyController _ctl;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _ctl = widget.controller ?? SafetyController.shared;
    _ctl.addListener(_onChange);
    _ctl.load();
  }

  @override
  void dispose() {
    _ctl.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _open(Widget page) async {
    if (_opening) return;
    _opening = true;
    try {
      await Navigator.push(context, RightToLeftTransition(page));
      await _ctl.load();
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafetyScaffold(
      title: context.l10n.safetyTitle,
      showTitle: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          const SizedBox(height: 8),
          const Center(child: SafetyMark(SafetyMarks.shield, size: 120)),
          const SizedBox(height: 18),
          Text(
            context.l10n.safetyTitle,
            textAlign: TextAlign.center,
            style: SafetyUi.text(
              30,
              weight: FontWeight.w600,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.safetyHubTagline,
            textAlign: TextAlign.center,
            style: SafetyUi.text(15, color: SafetyUi.muted, height: 1.4),
          ),
          const SizedBox(height: 32),
          Text(
            context.l10n.safetyPreferences,
            style: SafetyUi.text(
              13,
              weight: FontWeight.w600,
              letterSpacing: 0.4,
              color: SafetyUi.muted,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: SafetyUi.cardDecoration(),
            child: Column(
              children: [
                SafetyRow(
                  mark: SafetyMarks.pin,
                  title: context.l10n.safetyPinTitle,
                  subtitle: context.l10n.safetyPinSubtitle,
                  status: _ctl.pinStatusLabel(),
                  onTap: () => _open(PinVerificationPage(controller: _ctl)),
                ),
                SafetyRow(
                  mark: SafetyMarks.contacts,
                  title: context.l10n.safetyContactsTitle,
                  subtitle: context.l10n.safetyContactsSubtitle,
                  status: _ctl.contactsStatusLabel(),
                  onTap: () => _open(EmergencyContactsPage(controller: _ctl)),
                ),
                SafetyRow(
                  mark: SafetyMarks.share,
                  title: context.l10n.safetyShareTitle,
                  subtitle: context.l10n.safetyShareSubtitle,
                  status: _ctl.shareStatusLabel(),
                  onTap: () => _open(TripSharePage(controller: _ctl)),
                ),
                SafetyRow(
                  mark: SafetyMarks.rideCheck,
                  title: context.l10n.rideCheckTitle,
                  subtitle: context.l10n.safetyRideCheckSubtitle,
                  status: _ctl.rideCheckStatusLabel(),
                  onTap: () => _open(RideCheckPage(controller: _ctl)),
                  showDivider: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            context.l10n.safetyResources,
            style: SafetyUi.text(
              13,
              weight: FontWeight.w600,
              letterSpacing: 0.4,
              color: SafetyUi.muted,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: SafetyUi.cardDecoration(),
            child: Column(
              children: [
                SafetyRow(
                  mark: SafetyMarks.tips,
                  title: context.l10n.safetyTipsTitle,
                  subtitle: context.l10n.safetyTipsSubtitle,
                  onTap: () => _open(const SafetyTipsPage()),
                ),
                SafetyRow(
                  mark: SafetyMarks.protect,
                  title: context.l10n.safetyProtectsTitle,
                  subtitle: context.l10n.safetyProtectsSubtitle,
                  onTap: () => _open(const HowMoveraProtectsPage()),
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
