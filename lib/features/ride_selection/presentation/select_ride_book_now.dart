part of 'select_ride.dart';

extension _SelectRideBookNow on _SelectRideState {
  void _bookNow() {
    final selected = _selectedRideOrNull;
    if (selected == null) {
      _releaseBookingLock();
      return;
    }
    final quote = _selection.quoteForBooking(selected.id);
    if (quote == null ||
        _selection.authoritativePriceFor(selected.id) == null ||
        !quote.bookable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.fareChangedRefreshing)),
      );
      _releaseBookingLock();
      unawaited(_loadQuotes());
      return;
    }
    final paymentItem = _selection.selectedPaymentItem();
    if (paymentItem == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.noPaymentMethod)));
      _releaseBookingLock();
      return;
    }
    var payment = _PaymentOption(
      brand: paymentItem.brand,
      name: paymentItem.name,
      detail: paymentItem.detail,
    );
    _withParkedMap(() async {
      try {
        if (!mounted) return;
        if (FindingDriverController.active != null) return;
        // A card needs to be saved first: Add card opens before Set pickup
        // and the new card becomes the chosen method.
        if (payment.brand == 'cards' && !_selection.hasSavedCard) {
          final card = await _addCardFirst();
          if (card == null || !mounted) return;
          payment = _PaymentOption(
            brand: card.methodBrand,
            name: card.displayName,
            detail: context.l10n.cardExpires(card.expiryLabel),
          );
        }
        // Set pickup every time; the current location is preselected.
        _pinQuote = null;
        _pinQuoteAdopted = false;
        final spot = await _openSetPickup(selected);
        if (!mounted) return;
        if (spot == null) {
          // The pin's price belongs to a point the rider did not confirm.
          if (_pinQuoteAdopted) unawaited(_loadQuotes());
          return;
        }
        _pickupAddress = spot.address;
        _pickupPosition = spot.position;
        _roadRoutePoints = null;
        unawaited(_refreshRoadRoute());
        _pickupConfirmed = true;
        _notes = _notes.withBagLevel(spot.bagLevel);
        final chosen = _selection.selectedPaymentItem();
        if (chosen != null) {
          payment = _PaymentOption(
            brand: chosen.brand,
            name: chosen.name,
            detail: chosen.detail,
          );
        }
        // rider-r3-6: the generic Card row picked on Set pickup needs a
        // saved card too, as it does before Set pickup.
        if (payment.brand == 'cards' && !_selection.hasSavedCard) {
          final card = await _addCardFirst();
          if (card == null || !mounted) return;
          payment = _PaymentOption(
            brand: card.methodBrand,
            name: card.displayName,
            detail: context.l10n.cardExpires(card.expiryLabel),
          );
        }

        // Book the price Set pickup showed, not the one from before it.
        var bookable = await _quoteAfterPickup(selected);
        if (!mounted) return;
        var shown = spot.fareTotalKr;
        while (bookable != null &&
            shown != null &&
            _selection.moneyOf(shown).amountMinor !=
                bookable.quote.totalMinor) {
          if (!await _acceptNewPrice(shown, bookable.price)) {
            if (!mounted) return;
            // ignore: invalid_use_of_protected_member
            setState(() {});
            // rider-79: the other categories are priced from the confirmed
            // pickup too.
            unawaited(_loadQuotes());
            return;
          }
          if (!mounted) return;
          // rider-u190: the dialog has no time limit. A quote that ran out
          // while it was open is priced again; a new price is asked again.
          shown = bookable.price;
          bookable = await _quoteAfterPickup(selected);
          if (!mounted) return;
        }
        if (bookable == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.priceUnavailableRefreshing)),
          );
          unawaited(_loadQuotes());
          return;
        }
        final quote = bookable.quote;
        final authoritativePrice = bookable.price;
        if (_walletCannotPay(authoritativePrice)) return;
        // The wallet part the rider was shown travels with the booking.
        final walletSplit = _selection.walletSplitFor(quote.totalMinor);

        final stops = await _routeStops();
        if (!mounted) return;

        String rideId;
        try {
          rideId = await (widget.booking ?? BookingController()).submitFinding(
            stops: stops,
            pickupAddress: _pickupAddress,
            destinationAddress: widget.destinationAddress,
            pickupLat: _pickupPosition.latitude,
            pickupLng: _pickupPosition.longitude,
            destinationLat: widget.destinationPosition.latitude,
            destinationLng: widget.destinationPosition.longitude,
            rideType: selected.id,
            price: authoritativePrice,
            paymentMethod: payment.brand,
            quoteId: quote.id,
            quoteSignedPayload: quote.signedPayload,
            quoteExpiresAt: quote.expiresAt,
            quoteTotalMinor: quote.totalMinor,
            quoteCurrency: quote.currency,
            rideTypeLabel: selected.name,
            paymentMethodLabel: payment.name,
            notes: _notes,
            useWalletFirst: _selection.useWalletFirst,
            walletAmountMinor: walletSplit.walletMinor,
          );
          if (rideId.trim().isEmpty) {
            throw StateError('Booking response did not contain a ride id.');
          }
        } catch (error) {
          if (!mounted) return;
          if (error is ApiError && error.detail == 'active_trip_exists') {
            await _openRideAlreadyGoing();
            return;
          }
          // v0.18.10 (owner G8 item 2): a payment method the server does
          // not take is said plainly, then back to the payment choice;
          // never a silent return to Select Ride.
          // G16-1: a paused account cannot book; it is said plainly.
          if (error is ApiError && error.detail == 'account_suspended') {
            // v0.18.43 §64: the projection is Rider.moderation; a paused or
            // banned rider gets the level screen.
            final level = RiderModeration.fromRider(error.projection);
            if (level.blocksRiding) RiderModeration.current.value = level;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                key: const ValueKey('booking-account-suspended'),
                content: Text(context.l10n.accountSuspended),
              ),
            );
            return;
          }
          if (error is ApiError && error.detail.startsWith('payment_method_')) {
            await _paymentMethodRefused(error.detail);
            return;
          }
          // RC-09: a booking that may exist on the server is not "refused".
          final uncertain = BookingController.mayHaveBooked(error);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                uncertain
                    ? context.l10n.bookingUncertain
                    : context.l10n.bookingFailed,
              ),
            ),
          );
          unawaited(_loadQuotes());
          return;
        }

        if (!mounted) {
          await RideRestoreCoordinator.instance.recoverCreatedFinding(
            rideId,
            realtime: widget.realtime,
          );
          return;
        }

        final existingOwner = FindingDriverController.active;
        if (existingOwner != null) {
          final authoritativeRideId =
              await (widget.booking ?? BookingController())
                  .reconcileCreatedFinding(rideId);
          if (!mounted) {
            if (authoritativeRideId == rideId) {
              await RideRestoreCoordinator.instance.recoverCreatedFinding(
                rideId,
                realtime: widget.realtime,
              );
            }
            return;
          }

          final ownerAfterReconcile = FindingDriverController.active;
          if (authoritativeRideId != rideId ||
              ownerAfterReconcile?.ownedRideId == rideId) {
            return;
          }
        }

        SheetCoordinator.instance.open(RideSheet.finding);
        try {
          await Navigator.push(
            context,
            RideStageTransition(
              FindingDrivers(
                pickupAddress: _pickupAddress,
                destinationAddress: widget.destinationAddress,
                pickupPosition: _pickupPosition,
                destinationPosition: widget.destinationPosition,
                rideType: selected.name,
                price: authoritativePrice,
                currency: quote.currency,
                paymentMethod: payment.name,
                walletAmountMinor: walletSplit.walletMinor,
                notes: _notes,
                stops: stops,
                realtime: widget.realtime,
                etaMinutes: selected.etaMin,
              ),
              settings: const RouteSettings(name: AppRoutes.findingDriver),
            ),
          );
        } finally {
          SheetCoordinator.instance.close(RideSheet.finding);
        }
      } finally {
        _releaseBookingLock();
      }
    });
  }
}
