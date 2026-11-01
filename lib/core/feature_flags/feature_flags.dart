import 'package:movera_rider/app/config/env.dart';

class FeatureFlags {
  const FeatureFlags({
    this.enableCash = true,
    this.enableApplePay = true,
    this.enableScheduledRide = true,
    this.enableLuxury = true,
    this.enableWallet = true,
    this.enableRidePin = false,
    this.enableSafetyShareTrip = true,
    this.enableBookingLater = true,
    this.enableBusinessProfile = false,
    this.enableSavedCards = true,
  });

  final bool enableCash;
  final bool enableApplePay;
  final bool enableScheduledRide;
  final bool enableLuxury;
  final bool enableWallet;
  final bool enableRidePin;
  final bool enableSafetyShareTrip;
  final bool enableBookingLater;

  /// FLOW-11: Personal/Business only becomes a choice once booking, history
  /// and receipts use it; until then the toggle is hidden.
  final bool enableBusinessProfile;

  /// Cards saved on the rider's account. Off in release until card entry
  /// runs through the payment provider's hosted fields (ARCH-7, PCI scope).
  final bool enableSavedCards;

  bool get wallet => enableWallet;
  bool get scheduledRides => enableScheduledRide;
  bool get safetyShareTrip => enableSafetyShareTrip;
  bool get bookingLater => enableBookingLater;
  bool get businessProfile => enableBusinessProfile;
  bool get savedCards => enableSavedCards;

  static const current = FeatureFlags();

  /// Staging/production keep the features whose data still lives only on
  /// this device switched off until a server repository exists (ARCH-6,
  /// ARCH-7): the wallet ledger, Book for later and saved cards.
  static const release = FeatureFlags(
    enableWallet: false,
    enableScheduledRide: false,
    enableBookingLater: false,
    enableSavedCards: false,
  );

  static FeatureFlags forEnvironment(AppEnv environment) =>
      environment.isReleaseLike ? release : current;
}
