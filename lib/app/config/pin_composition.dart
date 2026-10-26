import 'package:movera_rider/app/config/env.dart';

/// PIN issuance must never silently fall back to the in-process mock in a
/// release composition. A separate backend contract remains required.
abstract final class PinComposition {
  static void validate({
    required AppEnv environment,
    required bool usesMockPinIssuance,
  }) {
    if (environment.isReleaseLike && usesMockPinIssuance) {
      throw StateError(
        'Mock PIN issuance is forbidden in ${environment.flavor.name}',
      );
    }
  }
}
