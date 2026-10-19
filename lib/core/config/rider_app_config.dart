import 'package:movera_rider/core/contracts/cancel_fee.dart';
import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/money.dart';

/// The part of `RiderAppConfig` (CONTRACT.md §6) the Rider reads today:
/// cancel fees per category. Unknown keys are ignored; a missing or bad
/// rule falls back to the seed document's rule for that category.
class RiderAppConfig {
  const RiderAppConfig({
    required this.version,
    required this.zoneId,
    required this.currency,
    required this.liveCancelFees,
    required this.reservationCancelFees,
  });

  final int version;
  final String zoneId;
  final String currency;
  final Map<String, FeeRule> liveCancelFees;
  final Map<String, FeeRule> reservationCancelFees;

  /// The live-trip rule for [categoryId] (aliases resolved), or null.
  FeeRule? liveFeeFor(String categoryId) =>
      liveCancelFees[CategoryIds.canonical(categoryId)];

  /// The reservation rule for [categoryId] (aliases resolved), or null.
  FeeRule? reservationFeeFor(String categoryId) =>
      reservationCancelFees[CategoryIds.canonical(categoryId)];

  /// Parses a published document. Returns null when it is not a config
  /// document at all (no integer version or ISO currency).
  static RiderAppConfig? fromJson(Object? raw, {RiderAppConfig? fallback}) {
    if (raw is! Map) return null;
    final version = raw['version'];
    final currency = raw['currency'];
    if (version is! int ||
        currency is! String ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      return null;
    }
    final fees = raw['cancelFees'];
    Map<String, FeeRule> table(String name, Map<String, FeeRule> seed) {
      final rows = fees is Map ? fees[name] : null;
      final out = Map<String, FeeRule>.of(seed);
      if (rows is Map) {
        for (final entry in rows.entries) {
          final id = CategoryIds.tryCanonical(entry.key);
          final rule = FeeRule.fromJson(entry.value);
          if (id != null && rule != null) out[id] = rule;
        }
      }
      return out;
    }

    return RiderAppConfig(
      version: version,
      zoneId: raw['zoneId'] is String ? raw['zoneId'] as String : '',
      currency: currency,
      liveCancelFees: table('live', fallback?.liveCancelFees ?? const {}),
      reservationCancelFees: table(
        'reservation',
        fallback?.reservationCancelFees ?? const {},
      ),
    );
  }

  /// Money in this zone's currency.
  Money money(int amountMinor) => Money(amountMinor, currency);
}

/// Where the Rider gets its config document. Today a local seed;
/// `GET /rider/config?zoneId` later (CONTRACT.md §6).
abstract class RiderConfigRepository {
  /// The last good document. Never throws: the seed is always there.
  Future<RiderAppConfig> current();
}

/// The seed document the app ships with (Stockholm zone). Same values as
/// `contracts/fixtures/config/rider_app_config.json` (a contract test keeps
/// them equal).
class SeedRiderConfigRepository implements RiderConfigRepository {
  const SeedRiderConfigRepository();

  static final RiderAppConfig seed = RiderAppConfig.fromJson(seedDocument)!;

  @override
  Future<RiderAppConfig> current() async => seed;

  static const Map<String, Object?> seedDocument = {
    'version': 12,
    'zoneId': 'Z001',
    'currency': 'SEK',
    'cancelFees': {
      'live': {
        'economy': {'freeMin': 2, 'type': 'fixed', 'value': 3500, 'min': null, 'max': null},
        'comfort': {'freeMin': 2, 'type': 'fixed', 'value': 4500, 'min': null, 'max': null},
        'premium': {
          'freeMin': 3, 'type': 'percent', 'value': 15,
          'min': {'amountMinor': 5000, 'currency': 'SEK'},
          'max': {'amountMinor': 15000, 'currency': 'SEK'},
        },
        'xl': {
          'freeMin': 3, 'type': 'percent', 'value': 15,
          'min': {'amountMinor': 5000, 'currency': 'SEK'},
          'max': {'amountMinor': 15000, 'currency': 'SEK'},
        },
        'electric': {'freeMin': 2, 'type': 'fixed', 'value': 3500, 'min': null, 'max': null},
      },
      'reservation': {
        'economy': {'freeMin': 60, 'type': 'fixed', 'value': 5000, 'min': null, 'max': null},
        'comfort': {'freeMin': 60, 'type': 'fixed', 'value': 6000, 'min': null, 'max': null},
        'premium': {
          'freeMin': 120, 'type': 'percent', 'value': 25,
          'min': {'amountMinor': 8000, 'currency': 'SEK'},
          'max': {'amountMinor': 30000, 'currency': 'SEK'},
        },
        'xl': {
          'freeMin': 120, 'type': 'percent', 'value': 25,
          'min': {'amountMinor': 8000, 'currency': 'SEK'},
          'max': {'amountMinor': 30000, 'currency': 'SEK'},
        },
        'electric': {'freeMin': 60, 'type': 'fixed', 'value': 5000, 'min': null, 'max': null},
      },
    },
  };
}

/// What cancelling a live trip costs the rider right now, worked out on
/// the device only to show it before they confirm. The server charges what
/// it decides (`cancellation.fee`).
class LiveCancelFeePreview {
  const LiveCancelFeePreview({required this.fee, required this.freeMinutesLeft});

  final Money fee;

  /// Whole minutes the cancel stays free; 0 once a fee applies.
  final int freeMinutesLeft;

  /// The preview for [categoryId] with [fare], [acceptedAt] being when the
  /// driver accepted. Null when the config has no rule for the category.
  static LiveCancelFeePreview? of(
    RiderAppConfig config, {
    required String categoryId,
    required Money fare,
    required DateTime acceptedAt,
    required DateTime now,
  }) {
    final rule = config.liveFeeFor(categoryId);
    if (rule == null) return null;
    final elapsed = now.difference(acceptedAt);
    final minutes = elapsed.isNegative ? 0 : elapsed.inMinutes;
    final fee = CancelFeeCalculator.live(rule, fare, minutes);
    return LiveCancelFeePreview(
      fee: fee,
      freeMinutesLeft: fee.isPositive ? 0 : rule.freeMin - minutes,
    );
  }
}
