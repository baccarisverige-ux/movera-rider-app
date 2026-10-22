/// Why the app cannot read the rider's location.
enum LocationAccessIssue {
  /// Permission was refused, but the system prompt can still be shown again.
  denied,

  /// Permission is blocked (Android "Don't ask again", any iOS refusal):
  /// only the system Settings can change it.
  deniedForever,

  /// Location Services are switched off for the whole device.
  servicesOff,

  /// rider-u114: only approximate location is allowed (iOS "Precise: Off",
  /// Android "Approximate"): the fix is too coarse to be the pickup.
  approximate,
}
