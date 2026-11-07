import 'package:flutter/widgets.dart';

/// Owner decision "Confirm and search" (2026-11-07, "Chargement sur le
/// bouton"): after Confirm and search, Set pickup stays on screen with a
/// spinner on its button while the caller prices the pickup and books the
/// ride. The caller then either replaces Set pickup with the next screen
/// ([replaceWith], Finding your driver) or closes it ([close]) and shows its
/// message on the screen below, as before.
class SetPickupHold {
  SetPickupHold(this._route);

  final Route<Object?> _route;

  /// Whether Set pickup is still on the stack.
  bool get isOpen => _route.isActive;

  /// Shows [next] in place of Set pickup: Set pickup stays under it until
  /// [next] has come in, then it is removed (no screen in between). When
  /// Set pickup is already gone, [next] is pushed on [fallback].
  Future<T?> replaceWith<T extends Object?>(
    NavigatorState fallback,
    Route<T> next,
  ) {
    final navigator = _route.navigator;
    if (navigator == null || !_route.isActive) return fallback.push(next);
    if (_route.isCurrent) return navigator.pushReplacement<T, Object?>(next);
    final shown = navigator.push(next);
    navigator.removeRoute(_route);
    return shown;
  }

  /// Closes Set pickup (as its own Confirm used to) and waits until it has
  /// gone, so what follows shows on the screen below. Nothing when closed.
  Future<void> close() async {
    final route = _route;
    final navigator = route.navigator;
    if (navigator == null || !route.isActive) return;
    if (!route.isCurrent) {
      navigator.removeRoute(route);
      return;
    }
    navigator.pop();
    if (route is TransitionRoute<Object?>) await route.completed;
  }
}
