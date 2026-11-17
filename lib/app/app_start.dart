import 'dart:async';

import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/location/start_warmup.dart';
import 'package:movera_rider/core/web/web_maps_available.dart';

/// Owner job "Fast start behind the intro" (REMINDERS 144/145): the start
/// order. [early] is started first and never awaited, so the position
/// search and the map load run while [boot] (the boot steps behind the
/// intro) runs; [firstScreen] (runApp) comes after [boot] only. The intro
/// is as long as before: nothing here waits for [early].
Future<void> runAppStart({
  required void Function() early,
  required Future<void> Function() boot,
  required void Function() firstScreen,
}) async {
  early();
  await boot();
  firstScreen();
}

/// What starts with the intro: for a rider who will see Home (signed in,
/// or a build whose Home needs no sign-in), the map script (web; LT-4 keeps
/// it off the sign-in screen) and, when location is already allowed, the
/// one position request Home reuses. Never asks for anything.
void startBehindIntro() {
  unawaited(
    StartWarmup.start(
      location: AppScope.instance.location,
      signedIn: homeComesFirst,
      warmMap: requestGoogleMaps,
    ),
  );
}

/// As the start route decides: Home without sign-in (demo), else a stored
/// session (access and refresh token).
Future<bool> homeComesFirst() async {
  const env = AppEnv.current;
  if (!env.authRequired && !env.authPreview) return true;
  final tokens = AppScope.instance.tokens;
  return (await tokens.readAccess())?.isNotEmpty == true &&
      (await tokens.readRefresh())?.isNotEmpty == true;
}
