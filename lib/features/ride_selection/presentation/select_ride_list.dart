part of 'select_ride.dart';

extension _SelectRideList on _SelectRideState {
  List<_RideOption> get _allRides {
    return _selection.rides().map((ride) {
      return _RideOption(
        id: ride.id,
        image: ride.image,
        name: ride.name,
        // v0.7.1: the admin's sub-line in the rider's language; else
        // (rider-77) the built-in note in the rider's language.
        note: ride.lineIn(L10n.current.localeName) ?? rideNoteFor(ride.note),
        arrival: ride.arrival,
        etaMin: ride.etaMin,
        price: ride.price,
        currency: ride.currency,
        seats: ride.seats,
        badge: ride.badge == null ? null : rideBadgeFor(ride.badge!),
        glyph: _SelectRideState._glyphIcon(ride.glyph),
        glyphKey: ride.glyph,
      );
    }).toList();
  }

  /// The list as it is drawn: the two headings (only when both groups have
  /// rides) and the rides under them.
  List<({String? heading, _RideOption? ride})> get _listEntries {
    final rides = _visibleRides;
    final premium = rides
        .where((r) => _SelectRideState._premiumGroup.contains(r.id))
        .toList();
    final everyday = rides
        .where((r) => !_SelectRideState._premiumGroup.contains(r.id))
        .toList();
    final headed = premium.isNotEmpty && everyday.isNotEmpty;
    return [
      if (headed) (heading: context.l10n.ridesForYou, ride: null),
      for (final ride in everyday) (heading: null, ride: ride),
      if (headed) (heading: context.l10n.ridesPremium, ride: null),
      for (final ride in premium) (heading: null, ride: ride),
    ];
  }
}
