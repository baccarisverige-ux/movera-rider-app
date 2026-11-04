part of 'select_ride.dart';

extension _SelectRideQuotes on _SelectRideState {
  /// rider-r4-29: [requoteSpent] (a booking flow just released the lock)
  /// prices again right away when a quote ran out meanwhile: the expiry
  /// timer skipped it while the flow was open.
  void _scheduleExpiryRequote({bool requoteSpent = false}) {
    _expiryRequote?.cancel();
    _expiryRequote = null;
    final spent = _selection.discardExpiredQuotes();
    if (spent && requoteSpent) {
      unawaited(_loadQuotes());
      return;
    }
    final next = _selection.nextQuoteExpiry;
    if (next == null) return;
    final wait = next.difference(ServerClock.now());
    // A quote that arrived already spent is not chased in a loop; Book
    // refreshes it.
    if (wait.isNegative) return;
    _expiryRequote = Timer(wait, _onQuotesExpired);
  }

  /// Set location moved the pin: price [ride] again from that exact point
  /// and adopt the quote, so Confirm books the price shown there. Goes
  /// through the selection, which keeps only the latest pin's answer.
  Future<SetPickupFare?> _requoteFromPin(_RideOption ride, LatLng pin) async {
    final stops = await _routeStops();
    final pending = _selection.quoteFromPin(
      stops: stops,
      rideId: ride.id,
      distanceMeters: straightLineMeters(pin, widget.destinationPosition),
      pickup: coordinatePickupAddress(pin),
      destination: widget.destinationAddress,
      pickupPoint: _SelectRideState._geoPoint(pin),
      destinationPoint: _SelectRideState._geoPoint(widget.destinationPosition),
    );
    _pinQuote = pending;
    final quote = await pending;
    if (quote == null || !mounted) return null;
    _pinQuoteAdopted = true;
    return _fareFor(quote);
  }

  SetPickupFare _fareFor(RideQuote quote) {
    final total = Money(quote.totalMinor, quote.currency).major;
    final discount = Money(quote.discountMinor, quote.currency).major;
    return SetPickupFare(
      totalKr: total,
      discountKr: discount,
      promotionPercent: discount > 0 ? _promotion?.percentOff : null,
      walletKr: Money(
        _selection.walletSplitFor(quote.totalMinor).walletMinor,
        quote.currency,
      ).major,
      currency: quote.currency,
    );
  }

  ({RideQuote quote, double price})? _bookableQuote(String rideId) {
    final soon = ServerClock.now().add(_SelectRideState._quoteMargin);
    final price = _selection.authoritativePriceFor(rideId, now: soon);
    final quote = _selection.authoritativeQuotes[rideId];
    if (price == null || quote == null) return null;
    // rider-79: a quote priced at another point than the confirmed pickup
    // (a category not re-priced after the pin moved, or a pin re-quote
    // that failed) is priced again from it.
    if (!_selection.quoteIsAt(
      rideId,
      _SelectRideState._geoPoint(_pickupPosition),
    )) {
      return null;
    }
    return (quote: quote, price: price);
  }

  /// After the steps the rider controls (Add card, Set pickup): the quote
  /// to book is the one the selection holds now, never the one captured
  /// before them (RIDE-1). A quote that expired meanwhile is refreshed in
  /// place from the confirmed pickup (RIDE-2). Returns null when no price
  /// can be had.
  Future<({RideQuote quote, double price})?> _quoteAfterPickup(
    _RideOption ride,
  ) async {
    final pending = _pinQuote;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // A failed pin quote keeps the price shown.
      }
    }
    if (!mounted) return null;
    final current = _bookableQuote(ride.id);
    if (current != null) return current;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.refreshingPrice)));
    try {
      final stops = await _routeStops();
      await _selection.quoteFromPin(
        stops: stops,
        rideId: ride.id,
        distanceMeters: straightLineMeters(
          _pickupPosition,
          widget.destinationPosition,
        ),
        pickup: _pickupAddress,
        destination: widget.destinationAddress,
        pickupPoint: _SelectRideState._geoPoint(_pickupPosition),
        destinationPoint: _SelectRideState._geoPoint(
          widget.destinationPosition,
        ),
      );
    } catch (_) {
      // Reported below.
    }
    if (!mounted) return null;
    return _bookableQuote(ride.id);
  }

  /// The price to book differs from the one Set pickup showed: the rider
  /// agrees to the new one first.
  Future<bool> _acceptNewPrice(double shown, double next) async {
    // rider-r4-33: the dialog opens on any öre difference, so it shows the
    // öre ("254,20 kr, was 254,40 kr"), never two equal whole kronor.
    String exact(double value) => formatMoney(_selection.moneyOf(value));
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('select-ride-price-updated'),
        title: Text(
          context.l10n.priceUpdated,
          style: _text(18, weight: FontWeight.w600),
        ),
        content: Text(
          context.l10n.priceUpdatedBody(exact(next), exact(shown)),
          style: _text(14.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.notNow),
          ),
          FilledButton(
            key: const ValueKey('select-ride-price-accept'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.bookForPrice(exact(next))),
          ),
        ],
      ),
    );
    return accepted == true;
  }

  /// The cars are asked for while the live map shows this screen, the app is
  /// in front and no booking step covers it; they follow the pickup.
  void _syncNearbyWatch() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    final visible =
        _mapReady &&
        !_mapParked &&
        !_bookingInFlight &&
        _appInForeground &&
        (route?.isCurrent ?? true);
    if (visible) {
      _nearby.watch(
        GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude),
      );
    } else {
      _nearby.pause();
    }
  }

  /// [_syncNearbyWatch] after this frame: build decides what shows, and the
  /// controller must not notify while the tree builds.
  void _scheduleNearbySync() {
    if (_nearbySyncScheduled) return;
    _nearbySyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nearbySyncScheduled = false;
      _syncNearbyWatch();
    });
  }

  /// The nearby cars as map markers, under the route's pins.
  Set<Marker> _nearbyCarMarkers() {
    final icons = _carIcons;
    if (icons == null) return const <Marker>{};
    return {
      for (final car in _nearby.frames())
        () {
          final pose = NearbyCarMarker.pose(car.heading);
          return Marker(
            markerId: MarkerId('nearby-car-${car.key}'),
            position: LatLng(car.latitude, car.longitude),
            icon: pose.mirrored ? icons.left : icons.right,
            rotation: pose.rotation,
            anchor: const Offset(0.5, 0.6),
            zIndexInt: 1,
            consumeTapEvents: true,
          );
        }(),
    };
  }

  _RideOption? get _selectedRideOrNull {
    final id = _selection.selectedRideId;
    for (final ride in _allRides) {
      if (ride.id == id) return ride;
    }
    return null;
  }

  double _priceFor(_RideOption ride) =>
      _selection.priceFor(ride.id, ride.price);
}
