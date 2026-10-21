import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/presentation/safety_hub.dart';
import 'package:movera_rider/features/safety/presentation/trip_share_page.dart';
import 'package:movera_rider/features/ride_booking/application/sheet_coordinator.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/l10n/l10n.dart';

const Color _ink = Color(0xFF1D252C);
const Color _muted = Color(0xFF5C656C);
const Color _line = Color(0xFFE7EBEE);
const Color _icon = Color(0xFF3A4550);

class SafetyKitMapButton extends StatelessWidget {
  const SafetyKitMapButton({super.key, this.rideId});

  final String? rideId;

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: () => showRideSafetyKit(context, rideId: rideId),
          borderRadius: BorderRadius.circular(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shield_outlined, size: 18, color: _icon),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      context.l10n.safetyKit,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SafetyKitSheetRow extends StatelessWidget {
  const SafetyKitSheetRow({super.key, this.rideId});

  final String? rideId;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => showRideSafetyKit(context, rideId: rideId),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _line),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, size: 22, color: _icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.safetyKit,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showRideSafetyKit(BuildContext context, {String? rideId}) {
  SheetCoordinator.instance.open(RideSheet.safety);
  return MoveraSheet.show<void>(
    context: context,
    builder: (_) => RideSafetyKitSheet(rideId: rideId),
  ).whenComplete(() => SheetCoordinator.instance.close(RideSheet.safety));
}

class RideSafetyKitSheet extends StatefulWidget {
  const RideSafetyKitSheet({super.key, this.rideId, this.controller});
  final String? rideId;
  final SafetyController? controller;

  @override
  State<RideSafetyKitSheet> createState() => _RideSafetyKitSheetState();
}

class _RideSafetyKitSheetState extends State<RideSafetyKitSheet> {
  late final SafetyController _ctl = widget.controller ?? SafetyController.shared;
  String? _audioNote;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onChange);
    // A Ride check now opens as its own card on the trip screen
    // (RideCheckLayer), so the kit no longer lists pending checks.
    _ctl.load();
  }

  @override
  void dispose() {
    _ctl.removeListener(_onChange);
    // FLOW-6: Stop audio lives only in this sheet, so closing the sheet
    // stops and saves the recording instead of leaving the mic open. When a
    // Ride check card closed the sheet, the card has taken the recording
    // over with its own Stop (rider-u212/u214).
    if (!_ctl.audio.handedOver) {
      unawaited(_ctl.audio.stopIfRecording(reason: 'sheet_closed'));
    }
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {
      // rider-u199: the OS interrupted the recording and it was saved.
      if (!_ctl.audio.isRecording &&
          _audioNote == context.l10n.safetyKitRecording) {
        _audioNote = context.l10n.recordingSavedLocal;
      }
    });
  }

  TextStyle _text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = _ink,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  /// rider-u215: the SOS reaches Movera whether or not the phone dialer
  /// opens, and the rider is told both results.
  Future<void> _call112() async {
    String? dialError;
    try {
      await _ctl.emergency.callEmergencyNumber();
    } on EmergencyCallException catch (error) {
      dialError = error.message;
    }
    bool? registered;
    try {
      registered = await _ctl.sos(rideId: widget.rideId);
    } catch (_) {
      registered = null;
    }
    if (!mounted) return;
    final l10n = context.l10n;
    final String message;
    if (dialError != null) {
      message = registered == true ? l10n.sosRegisteredNoDialer : dialError;
    } else {
      message = switch (registered) {
        true => l10n.sosRegistered,
        false => l10n.sosNeedsRide,
        null => l10n.sosNotRegistered,
      };
    }
    MoveraToast.show(context, message);
  }

  Future<void> _toggleAudio() async {
    try {
      if (_ctl.audio.isRecording) {
        await _ctl.audio.stop();
        if (!mounted) return;
        setState(
          () => _audioNote =
              context.l10n.recordingSavedLocal,
        );
      } else {
        await _ctl.audio.start(rideId: widget.rideId ?? 'ride_local');
        if (!mounted) return;
        setState(
          () => _audioNote =
              context.l10n.safetyKitRecording,
        );
      }
    } on SafetyAudioException catch (error) {
      if (!mounted) return;
      setState(() => _audioNote = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _audioNote =
          context.l10n.recordingFailed);
    }
  }

  Future<void> _shareTrip() async {
    if (!_ctl.preferences.tripShareEnabled ||
        !_ctl.contacts.any((contact) => contact.isEnabled &&
            (_ctl.preferences.tripShareContactIds.contains(contact.id) ||
                contact.shareTrips))) {
      final nav = Navigator.of(context);
      await popCurrentRouteAndWaitForExit(context);
      if (!nav.mounted) return;
      await nav.push(RightToLeftTransition(TripSharePage(controller: _ctl)));
      return;
    }
    try {
      final share = await _ctl.startShare(widget.rideId ?? '');
      if (!mounted) return;
      setState(() {
        _audioNote = share.isActive && share.contactIds.isNotEmpty
            ? context.l10n.tripSharingStarted(share.contactIds.length)
            : context.l10n.tripSharingNotStarted;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _audioNote = context.l10n.tripSharingFailed);
    }
  }

  Future<void> _openHub() async {
    final nav = Navigator.of(context);
    await popCurrentRouteAndWaitForExit(context);
    if (!nav.mounted) return;
    await nav.push(RightToLeftTransition(SafetyHub(controller: _ctl)));
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    final recording = _ctl.audio.isRecording;
    return PointerInterceptor(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + inset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: _ink),
                  tooltip: context.l10n.close,
                ),
                Expanded(
                  child: Text(
                    context.l10n.accountSafety,
                    textAlign: TextAlign.center,
                    style: _text(17, weight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 4),
            Text(context.l10n.safetyTools, style: _text(22, weight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Tool(
                    icon: Icons.call_outlined,
                    label: context.l10n.contact112,
                    onTap: _call112,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Tool(
                    icon: recording
                        ? Icons.stop_circle_outlined
                        : Icons.mic_outlined,
                    label: recording ? context.l10n.stopAudio : context.l10n.recordAudio,
                    onTap: _toggleAudio,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Tool(
                    icon: Icons.ios_share_outlined,
                    label: context.l10n.shareTrip,
                    onTap: _shareTrip,
                  ),
                ),
              ],
            ),
            if (_audioNote != null) ...[
              const SizedBox(height: 12),
              Text(_audioNote!, style: _text(12, color: _muted)),
            ],
            const SizedBox(height: 14),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: _openHub,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _line),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 22, color: _icon),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.safetyPreferences,
                              style: _text(14, weight: FontWeight.w600),
                            ),
                            Text(
                              context.l10n.safetyPreferencesBody,
                              style: _text(12, color: _muted),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: _muted),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _line),
          ),
          child: Column(
            children: [
              Icon(icon, color: _icon, size: 22),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
