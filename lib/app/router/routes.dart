import 'package:flutter/widgets.dart';

/// Named routes for the approved Rider flow.
/// Screens still push with existing transitions; names are the contract.
abstract final class AppRoutes {
  static const home = '/';
  static const confirmPickup = '/ride/pickup-confirm';
  static const selectRide = '/ride/select';
  static const findingDriver = '/ride/finding';
  static const waitingForDriver = '/ride/waiting';
  static const rideCompleted = '/ride/completed';
  static const notifications = '/notifications';
  static const reservationScheduled = '/reservation/scheduled';
  static const reservationUpcoming = '/reservation/upcoming';
  static const reservationLive = '/reservation/live';
  static const safety = '/safety';
  static const supportTicket = '/support/ticket';

  /// Home is a destination contract, not a stack-position assumption.
  /// Prefer the stable route name and keep the root fallback for legacy/restored
  /// stacks whose first route predates Batch 4 naming.
  static bool isHomeRoute(Route<dynamic> route) {
    return route.settings.name == home || route.isFirst;
  }
}
