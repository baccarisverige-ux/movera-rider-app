import 'package:movera_rider/core/contracts/cancel_fee.dart';
import 'package:movera_rider/core/contracts/cancel_reasons.dart';
import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/money.dart';

/// One category of the zone's catalog (`catalog.categories[]`).
class RiderConfigCategory {
  const RiderConfigCategory({
    required this.id,
    required this.label,
    required this.seats,
    required this.sort,
  });

  final String id;
  final String label;
  final int seats;
  final int sort;
}

/// One rider cancel reason with its title in the rider's language.
class RiderConfigCancelReason {
  const RiderConfigCancelReason({required this.code, required this.title});

  final String code;
  final String title;
}

/// Waiting at pickup and no-show (`waiting`).
class RiderWaitingRules {
  const RiderWaitingRules({
    required this.freeWaitMin,
    required this.perMin,
    required this.noShowAfterMin,
    required this.noShowFee,
  });

  final int freeWaitMin;
  final Money perMin;
  final int noShowAfterMin;
  final Money noShowFee;
}

/// `RiderAppConfig` (CONTRACT.md §6), the document Admin exports per zone.
///
/// Parsing never throws. Unknown keys are ignored; a missing or bad field
/// falls back to the `fallback` document (normally the seed) when that is
/// in the same currency, else to a safe built-in default. A document with
/// no integer `version` or ISO `currency` is not a config document at all
/// ([fromJson] returns null and the caller keeps its last good one).
class RiderAppConfig {
  const RiderAppConfig({
    required this.version,
    required this.zoneId,
    required this.currency,
    required this.liveCancelFees,
    required this.reservationCancelFees,
    this.publishedAt,
    this.timeZone = defaultTimeZone,
    this.categories = const [],
    this.features = const {},
    this.paymentMethods = const [],
    this.maxStops = defaultMaxStops,
    this.bookingHorizonDays = defaultBookingHorizonDays,
    this.waiting,
    this.cancelReasons = const [],
    this.rideCheck = const {},
    this.minimumAppVersion,
    this.latestAppVersion,
  });

  /// Built-in defaults for a field neither the document nor its fallback
  /// has: the values the app used before it read the document.
  static const defaultTimeZone = 'Europe/Stockholm';
  static const defaultMaxStops = 3;
  static const defaultBookingHorizonDays = 14;

  final int version;
  final String zoneId;
  final String currency;
  final Map<String, FeeRule> liveCancelFees;
  final Map<String, FeeRule> reservationCancelFees;
  final DateTime? publishedAt;

  /// IANA zone id of the zone (`Europe/Stockholm`, `Africa/Tunis`).
  final String timeZone;

  /// The zone's categories, in `sort` order.
  final List<RiderConfigCategory> categories;

  /// `features.*` flags; an unknown flag reads as off ([feature]).
  final Map<String, bool> features;

  /// Payment method ids offered in the zone.
  final List<String> paymentMethods;
  final int maxStops;
  final int bookingHorizonDays;

  /// Null when neither the document nor its fallback has valid waiting rules.
  final RiderWaitingRules? waiting;
  final List<RiderConfigCancelReason> cancelReasons;

  /// Ride check thresholds, as published (numbers and switches).
  final Map<String, Object> rideCheck;
  final String? minimumAppVersion;
  final String? latestAppVersion;

  /// Whether feature [name] is on (off when the document does not say).
  bool feature(String name) => features[name] ?? false;

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
    // Money-bearing fallbacks only carry over within one currency: a SEK
    // seed fee must never be read as a TND fee.
    final base = fallback != null && fallback.currency == currency
        ? fallback
        : null;
    Money? money(Object? json) {
      final value = Money.fromWire(json);
      return value != null && value.currency == currency ? value : null;
    }

    final fees = raw['cancelFees'];
    Map<String, FeeRule> table(String name, Map<String, FeeRule> seed) {
      final rows = fees is Map ? fees[name] : null;
      final out = Map<String, FeeRule>.of(seed);
      if (rows is Map) {
        for (final entry in rows.entries) {
          final id = CategoryIds.tryCanonical(entry.key);
          final rule = FeeRule.fromJson(entry.value);
          if (id == null || rule == null) continue;
          final bounds = [rule.min, rule.max].whereType<Money>();
          if (bounds.any((bound) => bound.currency != currency)) continue;
          out[id] = rule;
        }
      }
      return out;
    }

    final booking = raw['booking'];
    final appUpdate = raw['appUpdate'];
    return RiderAppConfig(
      version: version,
      zoneId: _string(raw['zoneId']) ?? fallback?.zoneId ?? '',
      currency: currency,
      publishedAt: _time(raw['publishedAt']),
      timeZone:
          _string(raw['timeZone']) ?? fallback?.timeZone ?? defaultTimeZone,
      categories: _categories(raw['catalog']) ?? fallback?.categories ?? const [],
      features: _features(raw['features']) ?? fallback?.features ?? const {},
      paymentMethods:
          _ids(raw['paymentMethods']) ?? fallback?.paymentMethods ?? const [],
      maxStops:
          _count(booking is Map ? booking['maxStops'] : null, max: 10) ??
          fallback?.maxStops ??
          defaultMaxStops,
      bookingHorizonDays:
          _count(
            booking is Map ? booking['bookingHorizonDays'] : null,
            max: 366,
          ) ??
          fallback?.bookingHorizonDays ??
          defaultBookingHorizonDays,
      liveCancelFees: table('live', base?.liveCancelFees ?? const {}),
      reservationCancelFees: table(
        'reservation',
        base?.reservationCancelFees ?? const {},
      ),
      waiting: _waiting(raw['waiting'], money) ?? base?.waiting,
      cancelReasons:
          _reasons(raw['cancelReasons']) ?? fallback?.cancelReasons ?? const [],
      rideCheck: _flat(raw['rideCheck']) ?? fallback?.rideCheck ?? const {},
      minimumAppVersion:
          _string(appUpdate is Map ? appUpdate['minimumVersion'] : null) ??
          fallback?.minimumAppVersion,
      latestAppVersion:
          _string(appUpdate is Map ? appUpdate['latestVersion'] : null) ??
          fallback?.latestAppVersion,
    );
  }

  static String? _string(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  static DateTime? _time(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

  static int? _count(Object? raw, {required int max}) =>
      raw is int && raw >= 0 && raw <= max ? raw : null;

  static List<RiderConfigCategory>? _categories(Object? catalog) {
    final rows = catalog is Map ? catalog['categories'] : null;
    if (rows is! List) return null;
    final seen = <String>{};
    final out = <RiderConfigCategory>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final id = CategoryIds.tryCanonical(row['id']);
      if (id == null || !seen.add(id)) continue;
      final seats = row['seats'];
      final sort = row['sort'];
      out.add(
        RiderConfigCategory(
          id: id,
          label: _string(row['label']) ?? id,
          seats: seats is int && seats > 0 ? seats : 4,
          sort: sort is int ? sort : out.length + 1,
        ),
      );
    }
    out.sort((a, b) => a.sort.compareTo(b.sort));
    return out;
  }

  static Map<String, bool>? _features(Object? raw) {
    if (raw is! Map) return null;
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is bool)
          entry.key as String: entry.value as bool,
    };
  }

  static List<String>? _ids(Object? raw) {
    if (raw is! List) return null;
    final out = <String>[];
    for (final id in raw) {
      final value = _string(id);
      if (value != null && !out.contains(value)) out.add(value);
    }
    return out;
  }

  static RiderWaitingRules? _waiting(
    Object? raw,
    Money? Function(Object?) money,
  ) {
    if (raw is! Map) return null;
    final freeWait = _count(raw['freeWaitMin'], max: 120);
    final noShowAfter = _count(raw['noShowAfterMin'], max: 120);
    final perMin = money(raw['perMin']);
    final noShowFee = money(raw['noShowFee']);
    if (freeWait == null ||
        noShowAfter == null ||
        perMin == null ||
        noShowFee == null) {
      return null;
    }
    return RiderWaitingRules(
      freeWaitMin: freeWait,
      perMin: perMin,
      noShowAfterMin: noShowAfter,
      noShowFee: noShowFee,
    );
  }

  /// Rider codes only (`contract.json#cancelReasons.rider`); another
  /// actor's code is never offered to the rider.
  static List<RiderConfigCancelReason>? _reasons(Object? raw) {
    if (raw is! List) return null;
    final out = <RiderConfigCancelReason>[];
    for (final row in raw) {
      if (row is! Map || !CancelReasonCodes.isRiderCode(row['code'])) continue;
      final title = _string(row['title']);
      if (title == null) continue;
      out.add(
        RiderConfigCancelReason(code: row['code'] as String, title: title),
      );
    }
    return out;
  }

  static Map<String, Object>? _flat(Object? raw) {
    if (raw is! Map) return null;
    return {
      for (final entry in raw.entries)
        if (entry.key is String && (entry.value is num || entry.value is bool))
          entry.key as String: entry.value as Object,
    };
  }

  /// Money in this zone's currency.
  Money money(int amountMinor) => Money(amountMinor, currency);
}

/// Where the Rider gets its config document. Today a local seed;
/// `GET /rider/config?zoneId` later (CONTRACT.md §6).
abstract class RiderConfigRepository {
  /// The last good document. Never throws: the seed is always there.
  Future<RiderAppConfig> current();

  /// The document of zone [zoneId] (Q7: the pickup's zone), or [current]
  /// when there is none for that zone. Never throws.
  Future<RiderAppConfig> forZone(String zoneId);
}

/// The seed document the app ships with (Stockholm zone). Same values as
/// `contracts/fixtures/config/rider_app_config.json` (a contract test keeps
/// them equal).
class SeedRiderConfigRepository implements RiderConfigRepository {
  const SeedRiderConfigRepository();

  static final RiderAppConfig seed = RiderAppConfig.fromJson(seedDocument)!;

  /// The seed of each zone the app knows (`RiderZones`): Stockholm's
  /// [seedDocument], and Paris Centre and Tunis Centre with their own
  /// currency, waiting and cancel fees as Admin exports them
  /// (`test/fixtures/admin_config/rider_app_config.<zone>.json`; a test
  /// keeps them equal).
  static final Map<String, RiderAppConfig> zoneSeeds = {
    seed.zoneId: seed,
    for (final overrides in [_franceOverrides, _tunisiaOverrides])
      overrides['zoneId'] as String: RiderAppConfig.fromJson({
        ...seedDocument,
        ...overrides,
      })!,
  };

  /// The seed of [zoneId], else Stockholm's.
  static RiderAppConfig seedFor(String? zoneId) => zoneSeeds[zoneId] ?? seed;

  /// The seed whose prices are in [currency], or null.
  static RiderAppConfig? seedForCurrency(String currency) {
    for (final config in zoneSeeds.values) {
      if (config.currency == currency) return config;
    }
    return null;
  }

  @override
  Future<RiderAppConfig> current() async => seed;

  @override
  Future<RiderAppConfig> forZone(String zoneId) async => seedFor(zoneId);

  static const Map<String, Object?> _franceOverrides = {
    'zoneId': 'FR-PC',
    'currency': 'EUR',
    'timeZone': 'Europe/Paris',
    'waiting': {
      'freeWaitMin': 2,
      'perMin': {'amountMinor': 115, 'currency': 'EUR'},
      'noShowAfterMin': 5,
      'noShowFee': {'amountMinor': 615, 'currency': 'EUR'},
    },
    'cancelFees': {
      'live': {
        'economy': {'freeMin': 2, 'type': 'fixed', 'value': 335, 'min': null, 'max': null},
        'comfort': {'freeMin': 2, 'type': 'fixed', 'value': 430, 'min': null, 'max': null},
        'premium': {'freeMin': 3, 'type': 'percent', 'value': 15, 'min': {'amountMinor': 475, 'currency': 'EUR'}, 'max': {'amountMinor': 1425, 'currency': 'EUR'}},
        'priority': {'freeMin': 2, 'type': 'fixed', 'value': 335, 'min': null, 'max': null},
        'xl': {'freeMin': 3, 'type': 'percent', 'value': 15, 'min': {'amountMinor': 475, 'currency': 'EUR'}, 'max': {'amountMinor': 1425, 'currency': 'EUR'}},
        'electric': {'freeMin': 2, 'type': 'fixed', 'value': 335, 'min': null, 'max': null},
        'pet': {'freeMin': 2, 'type': 'fixed', 'value': 335, 'min': null, 'max': null},
        'child_seat': {'freeMin': 2, 'type': 'fixed', 'value': 335, 'min': null, 'max': null},
      },
      'reservation': {
        'economy': {'freeMin': 60, 'type': 'fixed', 'value': 475, 'min': null, 'max': null},
        'comfort': {'freeMin': 60, 'type': 'fixed', 'value': 570, 'min': null, 'max': null},
        'premium': {'freeMin': 120, 'type': 'percent', 'value': 25, 'min': {'amountMinor': 760, 'currency': 'EUR'}, 'max': {'amountMinor': 2850, 'currency': 'EUR'}},
        'priority': {'freeMin': 60, 'type': 'fixed', 'value': 475, 'min': null, 'max': null},
        'xl': {'freeMin': 120, 'type': 'percent', 'value': 25, 'min': {'amountMinor': 760, 'currency': 'EUR'}, 'max': {'amountMinor': 2850, 'currency': 'EUR'}},
        'electric': {'freeMin': 60, 'type': 'fixed', 'value': 475, 'min': null, 'max': null},
        'pet': {'freeMin': 60, 'type': 'fixed', 'value': 475, 'min': null, 'max': null},
        'child_seat': {'freeMin': 60, 'type': 'fixed', 'value': 475, 'min': null, 'max': null},
      },
    },
  };

  static const Map<String, Object?> _tunisiaOverrides = {
    'zoneId': 'TN-TC',
    'currency': 'TND',
    'timeZone': 'Africa/Tunis',
    'waiting': {
      'freeWaitMin': 2,
      'perMin': {'amountMinor': 3700, 'currency': 'TND'},
      'noShowAfterMin': 5,
      'noShowFee': {'amountMinor': 19500, 'currency': 'TND'},
    },
    'cancelFees': {
      'live': {
        'economy': {'freeMin': 2, 'type': 'fixed', 'value': 10500, 'min': null, 'max': null},
        'comfort': {'freeMin': 2, 'type': 'fixed', 'value': 13500, 'min': null, 'max': null},
        'premium': {'freeMin': 3, 'type': 'percent', 'value': 15, 'min': {'amountMinor': 15000, 'currency': 'TND'}, 'max': {'amountMinor': 45000, 'currency': 'TND'}},
        'priority': {'freeMin': 2, 'type': 'fixed', 'value': 10500, 'min': null, 'max': null},
        'xl': {'freeMin': 3, 'type': 'percent', 'value': 15, 'min': {'amountMinor': 15000, 'currency': 'TND'}, 'max': {'amountMinor': 45000, 'currency': 'TND'}},
        'electric': {'freeMin': 2, 'type': 'fixed', 'value': 10500, 'min': null, 'max': null},
        'pet': {'freeMin': 2, 'type': 'fixed', 'value': 10500, 'min': null, 'max': null},
        'child_seat': {'freeMin': 2, 'type': 'fixed', 'value': 10500, 'min': null, 'max': null},
      },
      'reservation': {
        'economy': {'freeMin': 60, 'type': 'fixed', 'value': 15000, 'min': null, 'max': null},
        'comfort': {'freeMin': 60, 'type': 'fixed', 'value': 18000, 'min': null, 'max': null},
        'premium': {'freeMin': 120, 'type': 'percent', 'value': 25, 'min': {'amountMinor': 24000, 'currency': 'TND'}, 'max': {'amountMinor': 90000, 'currency': 'TND'}},
        'priority': {'freeMin': 60, 'type': 'fixed', 'value': 15000, 'min': null, 'max': null},
        'xl': {'freeMin': 120, 'type': 'percent', 'value': 25, 'min': {'amountMinor': 24000, 'currency': 'TND'}, 'max': {'amountMinor': 90000, 'currency': 'TND'}},
        'electric': {'freeMin': 60, 'type': 'fixed', 'value': 15000, 'min': null, 'max': null},
        'pet': {'freeMin': 60, 'type': 'fixed', 'value': 15000, 'min': null, 'max': null},
        'child_seat': {'freeMin': 60, 'type': 'fixed', 'value': 15000, 'min': null, 'max': null},
      },
    },
  };


  static const Map<String, Object?> seedDocument = {
    'version': 12,
    'publishedAt': '2026-10-19T08:00:00Z',
    'zoneId': 'Z001',
    'currency': 'SEK',
    'timeZone': 'Europe/Stockholm',
    'catalog': {
      'categories': [
        {'id': 'economy', 'label': 'Movera', 'seats': 4, 'sort': 1},
        {'id': 'comfort', 'label': 'Comfort', 'seats': 4, 'sort': 2},
        {'id': 'premium', 'label': 'Premium', 'seats': 4, 'sort': 3},
        {'id': 'xl', 'label': 'XL', 'seats': 6, 'sort': 4},
        {'id': 'electric', 'label': 'Electric', 'seats': 4, 'sort': 5},
      ],
    },
    'features': {
      'scheduledRides': true,
      'wallet': true,
      'pin': false,
      'shareTrip': true,
    },
    'paymentMethods': ['card', 'swish', 'apple', 'google', 'wallet', 'cash'],
    'booking': {'maxStops': 3, 'bookingHorizonDays': 14},
    'waiting': {
      'freeWaitMin': 2,
      'perMin': {'amountMinor': 500, 'currency': 'SEK'},
      'noShowAfterMin': 5,
      'noShowFee': {'amountMinor': 5000, 'currency': 'SEK'},
    },
    'cancelReasons': [
      {'code': 'pickup_incorrect', 'title': 'Pickup point is incorrect'},
      {'code': 'plans_changed', 'title': 'Plans changed'},
      {'code': 'something_else', 'title': 'Something else'},
    ],
    'rideCheck': {'stopMinutes': 2, 'offRouteKm': 3},
    'appUpdate': {'minimumVersion': '1.0.0', 'latestVersion': '1.2.0'},
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
