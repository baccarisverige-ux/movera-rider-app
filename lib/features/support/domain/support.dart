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
    this.extra,
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
  final String? extra;

  String get whenLabel {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
    final minute = when.minute.toString().padLeft(2, '0');
    final ampm = when.hour >= 12 ? 'PM' : 'AM';
    return '${months[when.month - 1]} ${when.day} · $hour:$minute $ampm';
  }

  String get longWhen {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final hour = when.hour.toString().padLeft(2, '0');
    final minute = when.minute.toString().padLeft(2, '0');
    return '${when.day} ${months[when.month - 1]} · $hour:$minute · $priceLabel';
  }

  String get monthTitle {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[when.month - 1]} ${when.year}';
  }

  String get priceLabel {
    if (cancelled) {
      final zero = formatMajor(0, currency);
      return extra == null ? '$zero · Cancelled' : '$zero · Cancelled · $extra';
    }
    if (failed) return 'Failed';
    return formatMajor(price, currency);
  }
}
