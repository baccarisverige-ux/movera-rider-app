part of 'finding_driver_controller.dart';

/// Rule 25 split (owner 2026-11-05 "Split, then fix"): the price raise,
/// moved from finding_driver_controller.dart without a change.
extension _FindingDriverRaise on FindingDriverController {
  Future<bool> _raisePrice(Money increase) async {
    if (!increase.isPositive || increase.currency != currency) return false;
    final snapshot = _snapshot;
    final id = snapshot?.rideId ?? ride.rideId;
    if (snapshot == null || id == null) return false;
    final next = Money(
      snapshot.fare.amountMinor + increase.amountMinor,
      currency,
    ).major;
    // v0.18.6 (G4-E4): never above the zone's raise limit.
    if (snapshot.fare.amountMinor + increase.amountMinor >
        Money.fromLegacyMajor(maxOfferPrice, currency).amountMinor) {
      editFeedback = L10n.current.raiseAboveLimit;
      _onTick?.call(elapsedSeconds);
      return false;
    }
    if (await _walletCannotPay(snapshot, next)) {
      // rider-r5-16: as Select Ride refuses the wallet for a fare above
      // its balance (rider-74), a wallet trip is not raised above it.
      editFeedback = L10n.current.walletTooLowForRide;
      _onTick?.call(elapsedSeconds);
      return false;
    }
    final editToken = _beginEdit();
    if (editToken == null) {
      editFeedback = _assigned || _assignmentPending
          ? L10n.current.editOfferTooLate
          : L10n.current.editOfferFailed;
      _onTick?.call(elapsedSeconds);
      return false;
    }
    editFeedback = null;
    _onTick?.call(elapsedSeconds);
    // D-012: send only the rider's intent — how much to raise the offer by.
    // The client-computed total is a preview for the button label, never a
    // value the server is asked to accept. The fare shown afterwards is the
    // one the server's response actually carries.
    final intent = jsonEncode({
      'rideId': id,
      'fromPrice': snapshot.price,
      'offerIncrease': increase.toJson(),
    });
    try {
      // R-O2: raised on the trip this search last saw.
      final version = _priceMutation.versionFor(
        intent,
        ride.projectionVersionOf(id),
      );
      final key = _priceMutation.keyFor(intent);
      // Contract v0.5.5 (owner decision 25): on the live wire the raise is
      // its own command, with the trip version the rider last saw; the
      // server answers the TripProjection with the new fare. The demo's
      // mock keeps the pre-v0.5 PATCH.
      Future<Map<String, dynamic>> raise() => api.contractWire
          ? api.post(
              '/api/v1/trips/${Uri.encodeComponent(id)}/raise-price',
              body: {
                'increase': increase.toJson(),
                'expectedVersion': ?version,
              },
              idempotencyKey: key,
            )
          : api.patch(
              '/api/v1/rides/$id',
              // Contract v0.3.0: the raise as Money, not kronor.
              body: {
                'offerIncrease': increase.toJson(),
                'expectedVersion': ?version,
              },
              idempotencyKey: key,
            );
      Map<String, dynamic> response;
      try {
        response = await raise();
      } catch (error) {
        // rider-u97: a timeout or dropped connection says nothing about
        // whether the server applied the raise. The same request again
        // (same key) gets the server's answer and the fare it applied.
        if (error is ApiError && !error.isRetryable) rethrow;
        if (_appliedEditDropped(editToken)) return false;
        response = await raise();
      }
      _priceMutation.succeeded(intent);
      ride.observeProjection(response);
      if (_appliedEditDropped(editToken)) return false;
      _bumpDismissed = true;
      final serverPrice = _serverPrice(response);
      if (serverPrice == null) {
        // Accepted, but the response did not say what the fare now is.
        // Keep showing the last fare the server confirmed rather than
        // assuming the preview total is what happened.
        offerConfirmation = null;
        editFeedback = L10n.current.offerSentUnconfirmed;
        AppLog.warning(
          'ride.offer.price_unconfirmed',
          extra: {'rideId': id, 'increase': increase.majorString},
        );
        _onTick?.call(elapsedSeconds);
        _reportQa();
        return true;
      }
      _priceUpdated = true;
      offerConfirmation = L10n.current.offerUpdatedTo(
        formatMoney(Money.fromLegacyMajor(serverPrice, currency), whole: true),
      );
      editFeedback = offerConfirmation;
      _snapshot = snapshot.copyWith(
        status: ride.status,
        price: serverPrice,
        savedAt: DateTime.now(),
        maxOfferMinor: FindingDriverController._serverMaxOfferMinor(response),
        bookedFareMinor: _serverBookedFareMinor(response),
      );
      await _store.save(_snapshot!);
      if (_appliedEditDropped(editToken)) return false;
      AppLog.info(
        'ride.offer.updated',
        extra: {
          'rideId': id,
          'increase': increase.majorString,
          'serverPrice': serverPrice,
          if (serverPrice != next) 'previewPrice': next,
        },
      );
      _onTick?.call(elapsedSeconds);
      _reportQa();
      return true;
    } catch (error) {
      if (FindingDriverController._raiseTooHigh(error)) {
        // v0.18.6 (G4-E4): the server's limit is lower than this screen
        // knew (the admin lowered it). Nothing changed; the zone's config
        // is read again so the buttons over the limit go away.
        _priceMutation.reset();
        editFeedback = L10n.current.raiseAboveLimit;
        onRaiseLimitRefused?.call();
        _onTick?.call(elapsedSeconds);
        _reportQa();
        return false;
      }
      editFeedback = _staleEdit(error, _priceMutation)
          ? rideJustChangedMessage
          : L10n.current.editOfferFailed;
      _onTick?.call(elapsedSeconds);
      _reportQa();
      return false;
    } finally {
      _finishEdit(editToken);
    }
  }
}
