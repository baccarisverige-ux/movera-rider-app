/// Cancel reason codes (`contract.json#cancelReasons`, v0.3.0), sent as
/// `reasonCode`. The server validates them per actor; the Rider only ever
/// sends [rider] codes.
abstract final class CancelReasonCodes {
  static const rider = <String>[
    'pickup_incorrect',
    'wrong_ride_option',
    'requested_by_mistake',
    'wait_too_long',
    'destination_change',
    'driver_not_suitable',
    'plans_changed',
    'something_else',
  ];

  /// Codes other actors use; the Rider reads them on a cancelled trip
  /// (`cancellation.reasonCode`) and never sends them.
  static const noShow = <String>['rider_no_show'];
  static const admin = <String>[
    'admin_safety',
    'admin_fraud',
    'admin_rider_request',
    'admin_driver_request',
    'admin_operational',
    'admin_other',
  ];
  static const system = <String>[
    'system_no_driver',
    'system_payment_failed',
    'system_zone_closed',
    'system_error',
  ];

  static bool isRiderCode(Object? raw) => raw is String && rider.contains(raw);

  /// The reason part of a rider cancel body: contract `reasonCode` for a
  /// registry code, plus the pre-v0.3 `reason` key the stand-in server and
  /// older backends read (compatibility, one release).
  static Map<String, Object> riderCancelBody(String? reason) => {
    if (isRiderCode(reason)) 'reasonCode': reason!,
    if (reason != null) 'reason': reason,
  };
}
