// Step 74 split: these State members moved verbatim out of
// waiting_for_driver.dart into an extension, where `setState` is protected.
// ignore_for_file: invalid_use_of_protected_member
part of 'waiting_for_driver.dart';

extension _WaitingTerminal on _WaitingForDriverState {
  Future<void> _handleExternalTerminal(RideStatus status) async {
    if (!mounted ||
        _leaving ||
        _completedOpened ||
        !status.isTerminal ||
        status.isCompletedSurface) {
      return;
    }
    // A driver dropping the ride before pickup does not end the rider's trip.
    // Dispatch looks again, so say what happened and go back to searching
    // rather than sending them Home to rebook from scratch.
    if (status == RideStatus.cancelledByDriver &&
        !_tracking.status.isCompletedSurface) {
      await _researchAfterDriverCancel();
      return;
    }
    _leaving = true;
    setState(() {});
    // "Search again" after a driver's end starts where the car stopped
    // (the server's last position on the trip), so read it before the
    // tracker lets go.
    final carStop =
        _tracking.eta?.latitude != null && _tracking.eta?.longitude != null
        ? GeoPoint(_tracking.eta!.latitude!, _tracking.eta!.longitude!)
        : null;
    _tracking.dispose();
    if (status == RideStatus.endedByDriver) {
      final rideId = _rideId?.trim();
      if (rideId != null && rideId.isNotEmpty) await _awaitRideCheck(rideId);
      if (!mounted) return;
    }

    // rider-u52: `closed` is a finished trip once it is paid and rated (a
    // resync after a long disconnect in trip can jump straight there). It
    // is not an external terminal and gets no error sheet: file it as
    // completed and go Home.
    if (status == RideStatus.closed) {
      final customTerminal = widget.onTerminal;
      if (customTerminal == null) await _ride.markClosedByServer();
      if (!mounted) return;
      await _parkMapForStageChange();
      if (!mounted) return;
      if (customTerminal != null) {
        await customTerminal(context, status);
      } else {
        RideNavigator.home(context, status: status);
      }
      return;
    }

    // A queued outbox cancel (D-013/D-020) can land after the rider was told
    // the ride is still active. The server then reports cancelledByRider:
    // commit it locally instead of treating it as an external terminal.
    if (status == RideStatus.cancelledByRider && widget.onTerminal == null) {
      await _ride.completeServerConfirmedCancel(
        drivenMeters: _tracking.drivenMeters > 0
            ? _tracking.drivenMeters
            : null,
      );
      if (!mounted) return;
      await _parkMapForStageChange();
      if (!mounted) return;
      // rider-u51: a queued on-board End trip the outbox delivered is a
      // finished trip with a receipt (UI-01), like the direct path.
      final endedEarly = _ride.endedEarly;
      if (endedEarly != null) {
        _openEndedEarlySummary(endedEarly);
        return;
      }
      RideNavigator.home(context);
      return;
    }

    final customTerminal = widget.onTerminal;
    if (customTerminal != null) {
      await showRideTerminalStateSheet(context, status: status);
      if (!mounted) return;
      await _parkMapForStageChange();
      if (!mounted) return;
      await customTerminal(context, status);
      return;
    }

    // N10 (owner, 2026-10-26): after a no-show or a driver's end the same
    // sheet offers "Search again" first, "Back to Home" second. The trip is
    // read before the session files it as over.
    final again = canSearchAgainAfter(status)
        ? _searchAgainTrip(status == RideStatus.endedByDriver ? carStop : null)
        : null;
    await _ride.markExternalTerminal(status);
    if (!mounted) return;
    if (again != null) {
      final searchAgain = await showRideEndedSearchAgainSheet(
        context,
        status: status,
        // v0.18.7 (Q6): a no-show says its fee (or "No fee").
        feeLine: status == RideStatus.noShow
            ? riderCancelFeeText(_tracking.cancellation)
            : null,
      );
      if (!mounted) return;
      await _parkMapForStageChange();
      if (!mounted) return;
      if (searchAgain && await _searchAgain(again)) return;
      if (!mounted) return;
      RideNavigator.home(context, status: status);
      return;
    }
    await showRideTerminalStateSheet(context, status: status);
    if (!mounted) return;
    await _parkMapForStageChange();
    if (!mounted) return;
    RideNavigator.home(context, status: status);
  }
}
