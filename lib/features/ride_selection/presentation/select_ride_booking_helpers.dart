part of 'select_ride.dart';

extension _SelectRideBookingHelpers on _SelectRideState {
  /// rider-r4-35: prices [ride] again after Review changes outlasted its
  /// quote; a different price is agreed to first. Null: nothing to save.
  Future<double?> _requoteReviewed(_RideOption ride, double reviewed) async {
    final bookable = await _quoteAfterPickup(ride);
    if (!mounted) return null;
    if (bookable == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.priceUnavailableRefreshing)),
      );
      return null;
    }
    if (_selection.moneyOf(reviewed).amountMinor != bookable.quote.totalMinor &&
        !await _acceptNewPrice(reviewed, bookable.price)) {
      return null;
    }
    return mounted ? bookable.price : null;
  }

  String? _driverNote(String? extra) {
    final parts = <String>[
      if (extra != null && extra.trim().isNotEmpty) extra.trim(),
      ..._notes.selected,
    ];
    if (parts.isEmpty) return extra;
    return parts.join(' · ');
  }

  void _releaseRouteWork() {
    _bookingInFlight = false;
    _expiryRequote?.cancel();
    _expiryRequote = null;
    _selection.cancelPendingQuotes();
  }

  /// Where the rider's Home is, so Set pickup can offer a "Near Home" spot.
  /// Best effort: no Home, or a slow lookup, simply means no such spot.
  Future<LatLng?> _homePosition() async {
    try {
      final places = AppScope.instance.savedPlaces;
      await places.hydrate().timeout(const Duration(milliseconds: 600));
      final home = places.shortcuts().where((p) => p.kind == 'home');
      if (home.isEmpty) return null;
      final found = await AppScope.instance.geocoding
          .geocodeAddress(home.first.subtitle)
          .timeout(const Duration(milliseconds: 900));
      if (found == null) return null;
      return LatLng(found.point.latitude, found.point.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<SetPickupResult?> _openSetPickup(
    _RideOption ride, {
    String? confirmLabel,
    DateTime? scheduledPickup,
    bool holdOnConfirm = false,
  }) async {
    final home = await _homePosition();
    if (!mounted) return null;
    final quote = _selection.authoritativeQuotes[ride.id];
    final promotion = _promotion;
    SetPickupPayment paymentLine() {
      final item = _selection.selectedPaymentItem();
      return SetPickupPayment(
        brand: item?.brand ?? 'cash',
        name: item?.name ?? context.l10n.payCash,
        detail: item?.detail ?? '',
      );
    }

    return SetPickupPage.open(
      context,
      initialPosition: _pickupPosition,
      initialAddress: _pickupAddress,
      destinationAddress: widget.destinationAddress,
      destinationPosition: widget.destinationPosition,
      stops: [for (final stop in _locatedStops) stop.address],
      ride: SetPickupRide(
        name: ride.name,
        image: ride.image,
        seats: ride.seats,
        etaMin: ride.etaMin,
        tripMinutes: _tripMinutes(),
      ),
      fare: SetPickupFare(
        totalKr: _priceFor(ride),
        walletKr: _selection.walletAppliedKr(_priceFor(ride)),
        discountKr: _discountFor(ride),
        promotionPercent: quote != null && quote.discountMinor > 0
            ? promotion?.percentOff
            : null,
        currency: _selection.currency,
      ),
      payment: paymentLine(),
      brandMark: _brandMark,
      onChangePayment: () async {
        await _showPaymentPicker();
        return paymentLine();
      },
      onRequote: (pin) => _requoteFromPin(ride, pin),
      fareAfterPaymentChange: (fare) => SetPickupFare(
        totalKr: fare.totalKr,
        discountKr: fare.discountKr,
        promotionPercent: fare.promotionPercent,
        walletKr: _selection.walletAppliedKr(fare.totalKr),
        currency: fare.currency,
      ),
      initialBagLevel: _notes.bagLevel,
      home: home,
      initialIsCurrentLocation: !_pickupConfirmed && !widget.pickupIsFallback,
      positionIsFallback: widget.pickupIsFallback && !_pickupConfirmed,
      confirmLabel: confirmLabel,
      scheduledPickup: scheduledPickup,
      holdOnConfirm: holdOnConfirm,
    );
  }

  /// [_locateStops], looked up once per screen and shared by quoting and
  /// booking so both price the same route.
  Future<List<RouteStop>> _routeStops() {
    if (widget.stops.every((stop) => stop.trim().isEmpty)) {
      return Future.value(const <RouteStop>[]);
    }
    return _stopsLookup ??= _locateStops();
  }

  /// Live test 2026-10-26: the server keeps one live ride per rider and
  /// refuses a booking with `active_trip_exists` while one is still going,
  /// for example a ride this device lost track of. That ride is opened
  /// instead of the "check the fare" message, which sent the rider back to
  /// a price that was never the problem.
  Future<void> _openRideAlreadyGoing() async {
    final trip = await (widget.booking ?? BookingController())
        .adoptRideAlreadyGoing(activeTrips: widget.activeTrips);
    if (!mounted) return;
    final coordinator = RideRestoreCoordinator.instance;
    final surface = coordinator.surfaceFor(trip);
    if (trip == null ||
        (surface != RestoredSurface.finding &&
            surface != RestoredSurface.waiting)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.rideAlreadyGoing)));
      unawaited(_loadQuotes());
      return;
    }
    AppLog.info('booking.opened_active_trip', extra: {'rideId': trip.rideId});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.rideAlreadyGoingOpened)),
    );
    final finding = surface == RestoredSurface.finding;
    if (finding) SheetCoordinator.instance.open(RideSheet.finding);
    try {
      await Navigator.push(
        context,
        RideStageTransition(
          coordinator.pageFor(trip),
          settings: RouteSettings(
            name: finding
                ? AppRoutes.findingDriver
                : AppRoutes.waitingForDriver,
          ),
        ),
      );
    } finally {
      if (finding) SheetCoordinator.instance.close(RideSheet.finding);
    }
  }
}
