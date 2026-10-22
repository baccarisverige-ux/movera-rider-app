import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';

class SupportRide {
  const SupportRide({
    required this.title,
    required this.when,
    required this.price,
    required this.image,
    this.currency = 'SEK',
    this.cancelled = false,
    this.failed = false,
    this.endedEarly = false,
    this.extra,
    this.cancellationFee,
    this.id,
  });

  /// The reservation or on-demand ride id this row is about.
  final String? id;

  final String title;
  final DateTime when;
  /// Whole units of [currency] (the ride's).
  final double price;
  final String currency;
  final String image;
  final bool cancelled;
  final bool failed;

  /// UI-01: the rider ended the trip on board; [price] is what they were
  /// charged for the distance driven.
  final bool endedEarly;
  final String? extra;

  /// rider-u230: the late-cancel fee charged for a cancelled ride, in whole
  /// units of [currency] (History shows it too). Null: cancelled for free.
  final double? cancellationFee;

  /// "20 Oct · 09:05" in the app language (24-hour, as elsewhere).
  String get whenLabel =>
      '${L10n.formatDate(when, 'd MMM')} · ${L10n.formatTime(when)}';

  String get longWhen =>
      '${L10n.formatDate(when, 'd MMMM')} · ${L10n.formatTime(when)} · '
      '$priceLabel';

  String get monthTitle => L10n.formatDate(when, 'MMMM y');

  String get priceLabel {
    if (cancelled) {
      final charged = formatMajor(cancellationFee ?? 0, currency);
      return extra == null
          ? L10n.current.supportPriceCancelled(charged)
          : L10n.current.supportPriceCancelledExtra(charged, extra!);
    }
    if (failed) return L10n.current.supportFailed;
    if (endedEarly) {
      return '${formatMajor(price, currency)} · ${L10n.current.endedEarly}';
    }
    return formatMajor(price, currency);
  }
}
