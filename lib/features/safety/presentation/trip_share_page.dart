import 'package:flutter/material.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/domain/emergency_contact.dart';
import 'package:movera_rider/features/safety/domain/safety_preferences.dart';
import 'package:movera_rider/features/safety/presentation/emergency_contacts_page.dart';
import 'package:movera_rider/features/safety/presentation/safety_marks.dart';
import 'package:movera_rider/features/safety/presentation/safety_ui.dart';
import 'package:movera_rider/shared/design_system/adaptive_switch_colors.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/l10n/l10n.dart';

class TripSharePage extends StatefulWidget {
  const TripSharePage({super.key, required this.controller});
  final SafetyController controller;

  @override
  State<TripSharePage> createState() => _TripSharePageState();
}

class _TripSharePageState extends State<TripSharePage> {
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

  /// rider-85: the selection list and the contact's "Share trips" are
  /// saved together. A failure is shown to the rider, and when only the
  /// second save fails the first is undone, so the two stay in step.
  Future<void> _setShared(EmergencyContact contact, bool value) async {
    final previous = [..._ctl.preferences.tripShareContactIds];
    final selected = [
      for (final id in previous)
        if (id != contact.id) id,
      if (value) contact.id,
    ];
    await _ctl.setTripShare(contactIds: selected);
    if (_ctl.error != null) {
      _showFailure();
      return;
    }
    try {
      await _ctl.editContact(contact.copyWith(shareTrips: value));
    } catch (_) {
      await _ctl.setTripShare(contactIds: previous);
      _showFailure();
    }
  }

  void _showFailure() {
    if (!mounted) return;
    MoveraToast.show(context, context.l10n.safetyShareUpdateFailed);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _ctl.preferences;
    final shareable = _ctl.contacts.where((c) => c.isEnabled).toList();
    return SafetyScaffold(
      title: context.l10n.safetyShareTitle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Center(child: SafetyMark(SafetyMarks.share, size: 96)),
          const SizedBox(height: 16),
          Text(
            context.l10n.shareIntro,
            textAlign: TextAlign.center,
            style: SafetyUi.text(15, color: SafetyUi.muted, height: 1.45),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: SafetyUi.cardDecoration(),
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.protectSharingTitle,
                        style: SafetyUi.text(15.5, weight: FontWeight.w500),
                      ),
                    ),
                    Switch.adaptive(
                      value: prefs.tripShareEnabled,
                      activeThumbColor: adaptiveSwitchThumbColor(
                        context,
                        SafetyUi.accent,
                      ),
                      activeTrackColor: adaptiveSwitchTrackColor(
                        context,
                        SafetyUi.accent,
                      ),
                      onChanged: (value) => _ctl.setTripShare(enabled: value),
                    ),
                  ],
                ),
                const Divider(height: 1, color: SafetyUi.line),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    context.l10n.shareAuto,
                    style: SafetyUi.text(15),
                  ),
                  subtitle: Text(
                    context.l10n.shareAutoBody,
                    style: SafetyUi.text(12.5, color: SafetyUi.muted),
                  ),
                  value: prefs.tripShareMode == TripShareMode.auto,
                  activeThumbColor: adaptiveSwitchThumbColor(
                    context,
                    SafetyUi.accent,
                  ),
                  activeTrackColor: adaptiveSwitchTrackColor(
                    context,
                    SafetyUi.accent,
                  ),
                  onChanged: prefs.tripShareEnabled
                      ? (value) => _ctl.setTripShare(
                          mode: value
                              ? TripShareMode.auto
                              : TripShareMode.manual,
                        )
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            context.l10n.shareTrusted,
            style: SafetyUi.text(16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.shareLinkNote,
            style: SafetyUi.text(13, color: SafetyUi.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: SafetyUi.cardDecoration(),
            child: shareable.isEmpty
                ? MoveraEmptyState(
                    icon: Icons.group_add_outlined,
                    title: context.l10n.shareEmptyTitle,
                    message:
                        context.l10n.shareEmptyBody,
                    actionLabel: context.l10n.shareAddContact,
                    onAction: () {
                      Navigator.push(
                        context,
                        RightToLeftTransition(
                          EmergencyContactsPage(controller: _ctl),
                        ),
                      );
                    },
                    compact: true,
                  )
                : Column(
                    children: [
                      for (var i = 0; i < shareable.length; i++)
                        Column(
                          children: [
                            CheckboxListTile(
                              value:
                                  prefs.tripShareContactIds.contains(
                                    shareable[i].id,
                                  ) ||
                                  shareable[i].shareTrips,
                              activeColor: SafetyUi.accent,
                              title: Text(
                                shareable[i].name,
                                style: SafetyUi.text(15.5),
                              ),
                              // rider-u218: as on Emergency contacts.
                              subtitle: Text(
                                relationshipLabel(shareable[i].relationship),
                                style: SafetyUi.text(
                                  12.5,
                                  color: SafetyUi.muted,
                                ),
                              ),
                              onChanged: prefs.tripShareEnabled
                                  ? (value) => _setShared(
                                      shareable[i],
                                      value == true,
                                    )
                                  : null,
                            ),
                            if (i != shareable.length - 1)
                              const Divider(height: 1, color: SafetyUi.line),
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
