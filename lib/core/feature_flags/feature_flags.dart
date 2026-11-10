import 'package:movera_rider/app/config/env.dart';

class FeatureFlags {
  const FeatureFlags({
    this.enableCash = true,
    this.enableApplePay = true,
    bool enableScheduledRide = true,
    this.enableLuxury = true,
    bool enableWallet = true,
    bool enableRidePin = false,
    bool enableSafetyShareTrip = true,
    this.enableBookingLater = true,
    this.enableBusinessProfile = false,
    this.enableSavedCards = true,
  }) : _enableWallet = enableWallet,
       _enableRidePin = enableRidePin,
       _enableSafetyShareTrip = enableSafetyShareTrip,
       _enableScheduledRide = enableScheduledRide;

  final bool enableCash;
  final bool enableApplePay;
  final bool _enableScheduledRide;

  /// The build's value, unless the server's rider config of the zone in
  /// use says otherwise (`features.scheduledRides`, owner 2026-11-10 R10 #4).
  bool get enableScheduledRide =>
      ServerFeatures.of('scheduledRides') ?? _enableScheduledRide;
  final bool enableLuxury;
  final bool _enableWallet;

  /// The build's value, unless the server's rider config of the zone in
  /// use says otherwise (`features.wallet`, owner 2026-11-10 R10 #4).
  bool get enableWallet => ServerFeatures.of('wallet') ?? _enableWallet;
  final bool _enableRidePin;

  /// The build's value, unless the server's rider config of the zone in
  /// use says otherwise (`features.pin`, owner 2026-11-10 R10 #4).
  bool get enableRidePin => ServerFeatures.of('pin') ?? _enableRidePin;
  final bool _enableSafetyShareTrip;

  /// The build's value, unless the server's rider config of the zone in
  /// use says otherwise (`features.shareTrip`, owner 2026-11-10 R10 #4).
  bool get enableSafetyShareTrip =>
      ServerFeatures.of('shareTrip') ?? _enableSafetyShareTrip;
  final bool enableBookingLater;

  /// FLOW-11: Personal/Business only becomes a choice once booking, history
  /// and receipts use it; until then the toggle is hidden.
  final bool enableBusinessProfile;

  /// Cards saved on the rider's account. Off in release until card entry
  /// runs through the payment provider's hosted fields (ARCH-7, PCI scope).
  final bool enableSavedCards;

  bool get wallet => enableWallet;
  bool get scheduledRides => enableScheduledRide;
  bool get ridePin => enableRidePin;
  bool get safetyShareTrip => enableSafetyShareTrip;
  bool get bookingLater => enableBookingLater;
  bool get businessProfile => enableBusinessProfile;
  bool get savedCards => enableSavedCards;

  static const current = FeatureFlags();

  /// Staging/production keep the features whose data still lives only on
  /// this device switched off until a server repository exists (ARCH-6,
  /// ARCH-7): the wallet ledger and saved cards. Contract v0.18.17 (owner
  /// 2026-11-03 "Build it for real"): Book for later is on, on the server
  /// (`ApiReservationRepository`).
  /// Movera fix job 6 (owner 2026-11-04 "Turn it on"): the wallet is on,
  /// on the server (`ApiWalletRepository`, one balance per currency).
  static const release = FeatureFlags(enableSavedCards: false);

  static FeatureFlags forEnvironment(AppEnv environment) =>
      environment.isReleaseLike ? release : current;
}

/// Owner 2026-11-10 (R10 #4 "Follow admin switches"): the feature switches
/// (`RiderAppConfig.features`, contract §3.2: scheduledRides, wallet, pin,
/// shareTrip and any other) of the zone the rider is in, as the server
/// sent them. Set by the live config repository; empty in the demo and
/// until a server document is read, when the build's values stand.
abstract final class ServerFeatures {
  static Map<String, bool> _switches = const {};

  /// The server's switch [name], or null when it has not said.
  static bool? of(String name) => _switches[name];

  static Map<String, bool> get all => _switches;

  static void apply(Map<String, bool> switches) =>
      _switches = Map.unmodifiable(switches);

  static void clear() => _switches = const {};
}
