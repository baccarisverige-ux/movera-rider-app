part of 'finding_driver_controller.dart';

extension _FindingDriverEdits on FindingDriverController {
  int? _beginEdit() {
    if (_assigned ||
        _assignmentPending ||
        _editInFlight ||
        _cancelInFlight ||
        _cancelled ||
        _terminated ||
        _disposed) {
      return null;
    }
    _editInFlight = true;
    _editEpoch += 1;
    return _editEpoch;
  }

  bool _editInvalid(int token) =>
      token != _editEpoch || _cancelled || _terminated || _disposed;

  /// An edit the server applied is dropped only when the search it belongs
  /// to is over: a cancel started meanwhile that has not committed does
  /// not undo it (rider-u96).
  bool _appliedEditDropped(int token) =>
      _editInvalid(token) &&
      (token != _editRacedByCancel || _cancelled || _terminated || _disposed);

  void _finishEdit(int token) {
    if (token == _editEpoch || _editInFlight) {
      _editInFlight = false;
    }
    _onTick?.call(elapsedSeconds);
    if (_assignmentPending &&
        !_cancelInFlight &&
        !_cancelled &&
        !_terminated &&
        !_disposed) {
      _assignmentPending = false;
      _completeAssigned();
    }
  }

  /// Whether [snapshot] is paid with the wallet and its balance (in the
  /// trip's currency) is below [total]. False when unknown.
  Future<bool> _walletCannotPay(RideSnapshot snapshot, double total) async {
    final methodId = snapshot.paymentMethodId;
    final byWallet = methodId != null
        ? methodId == 'wallet'
        : WalletController.isWalletPayment(snapshot.paymentMethod);
    if (!byWallet) return false;
    try {
      final wallet = AppScope.instance.walletController.forCurrency(currency);
      if (!wallet.available) return false;
      final balance = await wallet.loadBalance();
      return Money.fromLegacyMajor(balance, currency).amountMinor <
          Money.fromLegacyMajor(total, currency).amountMinor;
    } catch (_) {
      return false;
    }
  }

  /// R-O2: an edit refused as stale changed nothing; its key is dropped so
  /// the rider's next try is a new request on the trip as it is now. The
  /// screen reads the ride again.
  bool _staleEdit(Object error, MutationAttempt mutation) {
    if (error is! ApiError || !error.isVersionMismatch) return false;
    mutation.reset();
    ride.observeProjection(error.projection);
    final id = ownedRideId;
    if (id != null) {
      unawaited(
        _realtime.reconnectAndResync(id).catchError((Object resyncError) {
          AppLog.warning(
            'ride.edit.resync_failed',
            extra: {'rideId': id, 'error': resyncError.toString()},
          );
        }),
      );
    }
    return true;
  }

  /// The booked fare the server's answer carries, when it says.
  int? _serverBookedFareMinor(Map<String, dynamic> response) {
    final ride = response['ride'];
    return RaiseLimit.bookedFareMinorOf(
      ride is Map ? ride : response,
      currency,
    );
  }

  /// The fare the server says the ride now has, from a PATCH response's
  /// `ride.price` (or a top-level `price`). Null when absent or unusable.
  double? _serverPrice(Map<String, dynamic> response) {
    final ride = response['ride'];
    final fare = Money.fromWire(ride is Map ? ride['fare'] : response['fare']);
    // A fare in another currency is not this trip's price.
    if (fare != null) {
      return fare.isPositive && fare.currency == currency ? fare.major : null;
    }
    final raw = ride is Map ? ride['price'] : response['price'];
    if (raw is! num) return null;
    final value = raw.toDouble();
    return value.isFinite && value > 0 ? value : null;
  }
}
