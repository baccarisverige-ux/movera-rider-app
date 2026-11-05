import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';

/// v0.18.32 (contract.json#bookedRideSeen.rulesSource, fix job 2 L3): the
/// booked-ride rules come from the published rider config
/// (`GET /rider/config`): `booking.freeChangeBeforeMin` is the free change
/// and cancel window; the fee per category stays `cancelFees.reservation`
/// (the reservation controller reads it from the same config). The driver
/// is shown from driver_to_pickup on (bookLater.liveFixes.driverShown),
/// never on accept. Replaces the never-served PROPOSED
/// `/rider/scheduled-rides/rules` on the live wire.
class ConfigScheduledRideRulesSource implements ScheduledRideRulesSource {
  ConfigScheduledRideRulesSource(this._load);

  final Future<RiderAppConfig> Function() _load;

  @override
  Future<ScheduledRideRules?> fetch() async {
    try {
      final config = await _load();
      final minutes = config.freeChangeBeforeMin;
      return ScheduledRideRules(
        freeCancelMinutesBeforePickup:
            minutes >= 0 && minutes <= ScheduledRideRules.maxFreeCancelMinutes
            ? minutes
            : ScheduledRideRules.defaults.freeCancelMinutesBeforePickup,
        showDriverOnAccept: false,
      );
    } catch (error) {
      AppLog.warning(
        'reservation.rules.config_failed',
        extra: {'error': error.runtimeType.toString()},
      );
      return null;
    }
  }
}
