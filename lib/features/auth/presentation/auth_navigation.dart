import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/auth/domain/phone_country.dart';
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
  // language, consents) on this device; rider-r5-42: a language picked on
  // Sign in goes to it.
  unawaited(
    AppScope.instance.profile.hydrateWithLanguage(AppScope.instance.language),
  );
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
/// rider-30 / rider-r3-11: national ("070 123 45 67", "70 123 45 67") and
/// international (+46, 0046, a bare 46 of full length) forms of a Swedish
/// mobile (+46 7 and eight more digits); anything else is refused.
///
/// Owner decision 7: the sign-in screens now take every country through
/// [phoneNumberFromField]; this is its Sweden-only form.
String? swedishNumberFromField(String typed) {
  final number = phoneNumberFromField(typed, PhoneCountries.sweden);
  return number != null && number.startsWith('+46') ? number : null;
}
