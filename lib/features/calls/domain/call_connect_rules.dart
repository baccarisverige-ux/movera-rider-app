import 'dart:ui' show FlutterView;

import 'package:flutter/widgets.dart';

/// Contract v0.18.66 §87 (owner answers 2026-11-11, `contract.json#callConnect`):
/// the in-app call's connect time limit and the speaker default. Same rules
/// as the driver app (`lib/core/calls/call_connect_rules.dart`).
abstract final class CallConnectRules {
  /// `configDefaults.calls.connectTimeoutSeconds`: used when the server
  /// sends no `connectTimeoutSeconds` (an older server).
  static const defaultTimeout = Duration(seconds: 25);

  /// The admin setting's range (`inAppCalls.limits.connectTimeoutSeconds`).
  static const minSeconds = 10;
  static const maxSeconds = 60;

  /// `TripCall.connectTimeoutSeconds` / `CallView.connectTimeoutSeconds`;
  /// null when missing or unreadable. A value outside 10–60 is held to
  /// the range.
  static Duration? timeoutOf(Map<String, dynamic> json) {
    final raw = json['connectTimeoutSeconds'];
    if (raw is! num || !raw.isFinite || raw <= 0) return null;
    return Duration(seconds: raw.round().clamp(minSeconds, maxSeconds));
  }

  /// A tablet: the screen's shortest side is at least 600 dp
  /// (owner "Tablet ON, phone OFF"). No screen known → a phone.
  static const tabletShortestSide = 600.0;

  static bool isTabletScreen() {
    final Iterable<FlutterView> views;
    try {
      views = WidgetsBinding.instance.platformDispatcher.views;
    } catch (_) {
      return false;
    }
    if (views.isEmpty) return false;
    final view = views.first;
    if (view.devicePixelRatio <= 0) return false;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.shortestSide >= tabletShortestSide;
  }
}
