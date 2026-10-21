import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/safety/domain/phone_e164.dart';
import 'package:movera_rider/shared/widgets/push_permission_primer.dart';

/// Leaves the sign-in flow for the map, clearing it from the back stack.
///
/// The root RideRestoreGate stays mounted: Home becomes its child and every
/// auth route above it is popped. Removing the root route instead disposed
/// the gate, so later ride restores, notification opens and post-create
/// recovery had nowhere to draw. A live ride kept through a lost session is
/// resumed once the rider is back in.
void enterMoveraApp(BuildContext context) {
  final shown = showMoveraRoot(
    const Home(),
    navigator: Navigator.of(context),
    name: AppRoutes.home,
  );
  if (shown) {
    unawaited(RideRestoreCoordinator.instance.resumeIfNeeded());
  }
  // rider-u148: a returning rider gets their server profile (name,
  // language, consents) on this device.
  unawaited(AppScope.instance.profile.hydrate());
  // UI-17: explain ride updates before the OS notification prompt.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final home = moveraNavigatorKey.currentContext;
    if (home == null) return;
    unawaited(
      maybeShowPushPrimer(home, gate: AppScope.instance.pushPermission),
    );
  });
}

/// Puts [page] at the app root and closes every route above it.
///
/// Returns true when the root gate showed [page]. Hosts without the gate
/// (isolated widget tests) get [page] as the only route instead.
bool showMoveraRoot(
  Widget page, {
  NavigatorState? navigator,
  String? name,
}) {
  final nav = navigator ?? moveraNavigatorKey.currentState;
  final coordinator = RideRestoreCoordinator.instance;
  if (coordinator.replaceRootSurface(page, RestoredSurface.home)) {
    nav?.popUntil((route) => route.isFirst);
    return true;
  }
  nav?.pushAndRemoveUntil(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: (_) => page,
    ),
    (_) => false,
  );
  return false;
}

/// The +46 number a rider typed into the national-number field, or null.
///
/// Accepts both "70 123 45 67" and the everyday "070 123 45 67". The old
/// screens prefixed +46 to whatever was typed, turning "070..." into the
/// invalid "+46070...".
///
/// rider-30: the international forms (+46 ..., 0046 ..., 46 ... pasted
/// from Contacts) are the same number, not one to put a second +46 in
/// front of. Without a trunk 0 a Swedish number has at most nine digits,
/// so a longer one is refused instead of sent somewhere else.
String? swedishNumberFromField(String typed) {
  final digits = typed.replaceAll(RegExp(r'\s+'), '').trim();
  if (digits.isEmpty) return null;
  if (digits.startsWith('+') || digits.startsWith('0')) {
    return SwedishPhone.toE164(digits);
  }
  if (digits.startsWith('46') && digits.length >= 11) {
    return SwedishPhone.toE164('+$digits');
  }
  if (digits.length > 9) return null;
  return SwedishPhone.toE164('+46$digits');
}
