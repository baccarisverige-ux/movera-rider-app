import 'package:movera_rider/core/config/live_data_only.dart';
import 'package:movera_rider/core/contracts/cancel_fee.dart';
import 'package:movera_rider/core/contracts/cancel_reasons.dart';
import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/raise_limit.dart';

import 'zone_settings.dart';

export 'seed_rider_config_repository.dart';
export 'zone_settings.dart';

/// One category of the zone's catalog (`catalog.categories[]`).
class RiderConfigCategory {
  const RiderConfigCategory({
    required this.id,
    required this.label,
    required this.seats,
    required this.sort,
    this.line,
  });

  final String id;
  final String label;
  final int seats;
  final int sort;

  /// Contract v0.7.1: the admin's sub-line per language (`sv`, `fr`, `en`).
  final Map<String, String>? line;
}

/// The rider's fixed pickup fee of one category (`RiderAppConfig.pickupFee`,
/// contract §3.2): live rides and reservations; null = off.
class RiderPickupFee {
  const RiderPickupFee({this.live, this.reservation});

  final Money? live;
  final Money? reservation;
}

/// One rider cancel reason with its title in the rider's language.
class RiderConfigCancelReason {
  const RiderConfigCancelReason({required this.code, required this.title});

  final String code;
  final String title;
}

/// Waiting at pickup and no-show of one category (`CategoryWaiting`).
/// Owner Q41: the no-show is allowed once the free wait is over, so
/// [noShowAfterMin] normally equals [freeWaitMin]; [perMin] is the waiting
/// fee per minute after the free wait (Q42).
class RiderCategoryWaiting {
  const RiderCategoryWaiting({
    required this.freeWaitMin,
    required this.perMin,
    required this.noShowAfterMin,
    required this.noShowFee,
    this.perMinShown,
  });

  final int freeWaitMin;
  final Money perMin;
  final int noShowAfterMin;
  final Money noShowFee;

  /// v0.18.85 (`waitingPriceShown`): [perMin] with the category's app fee,
  /// as the rider pays it (served by the server); null from an older one.
  final Money? perMinShown;

  /// The waiting price per minute the rider sees.
  Money get perMinToShow => perMinShown ?? perMin;
}

/// Waiting at pickup and no-show (`waiting`). The top-level terms are the
/// headline category's; [byCategory] has each category's own terms.
class RiderWaitingRules extends RiderCategoryWaiting {
  const RiderWaitingRules({
    required super.freeWaitMin,
    required super.perMin,
    required super.noShowAfterMin,
    required super.noShowFee,
    super.perMinShown,
    this.byCategory = const {},
  });

  final Map<String, RiderCategoryWaiting> byCategory;

  /// The terms of [categoryId] (aliases resolved), else the top-level ones.
  RiderCategoryWaiting forCategory(String categoryId) =>
      byCategory[CategoryIds.tryCanonical(categoryId) ?? categoryId] ?? this;
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
    this.paymentMethods = ZoneDefaults.paymentMethods,
    this.maxStops = defaultMaxStops,
    this.bookingHorizonDays = defaultBookingHorizonDays,
    this.minAheadMin = defaultMinAheadMin,
    this.freeChangeBeforeMin = defaultFreeChangeBeforeMin,
    this.reservationsOn = true,
    this.maxPickupMoveMeters = defaultMaxPickupMoveAfterAcceptMeters,
    this.country = 'SE',
    this.languages = const AppLanguages(rider: 'sv', driver: 'sv', admin: 'sv'),
    this.tips = const [],
    this.raiseSteps = const [],
    this.promoCap,
    this.walletUsedFirst = true,
    this.waiting,
    this.cancelReasons = const [],
    this.rideCheck = const {},
    this.routeChange = const {},
    this.minimumAppVersion,
    this.latestAppVersion,
    this.pickupFees = const {},
    this.usesStandard = false,
    this.raiseMaxFactor = RaiseLimit.defaultMaxFactor,
    this.cancelAfterArrivedIsNoShow = true,
    this.paymentOptions,
    this.tipRules = const TipRules(),
  });

  /// Built-in defaults for a field neither the document nor its fallback
  /// has: the values the app used before it read the document.
  static const defaultTimeZone = 'Europe/Stockholm';
  static const defaultMaxStops = 3;
  static const defaultBookingHorizonDays = 14;

  /// Contract v0.18.17 Book later (owner Q1, Q6): the earliest pickup, in
  /// minutes after booking, and the free change / cancel time before it.
  /// The server writes both from the zone's settings.
  static const defaultMinAheadMin = 15;
  static const defaultFreeChangeBeforeMin = 60;

  /// Q40: how far, in metres, a rider may move the pickup once a driver
  /// has accepted; further means cancel and rebook. The zone's value is
  /// `booking.maxPickupMoveMeters` ([maxPickupMoveMeters]); this is the
  /// default (`contract.json#configDefaults`).
  static const defaultMaxPickupMoveAfterAcceptMeters =
      ZoneDefaults.maxPickupMoveMeters;

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

  /// Contract zone payment methods offered (`cash`, `card`, `apple_pay`;
  /// owner Q7, v0.18.10 no Google Pay). The wallet is separate ([walletUsedFirst]).
  final List<String> paymentMethods;
  final int maxStops;
  final int bookingHorizonDays;

  /// Contract v0.18.17 `booking.minAheadMin` (owner Q1, default 15).
  final int minAheadMin;

  /// Contract v0.18.17 `booking.freeChangeBeforeMin` (owner Q6, default 60).
  final int freeChangeBeforeMin;

  /// Contract v0.18.19 `booking.reservationsOn` (owner A): the zone's Book
  /// later switch. Off: Book later stays on screen and says "Not
  /// available in this area yet" when tapped.
  final bool reservationsOn;

  /// `booking.maxPickupMoveMeters`: how far the pickup may move after
  /// accept (Q40).
  final int maxPickupMoveMeters;

  /// ISO 3166 country of the zone (`SE`, `FR`, `TN`).
  final String country;

  /// App languages and the country's default per app (Q48/Q49).
  final AppLanguages languages;

  /// Tip options in the zone's currency, enabled or not (Q5).
  final List<AmountOption> tips;

  /// Raise-offer quick steps in the zone's currency (Q6).
  final List<AmountOption> raiseSteps;

  /// Most a promotion may take off one trip (Q10); null = no cap set.
  final Money? promoCap;

  /// The wallet balance (one per currency) pays first (Q7/Q8).
  final bool walletUsedFirst;

  static Map<String, String>? _paymentOptions(Object? raw) {
    if (raw is! List) return null;
    final out = <String, String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final method = item['method'];
      final status = item['status'];
      if (method is! String || status is! String) continue;
      if (!ZoneDefaults.paymentMethods.contains(method)) continue;
      if (status != 'available' && status != 'coming_soon') continue;
      out[method] = status;
    }
    return out;
  }

  /// The tips the rider may pick.
  List<Money> get enabledTips => [
    for (final option in tips)
      if (option.enabled) option.amount,
  ];

  /// Contract v0.18.6 `RiderAppConfig.raisePrice.maxFactor` (owner G4-E4
  /// "2×, admin can change"): the fare may be raised to at most this many
  /// times the booked fare. The admin sets it per zone in Dispatch; the
  /// server copies it here. Missing or outside the contract's range: the
  /// contract default (2).
  final double raiseMaxFactor;

  /// The raise-offer steps the rider may pick.
  List<Money> get enabledRaiseSteps => [
    for (final option in raiseSteps)
      if (option.enabled) option.amount,
  ];

  /// Null when neither the document nor its fallback has valid waiting rules.
  final RiderWaitingRules? waiting;

  /// v0.18.7 (Q2): `waiting.cancelAfterArrivedIsNoShow`, the admin's
  /// per-zone switch "Cancel after the driver arrived counts as a no-show"
  /// (default on), copied into the rider document when served. Only shown
  /// in the Terms; the server charges by it.
  final bool cancelAfterArrivedIsNoShow;

  /// v0.18.10 (`finish.paymentMethods.served`, owner G8 item 2): the
  /// server's `paymentOptions`, method → `available | coming_soon`, in
  /// the admin's order; a method the admin turned off is not listed. Null
  /// from an older server: then only cash is taken and card / Apple Pay
  /// read as coming soon.
  final Map<String, String>? paymentOptions;

  /// v0.18.10 `RiderAppConfig.tipRules` (Admin › Tips & limits).
  final TipRules tipRules;

  /// [method]'s state: `available`, `coming_soon`, or null when it is not
  /// offered here. Google Pay and the wallet are never a ride method.
  String? paymentStatus(String method) {
    if (!ZoneDefaults.paymentMethods.contains(method)) return null;
    final options = paymentOptions;
    if (options != null) return options[method];
    if (!paymentMethods.contains(method)) return null;
    return method == 'cash' ? 'available' : 'coming_soon';
  }

  final List<RiderConfigCancelReason> cancelReasons;

  /// Ride check thresholds, as published (numbers and switches).
  final Map<String, Object> rideCheck;

  /// Contract v0.18.9 `RiderAppConfig.routeChange` (G7 decision 3): the
  /// zone's switches for changing the route during the trip.
  final Map<String, Object> routeChange;

  /// `routeChange.on` (default on): the rider may change the destination or
  /// the stops of a booked trip.
  bool get routeChangeOn => routeChange['on'] != false;

  /// `routeChange.beforePickup` (default on): the route may change before
  /// the rider is on board; off = only once on board.
  bool get routeChangeBeforePickup => routeChange['beforePickup'] != false;
  final String? minimumAppVersion;
  final String? latestAppVersion;

  /// `pickupFee.byCategory` (contract §3.2): the fee the quote's
  /// `pickup_fee` line carries, per category; the server prices it.
  final Map<String, RiderPickupFee> pickupFees;

  /// v0.8.0: the zone has no settings of its own and the server sent its
  /// country's Standard.
  final bool usesStandard;

  /// The pickup fee of [categoryId] (aliases resolved) for a live ride or a
  /// reservation, or null when it is off.
  Money? pickupFeeFor(String categoryId, {bool reservation = false}) {
    final fee = pickupFees[CategoryIds.canonical(categoryId)];
    return reservation ? fee?.reservation : fee?.live;
  }

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
    // D1 (R10 #2 "Server values only"): on a live build a fee the server
    // left out stays absent (the screens show their "no fee" state); the
    // sample fees fill gaps for the demo alone.
    final feeBase = LiveDataOnly.on ? null : base;
    Money? money(Object? json) {
      final value = Money.fromWire(json);
      return value != null && value.currency == currency ? value : null;
    }

    final fees = raw['cancelFees'];
    Map<String, FeeRule> table(String name, Map<String, FeeRule> seed) {
      final rows = fees is Map ? fees[name] : null;
      // Owner 2026-11-10 (R10 #2 "Server values only"): a live build keeps
      // only the rows the server sent; the built-in sample rows fill the
      // gaps for the demo alone.
      final out = LiveDataOnly.on
          ? <String, FeeRule>{}
          : Map<String, FeeRule>.of(seed);
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
    final country =
        _country(raw['country']) ??
        base?.country ??
        ZoneDefaults.countryOf(currency);
    final wallet = raw['wallet'];
    final usedFirst = wallet is Map ? wallet['usedFirst'] : null;
    return RiderAppConfig(
      version: version,
      zoneId: _string(raw['zoneId']) ?? fallback?.zoneId ?? '',
      currency: currency,
      publishedAt: _time(raw['publishedAt']),
      timeZone:
          _string(raw['timeZone']) ?? fallback?.timeZone ?? defaultTimeZone,
      categories:
          _categories(raw['catalog']) ?? fallback?.categories ?? const [],
      features: _features(raw['features']) ?? fallback?.features ?? const {},
      paymentMethods:
          readZonePaymentMethods(raw['paymentMethods']) ??
          fallback?.paymentMethods ??
          ZoneDefaults.paymentMethods,
      maxPickupMoveMeters:
          _count(
            booking is Map ? booking['maxPickupMoveMeters'] : null,
            max: 100000,
          ) ??
          fallback?.maxPickupMoveMeters ??
          defaultMaxPickupMoveAfterAcceptMeters,
      country: country,
      languages:
          readAppLanguages(raw['languages'], country) ??
          (base?.country == country ? base?.languages : null) ??
          AppLanguages.forCountry(country),
      tips:
          readAmountOptions(raw['tips'], currency) ??
          base?.tips ??
          ZoneDefaults.tipsIn(currency),
      raiseSteps:
          readAmountOptions(raw['raiseSteps'], currency) ??
          base?.raiseSteps ??
          ZoneDefaults.raiseStepsIn(currency),
      promoCap: raw.containsKey('promoCap') && raw['promoCap'] == null
          ? null
          : _positive(money(raw['promoCap'])) ?? base?.promoCap,
      walletUsedFirst: usedFirst is bool
          ? usedFirst
          : fallback?.walletUsedFirst ?? true,
      maxStops:
          _count(booking is Map ? booking['maxStops'] : null, max: 10) ??
          fallback?.maxStops ??
          defaultMaxStops,
      // Contract v0.18.17 (owner Q1 "15 min to 90 days"): the zone's
      // maxAheadDays, when the server sends it, is how far ahead it books.
      bookingHorizonDays:
          _count(booking is Map ? booking['maxAheadDays'] : null, max: 366) ??
          _count(
            booking is Map ? booking['bookingHorizonDays'] : null,
            max: 366,
          ) ??
          fallback?.bookingHorizonDays ??
          defaultBookingHorizonDays,
      minAheadMin:
          _count(booking is Map ? booking['minAheadMin'] : null, max: 240) ??
          fallback?.minAheadMin ??
          defaultMinAheadMin,
      freeChangeBeforeMin:
          _count(
            booking is Map ? booking['freeChangeBeforeMin'] : null,
            max: 1440,
          ) ??
          fallback?.freeChangeBeforeMin ??
          defaultFreeChangeBeforeMin,
      reservationsOn: booking is Map && booking['reservationsOn'] is bool
          ? booking['reservationsOn'] as bool
          : fallback?.reservationsOn ?? true,
      liveCancelFees: table('live', base?.liveCancelFees ?? const {}),
      reservationCancelFees: table(
        'reservation',
        base?.reservationCancelFees ?? const {},
      ),
      waiting:
          _waiting(raw['waiting'], money, feeBase?.waiting) ?? feeBase?.waiting,
      cancelAfterArrivedIsNoShow: switch (raw['waiting']) {
        {'cancelAfterArrivedIsNoShow': final bool on} => on,
        _ => fallback?.cancelAfterArrivedIsNoShow ?? true,
      },
      cancelReasons:
          _reasons(raw['cancelReasons']) ?? fallback?.cancelReasons ?? const [],
      rideCheck: _flat(raw['rideCheck']) ?? fallback?.rideCheck ?? const {},
      routeChange:
          _flat(raw['routeChange']) ?? fallback?.routeChange ?? const {},
      minimumAppVersion:
          _string(appUpdate is Map ? appUpdate['minimumVersion'] : null) ??
          fallback?.minimumAppVersion,
      latestAppVersion:
          _string(appUpdate is Map ? appUpdate['latestVersion'] : null) ??
          fallback?.latestAppVersion,
      pickupFees:
          _pickupFees(raw['pickupFee'], money) ??
          feeBase?.pickupFees ??
          const {},
      usesStandard: raw['usesStandard'] == true,
      paymentOptions: _paymentOptions(raw['paymentOptions']),
      tipRules:
          TipRules.read(raw['tipRules'], money, country) ??
          base?.tipRules ??
          TipRules.forCountry(country, currency),
      raiseMaxFactor:
          RaiseLimit.validFactor(
            raw['raisePrice'] is Map
                ? (raw['raisePrice'] as Map)['maxFactor']
                : null,
          ) ??
          fallback?.raiseMaxFactor ??
          RaiseLimit.defaultMaxFactor,
    );
  }

  static Map<String, RiderPickupFee>? _pickupFees(
    Object? raw,
    Money? Function(Object?) money,
  ) {
    final rows = raw is Map ? raw['byCategory'] : null;
    if (rows is! Map) return null;
    final out = <String, RiderPickupFee>{};
    for (final entry in rows.entries) {
      final id = CategoryIds.tryCanonical(entry.key);
      final fee = entry.value;
      if (id == null || fee is! Map) continue;
      out[id] = RiderPickupFee(
        live: _positive(money(fee['live'])),
        reservation: _positive(money(fee['reservation'])),
      );
    }
    return out;
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

  static String? _country(Object? raw) =>
      raw is String && RegExp(r'^[A-Z]{2}$').hasMatch(raw) ? raw : null;

  static Money? _positive(Money? value) =>
      value != null && value.amountMinor > 0 ? value : null;

  /// `{ sv, fr, en }` with the texts that are set; null when none is.
  static Map<String, String>? _line(Object? raw) {
    if (raw is! Map) return null;
    final out = <String, String>{
      for (final code in const ['sv', 'fr', 'en'])
        if (raw[code] is String && (raw[code] as String).trim().isNotEmpty)
          code: (raw[code] as String).trim(),
    };
    return out.isEmpty ? null : Map.unmodifiable(out);
  }

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
          line: _line(row['line']),
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

  /// rider-r4-3: a missing or bad field falls back on its own (CONTRACT
  /// §6), never the whole block: the free wait takes [base]'s (else 5
  /// min), the no-show wait equals the free wait (Q41), and the money takes
  /// [base]'s terms in the same currency. Null only when the block is
  /// absent or no money can be found for it.
  static RiderWaitingRules? _waiting(
    Object? raw,
    Money? Function(Object?) money,
    RiderWaitingRules? base,
  ) {
    if (raw is! Map) return null;
    final freeWait =
        _count(raw['freeWaitMin'], max: 120) ??
        base?.freeWaitMin ??
        ZoneDefaults.freeWaitMin;
    final noShowAfter = _count(raw['noShowAfterMin'], max: 120) ?? freeWait;
    final perMin = money(raw['perMin']) ?? base?.perMin;
    final noShowFee = money(raw['noShowFee']) ?? base?.noShowFee;
    if (perMin == null || noShowFee == null) return null;
    // v0.18.85: the shown price belongs to the raw one it was served with.
    final ownPerMin = money(raw['perMin']);
    final perMinShown = ownPerMin == null ? null : money(raw['perMinShown']);
    return RiderWaitingRules(
      freeWaitMin: freeWait,
      perMin: perMin,
      noShowAfterMin: noShowAfter,
      noShowFee: noShowFee,
      perMinShown: perMinShown,
      byCategory: _byCategory(
        raw['byCategory'],
        money,
        perMin,
        noShowFee,
        perMinShown,
      ),
    );
  }

  /// `waiting.byCategory`: a missing free wait takes the category default
  /// (5 min, XL 3), a missing no-show wait equals the free wait (Q41), and
  /// missing money takes the top-level terms. Bad rows are skipped.
  static Map<String, RiderCategoryWaiting> _byCategory(
    Object? raw,
    Money? Function(Object?) money,
    Money perMin,
    Money noShowFee,
    Money? perMinShown,
  ) {
    if (raw is! Map) return const {};
    final out = <String, RiderCategoryWaiting>{};
    for (final entry in raw.entries) {
      final id = CategoryIds.tryCanonical(entry.key);
      final row = entry.value;
      if (id == null || row is! Map) continue;
      final freeWait =
          _count(row['freeWaitMin'], max: 120) ??
          ZoneDefaults.freeWaitMinOf(id);
      final ownPerMin = money(row['perMin']);
      out[id] = RiderCategoryWaiting(
        freeWaitMin: freeWait,
        perMin: ownPerMin ?? perMin,
        // A row without its own price takes the top-level one, shown too.
        perMinShown: ownPerMin == null
            ? perMinShown
            : money(row['perMinShown']),
        noShowAfterMin: _count(row['noShowAfterMin'], max: 120) ?? freeWait,
        noShowFee: money(row['noShowFee']) ?? noShowFee,
      );
    }
    return Map.unmodifiable(out);
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

/// What cancelling a live trip costs the rider right now, worked out on
/// the device only to show it before they confirm. The server charges what
/// it decides (`cancellation.fee`).
class LiveCancelFeePreview {
  const LiveCancelFeePreview({
    required this.fee,
    required this.freeMinutesLeft,
  });

  final Money fee;

  /// Whole minutes the cancel stays free; 0 once the free window is over
  /// (a fee applies, or a zero-fee rule keeps it free for good). Never
  /// negative (rider-r4-18).
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
      freeMinutesLeft: fee.isPositive || minutes >= rule.freeMin
          ? 0
          : rule.freeMin - minutes,
    );
  }
}

/// v0.18.10 `RiderAppConfig.tipRules` (contract `finish.tips.settings`):
/// a cash tip only in the car unless [cashAfterTrip]; a typed amount up
/// to [customMax] only when [customAmount].
class TipRules {
  const TipRules({
    this.cashAfterTrip = false,
    this.cashInCarMinutes = 5,
    this.customAmount = false,
    this.customMax,
  });

  final bool cashAfterTrip;
  final int cashInCarMinutes;
  final bool customAmount;
  final Money? customMax;

  /// The contract defaults: SE 200 kr, FR 20 €.
  static TipRules forCountry(String country, String currency) =>
      TipRules(customMax: Money(currency == 'SEK' ? 20000 : 2000, currency));

  static TipRules? read(
    Object? raw,
    Money? Function(Object?) money,
    String country,
  ) {
    if (raw is! Map) return null;
    final minutes = raw['cashInCarMinutes'];
    final max = money(raw['customMax']);
    return TipRules(
      cashAfterTrip: raw['cashAfterTrip'] == true,
      cashInCarMinutes: minutes is int && minutes >= 0 && minutes <= 60
          ? minutes
          : 5,
      customAmount: raw['customAmount'] == true,
      customMax: max != null && max.amountMinor > 0 ? max : null,
    );
  }
}
