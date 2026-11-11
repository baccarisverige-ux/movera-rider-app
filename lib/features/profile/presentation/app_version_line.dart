import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/app_version.dart';
import 'package:movera_rider/core/observability/crash_report.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';

/// Owner 2026-11-11 (set 2 "Yes, both apps"; contract v0.18.66 §87, app
/// only, Rule 43(1)): the last line of the Account screen, the app version
/// and build number, e.g. "Version 1.0.0 (583)". Read from the build
/// ([appVersion], `--dart-define=MOVERA_APP_VERSION=<version>+<build>` as
/// the crash reports use it); a local build says "Version dev". Same as
/// the driver app's Account line.
class AppVersionLine extends StatelessWidget {
  const AppVersionLine({super.key, this.raw = appVersion});

  /// `1.0.0+583`; tests pass their own.
  final String raw;

  /// "Version 1.0.0 (583)", or "Version 1.0.0" without a build number.
  static String text(String raw, [AppLocalizations? l10n]) {
    final words = l10n ?? L10n.current;
    final parts = CrashReport.splitVersion(raw);
    final build = parts.build;
    return build == null
        ? words.appVersionOnly(parts.version)
        : words.appVersionLine(parts.version, build);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 4),
    child: Text(
      text(raw, context.l10n),
      key: const ValueKey<String>('account-app-version'),
      textAlign: TextAlign.center,
      style: const TextStyle(color: MoveraTokens.subtle, fontSize: 12),
    ),
  );
}
