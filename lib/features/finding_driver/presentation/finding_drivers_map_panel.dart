part of 'finding_drivers.dart';

// ignore_for_file: invalid_use_of_protected_member

// The map bits and the search panel body of [FindingDrivers] (Rule 25
// split, no behaviour change).
extension _FindingDriversMapPanel on _FindingDriversState {
  /// rider-u61: on the web the car bitmap comes turned (the plugin ignores
  /// rotation there).
  Marker _nearbyMarker(NearbyVehicle vehicle) {
    final look = MoveraVehicleMarker.look(
      _driverCar,
      vehicle.bearing,
      onReady: () {
        if (mounted) setState(_loadMapBits);
      },
    );
    return Marker(
      markerId: MarkerId('nearby-${vehicle.id}'),
      position: LatLng(vehicle.latitude, vehicle.longitude),
      rotation: look.rotation,
      flat: true,
      anchor: const Offset(0.5, 0.5),
      icon:
          look.icon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
    );
  }

  void _loadMapBits() {
    final routePoints = _roadRoutePoints;
    _markers = {
      if (_riderPuck != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: _pickupPosition,
          infoWindow: InfoWindow(title: _pickupAddress),
          icon: _riderPuck!,
          anchor: _pinAnchor,
        ),
      ...routeStopMarkers(_stops),
      Marker(
        markerId: const MarkerId('destination'),
        position: _destinationPosition,
        infoWindow: InfoWindow(title: _destinationAddress),
        icon:
            _destinationPin ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: _pinAnchor,
      ),
      for (final vehicle in _match.nearby) _nearbyMarker(vehicle),
    };
    // A14: the road through every stop, straight through them until then.
    _polylines = styledRoute(
      resolvedRoutePolyline(
        id: 'route',
        points: routePoints != null && routePoints.length >= 2
            ? routePoints
            : straightTripLine(_pickupPosition, _stops, _destinationPosition),
        color: RiderRouteStyle.color,
      ),
    );
  }

  Future<void> _prepareMapVisuals() async {
    final eta = widget.etaMinutes;
    final tripMinutes = estimatedTripMinutes(
      GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude),
      GeoPoint(_destinationPosition.latitude, _destinationPosition.longitude),
    );
    final icons = await Future.wait<BitmapDescriptor>([
      // While searching the pins carry the estimate; the live driver ETA
      // takes over once a driver is found.
      eta == null
          ? RouteEndpointMarker.createIcon(pickup: true)
          : RouteTimeMarker.createIcon(
              pickup: true,
              label: context.l10n.minLineBreak('$eta'),
            ),
      MoveraVehicleMarker.createIcon(),
      eta == null
          ? RouteEndpointMarker.createIcon(pickup: false)
          : RouteTimeMarker.createIcon(
              pickup: false,
              label: context.l10n.arriveBy(
                clockTime(
                  DateTime.now().add(Duration(minutes: eta + tripMinutes)),
                ),
              ),
            ),
    ]);
    if (!mounted) return;
    _riderPuck = icons[0];
    _destinationPin = icons[2];
    _driverCar = icons[1];
    _pinAnchor = eta == null ? const Offset(0.5, 0.5) : RouteTimeMarker.anchor;
    _loadMapBits();
    setState(() {});
  }

  Future<void> _refreshRoadRoute() async {
    final from = _pickupPosition;
    final stops = _stops;
    final to = _destinationPosition;
    final route = await roadTripLine(from: from, stops: stops, to: to);
    if (!mounted || route == null) return;
    // rider-35: the route changed while this answer was on its way; the
    // newer request draws the line.
    if (from != _pickupPosition ||
        to != _destinationPosition ||
        !identical(stops, _stops)) {
      return;
    }
    _roadRoutePoints = route.points;
    _roadApproximate = route.approximate;
    _loadMapBits();
    setState(() {});
  }

  /// Deep-fix 2026-11-02: the admin's search step (Dispatch › search
  /// steps) as the server sent it: its message, and for keep_waiting the
  /// Keep waiting / Stop answer.
  Widget _searchStepCard(TripSearchStep step) {
    final l10n = context.l10n;
    final message = step.message.isNotEmpty
        ? step.message
        : step.asksKeepWaiting
        ? l10n.searchStepKeepWaitingFallback
        : l10n.searchStepBusyFallback;
    return Container(
      key: ValueKey('search-step-${step.id}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EBEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            key: const ValueKey('search-step-message'),
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1F2A30),
            ),
          ),
          if (step.asksKeepWaiting) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('search-step-stop'),
                    onPressed: _match.keepWaitingInFlight
                        ? null
                        : () => _answerStep(wait: false),
                    child: Text(l10n.searchStepStop),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('search-step-wait'),
                    onPressed: _match.keepWaitingInFlight
                        ? null
                        : () => _answerStep(wait: true),
                    child: Text(l10n.keepWaiting),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _panelBody(double progress, String headline, String subtitle) {
    return SingleChildScrollView(
      // N4: the sheet's own scroll controller, so the drag is shared.
      primary: true,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1D252C),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: const Color(0xFF5C656C),
            ),
          ),
          if (_match.offerConfirmation != null) ...[
            const SizedBox(height: 10),
            Text(
              _match.offerConfirmation!,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2D5878),
              ),
            ),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0xFFEAF2F8),
              color: const Color(0xFF2D5878),
            ),
          ),
          if (_match.searchStep case final step?) ...[
            const SizedBox(height: 16),
            _searchStepCard(step),
          ],
          if (_match.showStillLooking &&
              !(_match.searchStep?.asksKeepWaiting ?? false)) ...[
            const SizedBox(height: 16),
            StillLookingCard(
              onKeepSearching: () {
                _match.keepSearching();
                setState(() {});
              },
              onCancel: _confirmCancel,
            ),
          ],
          if (_match.showPriceBumpCard) ...[
            const SizedBox(height: 16),
            PriceBumpCard(
              currentPrice: _match.currentPrice,
              maxPrice: _match.maxOfferPrice,
              currency: _match.currency,
              busy: _match.editInFlight,
              // Q6: the zone's raise steps, in the trip's currency.
              steps: _raiseSteps(_match.currency),
              onConfirm: (kr) => _raiseOffer(_match.confirmPriceIncrease(kr)),
              onConfirmIncrease: (increase) =>
                  _raiseOffer(_match.confirmPriceIncreaseBy(increase)),
              onKeepWaiting: () {
                _match.dismissPriceBump();
                setState(() {});
              },
            ),
          ],
          if (_match.showRaiseEntry)
            RaiseOfferEntry(
              controller: _match,
              onOpened: () => setState(() {}),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE7EBEE)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rideNameFor(widget.rideType),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: const Color(0xFF5C656C),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.meetAt(_shortPlace(_pickupAddress)),
                        style: GoogleFonts.poppins(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1D252C),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bookedPaymentLine(
                          // rider-u231: the method in the app language.
                          paymentMethod: paymentLabelFor(widget.paymentMethod),
                          priceKr: _match.currentPrice,
                          currency: _match.currency,
                          walletMinor: widget.walletAmountMinor,
                          separator: '  ·  ',
                        ),
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF2D5878),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _openDetails,
                  icon: const Icon(Icons.more_horiz_rounded),
                  tooltip: context.l10n.rideDetails,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SafetyKitSheetRow(rideId: _match.ride.rideId, driverAssigned: false),
        ],
      ),
    );
  }
}
