import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/location/location_access_issue.dart';
import 'package:movera_rider/l10n/l10n.dart';

export 'package:movera_rider/core/location/location_access_issue.dart';

/// Opens a system settings screen; resolves with whether it opened.
typedef LocationSettingsOpener = Future<bool> Function();

/// The system screen that fixes [issue]: app settings for a blocked
/// permission, location settings when Location Services are off. Null for a
/// plain refusal (asking again fixes it) and on the web, where no settings
/// screen can be opened.
LocationSettingsOpener? locationSettingsOpenerFor(
  LocationAccessIssue issue, {
  bool isWeb = kIsWeb,
  LocationSettingsOpener? openAppSettings,
  LocationSettingsOpener? openLocationSettings,
}) {
  if (isWeb) return null;
  return switch (issue) {
    LocationAccessIssue.denied => null,
    LocationAccessIssue.deniedForever =>
      openAppSettings ?? Geolocator.openAppSettings,
    LocationAccessIssue.servicesOff =>
      openLocationSettings ?? Geolocator.openLocationSettings,
    // rider-u114: asked through [LocationAccessNotice.onPrecise].
    LocationAccessIssue.approximate => null,
  };
}

/// A small card that explains why location is unavailable and offers the
/// way back: "Open settings" when only the system can fix it, otherwise
/// "Allow location" / "Try again" through [onRetry]. Setting the pickup on
/// the map always remains possible, and the copy says so.
class LocationAccessNotice extends StatelessWidget {
  const LocationAccessNotice({
    super.key,
    required this.issue,
    this.onRetry,
    this.onPrecise,
    this.onDismiss,
    this.isWeb = kIsWeb,
    this.openAppSettings,
    this.openLocationSettings,
  });

  final LocationAccessIssue issue;

  /// Asks for location again (re-runs the permission request).
  final VoidCallback? onRetry;

  /// rider-u114: asks for precise location ("Turn on").
  final VoidCallback? onPrecise;
  final VoidCallback? onDismiss;
  final bool isWeb;

  /// For tests; default to geolocator's settings deep links.
  final LocationSettingsOpener? openAppSettings;
  final LocationSettingsOpener? openLocationSettings;

  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);

  String get _title => switch (issue) {
    LocationAccessIssue.denied => L10n.current.locNeededTitle,
    LocationAccessIssue.deniedForever => L10n.current.locOffTitle,
    LocationAccessIssue.servicesOff => L10n.current.locServicesOffTitle,
    LocationAccessIssue.approximate => L10n.current.locPreciseOffTitle,
  };

  String get _body {
    if (isWeb) {
      return switch (issue) {
        LocationAccessIssue.denied => L10n.current.locWebDenied,
        LocationAccessIssue.deniedForever => L10n.current.locWebDeniedForever,
        LocationAccessIssue.servicesOff => L10n.current.locWebServicesOff,
        LocationAccessIssue.approximate => L10n.current.locPreciseOffBody,
      };
    }
    return switch (issue) {
      LocationAccessIssue.denied => L10n.current.locDenied,
      LocationAccessIssue.deniedForever => L10n.current.locDeniedForever,
      LocationAccessIssue.servicesOff => L10n.current.locServicesOffBody,
      LocationAccessIssue.approximate => L10n.current.locPreciseOffBody,
    };
  }

  @override
  Widget build(BuildContext context) {
    final openSettings = locationSettingsOpenerFor(
      issue,
      isWeb: isWeb,
      openAppSettings: openAppSettings,
      openLocationSettings: openLocationSettings,
    );
    final String actionLabel;
    final VoidCallback? action;
    if (issue == LocationAccessIssue.approximate) {
      actionLabel = context.l10n.locPreciseTurnOn;
      action = onPrecise;
    } else if (openSettings != null) {
      actionLabel = context.l10n.locOpenSettings;
      action = () => openSettings();
    } else {
      actionLabel = issue == LocationAccessIssue.denied
          ? context.l10n.locAllow
          : context.l10n.tryAgain;
      action = onRetry;
    }
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        key: const ValueKey('location-access-notice'),
        color: Colors.white,
        elevation: 6,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  issue == LocationAccessIssue.approximate
                      ? Icons.location_searching_rounded
                      : Icons.location_off_outlined,
                  color: _ink,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _title,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _body,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        height: 1.35,
                        color: _muted,
                      ),
                    ),
                    if (action != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const ValueKey('location-access-action'),
                          onPressed: action,
                          style: TextButton.styleFrom(
                            foregroundColor: _ink,
                            padding: const EdgeInsets.symmetric(horizontal: 0),
                            minimumSize: const Size(48, 44),
                            textStyle: GoogleFonts.poppins(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(actionLabel),
                        ),
                      ),
                  ],
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  tooltip: context.l10n.dismiss,
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close_rounded, color: _muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
