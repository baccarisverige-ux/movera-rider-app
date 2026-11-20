import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// J10 (contract v0.18.84 `debtModel.maxRiderDebt`, owner Q-S5-3 / Q-S5-4
/// "Block only cash trip"): `POST /trips` paid in the car while the rider
/// owes at or above the country's max → `409 conflict`, reason
/// `rider_debt_above_max`, details
/// `["debt:<minor> <CUR>", "max:<minor> <CUR>"]`. Nothing is booked;
/// card, Apple Pay and wallet stay allowed.
abstract final class RiderDebtRefusal {
  static const reason = 'rider_debt_above_max';

  static bool matches(Object error) =>
      error is ApiError && error.detail == reason;

  /// The debt the server named in [error]'s details, or null.
  static Money? debtOf(Object error) =>
      error is ApiError ? _detail(error.details, 'debt') : null;

  /// The rider's words (`debtModel.texts.riderDebtAboveMax`) with the
  /// server's amount, or null when [error] is another refusal. Without a
  /// readable amount the server's own message is shown.
  static String? messageOf(Object error) {
    if (error is! ApiError || !matches(error)) return null;
    final debt = debtOf(error);
    if (debt == null) return error.message;
    return L10n.current.riderDebtAboveMax(formatMoney(debt));
  }

  /// `<key>:<minor> <CUR>` in [details], e.g. `debt:24000 SEK`.
  static Money? _detail(List<String>? details, String key) {
    for (final item in details ?? const <String>[]) {
      final match = RegExp('^$key:\\s*(-?\\d+)\\s+([A-Z]{3})\\s*\$')
          .firstMatch(item.trim());
      if (match == null) continue;
      return Money(int.parse(match.group(1)!), match.group(2)!);
    }
    return null;
  }
}
