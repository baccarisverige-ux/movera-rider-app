part of 'select_ride.dart';

extension _SelectRideBookScheduled on _SelectRideState {
  Future<void> _bookScheduled() async {
    try {
      final pickupConfirmedBefore = _pickupConfirmed;
      if (_selection.scheduledFor == null) {
        await _chooseLater();
      } else if (_returnTimeNeedsPicker) {
        // Route the rider through the shared validated picker, which opens on
        // the prefill clamped to the next legal slot.
        await _chooseLater(initial: _selection.scheduledFor);
      }
      if (_selection.scheduledFor == null || !mounted) return;
      // Still stale after the picker: the rider dismissed it, so book nothing.
      // Unless the pickup spot was confirmed in that same pass - then the
      // chosen time went stale on the pickup screen, and the re-pick below
      // must ask again rather than silently dropping the booking.
      if (_returnTimeNeedsPicker && _pickupConfirmed == pickupConfirmedBefore) {
        return;
      }
      await _withParkedMap(() async {
        if (!mounted) return;
        // rider-r4-34: as Book now, the generic Card row needs a saved card
        // first; a reservation is never paid by "Card" with none behind it.
        final method = _selection.selectedPaymentItem();
        if (method?.brand == 'cards' && !_selection.hasSavedCard) {
          if (await _addCardFirst() == null || !mounted) return;
        }
        SetPickupResult? spot;
        if (!_pickupConfirmed) {
          // Same Set pickup sheet as Book now, ending in "Confirm and
          // schedule" instead of a search.
          final ride = _selectedRideOrNull;
          if (ride == null) return;
          // rider-r4-30: the date picker can outlast the quote; Set pickup
          // shows a live quote, never the list price it falls back to.
          if (_bookableQuote(ride.id) == null) {
            final fresh = await _quoteAfterPickup(ride);
            if (!mounted) return;
            if (fresh == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.l10n.priceUnavailableRefreshing),
                ),
              );
              unawaited(_loadQuotes());
              return;
            }
          }
          _pinQuote = null;
          _pinQuoteAdopted = false;
          spot = await _openSetPickup(
            ride,
            confirmLabel: context.l10n.confirmAndSchedule,
            scheduledPickup: _selection.scheduledFor,
          );
          if (!mounted) return;
          if (spot == null) {
            // rider-u188: as Book now, the pin's price belongs to a point
            // the rider did not confirm.
            if (_pinQuoteAdopted) unawaited(_loadQuotes());
            return;
          }
          _pickupAddress = spot.address;
          _pickupPosition = spot.position;
          _roadRoutePoints = null;
          unawaited(_refreshRoadRoute());
          _pickupConfirmed = true;
          _notes = _notes.withBagLevel(spot.bagLevel);
          // rider-r3-6: Card may have been picked on Set pickup.
          if (_selection.selectedPaymentItem()?.brand == 'cards' &&
              !_selection.hasSavedCard) {
            if (await _addCardFirst() == null || !mounted) return;
          }
        }
        if (_returnTimeNeedsPicker) {
          // The prefill went stale while the rider confirmed the pickup spot.
          final when = await ScheduleDateTimeSelector.choose(
            context,
            initial: _selection.scheduledFor,
            // rider-89: Arrive by needs the trip estimate here too.
            tripMinutes: _tripMinutes(),
            timeZone: _pickupSchedule.timeZone,
            horizonDays: _pickupSchedule.horizonDays,
            freeChangeBeforeMin:
                _zoneConfig?.freeChangeBeforeMin ??
                RiderAppConfig.defaultFreeChangeBeforeMin,
          );
          if (when == null || !mounted) return;
          _selection.scheduleFor(when);
        }
        final booked = _selectedRideOrNull;
        if (booked == null) return;
        // rider-79: as Book now, the price booked is the confirmed
        // pickup's: a pin price still loading is waited for, and a quote
        // from another point is priced again.
        final bookable = await _quoteAfterPickup(booked);
        if (!mounted) return;
        if (bookable == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.priceUnavailableRefreshing)),
          );
          unawaited(_loadQuotes());
          return;
        }
        final shown = spot?.fareTotalKr;
        if (shown != null &&
            _selection.moneyOf(shown).amountMinor !=
                bookable.quote.totalMinor &&
            !await _acceptNewPrice(shown, bookable.price)) {
          if (!mounted) return;
          // ignore: invalid_use_of_protected_member
          setState(() {});
          unawaited(_loadQuotes());
          return;
        }
        if (!mounted) return;
        if (_walletCannotPay(bookable.price)) return;
        // rider-r4-28: the stops the price was quoted for are booked too.
        final stops = await _routeStops();
        if (!mounted) return;
        final Reservation? created;
        try {
          created = await ScheduledRideCheckout.run(
            context,
            reservations: _reservations,
            selection: _selection,
            pickup: ReservationPlace(
              label: _pickupAddress,
              lat: _pickupPosition.latitude,
              lng: _pickupPosition.longitude,
            ),
            destination: ReservationPlace(
              label: widget.destinationAddress,
              lat: widget.destinationPosition.latitude,
              lng: widget.destinationPosition.longitude,
            ),
            pickupPosition: _pickupPosition,
            note: _driverNote(widget.note),
            parentReservationId: widget.parentReservationId,
            editingReservationId: widget.editingReservationId,
            original: widget.editingReservationId == null
                ? null
                : _reservations.byId(widget.editingReservationId!),
            // rider-63: the zone the time was picked in.
            timeZone: _pickupSchedule.timeZone,
            stops: [
              for (final stop in stops)
                ReservationPlace(
                  label: stop.address,
                  lat: stop.latitude,
                  lng: stop.longitude,
                ),
            ],
            // rider-r4-35: the quote ran out on Review changes.
            requote: (reviewed) => _requoteReviewed(booked, reviewed),
          );
        } catch (error, stack) {
          final action = widget.editingReservationId == null
              ? ReservationAction.book
              : ReservationAction.edit;
          AppScope.instance.crashes.record(
            error,
            stack,
            operation: 'reservation.${action.name}',
          );
          if (mounted) {
            MoveraToast.show(context, reservationErrorMessage(error, action));
          }
          return;
        }
        if (!mounted || created == null) return;
        final opener = widget.onScheduled;
        if (opener != null) {
          await opener(context, created.reservationId);
          return;
        }
        Navigator.pop(context, created);
      });
    } finally {
      _releaseBookingLock();
    }
  }
}
