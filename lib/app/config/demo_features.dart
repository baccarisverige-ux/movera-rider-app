import 'package:flutter/foundation.dart';
import 'package:movera_rider/app/di.dart';

/// Demo-only things (simulated top-up, "coming soon" cards, promotion
/// switches): on in the demo/dev/test builds whose transport is mocked, off
/// on the live web build (flavor staging) and in production.
abstract final class DemoFeatures {
  /// Tests set it to see a live build's screens; null follows the build.
  @visibleForTesting
  static bool? debugOverride;

  static bool get on =>
      debugOverride ?? AppScope.instance.environment.allowsMockTransport;
}
