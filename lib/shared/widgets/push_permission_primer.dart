import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/notifications/push_permission_gate.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Opens the app's page in system Settings (notifications live there).
typedef AppSettingsOpener = Future<bool> Function();

const Color _ink = Color(0xFF1D252C);
const Color _muted = Color(0xFF5C656C);
const Color _cta = Color(0xFF11181D);

/// Shows the ride-updates explanation once, before the OS prompt (UI-17).
/// Does nothing when [gate] has nothing to offer (mock push, or the rider
/// already answered).
Future<void> maybeShowPushPrimer(
  BuildContext context, {
  required PushPermissionGate gate,
  AppSettingsOpener? openAppSettings,
}) async {
  if (!await gate.shouldOffer()) return;
  if (!context.mounted) return;
  await MoveraSheet.show<void>(
    context: context,
    builder: (_) =>
        PushPrimerSheet(gate: gate, openAppSettings: openAppSettings),
  );
}

/// "Get ride updates": why Movera wants notifications, then "Turn on" (the
/// OS prompt) or "Not now". A system refusal switches to a Settings path.
class PushPrimerSheet extends StatefulWidget {
  const PushPrimerSheet({
    super.key,
    required this.gate,
    this.openAppSettings,
    this.startBlocked = false,
  });

  final PushPermissionGate gate;
  final AppSettingsOpener? openAppSettings;

  /// Opens straight on the Settings path (the rider already refused).
  final bool startBlocked;

  @override
  State<PushPrimerSheet> createState() => _PushPrimerSheetState();
}

class _PushPrimerSheetState extends State<PushPrimerSheet> {
  late bool _blocked = widget.startBlocked;
  bool _busy = false;
  bool _failed = false;

  Future<void> _turnOn() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final result = await widget.gate.accept();
    if (!mounted) return;
    switch (result) {
      case PushOptInResult.registered:
        Navigator.of(context).pop();
      case PushOptInResult.blockedBySystem:
        setState(() {
          _busy = false;
          _blocked = true;
        });
      case PushOptInResult.failed:
        setState(() {
          _busy = false;
          _failed = true;
        });
    }
  }

  Future<void> _notNow() async {
    if (!_blocked) await widget.gate.decline();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openSettings() async {
    await (widget.openAppSettings ?? Geolocator.openAppSettings)();
  }

  @override
  Widget build(BuildContext context) {
    final title = _blocked ? context.l10n.pushOff : context.l10n.pushGetUpdates;
    final body = _blocked
        ? context.l10n.pushBlockedBody
        : context.l10n.pushBody;
    return MoveraSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        child: Column(
          key: const ValueKey('push-primer'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.notifications_active_outlined,
              color: _ink,
              size: 28,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                height: 1.4,
                color: _muted,
              ),
            ),
            if (_failed) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.pushFailed,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: const Color(0xFF9A3412),
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                key: const ValueKey('push-primer-primary'),
                style: FilledButton.styleFrom(
                  backgroundColor: _cta,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _busy ? null : (_blocked ? _openSettings : _turnOn),
                child: Text(
                  _blocked ? context.l10n.openSettings : context.l10n.pushTurnOn,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (_blocked)
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('push-primer-retry'),
                      onPressed: _busy ? null : _turnOn,
                      style: TextButton.styleFrom(foregroundColor: _ink),
                      child: Text(context.l10n.tryAgain),
                    ),
                  ),
                Expanded(
                  child: TextButton(
                    key: const ValueKey('push-primer-not-now'),
                    onPressed: _busy ? null : _notNow,
                    style: TextButton.styleFrom(foregroundColor: _muted),
                    child: Text(context.l10n.notNow),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A row for the Notifications screen while ride updates are not on: it
/// reopens the explanation, or the Settings path after a system refusal.
class PushStatusBanner extends StatefulWidget {
  const PushStatusBanner({super.key, required this.gate, this.openAppSettings});

  final PushPermissionGate gate;
  final AppSettingsOpener? openAppSettings;

  @override
  State<PushStatusBanner> createState() => _PushStatusBannerState();
}

class _PushStatusBannerState extends State<PushStatusBanner> {
  late Future<PushConsent> _consent = widget.gate.consent();

  Future<void> _open(bool blocked) async {
    await MoveraSheet.show<void>(
      context: context,
      builder: (_) => PushPrimerSheet(
        gate: widget.gate,
        openAppSettings: widget.openAppSettings,
        startBlocked: blocked,
      ),
    );
    if (mounted) setState(() => _consent = widget.gate.consent());
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.gate.enabled) return const SizedBox.shrink();
    return FutureBuilder<PushConsent>(
      future: _consent,
      builder: (context, snapshot) {
        final consent = snapshot.data;
        if (consent == null || consent == PushConsent.accepted) {
          return const SizedBox.shrink();
        }
        final blocked = consent == PushConsent.blockedBySystem;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Material(
            key: const ValueKey('push-status-banner'),
            color: const Color(0xFFF6F7F7),
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              leading: const Icon(
                Icons.notifications_off_outlined,
                color: _ink,
              ),
              title: Text(
                context.l10n.pushRideUpdatesOff,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
              subtitle: Text(
                blocked
                    ? context.l10n.pushTurnOnInSettings
                    : context.l10n.pushHearDriver,
                style: GoogleFonts.poppins(fontSize: 12.5, color: _muted),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, color: _muted),
              onTap: () => _open(blocked),
            ),
          ),
        );
      },
    );
  }
}
