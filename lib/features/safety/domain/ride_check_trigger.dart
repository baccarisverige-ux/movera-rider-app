import 'package:movera_rider/features/safety/domain/ride_check.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// What made Ride check open the card. Movera sets each one (on/off and its
/// numbers); the app only reads them.
enum RideCheckTrigger { droppedFar, longStop, offRoute, possibleCrash }

extension RideCheckTriggerX on RideCheckTrigger {
  /// The value sent to and read from the API.
  String get wire => switch (this) {
    RideCheckTrigger.droppedFar => 'dropped_far',
    RideCheckTrigger.longStop => 'long_stop',
    RideCheckTrigger.offRoute => 'off_route',
    RideCheckTrigger.possibleCrash => 'possible_crash',
  };

  /// Short name shown in the trip's details.
  String get label => switch (this) {
    RideCheckTrigger.droppedFar => L10n.current.rcTriggerDroppedFar,
    RideCheckTrigger.longStop => L10n.current.rcTriggerLongStop,
    RideCheckTrigger.offRoute => L10n.current.rcTriggerOffRoute,
    RideCheckTrigger.possibleCrash => L10n.current.rcTriggerPossibleCrash,
  };

  /// The safety event type this trigger posts to the ride.
  RideCheckEventType get eventType => switch (this) {
    RideCheckTrigger.droppedFar => RideCheckEventType.droppedFar,
    RideCheckTrigger.longStop => RideCheckEventType.unexpectedStop,
    RideCheckTrigger.offRoute => RideCheckEventType.routeDeviation,
    RideCheckTrigger.possibleCrash => RideCheckEventType.possibleCrash,
  };
}

/// Reads a trigger from its name, its API value or an older event type name
/// (`unexpectedStop`, `routeDeviation`). Null when it is none of them.
RideCheckTrigger? parseRideCheckTrigger(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  for (final trigger in RideCheckTrigger.values) {
    if (trigger.name == value || trigger.wire == value) return trigger;
  }
  return switch (value) {
    'unexpectedStop' || 'movementLost' => RideCheckTrigger.longStop,
    'routeDeviation' || 'destinationPassed' => RideCheckTrigger.offRoute,
    _ => null,
  };
}

/// The admin's Ride check numbers. Defaults are the app's own values for
/// when the server has sent none.
class RideCheckTriggerSettings {
  const RideCheckTriggerSettings({
    this.droppedFarEnabled = true,
    this.finishFarFromDropoffKm = defaultFinishFarFromDropoffKm,
    this.longStopEnabled = true,
    this.longStopMinutes = defaultLongStopMinutes,
    this.offRouteEnabled = true,
    this.offRouteKm = 2,
    this.longerThanExpectedPercent = 50,
    this.possibleCrashEnabled = true,
  });

  /// Admin's "Finished far from drop-off" distance (X km) when it sends none.
  static const double defaultFinishFarFromDropoffKm = 3;

  /// Admin's "Unexpected long stop" time (Y min) when it sends none.
  static const int defaultLongStopMinutes = 2;

  final bool droppedFarEnabled;

  /// The driver finishes the trip more than this far from the drop-off:
  /// Ride check opens right after finish.
  final double finishFarFromDropoffKm;
  final bool longStopEnabled;

  /// The car stands still mid-trip for more than this: Ride check opens.
  final int longStopMinutes;
  final bool offRouteEnabled;
  final double offRouteKm;
  final int longerThanExpectedPercent;
  final bool possibleCrashEnabled;

  bool isOn(RideCheckTrigger trigger) => switch (trigger) {
    RideCheckTrigger.droppedFar => droppedFarEnabled,
    RideCheckTrigger.longStop => longStopEnabled,
    RideCheckTrigger.offRoute => offRouteEnabled,
    RideCheckTrigger.possibleCrash => possibleCrashEnabled,
  };

  /// The trip finished [metersFromDropoff] from the drop-off: is that more
  /// than admin's distance? (On/off is checked separately.)
  bool finishedFarFromDropoff(double metersFromDropoff) =>
      metersFromDropoff > finishFarFromDropoffKm * 1000;

  /// The car has stood still for [still]: is that more than admin's time?
  bool isLongStop(Duration still) => still > Duration(minutes: longStopMinutes);

  RideCheckTriggerSettings copyWith({
    bool? droppedFarEnabled,
    double? finishFarFromDropoffKm,
    bool? longStopEnabled,
    int? longStopMinutes,
    bool? offRouteEnabled,
    double? offRouteKm,
    int? longerThanExpectedPercent,
    bool? possibleCrashEnabled,
  }) {
    return RideCheckTriggerSettings(
      droppedFarEnabled: droppedFarEnabled ?? this.droppedFarEnabled,
      finishFarFromDropoffKm:
          finishFarFromDropoffKm ?? this.finishFarFromDropoffKm,
      longStopEnabled: longStopEnabled ?? this.longStopEnabled,
      longStopMinutes: longStopMinutes ?? this.longStopMinutes,
      offRouteEnabled: offRouteEnabled ?? this.offRouteEnabled,
      offRouteKm: offRouteKm ?? this.offRouteKm,
      longerThanExpectedPercent:
          longerThanExpectedPercent ?? this.longerThanExpectedPercent,
      possibleCrashEnabled: possibleCrashEnabled ?? this.possibleCrashEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'finishFarFromDropoffKm': finishFarFromDropoffKm,
    'longStopMinutes': longStopMinutes,
    'droppedFar': {'enabled': droppedFarEnabled, 'km': finishFarFromDropoffKm},
    'longStop': {'enabled': longStopEnabled, 'minutes': longStopMinutes},
    'offRoute': {
      'enabled': offRouteEnabled,
      'km': offRouteKm,
      'longerPercent': longerThanExpectedPercent,
    },
    'possibleCrash': {'enabled': possibleCrashEnabled},
  };

  factory RideCheckTriggerSettings.fromJson(Object? raw) {
    const defaults = RideCheckTriggerSettings();
    if (raw is! Map) return defaults;
    Map<String, dynamic> part(String key) {
      final value = raw[key];
      return value is Map ? Map<String, dynamic>.from(value) : const {};
    }

    bool on(Map<String, dynamic> json, bool fallback) =>
        json['enabled'] is bool ? json['enabled'] as bool : fallback;
    int whole(Object? value, int fallback, {int min = 1}) {
      if (value is! num || !value.isFinite || value < min) return fallback;
      return value.round();
    }

    double? positive(Object? value) =>
        value is num && value.isFinite && value > 0 ? value.toDouble() : null;

    final dropped = part('droppedFar');
    final stop = part('longStop');
    final route = part('offRoute');
    final crash = part('possibleCrash');
    final km = route['km'];
    // Admin's named settings first, then the per-trigger part; an older
    // server's `meters` still reads.
    final legacyMeters = positive(dropped['meters']);
    final finishKm =
        positive(raw['finishFarFromDropoffKm']) ??
        positive(dropped['km']) ??
        (legacyMeters == null ? null : legacyMeters / 1000) ??
        defaults.finishFarFromDropoffKm;
    final rawMinutes = raw['longStopMinutes'];
    return RideCheckTriggerSettings(
      droppedFarEnabled: on(dropped, defaults.droppedFarEnabled),
      finishFarFromDropoffKm: finishKm,
      longStopEnabled: on(stop, defaults.longStopEnabled),
      longStopMinutes: whole(
        rawMinutes is num ? rawMinutes : stop['minutes'],
        defaults.longStopMinutes,
      ),
      offRouteEnabled: on(route, defaults.offRouteEnabled),
      offRouteKm: km is num && km.isFinite && km > 0
          ? km.toDouble()
          : defaults.offRouteKm,
      longerThanExpectedPercent: whole(
        route['longerPercent'],
        defaults.longerThanExpectedPercent,
      ),
      possibleCrashEnabled: on(crash, defaults.possibleCrashEnabled),
    );
  }
}

/// Why the card opened, for its reason line ("Your trip ended 1.2 km from
/// Solna centrum"). Only the fields for its trigger are set.
class RideCheckReason {
  const RideCheckReason({
    this.distanceMeters,
    this.stoppedMinutes,
    this.longerPercent,
    this.place,
    this.destinationLabel,
  });

  /// Dropped far: metres from the drop-off. Off route: metres off the route.
  final double? distanceMeters;
  final int? stoppedMinutes;

  /// Off route by time: how much longer than expected the trip is.
  final int? longerPercent;

  /// Where the car stopped, when known.
  final String? place;
  final String? destinationLabel;

  Map<String, dynamic> toJson() => {
    if (distanceMeters != null) 'distanceMeters': distanceMeters!.round(),
    if (stoppedMinutes != null) 'stoppedMinutes': stoppedMinutes,
    if (longerPercent != null) 'longerPercent': longerPercent,
    if (place != null) 'place': place,
    if (destinationLabel != null) 'destinationLabel': destinationLabel,
  };

  factory RideCheckReason.fromJson(Object? raw) {
    if (raw is! Map) return const RideCheckReason();
    num? number(Object? value) => value is num && value.isFinite ? value : null;
    String? text(Object? value) {
      final out = value is String ? value.trim() : '';
      return out.isEmpty ? null : out;
    }

    return RideCheckReason(
      distanceMeters: number(raw['distanceMeters'])?.toDouble(),
      stoppedMinutes: number(raw['stoppedMinutes'])?.round(),
      longerPercent: number(raw['longerPercent'])?.round(),
      place: text(raw['place']),
      destinationLabel: text(raw['destinationLabel']),
    );
  }
}

/// "650 m" below a kilometre, "1.2 km" from there (rider-u209: "1,2 km" in
/// French and Swedish).
String formatRideCheckDistance(double meters) {
  // rider-r3-5: round first, then pick the unit, so 995-999 m reads
  // "1,0 km" rather than "1000 m".
  final rounded = (meters / 10).round() * 10;
  if (rounded < 1000) return '$rounded m';
  final km = meters / 1000;
  return '${L10n.formatDecimal(km, digits: km >= 10 ? 0 : 1)} km';
}
