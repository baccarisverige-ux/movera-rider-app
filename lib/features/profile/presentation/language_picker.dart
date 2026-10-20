import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/profile/application/app_language_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Lets the rider pick the app language (owner Q48): "EN · English",
/// "FR · Français", "SV · Svenska". The choice is saved and wins over the
/// zone's default; the profile keeps the same code for the server.
Future<void> pickAppLanguage(
  BuildContext context, {
  AppLanguageController? language,
  ProfileController? profile,
}) async {
  final controller = language ?? AppScope.instance.language;
  final next = await showAccountChoice(
    context,
    title: context.l10n.language,
    options: [for (final l in L10n.languages) l.code],
    selected: controller.code,
    labelOf: (code) => L10n.languageOf(code).label,
  );
  if (next == null) return;
  await controller.choose(next);
  final owner = profile ?? AppScope.instance.profile;
  try {
    await owner.update(owner.profile.copyWith(language: next));
  } catch (error) {
    // The app language is already saved on the device.
    AppLog.warning('language.profile_save_failed', extra: {'error': '$error'});
  }
}
