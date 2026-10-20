import 'package:movera_rider/l10n/l10n.dart';
/// Shared booking context for the one Movera category selector.
///
/// Book now and Book for later use the same ride cards. Only the next
/// action changes: now enters Finding Driver, scheduled creates a
/// reservation and never starts a live search.
enum BookingMode { now, scheduled }

extension BookingModeBehavior on BookingMode {
  bool get entersFindingDriver => this == BookingMode.now;

  bool get createsReservation => this == BookingMode.scheduled;

  /// "Select Movera" / "Schedule Movera" in the app language.
  String ctaLabel(String categoryName) => this == BookingMode.scheduled
      ? L10n.current.ctaSchedule(categoryName)
      : L10n.current.ctaSelect(categoryName);
}
