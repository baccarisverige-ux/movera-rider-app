import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/application/share_trip_actions.dart';
import 'package:movera_rider/features/safety/domain/emergency_contact.dart';
import 'package:movera_rider/features/safety/presentation/safety_ui.dart';
import 'package:movera_rider/features/safety/presentation/trip_share_page.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

/// Movera colours (no blue): ink #12201C, green #2FBF5B.
const Color _ink = Color(0xFF12201C);
const Color _green = Color(0xFF2FBF5B);

/// Share my trip (contract v0.18.116 `contract.json#shareTrip`; owner
/// 2026-11-02 "Build it for real"): the one Share trip sheet of a live
/// trip, opened from the trip screen's share button and from the Safety
/// sheet. Nothing opens while the zone's switch is off. The link ends by
/// itself at drop-off; the sheet then says "ended", not an error.
Future<void> showShareTripSheet(
  BuildContext context, {
  required String? rideId,
  SafetyController? controller,
}) async {
  final safety = controller ?? SafetyController.shared;
  final id = rideId?.trim() ?? '';
  if (!safety.shareTripOn || id.isEmpty) return;
  await MoveraSheet.show<void>(
    context: context,
    builder: (_) => ShareTripSheet(rideId: id, controller: safety),
  );
}

class ShareTripSheet extends StatefulWidget {
  const ShareTripSheet({super.key, required this.rideId, this.controller});

  final String rideId;
  final SafetyController? controller;

  @override
  State<ShareTripSheet> createState() => _ShareTripSheetState();
}

class _ShareTripSheetState extends State<ShareTripSheet> {
  late final SafetyController _ctl =
      widget.controller ?? SafetyController.shared;
  bool _busy = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onChange);
    // A link this phone still holds may have ended on the server.
    unawaited(
      _ctl.refreshShare(widget.rideId).catchError((Object error) {
        AppLog.warning('safety.share.refresh_failed', extra: {'e': '$error'});
      }),
    );
  }

  @override
  void dispose() {
    _ctl.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  List<EmergencyContact> get _contacts {
    final ids = _ctl.tripShareRecipients.toSet();
    return [
      for (final contact in _ctl.contacts)
        if (ids.contains(contact.id)) contact,
    ];
  }

  /// The message with the trip's link, or null (and a line saying why).
  Future<String?> _message() async {
    final l10n = context.l10n;
    try {
      return l10n.shareTripMessage(await _ctl.shareLink(widget.rideId));
    } on ApiError catch (error) {
      // 403 share_trip_off and 410 (ended) show their own state.
      if (mounted &&
          error.reason != 'share_trip_off' &&
          error.statusCode != 410) {
        setState(() => _note = l10n.tripSharingFailed);
      }
    } catch (_) {
      if (mounted) setState(() => _note = l10n.tripSharingFailed);
    }
    return null;
  }

  Future<void> _run(Future<void> Function(String text) send) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      final text = await _message();
      if (text != null) await send(text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(Future<void> Function(String text) action) =>
      _run((text) async {
        final l10n = context.l10n;
        try {
          await action(text);
        } catch (_) {
          if (mounted) setState(() => _note = l10n.tripSharingFailed);
        }
      });

  Future<void> _sendTo(EmergencyContact contact) =>
      _send((text) => ShareTripActions.sendSms(contact.phoneE164, text));

  Future<void> _shareWith() => _send(ShareTripActions.sharer);

  Future<void> _stop() async {
    if (_busy) return;
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      await _ctl.stopShare(widget.rideId);
      if (mounted) setState(() => _note = l10n.shareTripStopped);
    } catch (_) {
      if (mounted) setState(() => _note = l10n.shareTripStopFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openContacts() async {
    final nav = Navigator.of(context);
    final ctl = _ctl;
    if (nav.canPop()) await popCurrentRouteAndWaitForExit(context);
    if (!nav.mounted) return;
    await nav.push(RightToLeftTransition(TripSharePage(controller: ctl)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final off = _ctl.shareRefusedFor(widget.rideId) || !_ctl.shareTripOn;
    final ended = !off && _ctl.shareEndedFor(widget.rideId);
    final sharing = _ctl.shareFor(widget.rideId)?.canSend ?? false;
    final contacts = _contacts;
    final inset = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + inset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close_rounded, color: _ink),
                    tooltip: l10n.close,
                  ),
                  Expanded(
                    child: Text(
                      l10n.shareTrip,
                      textAlign: TextAlign.center,
                      style: SafetyUi.text(17, weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 8),
              if (off)
                Text(
                  l10n.shareTripOffInZone,
                  key: const ValueKey('share-trip-off'),
                  style: SafetyUi.text(15, color: _ink, height: 1.4),
                )
              else if (ended)
                Row(
                  key: const ValueKey('share-trip-ended'),
                  children: [
                    const Icon(Icons.check_circle_rounded, color: _green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.shareTripEnded,
                        style: SafetyUi.text(15, color: _ink, height: 1.4),
                      ),
                    ),
                  ],
                )
              else ...[
                Text(
                  l10n.shareTripWhatTheySee,
                  style: SafetyUi.text(14, color: SafetyUi.muted, height: 1.4),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < contacts.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            contacts[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SafetyUi.text(16, weight: FontWeight.w500),
                          ),
                        ),
                        FilledButton(
                          key: ValueKey('share-trip-send-$i'),
                          onPressed: _busy ? null : () => _sendTo(contacts[i]),
                          style: FilledButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(88, 48),
                          ),
                          child: Text(l10n.shareTripSend),
                        ),
                      ],
                    ),
                  ),
                if (contacts.isEmpty)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const ValueKey('share-trip-contacts'),
                      style: TextButton.styleFrom(foregroundColor: _ink),
                      onPressed: _openContacts,
                      child: Text(l10n.shareTrusted),
                    ),
                  ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  key: const ValueKey('share-trip-with'),
                  onPressed: _busy ? null : _shareWith,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: _ink,
                    side: const BorderSide(color: _green),
                  ),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: Text(l10n.shareTripWith),
                ),
                if (sharing) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    key: const ValueKey('share-trip-stop'),
                    onPressed: _busy ? null : _stop,
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: _ink,
                    ),
                    child: Text(l10n.shareTripStop),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  l10n.shareTripEndsAtDropoff,
                  textAlign: TextAlign.center,
                  style: SafetyUi.text(12.5, color: SafetyUi.muted),
                ),
              ],
              if (_note != null) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _note!,
                    key: const ValueKey('share-trip-note'),
                    textAlign: TextAlign.center,
                    style: SafetyUi.text(13.5, weight: FontWeight.w500),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
